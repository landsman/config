---
name: orm
description: Load before writing or reviewing code that goes through Hibernate/JPA (Spring Data included) or Doctrine ORM (Symfony, Nette) — a repository method or query, an entity association or its fetch type, a list or paginated endpoint, a loop over entities, a serializer or template walking relations, an import or batch job. Carries the N+1, fetch-plan, pagination and batch-write traps, the facts that changed between versions, and a review checklist.
---

# Hibernate and Doctrine

Both ORMs make the expensive thing look like a property access. The code reads
the same whether it runs one query or a thousand, so what gets reviewed is the
query count, not the code.

**Read the version before trusting anything below.** Two of these answers
changed in a release: Hibernate 7.4 paginates a collection fetch in SQL, and
Doctrine 3.0 removed `PARTIAL` and `clear(Entity::class)`. Take it from
`composer.lock`, `gradle dependencies` or `mvn dependency:tree` — the version
Spring Boot or Symfony actually resolves, not the one remembered.

## Count the queries first

"This is not N+1" is a number, and the method has to be one that can disagree:

- **Hibernate:** `org.hibernate.SQL` at DEBUG prints every statement;
  `hibernate.generate_statistics=true` and
  `getStatistics().getPrepareStatementCount()` count them in a test.
- **Symfony:** the profiler's Doctrine panel; a functional test reads the same
  number through `$client->enableProfiler()` and
  `getProfile()->getCollector('db')->getQueryCount()`.
- **Nette:** the Tracy Doctrine panel, where the project wires one.

Seed more than one parent, each with more than one child. N+1 over a single row
is one query, and the test passes for the wrong reason.

A test that pins the count is what keeps a fix fixed. Use what the project
already has for it; a new library is a question, not a side effect.

## Lazy in the mapping, explicit in the query

The mapping says what *can* be loaded; the query says what this use case loads.

- **Every association lazy.** JPA defaults `@ManyToOne` and `@OneToOne` to
  EAGER — Hibernate's own guide calls it a misfeature — so every one of them
  says `fetch = FetchType.LAZY` out loud. Doctrine is lazy by default; keep
  `fetch: 'EAGER'` out of the mapping. EAGER in a mapping fires on every load
  of that entity, for every use case, including the ones that never read it.
- **Fetch per query.** Hibernate: `join fetch` in JPQL/HQL, `@EntityGraph` on a
  Spring Data method. Doctrine: `->leftJoin('o.items', 'i')->addSelect('i')` —
  the `addSelect` is what makes it a fetch join; without it the join only
  filters.
- **Batch fetching is the fallback, not the fix.** It turns N lazy loads into
  N/size `IN (...)` queries. Hibernate: `hibernate.default_batch_fetch_size`
  globally or `@BatchSize` per association, both off by default. Doctrine:
  `$query->setFetchMode(Order::class, 'customer', ClassMetadata::FETCH_EAGER)`
  does it for a to-one on one query.

N+1 hides where no query is written: a serializer (Jackson, Symfony Serializer,
API Platform) walking the graph, `{{ order.customer.name }}` inside a Twig or
Latte loop, a mapper copying an association into a DTO, a generated `toString`.
Every association the code path touches is either fetched by the query or
covered by batch fetching.

## One collection per query, and no naive limit on it

A collection fetch multiplies rows: an order with 20 items is 20 rows.

- **Two collections in one query is a Cartesian product.** Hibernate refuses two
  `List`s with `MultipleBagFetchException`; changing them to `Set` silences the
  exception and keeps the product. Fetch one collection per query, and the next
  one by batch fetching or a query of its own.
- **Hibernate before 7.4:** `setMaxResults`, or a Spring Data `Pageable`, on a
  query with a collection `join fetch` or `@EntityGraph` loads the *whole*
  result and pages it in memory, with only a warning (`HHH90003004`, `HHH000104`
  on 5.x). Set `hibernate.query.fail_on_pagination_over_collection_fetch=true`
  so it throws instead, and page in two queries: the ids with the limit, then
  the entities `where id in :ids` with the fetch.
- **Hibernate 7.4 and later** apply that limit in SQL on every supported database
  but Sybase ASE, so the two-query dance is not needed there. The
  `org.hibernate.limitInMemory` hint brings the old behaviour back; never set it.
- **Doctrine:** `setMaxResults` counts SQL rows, not entities, so a fetch-joined
  page comes back short. Use `Doctrine\ORM\Tools\Pagination\Paginator`, which
  runs a count, a `DISTINCT` id query with the limit, and a `WHERE IN` for the
  page. `toIterable()` refuses a fetch-joined collection outright.

## Read-only means no entities

An endpoint that only returns data needs no managed entities, no dirty checking
and no persistence context. Select the columns into a DTO:

- Hibernate: `select new com.example.OrderRow(o.id, c.name) from Order o join o.customer c`,
  or a Spring Data interface or record projection.
