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

    -- first: a bid with this (auction_id, request_id) exists → return its outcome
    UPDATE auction
       SET current_price = :amount, leading_bidder_id = :me, version = version + 1
     WHERE id = :id AND status = 'OPEN' AND ends_at > now()
       AND :amount >= current_price + min_increment
       AND seller_id <> :me
    -- then: INSERT the immutable bid row, UNIQUE (auction_id, request_id)
    -- then: INSERT the outbox row; commit; only now answer "accepted"

- **The condition is what the user agreed to.** A bid is an absolute amount, so
  it still stands when the price moved but the amount clears it. Add
  `AND version = :seenVersion` (the `If-Match`) only where the decision rested on
  the exact state shown — buying at a displayed price, approving a balance.
- **Zero rows is a refusal with the current state** — the price now, who leads,
  whether it closed — and the user decides again. Never retry with fresh values:
  that commits an amount nobody agreed to. A retry repeats the same check.
- **The idempotency key answers a timeout.** The client did not hear the answer
  and sends the same key again. It is looked up before the update — by then the
  price is the client's own bid and the check would refuse it — and the unique
  constraint catches two copies racing each other.
- **Time is the server's, inside the transaction**, and the boundary is decided
  once: is a bid at exactly `ends_at` in or out.
- **Closing is a transition too** — `UPDATE … SET status = 'CLOSED' WHERE status
  = 'OPEN'` — so a finaliser that runs twice closes once.
- **Money is integer minor units with a currency**, never a float.

The other forms of the same write: a row lock (`SELECT … FOR UPDATE`) in a short
transaction; a unique constraint, the violation read as "somebody was first";
`SERIALIZABLE`, where the database aborts the loser and the app reruns the same
check.

## A message that must go out: transactional outbox

The domain change and the message it causes commit in **one local transaction**,
as domain rows plus an outbox row. A relay sends the outbox afterwards, at least
once, and the receiver deduplicates by the message id.

Never a dual write — commit, then call the broker or an HTTP endpoint. A crash, a
deploy or a timeout between the two loses the message, and nothing knows it was
owed. An after-commit listener (`@TransactionalEventListener(AFTER_COMMIT)`,
Doctrine's `postFlush`) is that dual write: fine for best effort, wrong for
anything someone else's books rely on.

## A cache on top

- Commit to the database, then evict. A cache never holds a write the database
  has not committed.
- Money and permissions are read inside the transaction that acts on them, never
  from a cache.
- A tenant's id is part of the key; row-level security does not reach a cache.

The `caching` skill carries the rest — keys, invalidation, stampedes.
