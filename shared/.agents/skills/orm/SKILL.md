---
name: orm
description: Load before writing or reviewing code that goes through Hibernate/JPA (Spring Data included) or Doctrine ORM (Symfony, Nette) — a repository method or query, an entity association or its fetch type, a list or paginated endpoint, a loop over entities, a serializer or template walking relations, an import or batch job. Carries the N+1, fetch-plan, pagination and batch-write traps, the facts that changed between versions, and a review checklist.
---

# Hibernate and Doctrine

ORMs disguise expensive queries as property access. Because the code looks identical whether it runs one query or a thousand, reviews must target the query count, not just the code.

**Check the exact version first.** Hibernate 7.4 paginates collection fetches in SQL, and Doctrine 3.0 dropped `PARTIAL` and `clear(Entity::class)`. Verify resolved versions via `composer.lock`, `gradle dependencies`, or `mvn dependency:tree`, not memory.

## Count the queries first

"This is not N+1" is a measurable number. Prove it:

- **Hibernate:** `org.hibernate.SQL` at DEBUG, or `hibernate.generate_statistics=true` with `getStatistics().getPrepareStatementCount()` in tests.
- **Symfony:** Doctrine profiler, or `$client->enableProfiler()` and `getProfile()->getCollector('db')->getQueryCount()` in functional tests.
- **Nette:** Tracy Doctrine panel.

Always seed >1 parent with >1 child. N+1 on a single row yields 1 query, passing tests for the wrong reason. Pin the count in a test to prevent regressions using existing project tools; avoid adding libraries just for this.

## Lazy in the mapping, explicit in the query

Mappings define what *can* load; queries define what *this use case* loads.

- **Map every association lazy.** JPA defaults `@ManyToOne`/`@OneToOne` to EAGER (a known misfeature); explicitly set `fetch = FetchType.LAZY`. Doctrine defaults to lazy; never add `fetch: 'EAGER'`. Mapped EAGERs fire universally, even when unused.
- **Fetch per query.** Hibernate: `join fetch` (JPQL/HQL) or `@EntityGraph` (Spring Data). Doctrine: `->leftJoin('o.items', 'i')->addSelect('i')` (`addSelect` turns a filter join into a fetch join).
- **EntityGraph types:** Spring Data's `@EntityGraph` defaults to `FETCH` (unmapped fields stay lazy). `LOAD` respects legacy mapped EAGERs. If everything is mapped lazy, they behave identically.
- **Batch fetching is a fallback, not a fix.** It turns N queries into N/size `IN (...)` queries. Hibernate: `hibernate.default_batch_fetch_size` or `@BatchSize`. Doctrine: `setFetchMode(..., FETCH_EAGER)`.

N+1 hides where queries aren't visible: serializers (Jackson, API Platform), Twig/Latte loops (`{{ order.customer.name }}`), DTO mappers, or generated `toString`s. Ensure every touched association is explicitly fetched or batched.

## One collection per query, no naive limits

Collection fetches multiply rows (1 order × 20 items = 20 SQL rows).

- **Never fetch two collections per query (Cartesian product).** Changing `List` to `Set` only silences Hibernate's `MultipleBagFetchException` without fixing the product. Fetch one collection in the query, batch-fetch the rest.
- **Hibernate before 7.4:** `setMaxResults` / Spring Data `Pageable` over a collection fetch pages in *memory* (warning `HHH90003004`). Set `hibernate.query.fail_on_pagination_over_collection_fetch=true` to fail fast. Fix: query IDs with a limit, then fetch entities `where id in :ids`.
- **Hibernate 7.4+:** Paginates collection fetches natively in SQL (except Sybase ASE). Never set the `hibernate.limitInMemory` hint.
- **Doctrine:** `setMaxResults` limits SQL rows, truncating fetch-joined collections. Use `Paginator` (counts, limits IDs via `DISTINCT`, then `WHERE IN`). `toIterable()` outright refuses fetch-joined collections.

## Read-only means no entities

Read-only endpoints need no managed entities, dirty checking, or persistence context. Select directly into DTOs:

- Hibernate: `select new com.example.OrderRow(o.id, c.name)...` or Spring Data projections.
- Doctrine: `SELECT NEW App\Dto\OrderRow(...)`, `NEW NAMED`, or `getArrayResult()`.

Projections lack lazy associations, strictly preventing accidental N+1s later. This safety beats the raw speed gain.

**Partial entities are not DTOs.** Doctrine's `PARTIAL` returns managed entities with missing fields—flushes silently ignore them, and uninitialized associations look like nulls. Use DTOs instead.

## Load inside the transaction

`LazyInitializationException` means a missing fetch found too late. Fix the originating query's fetch plan. These are **not** fixes:

- **`spring.jpa.open-in-view`:** Defers N+1 to serialization where tests miss it. Turn it off in new projects; disable carefully in legacy ones.
- **`hibernate.enable_lazy_load_no_trans`:** Unsafe. Opens a new connection/transaction for every lazy load.
- **Loop initialization:** Switching to EAGER or calling `.size()`/`Hibernate.initialize()` just executes the exact same N+1 earlier.

Doctrine's EntityManager lives per-request. Long-running processes (daemons, workers) grow the identity map and serve stale entities. Call `$em->clear()` manually if your worker (like Messenger) doesn't do it.

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
- Collection pagination: Hibernate 7.4+, two queries, or Doctrine `Paginator`?
- Max ONE fetch-joined collection per query?
- Read-only endpoints return DTOs/projections?
- No `PARTIAL` results flushed?
- No `open-in-view`, `enable_lazy_load_no_trans`, or `EAGER` used as bandaids?
- Loops stream, flush, clear, and commit per chunk? Writes batched (no `IDENTITY`), or bulk DQL/HQL?
- No generated `equals`, `hashCode`, or `toString`?
- Nullable columns mapped to nullable types? Collections modified in place?
- Test pins the query count?