- Doctrine: `SELECT NEW App\Dto\OrderRow(o.id, c.name) FROM ...`, `NEW NAMED` to
  match by argument name, `getArrayResult()` when a class is overkill.

A projection has no lazy associations, so it cannot turn into N+1 later. That
matters more than the speed.

**A partial entity is not a DTO.** Doctrine's `PARTIAL` (removed in 3.0, allowed
again in later 3.x) returns a *managed* entity with fields missing: changes to
them are silently not written on flush, and a null association cannot be told
apart from one that was never loaded. Never flush one. If only some fields are
needed, that is a DTO.

## Load inside the transaction

Hibernate's `LazyInitializationException` is a missing fetch, found late. The fix
is the fetch plan of the query that loaded the entity. None of these is a fix:

- **`spring.jpa.open-in-view`.** Spring Boot defaults it to `true` and warns about
  it at startup. It keeps the session open through rendering, so the lazy loads
  move into serialisation as N+1 that no service test counts. Set it to `false`
  in a new project. In an existing one, turning it off breaks whatever depended
  on it, so it is a change of its own and never a side effect.
- **`hibernate.enable_lazy_load_no_trans`**, which the user guide marks unsafe:
  every lazy load gets its own session and transaction.
- **Switching the association to EAGER**, or calling `.size()` or
  `Hibernate.initialize()` in a loop. Either way it is the same N+1, only earlier.

Doctrine's EntityManager lives for the whole request, so there the failure is
the reverse: a long-running process whose identity map grows and serves stale
entities. Messenger clears it after each message; a hand-written worker loop or
a daemon command has to do it itself.

## Batches: bounded memory, batched writes

An import, a sync, an export or a migration script runs against production row
counts, not the fixture's.

Reading:

- **Never `findAll()` or `getResult()` over a table that grows.** Stream it —
  Hibernate `getResultStream()` or `scroll()`, Doctrine `toIterable()` — or walk
  keyset pages (`where id > :last order by id`).
- **`flush()` and `clear()` every N rows**, or the persistence context keeps
  every entity it has ever seen. In Doctrine 3 `clear()` takes no argument and
  detaches everything.
- **After `clear()` every earlier object is detached.** Re-attach by id with
  `getReference()` rather than reusing it. In Doctrine, a detached entity put
  into a new association fails the flush with *A new entity was found through
  the relationship*.
- Hibernate's `StatelessSession` has no persistence context at all, which fits a
  job that moves rows without navigating the graph.

Writing:

- **Hibernate batches no statements until `hibernate.jdbc.batch_size` is set.**
  Add `hibernate.order_inserts` and `hibernate.order_updates` so interleaved
  entity types still batch. `GenerationType.IDENTITY` turns insert batching off
  without a word; `SEQUENCE` with a pooled optimizer keeps it. Check the TRACE
  output of `org.hibernate.orm.jdbc.batch` rather than the config. On MySQL,
  the driver also needs `rewriteBatchedStatements=true` in the URL; on
  PostgreSQL, `reWriteBatchedInserts=true`.
- **Doctrine has no statement batching.** Every persisted entity is its own
  `INSERT` on flush; the batch is the flush interval, not a setting.
- **A set-based change is one statement.** Updating or deleting rows by a
  condition is a DQL/HQL `UPDATE` or `DELETE`, not a loop of loads. It bypasses
  the persistence context: entities already loaded go stale, and listeners and
  lifecycle callbacks do not run. Decide whether that matters before choosing it.

## Kotlin entities

- **A final class cannot be proxied**, so a `LAZY` to-one pointing at a Kotlin
  entity quietly loads eagerly. `kotlin("plugin.jpa")` only adds no-arg
  constructors. The classes need `allOpen` on `jakarta.persistence.Entity`,
  `MappedSuperclass` and `Embeddable`.
- **No `data class` entities**, and no Lombok `@Data` in Java for the same
  reason: the generated `toString` loads lazy collections, a bidirectional pair
  recurses until the stack overflows, and a `hashCode` over the id changes on
  persist, which loses the entity from a `HashSet`.

## Review checklist

- How many statements does this request run with several parent rows — measured,
  not guessed?
- Is every `@ManyToOne` / `@OneToOne` explicitly `LAZY`, and was no `EAGER`
  added to a mapping?
- Is every association that this path touches — in a loop, a serializer, a
  template, a mapper — fetched by the query or covered by batch fetching?
- Where a collection fetch and a limit meet: is it Hibernate 7.4+, two queries,
  or Doctrine's `Paginator`?
- Is at most one collection fetch-joined per query?
- Does a read-only endpoint return a DTO or a projection, not entities?
- Does no `PARTIAL` result reach a flush?
- Was no `open-in-view`, `enable_lazy_load_no_trans` or `EAGER` added to make a
  `LazyInitializationException` go away?
- Does a loop over a table stream, flush and clear? Do its writes batch (no
  `IDENTITY` in the way), or are they one DQL/HQL statement?
- Does a test pin the statement count?
