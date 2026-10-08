# The database is the source of truth

**Nothing but the database may become the only record of something.** What the
business depends on — money, a decision, a fact somebody will ask about later — is
a committed row in the relational database, the single source of truth (the
system of record). Everything else is derived from it, and losing it costs latency
or a retry, never data.

The places that quietly become the record instead, a cache being only the best
known:

- **process memory** — a field on a singleton, a static or companion-object map,
  an executor's queue of work not yet run;
- **a session** — the HTTP or UI session, a half-filled form, a wizard's state;
- **the client** — local storage, a cookie, a token's claims, a hidden field;
- **the wire** — a message in a broker or a queue, an event between two services;
- **the local disk** — an upload or a generated file in a container that is
  replaced on the next deploy;
- **a log line or a metric** — retention deletes it, and nothing can query it
  as data;
- **a cache, a search index, a read model.**

A provider's record (a card processor, a bank) is theirs: ours mirrors it and is
reconciled against it, never assumed.

The test: wipe it and restart. Whatever is gone and cannot be rebuilt from the
database was the record.

## Two writers, one winner

Two people bid on an auction in its last second, and exactly one wins. The
database decides, in **one atomic write** — never read-then-write in the app, and
never a lock in a cache, a `synchronized` block or a concurrent map as the only
guard: a second instance has memory of its own.

The bid, worked through:

    POST /auctions/{id}/bids
    Idempotency-Key: <client-generated>
    If-Match: <auction version>              -- optional, see below
    { "amount": { "currency": "EUR", "minorUnits": 12345 } }

In one short transaction:

    INSERT INTO bid_request (auction_id, key, body_hash) VALUES (…)
        ON CONFLICT DO NOTHING               -- 0 rows: a copy got here first
    UPDATE auction
       SET current_price = :amount, leading_bidder_id = :me, version = version + 1
     WHERE id = :id AND status = 'OPEN' AND ends_at > :receivedAt
       AND :amount >= current_price + min_increment
       AND seller_id <> :me
    -- then: store the outcome on bid_request, accepted or refused
    -- then: INSERT the immutable bid row and the outbox row; commit; answer

- **Claim the key before the update.** Looking it up first is not enough: two
  copies both find nothing, the second waits on the row lock, and Postgres then
  re-checks its `WHERE` against the first's committed price — 0 rows, a refusal
  for a bid that was accepted. With the claim, the copy waits on the uncommitted
  key, inserts nothing, and reads the stored outcome. Locking the auction row
  (`FOR UPDATE`) and looking the key up again under the lock works too.
- **The key has rules of its own.** Refusals are stored as outcomes too; the same
  key with a different body is rejected (`422`); a copy still in flight gets
  `409`; keys expire (Stripe keeps them 24 hours).
- **The condition is what the user agreed to.** A bid is an absolute amount, so
  it still stands when the price moved but the amount clears it. Add
  `AND version = :seenVersion` (the `If-Match`) only where the decision rested on
  the exact state shown — buying at a displayed price — and answer a mismatch
  with `412`.
- **Zero rows is a refusal with the current state** — the price now, who leads,
  whether it closed — and the user decides again. Never retry with fresh values:
  that commits an amount nobody agreed to. Under row-level security zero rows can
  also mean "not visible", so tell the two apart before answering.
- **Time is fixed once, at arrival** — the request's received instant as a
  parameter, or `now()` in a transaction that starts at receipt. Never a clock
  read after a lock wait: a bid that queued behind a hot row did not arrive late.
  Decide whether exactly `ends_at` is in or out.
- **Closing is a transition too** — `UPDATE … SET status = 'CLOSED' WHERE status
  = 'OPEN'` — so a finaliser that runs twice closes once.
- **Money is integer minor units with a currency**, never a float.

The other forms of the same write: a row lock (`SELECT … FOR UPDATE`) and a
recount under it; a unique constraint, the violation read as "somebody was
first"; `SERIALIZABLE`, where Postgres aborts one of the conflicting transactions
(sometimes needlessly) and the app reruns the whole transaction.

An ORM bulk update (JPA `@Modifying`, Doctrine DQL `UPDATE`) returns the count
but skips the persistence context, optimistic `@Version` and audit listeners
such as Envers. On an audited entity, lock and write through the entity instead.

## A message that must go out: transactional outbox

The domain change and the message it causes commit in **one local transaction**,
as domain rows plus an outbox row. A relay sends the outbox afterwards, at least
once, and the receiver deduplicates by the message id.

- **The relay claims rows by status**, `FOR UPDATE SKIP LOCKED`, never by
  "ids above the last one seen": ids are taken in one order and committed in
  another, so a high-water mark skips rows.
- **Order is a decision.** If receivers need it per aggregate, the relay sends
  one aggregate's messages one at a time; otherwise say the stream is unordered.

Never a dual write — commit, then call the broker or an HTTP endpoint. A crash, a
deploy or a timeout between the two loses the message, and nothing knows it was
owed. An after-commit listener (`@TransactionalEventListener(AFTER_COMMIT)`,
Doctrine's `postFlush`) is that dual write: fine for best effort, wrong for
anything someone else's books rely on. A `BEFORE_COMMIT` listener that writes the
outbox row keeps the decoupling inside the transaction. Without a transaction
running, a Spring transactional listener is not called at all unless
`fallbackExecution = true`.

## A cache on top

- Commit to the database, then evict — and bound with a TTL or a versioned key
  what is left when a reader loaded the old value before the commit and stores
  it after the evict.
- Money and permissions are read inside the transaction that acts on them, never
  from a cache.
- A tenant's id is part of the key; row-level security does not reach a cache.

The `caching` skill carries the rest — keys, invalidation, stampedes.

Sources: [PostgreSQL, transaction isolation](https://www.postgresql.org/docs/current/transaction-iso.html),
[date/time functions](https://www.postgresql.org/docs/current/functions-datetime.html),
[Spring, transaction-bound events](https://docs.spring.io/spring-framework/reference/data-access/transaction/event.html),
[transactional outbox](https://microservices.io/patterns/data/transactional-outbox.html),
[Stripe, idempotent requests](https://docs.stripe.com/api/idempotent_requests),
[IETF Idempotency-Key draft](https://datatracker.ietf.org/doc/html/draft-ietf-httpapi-idempotency-key-header-07)
(an expired draft, not a standard).
