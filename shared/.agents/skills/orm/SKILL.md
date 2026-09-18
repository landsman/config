---
name: orm
description: Load before writing or reviewing code that goes through Hibernate/JPA (Spring Data included) or Doctrine ORM (Symfony, Nette) — a repository method or query (native SQL included), an entity association or its fetch type, a list or paginated endpoint, a loop over entities, a serializer or template walking relations, an import or batch job. Carries the N+1, fetch-plan, pagination and batch-write traps, the bar for native SQL, the facts that changed between versions, and a review checklist.
---

# Hibernate and Doctrine

ORMs disguise expensive queries as property access. Because the code looks identical whether it runs one query or a thousand, reviews must target the query count, not just the code.

**Check the exact version first.** Hibernate 7.4 paginates collection fetches in SQL, and Doctrine 3.0 dropped `PARTIAL` and `clear(Entity::class)`. Verify resolved versions via `composer.lock`, `gradle dependencies`, or `mvn dependency:tree`, not memory.

## Count the queries first

"This is not N+1" is a measurable number. Prove it:

- **Hibernate:** `org.hibernate.SQL` at DEBUG, or `hibernate.generate_statistics=true` with `getStatistics().getPrepareStatementCount()` in tests.
- **Symfony:** Doctrine profiler, or `$client->enableProfiler()` and `getProfile()->getCollector('db')->getQueryCount()` in functional tests.
- **Nette:** Tracy Doctrine panel.
- **Running PostgreSQL:** `pg_stat_statements`. N+1 shows up in `calls`, as a statement run far more often than the endpoint behind it.

**Pin it with an N vs 2N test.** Seed N parents (each with >1 child) and count, then seed 2N and count again. Assert that the count did not grow, or grew only by a small constant slack. A fixed number breaks on every unrelated change, but a flat delta keeps holding. N+1 over a single row is 1 query and passes for the wrong reason.

**Then watch it fail.** Revert the fix and confirm the test goes red; a guard that never failed has proven nothing. A build cache can replay a stale pass, so force the rerun (Gradle: `--rerun`). Use the project's existing tools; avoid adding libraries just for this.

## Lazy in the mapping, explicit in the query

Mappings define what *can* load; queries define what *this use case* loads.

- **Map every association lazy.** JPA defaults `@ManyToOne`/`@OneToOne` to EAGER (a known misfeature); explicitly set `fetch = FetchType.LAZY`. Doctrine defaults to lazy; never add `fetch: 'EAGER'`. Mapped EAGERs fire universally, even when unused.
- **Fetch per query.** Hibernate: `join fetch` (JPQL/HQL) or `@EntityGraph` (Spring Data). Doctrine: `->leftJoin('o.items', 'i')->addSelect('i')` (`addSelect` turns a filter join into a fetch join).
- **EntityGraph types:** Spring Data's `@EntityGraph` defaults to `FETCH` (unmapped fields stay lazy). `LOAD` respects legacy mapped EAGERs. If everything is mapped lazy, they behave identically.
- **Batch fetching is a fallback, not a fix.** It turns N queries into N/size `IN (...)` queries. Hibernate: `hibernate.default_batch_fetch_size` or `@BatchSize`. Doctrine: `setFetchMode(..., FETCH_EAGER)`.
- **Batching is not N+1.** With batch fetching on, a child table that shows up a few times per page as `IN (...)` / `= ANY(?)` is the batching doing its job. Don't "fix" it with `@BatchSize`; the N vs 2N test tells the two apart.

N+1 hides where queries aren't visible: serializers (Jackson, API Platform), Twig/Latte loops (`{{ order.customer.name }}`), DTO mappers, or generated `toString`s. Ensure every touched association is explicitly fetched or batched.

**N+1 needs no association.** An explicit call per row does the same thing:
- **A lookup inside a loop or `map`.** A repository or service call per row. Collect the keys, send one `IN (:keys)` query (`findAllByIdIn`), and group in memory.
- **Loading all to find one.** A whole table (with its EAGERs) fetched to pick a row by id. Use a targeted query instead.
- **One child query per parent.** Query the whole subtree once and group by parent.

## One collection per query, no naive limits

Collection fetches multiply rows (1 order × 20 items = 20 SQL rows).

