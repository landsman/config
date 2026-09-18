---
name: postgres
description: Load before adding or changing a PostgreSQL index, diagnosing a slow query or an EXPLAIN plan, or writing a migration that alters a live table — whatever the stack or migration tool in front of it. Carries how to measure before indexing, why an index silently stops matching its query (expressions, IMMUTABLE, trigram, partial indexes), what each index costs, how to change a schema without locking production, and a review checklist.
---

# PostgreSQL

An index that no longer matches its query fails no test. The query just gets slower, and nobody notices until production data is large enough to hurt. So measure first, and leave something behind that fails when the index and the query drift apart.

## Measure before changing anything

- **`EXPLAIN (ANALYZE, BUFFERS)`** shows the real plan, the timing and the pages read. `ANALYZE` executes the statement, so an `UPDATE` or `DELETE` goes inside `BEGIN … ROLLBACK`.
- **Say whether the cache was warm or cold.** A warm run measures the ceiling of the buffer cache, not of the query, and the two can differ by an order of magnitude.
- **`pg_stat_statements`** (it needs `shared_preload_libraries`): sort by `total_exec_time` for the heavy queries and by `calls` for the N+1 ones.
- **`track_io_timing = on`** is cheap and tells I/O apart from CPU. **`auto_explain`** with `log_min_duration` samples slow plans in production.
- **Check where the time goes before indexing.** When the request is dominated by the application, the network or rendering, a perfect index changes nothing the user can see.

## An index serves the exact expression it was built on

- **Same expression, or no index.** `where lower(name) like …` does not use an index on `name`. Wrapping an already indexed column in a function silently turns an index scan into a full read.
- **Only IMMUTABLE functions can be indexed.** `unaccent(text)` is STABLE, so accent-insensitive search needs an IMMUTABLE wrapper, and then the index on `wrapper(lower(col))`, the whole expression the predicate builds. The wrapper is a promise: if its dictionary changes, reindex.
- **`like '%term%'` needs `pg_trgm`,** as `gin (lower(col) gin_trgm_ops)`. Under three characters there is no trigram to narrow by, so give the search a minimum length. A prefix `like 'term%'` can use a btree, but outside the C collation only with `text_pattern_ops`.
- **A partial index needs its predicate spelled out in the query.** An index built `where active` is used by `and active = true`, but not by `and active = :active`: once PostgreSQL switches to a generic plan, a parameter proves nothing.
- **`LIMIT` does not rescue a plan that has to sort first.** It still reads everything before it returns the first row. Deep `OFFSET` pages read every row they skip, so use keyset pagination (`where id > :last order by id`).
- **Leave a plan assertion behind.** A test that runs `EXPLAIN` under `set local enable_seqscan = off` and asserts the index name is the only thing that fails when the predicate and the index drift apart.

## Every index costs writes

- **Index the table that needs it, not every searchable column.** Each index is written on every insert and update, and a GIN trigram index is expensive to maintain through a bulk import. Measure the small tables first: a sequential scan over a few thousand rows is fast.
- **Drop duplicates.** An index with the same columns as a primary key or a unique constraint is redundant; keep the constraint's own index. `pg_index` finds them by comparing `indkey`, `indclass`, `indexprs` and `indpred`.
- **Foreign keys are not indexed automatically.** Index the ones joined on a hot path or behind an `ON DELETE` on a large child table. An audit column that is never joined stays unindexed.

## Changing a live schema

- **`CREATE INDEX` blocks writes to the table for its whole duration.** Use `CREATE INDEX CONCURRENTLY` / `DROP INDEX CONCURRENTLY`, which cannot run inside a transaction, so the migration tool has to run that step outside one. A failed concurrent build leaves an `INVALID` index behind; drop it and retry.
- **Set `lock_timeout` before DDL.** `ALTER TABLE` waits for an exclusive lock behind every long transaction, and all traffic queues behind it. A short timeout fails the migration instead of freezing the application.
- **Some changes rewrite the whole table.** `ADD COLUMN` with a constant default is instant since PostgreSQL 11, but a volatile default rewrites the table, and so does most `ALTER COLUMN … TYPE`.
- **Add constraints in two steps.** `ADD CONSTRAINT … NOT VALID`, then `VALIDATE CONSTRAINT`. The first step is instant, and the scan in the second no longer blocks writes.

## Review checklist

- Measured with `EXPLAIN (ANALYZE, BUFFERS)`, warm or cold stated, time confirmed to be in the database?
- Index built on the exact expression the query uses, with IMMUTABLE functions only?
- `like '%…%'` backed by trigram, with a minimum search length?
- Partial index predicate spelled out literally in the query?
- Keyset instead of deep `OFFSET`?
- A plan assertion test left behind?
- The index pays for its write cost, and duplicates nothing?
- Concurrent index builds outside a transaction, `lock_timeout` set, no accidental table rewrite?
