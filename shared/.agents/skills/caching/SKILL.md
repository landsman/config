---
name: caching
description: Load before adding, changing or reviewing an application-level cache — Spring `@Cacheable`/`@CacheEvict`, Caffeine, Redis, Symfony Cache — or when the proposed fix for a slow or repeated query is "cache it". Carries when a cache is justified, the key and invalidation traps (tenant leaks, stale data after a migration or deploy, self-invocation), local vs shared caches, and a review checklist.
---

# Application caches

A cache is a second copy of the data with a lifetime of its own. Making it fast is the easy part; every rule below is about keeping that copy correct.

## Fix the access pattern first

- **A per-row query is N+1, not a cache miss.** Batch it into one `IN (...)` query first.
- **Data constant for one request** is loaded once at the top and passed down, not cached.
- **Worth caching:** reference data identical for every request (codelists, locales, roles, permission policies) that is re-read per row or per request.

## Every cache names its invalidation

- **Runtime write path:** evict on every write (`@CacheEvict`, `$pool->deleteItem()`, tags). A write path added later without eviction serves stale data silently.
- **Changes only through a migration:** evict at startup, after the migrations ran.
- **Neither is known:** don't cache it. A TTL is a backstop, not the invalidation.

## The key is the whole input

A key built from the method arguments ignores everything the method reads implicitly: the current tenant, a session filter, the locale, the user's permissions. Two tenants calling with the same arguments get the same entry. That is a data leak, not a stale read.

- **Put the implicit input into the key:** a tenant id, or a locale through SpEL (`T(org.springframework.context.i18n.LocaleContextHolder).getLocale().toLanguageTag()`).
- **Data narrowed by a tenant filter** always carries the tenant in the key. If the key cannot express it, don't cache.

## Shared caches outlive the deploy

- **Redis survives restarts and deploys.** After a migration changes cached data, the old value keeps being served until the TTL runs out. Clear the affected caches on startup, after the migrations (Spring: a listener that runs after Liquibase/Flyway; Symfony: `cache:pool:clear` in the deploy).
- **An outage of the shared cache** degrades to a database read, not an error (Spring: a `CacheErrorHandler`).

## Local or shared

- **Local (Caffeine, in-process):** immutable data on a hot path, with no network round trip. Every replica holds its own copy, so it suits data that changes only with a deploy, because a deploy starts fresh processes.
- **Shared (Redis):** data that changes at runtime and must be evicted on every replica at once.
- **Spring Boot backs off.** A second `CacheManager` bean makes Boot drop its auto-configured one (`@ConditionalOnMissingBean`). Declare both explicitly and choose per method with `@Cacheable(cacheManager = "...")`.

## Cache values, not entities

- **A cached entity is detached:** its lazy associations throw, and it cannot be saved as-is.
- **A local cache hands out the same instance.** A caller that modifies it modifies the cache for everyone. Cache immutable DTOs or values.
- **Redis serialises the value.** A Hibernate proxy or lazy collection inside it either fails to serialise or loads the whole graph on the way in.

## Spring's proxy

`@Cacheable` and `@CacheEvict` are applied by a proxy, so a bean calling its own method skips the cache silently, and so does a private method. Put cached methods on a separate bean and call them from the outside.

## Make it visible

- **Log fills and evictions:** a cache nobody sees working is one nobody can debug.
- **Expose hit/miss metrics:** Spring Boot Actuator binds cache metrics through Micrometer. Caffeine records none until `recordStats()` is on.

## Review checklist

- Access pattern fixed first (no per-row query hidden behind a cache)?
- Invalidation named: eviction on every write, or a startup clear after migrations?
- Key includes tenant, locale and every other implicit input?
- Shared cache cleared after a migration, and falling back to the database on an outage?
- Local only for data that changes with a deploy?
- Cached values immutable DTOs, not entities?
- Cached method public, on another bean, called from outside?
- Fills, evictions and hit rate visible?