- **Never fetch two collections per query (Cartesian product).** Changing `List` to `Set` only silences Hibernate's `MultipleBagFetchException` without fixing the product. Fetch one collection in the query, batch-fetch the rest.
- **Hibernate before 7.4:** `setMaxResults` / Spring Data `Pageable` over a collection fetch pages in *memory* (warning `HHH90003004`). Set `hibernate.query.fail_on_pagination_over_collection_fetch=true` to fail fast. Fix: query IDs with a limit, then fetch entities `where id in :ids`.
- **Hibernate 7.4+:** Paginates collection fetches natively in SQL (except Sybase ASE). Never set the `hibernate.limitInMemory` hint.
- **Doctrine:** `setMaxResults` limits SQL rows, truncating fetch-joined collections. Use `Paginator` (counts, limits IDs via `DISTINCT`, then `WHERE IN`). `toIterable()` outright refuses fetch-joined collections.
- **Filter by a collection with `EXISTS`, not a join.** `where exists (select i from Item i where i.order = o and i.status = :s)` returns each parent once (Criteria: `cb.exists`). A join multiplies rows and then needs `DISTINCT`, `GROUP BY` or `count(distinct)`, which stops the database from walking an index in order to satisfy the `LIMIT`. On PostgreSQL, `count(distinct)` also cannot run as a parallel aggregate. Once the query yields one row per parent, count it with `count(*)`.

## Read-only means no entities

Read-only endpoints need no managed entities, dirty checking, or persistence context. Select directly into DTOs:

- Hibernate: `select new com.example.OrderRow(o.id, c.name)...` or Spring Data projections.
- Doctrine: `SELECT NEW App\Dto\OrderRow(...)`, `NEW NAMED`, or `getArrayResult()`.

Projections lack lazy associations, strictly preventing accidental N+1s later. This safety beats the raw speed gain.

**Partial entities are not DTOs.** Doctrine's `PARTIAL` returns managed entities with missing fields—flushes silently ignore them, and uninitialized associations look like nulls. Use DTOs instead.

## ORM queries, not native SQL

Default to the ORM's query language: Spring Data derived queries, `@Query` in JPQL/HQL, Criteria; Doctrine DQL or the QueryBuilder. It names entities and fields, not tables and columns:
- **Renames fail early.** Spring Data validates JPQL `@Query` at startup; native SQL breaks on its first call in production.
- **The mapping still applies.** Native SQL silently skips soft-delete and tenant filters (`@SQLRestriction`, `@Filter`, Doctrine SQL filters), converters and inheritance.

**Native SQL needs a measured performance reason** the ORM cannot meet after a fetch plan, a DTO projection, a bulk DQL/HQL statement and an index were tried. Current HQL has window functions, CTEs, `union` and `insert ... on conflict`, so check the installed version before assuming only SQL can do it.

Two things that look like reasons but aren't:
- **Bypassing a filter:** declare that in the mapping, not in a SQL string. Use a read-only `@Immutable` entity over the same table without the `@Filter`, so the exemption is visible in the model instead of taken on trust.
- **Infrastructure:** an advisory lock, a stored-procedure call or a table the framework owns (a session store, say) is not a query over entities. It goes through `JdbcTemplate` or the DBAL `Connection`, outside repository code, and never becomes the back door for ordinary queries.

If the project gates native SQL with a lint and a baseline, the baseline records history. It is never regenerated to make a new finding pass.

When it clears that bar, propose it; don't wait for approval:
- **Comment beside the query:** ORM cost vs native cost (measured on representative data), and what it gives up.
- **Call it out in the PR:** a section of its own with the query and the numbers, requesting review of that query specifically.

## Load inside the transaction

`LazyInitializationException` means a missing fetch found too late. Fix the originating query's fetch plan, and map the entity to a DTO **inside** the service transaction. The controller receives the DTO and never reads an entity. `@Transactional` belongs on the service, never on a controller, because annotating the controller only widens the transaction around the same lazy loads. These are **not** fixes:

- **`spring.jpa.open-in-view`:** Defers N+1 to serialization where tests miss it. Turn it off in new projects; disable carefully in legacy ones.
- **`hibernate.enable_lazy_load_no_trans`:** Unsafe. Opens a new connection/transaction for every lazy load.
- **Loop initialization:** Switching to EAGER or calling `.size()`/`Hibernate.initialize()` just executes the exact same N+1 earlier.

Doctrine's EntityManager lives per-request. Long-running processes (daemons, workers) grow the identity map and serve stale entities. Call `$em->clear()` manually if your worker (like Messenger) doesn't do it.

**A tenant or soft-delete filter lives on one session.** A Hibernate `@Filter` is enabled per Session, usually by an aspect:
- **No transaction means no filter.** Spring's shared `EntityManager` (`@PersistenceContext`) then opens a throwaway, unfiltered one, and the query returns every tenant's rows without an error. A filtered read requires an active transaction and fails loudly without one: `EntityManagerFactoryUtils.getTransactionalEntityManager(emf)` returns `null` there.
- **Inside a transaction there is no "other session".** The shared proxy and `getTransactionalEntityManager` resolve to the same Session, on any Hibernate version. A filter that goes missing there was disabled, or enabled outside the transaction.
- **The aspect that enables it runs inside the transaction.** Order it after the transaction advice, which in Spring means a higher `@Order` value than `@EnableTransactionManagement(order = …)`.
- **`disableFilter` lasts for the rest of the transaction,** not just one query. A helper that switches it off leaves it off for every later query of its caller. Declare the exemption in the mapping (a read-only entity) instead. Doctrine's `$em->getFilters()->disable()` does the same for the rest of the request.

