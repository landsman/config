# Contended writes, idempotency keys and the outbox

The long form of the [source-of-truth rule](../../rules/source-of-truth.md). Open
it while designing a write two requests can race on, an idempotency key, or an
outbox relay.

## 1. A bid, worked through

Two people bid in an auction's last second and exactly one wins.

    POST /auctions/{id}/bids
    Idempotency-Key: <client-generated>
    If-Match: <auction version>              -- optional, see 1.3
    { "amount": { "currency": "EUR", "minorUnits": 12345 } }

One transaction, under **READ COMMITTED** (Postgres's default):

    INSERT INTO bid_request (auction_id, bidder_id, key, body_hash) VALUES (…)
        ON CONFLICT (auction_id, bidder_id, key) DO NOTHING
        -- 0 rows: a copy got here first → read its stored outcome, answer that
    UPDATE auction
       SET current_price = :amount, leading_bidder_id = :me, version = version + 1
     WHERE id = :id AND status = 'OPEN' AND ends_at > now()
       AND :amount >= current_price + min_increment
       AND seller_id <> :me
    -- store the outcome on bid_request, accepted or refused
    -- accepted: INSERT the immutable bid row and the outbox row
    -- commit, then answer

### 1.1 Claim the key before the update

A lookup first is wrong: two copies both find nothing, the second waits on the
row lock, and Postgres then re-checks its `WHERE` against the first's committed
price — 0 rows, a refusal for a bid that was accepted.

With the claim, the copy blocks on the first's uncommitted key. When the first
commits, the copy inserts nothing and its next statement — a new snapshot under
READ COMMITTED — sees the stored outcome. When the first rolls back, the copy's
insert goes ahead. Locking the auction row (`FOR UPDATE`) and looking the key up
again under the lock is the equivalent.

**This holds under READ COMMITTED only.** Under REPEATABLE READ or SERIALIZABLE
the blocked insert, and a different-key bid on the same row, fail with
`40001 could not serialize access`; the app reruns the whole transaction.

Name the conflict target. A bare `ON CONFLICT DO NOTHING` swallows every unique
violation, not only the key's.

### 1.2 The key's own rules

- **Scope it to the caller** — Stripe scopes keys per account. One client's key
  never answers another's request.
- **Store refusals as outcomes too**, so a retry gets the same answer. Stripe
  stores neither validation failures nor concurrent-conflict results.
- **Same key, different body** — compare `body_hash`, answer `422`.
- **Keys expire** (Stripe: 24 hours). A retry after expiry is safe here only
  because the same absolute amount no longer clears `current_price +
  min_increment`; where a retry would succeed twice, keep keys longer.
- **`409` for a copy in flight belongs to a different design**: one that commits
  the key in its own transaction first (`locked_at`, recovery points), which is
  needed once the work includes a call outside the database. In the
  one-transaction shape above, a copy waits and then gets the stored answer.

### 1.3 The condition is what the user agreed to

A bid is an absolute amount, so it stands when the price moved but it still
clears. Add `AND version = :seenVersion` (the `If-Match`) only where the decision
rested on the exact state shown — buying at a displayed price — and answer a
mismatch with `412`.

Zero rows is a refusal with the current state: the price now, who leads, whether
it closed. The user decides again. Never retry with fresh values. Under
row-level security zero rows may also mean "not visible" — tell the two apart.

### 1.4 One clock

The deadline is checked against **one clock**: the database's `now()`, read in a
transaction opened on arrival. `now()` is the transaction's start, so a bid that
queued behind a hot row is judged by when it arrived, not when it got the lock.
Not `clock_timestamp()`, which would refuse it for having waited. Not the app's
own clock either: several instances compare times across NTP skew, at the
millisecond scale a last-second auction is decided on (DDIA ch. 8, "Unreliable
clocks"). Decide once whether exactly `ends_at` is in or out.

### 1.5 The rest of the aggregate

- Closing is a transition — `UPDATE … SET status = 'CLOSED' WHERE status =
  'OPEN'` — so a finaliser that runs twice closes once.
- Money is integer minor units with a currency.

## 2. The other forms of the one atomic write

- A row lock, `SELECT … FOR UPDATE`, and a recount under it.
- A unique constraint, the violation read as "somebody was first".
- `SERIALIZABLE`: Postgres aborts one of the conflicting transactions, sometimes
  needlessly. `40001` and a deadlock's `40P01` need **the whole transaction
  rerun by the application** — Spring does not retry by itself.
- An ORM bulk update (JPA `@Modifying`, Doctrine DQL `UPDATE`) returns the count
  but skips the persistence context, optimistic `@Version` and audit listeners
  such as Envers. On an audited entity, lock and write through the entity.

## 3. The outbox relay

- **Claim, lease, commit, then send.** `FOR UPDATE SKIP LOCKED`, push the row's
  `next_attempt_at` out as a lease, commit — never hold the lock across the
  network call.
- **Not an id high-water mark** — ids are taken in one order and committed in
  another, so `id > last_seen` skips rows, unless the mark is guarded by
  `pg_snapshot_xmin`.
- **Stop poison messages**: a maximum number of attempts, then a parked state
  somebody looks at.
- **Prune sent rows** after a retention period, or the claim query slows down.
- **Order is a decision.** Per aggregate, the relay sends one aggregate's
  messages one at a time; otherwise say the stream is unordered.
- **The receiver is an idempotent consumer**: an inbox table keyed by message id,
  written in the consumer's own transaction.
- Alternatives: log tailing (Debezium) instead of polling; in Spring, Spring
  Modulith's Event Publication Registry is an off-the-shelf outbox.

Sources: [transactional outbox](https://microservices.io/patterns/data/transactional-outbox.html),
[polling publisher](https://microservices.io/patterns/data/polling-publisher.html),
[idempotent consumer](https://microservices.io/patterns/communication-style/idempotent-consumer.html),
[Spring Modulith events](https://docs.spring.io/spring-modulith/reference/events.html).

## 4. Spring transaction events

- `@TransactionalEventListener(AFTER_COMMIT)` is a dual write: the event lives in
  memory, and a crash after the commit loses it.
- `BEFORE_COMMIT` runs inside the transaction; a `RuntimeException` there
  propagates and rolls the business transaction back — which is the atomicity an
  outbox write wants. A plain synchronous `@EventListener` gives the same, more
  simply.
- Without a running transaction a transactional listener is not called at all,
  unless `fallbackExecution = true`.

Sources: [transaction-bound events](https://docs.spring.io/spring-framework/reference/data-access/transaction/event.html),
[TransactionSynchronization](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/transaction/support/TransactionSynchronization.html).

## 5. A cache over it

- Cache-aside with delete-on-write: commit, then delete the key.
- The race that leaves: a reader loads the old value before the commit and
  stores it after the delete. Bound it with a TTL or a versioned key, or use
  leases, which refuse a stale set after a delete
  ([memcache at Facebook](https://www.usenix.org/system/files/conference/nsdi13/nsdi13-final170.pdf)).
- **Spring's `@CacheEvict` on a `@Transactional` method evicts before the
  commit**, reopening exactly that race. Wrap the manager in
  `TransactionAwareCacheManagerProxy`, or evict `AFTER_COMMIT`.

The `caching` skill carries the rest — keys, stampedes, local versus shared.

## Sources

[PostgreSQL, transaction isolation](https://www.postgresql.org/docs/current/transaction-iso.html)
(the `ON CONFLICT DO NOTHING` note is in the Read Committed section),
[date/time functions](https://www.postgresql.org/docs/current/functions-datetime.html),
[Stripe, idempotent requests](https://docs.stripe.com/api/idempotent_requests),
[Brandur Leach, idempotency keys](https://brandur.org/idempotency-keys),
[IETF Idempotency-Key draft](https://datatracker.ietf.org/doc/html/draft-ietf-httpapi-idempotency-key-header-07)
(expired, not a standard).
