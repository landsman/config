---
name: spring-boot
description: Load before writing, reviewing or upgrading Spring Boot code — a dependency or starter, a test with MockMvc or a mocked bean, Jackson customisation, a retry, nullability annotations, an HTTP client interface, a `@Transactional` boundary or after-commit listener, an error handler. Carries how to tell Boot 3 from Boot 4 before writing anything, the API that moved between them (in boot-4.md), and the transaction and error-handling traps that hold on every version.
trigger-keywords: spring boot, spring-boot, springboot, @SpringBootTest, @MockBean, @MockitoBean, @Retryable, @TransactionalEventListener, jackson, jspecify, problemdetail*
---

# Spring Boot

## Read the version first

Boot 3 and Boot 4 are both in use, and code written for the wrong one either fails to compile or compiles against an API that is on its way out. Before writing anything, read the version the project actually builds with:

    ~/.agents/skills/spring-boot/boot-version.sh <project-dir>

It reads Maven (parent or BOM, `${property}` resolved) and Gradle (plugin, BOM, version catalog, `gradle.properties`) without running the build, and prints each declaration with its file. Exit 1 means no clean version is declared in the repo — a corporate parent, a convention plugin, or a build file it cannot read. Then ask the build, which resolves it (about a second on a small project, longer on a large one):

    ./mvnw -q -o dependency:list -DincludeArtifactIds=spring-boot -DoutputFile=/dev/stdout | grep -m1 spring-boot:jar
    ./gradlew -q dependencyInsight --dependency org.springframework.boot:spring-boot --configuration runtimeClasspath | grep -m1 spring-boot:

Drop `-o` when the dependencies were never downloaded.

- **Follow the project's version, never the newest.** A Boot 3 project gets Boot 3 code, even where Boot 4 has a nicer API. Upgrading is its own task, asked for, in its own diff.
- **Match what the module already does.** If it still uses Spring Retry or `org.springframework.lang.Nullable`, a new file does too, unless the task is the migration.
- Every fact below says which version it applies to. A fact without a version holds on both.

## Boot 4: read [boot-4.md](boot-4.md)

When the version is 4.x, or the task is an upgrade to it, read it before writing anything: the starters, test annotations, Jackson packages and properties that moved, and core retry, JSpecify nullability and `@HttpExchange` clients. On Boot 3 skip it, and keep the two things that differ inside 3.x:

- **`@MockitoBean` from Boot 3.4** (Spring Framework 6.2); `@MockBean` is deprecated there. On 3.3 and older only `@MockBean` exists.
- **Retry is Spring Retry**: `@EnableRetry`, `maxAttempts` (total calls), `@Backoff`, `@Recover`.

## Transactions — every version

- **A caught failure still rolls back.** An inner `REQUIRED` call that throws marks the shared transaction rollback-only; catching the exception does not clear it, and the outer commit throws `UnexpectedRollbackException`.
- **`REQUIRES_NEW` holds a second pooled connection** while the outer one waits. Under load that is how the pool runs dry.
- **A retry wraps the transaction, from another bean.** Retrying inside a transaction that already failed re-runs code in one marked rollback-only. The retrying method calls the `@Transactional` one on a different bean, and holds no transaction of its own.
- **The proxy is skipped** by a call on `this` and by a private method — for `@Transactional`, `@Retryable` and `@Cacheable` alike.
- **Checked exceptions commit** unless `rollbackFor` says otherwise.
- **`readOnly = true` is a hint**, not write protection and not routing to a replica.
- **`AFTER_COMMIT` is not delivery.** The listener is skipped when no transaction is active, a crash after the commit loses the event, and a database write from inside it needs `REQUIRES_NEW`. Required delivery is an outbox — see the `postgres` skill.

## Errors — every version

- **Keep the error contract the API already has.** Problem Details (`spring.mvc.problemdetails.enabled`) is for an API that uses it or a migration that was asked for.
- **`@RestControllerAdvice` does not see the security filter chain.** A 401 or 403 from a filter goes through `AuthenticationEntryPoint` and `AccessDeniedHandler`, which need the same format.
- **A 500 returns a generic message**; the exception goes to the log, never into the body.
