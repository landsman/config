# The database is the source of truth

**Nothing but the database may become the only record of something.** What the
business depends on — money, a decision, a fact somebody will ask about later — is
a committed row in the relational database, the single source of truth (the
system of record). Everything else is derived from it, and losing it costs latency
or a retry, never data.

What quietly becomes the record instead: process memory (a singleton's field, a
static map, an executor's queue), a session or a half-filled form, the client
(local storage, a cookie, a token's claims), a message on the wire, a container's
disk, a log line or a metric, a cache, a search index, a read model. A provider's
record — a card processor, a bank — is theirs; ours mirrors and reconciles it.

The test: wipe it and restart. Whatever is gone and cannot be rebuilt from the
database was the record.

- **Two writers are decided by one atomic write in the database.** Two people bid
  in an auction's last second and exactly one wins: a conditional `UPDATE`, a
  row lock and a recount, a unique constraint, or `SERIALIZABLE` with a rerun.
  Never read-then-write in the app, and never a lock in a cache or in memory as
  the only guard — a second instance has memory of its own.
- **The condition is what the user agreed to**, and zero rows is a refusal that
  shows the current state — never a retry with values nobody agreed to. Under
  row-level security zero rows may also mean "not visible".
- **An idempotency key is claimed before the write**, not looked up: a lookup lets
  a racing copy refuse a bid that was accepted.
- **A message that must go out is an outbox row in the same transaction** as the
  change it reports. Commit-then-send is a dual write, and so is an after-commit
  listener (`@TransactionalEventListener(AFTER_COMMIT)`, Doctrine's `postFlush`):
  fine for best effort, wrong for anything someone else's books rely on.
- **A cache is evicted after the commit**, never decides money or permissions,
  and carries the tenant in its key — row-level security does not reach it.
- **Money is integer minor units with a currency.**

**Before designing any of these, open `contended-writes.md` in the `postgres`
skill** — the auction worked through in SQL, the isolation level it depends on,
the idempotency key's rules, one clock for a deadline, the outbox relay, Spring's
transaction events and the cache race.