## Batches: bounded memory, batched writes

Reading:
- **Stream growing tables.** Never `findAll()`/`getResult()`. Use Hibernate `getResultStream()`/`scroll()`, Doctrine `toIterable()`, or keyset pagination. Keep the stream up to the loop: `toList()`/`iterator_to_array()` negates the memory savings.
- **`flush()` and `clear()` every N rows**, or the context holds every entity forever. (Doctrine 3 `clear()` detaches all).
- **Reload detached entities.** After `clear()`, earlier objects detach. Re-attach via `getReference()` instead of reusing them, or Doctrine throws *A new entity was found...*.
- **Hibernate's `StatelessSession`** fits simple row-moving jobs without graph navigation perfectly.

Writing:
- **Hibernate requires explicit batching config:**
  - `hibernate.jdbc.batch_size` enables it.
  - `order_inserts` / `order_updates` group types to prevent batch breaking.
  - `GenerationType.IDENTITY` silently disables insert batching (`SEQUENCE` keeps it).
  - JDBC URLs need `rewriteBatchedStatements=true` (MySQL) or `reWriteBatchedInserts=true` (Postgres).
  - Verify via `org.hibernate.orm.jdbc.batch` TRACE logs.
- **Doctrine does not batch statements.** Every persist is a single `INSERT`. The "batch" is just the flush interval.
- **Set-based changes are single statements.** Bulk `UPDATE`/`DELETE` via DQL/HQL bypasses the persistence context. Loaded entities go stale and lifecycle callbacks don't run.
- **Commit per chunk.** A single job-wide transaction holds locks indefinitely and rolls back entirely on failure. Two jobs writing rows in different orders cause deadlocks (Hibernate's `order_updates` prevents this by sorting PKs).

## No generated `equals`, `hashCode` or `toString`

Lombok (`@Data`, `@ToString`, `@EqualsAndHashCode`) and Kotlin `data class` break entities:
- `toString` triggers lazy loads, turning log lines into queries.
- Bidirectional associations cause stack overflows.
- Mutable `hashCode`s (like auto-generated IDs) lose entities from `HashSet`s upon persistence.
Write them manually using natural keys or DB IDs, matching the project convention.

## A nullable column needs a nullable type
Production fails when fixtures omit NULLs:
- **Primitives throw on load:** Kotlin's `Int` (compiles to Java `int`) and PHP's typed `int` crash when reading DB NULLs.
- **Non-null references fail later:** Hibernate injects NULLs via reflection despite Kotlin's null-safety. The NPE happens far from the entity.
**Fix:** Match column nullability exactly (`Int?`, `String?`, `?int`).

## Kotlin entities
- **Proxying requires open classes:** `LAZY` degrades to eager on final classes. `kotlin("plugin.jpa")` only adds no-arg constructors. Add `allOpen` for `@Entity`, `@MappedSuperclass`, and `@Embeddable`.
- **Protect collections with `val`:** `val items: MutableList<Item> = mutableListOf()` forces `clear()`/`addAll()` over reassignment. Reassigning breaks Hibernate's tracking, causing `orphanRemoval` flush exceptions or full delete/insert cycles. In Java, omit the setter.

## Review checklist
- Measured statement count for multiple parent rows?
- Every `@ManyToOne`/`@OneToOne` explicitly `LAZY`? No `EAGER` added?
- All accessed associations (loops, serializers, templates) fetched or batched?
- No lookup per row inside a loop or `map`? Keys collected into one `IN` query?
- Collection pagination: Hibernate 7.4+, two queries, or Doctrine `Paginator`?
- Max ONE fetch-joined collection per query? Filtering by a collection via `EXISTS`, not a join plus `DISTINCT`?
- Read-only endpoints return DTOs/projections?
- No `PARTIAL` results flushed?
- Native SQL only with a measured reason, commented beside it and called out in the PR? Filter bypasses in the mapping, infrastructure SQL outside repositories?
- Entities mapped to DTOs inside the service transaction? No `@Transactional` and no entity reads in controllers?
- No `open-in-view`, `enable_lazy_load_no_trans`, or `EAGER` used as bandaids?
- Filtered reads inside a transaction, failing loudly without one? No `disableFilter` in a helper?
- Loops stream, flush, clear, and commit per chunk? Writes batched (no `IDENTITY`), or bulk DQL/HQL?
- No generated `equals`, `hashCode`, or `toString`?
- Nullable columns mapped to nullable types? Collections modified in place?
- An N vs 2N test pins the query count, and was seen failing without the fix?