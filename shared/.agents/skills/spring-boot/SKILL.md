---
name: spring-boot
description: Load before writing, reviewing or upgrading Spring Boot code — a dependency or starter, a test with MockMvc or a mocked bean, Jackson customisation, a retry, nullability annotations, an HTTP client interface, a `@Transactional` boundary or after-commit listener, an error handler. Carries how to tell Boot 3 from Boot 4 before writing anything, the API that moved between them, and the transaction and error-handling traps that hold on every version.
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

## What moved in Boot 4

Boot 4 is Spring Framework 7, Jakarta EE 11, Servlet 6.1, Jackson 3. On Boot 3, none of this applies: write the left-hand side.

| Boot 3 | Boot 4 |
|--------|--------|
| `spring-boot-starter-web` | `spring-boot-starter-webmvc` (the old name is deprecated since 4.0, still resolves) |
| Flyway/Liquibase start from `flyway-core` / `liquibase-core` alone | needs `spring-boot-starter-flyway` / `spring-boot-starter-liquibase` — without it nothing auto-configures and the migrations do not run |
| `spring-boot-starter-aop` | `spring-boot-starter-aspectj` |
| `@MockBean`, `@SpyBean` | removed — `@MockitoBean`, `@MockitoSpyBean` (fields only, not in `@Configuration`) |
| `@SpringBootTest` with `RANDOM_PORT` gives `TestRestTemplate` | nothing is given: `@AutoConfigureMockMvc`, or `@AutoConfigureRestTestClient` for `RestTestClient` |
| `@WithMockUser` from `spring-security-test` | needs `spring-boot-starter-security-test` |
| `com.fasterxml.jackson.*` | `tools.jackson.*` — except annotations, which stay in `com.fasterxml.jackson.annotation` |
| an `ObjectMapper` bean replaces Boot's | declare a `JsonMapper` bean |
| `Jackson2ObjectMapperBuilderCustomizer`, `@JsonComponent`, `@JsonMixin` | `JsonMapperBuilderCustomizer`, `@JacksonComponent`, `@JacksonMixin` |
| `spring.jackson.read.*` / `write.*` | 4.0: `spring.jackson.json.read.*` / `write.*`; 4.1 adds `spring.jackson.read.*` / `write.*` back for the features every format shares |
| Spring Retry, version managed by Boot | core `@Retryable` (below); Spring Retry needs an explicit version |
| `org.springframework.lang.Nullable` | JSpecify `org.jspecify.annotations.Nullable` (below) |
| `spring.session.redis.*` | `spring.session.data.redis.*` |
| Undertow | removed, not Servlet 6.1 compatible |
| `hibernate-jpamodelgen` | `hibernate-processor` |

Within Boot 3 the minor matters too: `@MockitoBean` comes with Spring Framework 6.2, so from **Boot 3.4** it exists and `@MockBean` is deprecated — use `@MockitoBean` in new tests there. On 3.3 and older only `@MockBean` exists.

Within Boot 4:

- **4.1 removes what 4.0 deprecated.** Code that compiled on 4.0 with deprecation warnings may not compile on 4.1.
- **4.1 binds an `Optional` constructor parameter** of `@ConfigurationProperties` to `Optional.empty()`, not `null`.
- **4.1 Maven:** `-DskipTests` no longer skips AOT processing of tests; only `maven.test.skip` does.

An upgrade runs from the latest 3.5 with `spring-boot-properties-migrator` as a runtime dependency, which reports every renamed property at startup. Remove it before the release.

## Retry — Boot 4 only

Spring Framework 7 has retry in core, no extra dependency:

- **`@EnableResilientMethods`** on a `@Configuration` class; without it the annotations are ignored, silently.
- **`@Retryable`** from `org.springframework.resilience.annotation`, not `org.springframework.retry.annotation`.
- **`maxRetries` counts retries, not calls:** `maxRetries = 3` is up to four invocations. There is no `maxAttempts`.
- **Backoff is flat attributes** — `delay`, `multiplier`, `maxDelay`, `jitter` — no nested `@Backoff`.
- **There is no `@Recover`.** The caller catches the last exception.
- **`@ConcurrencyLimit(n)`** caps concurrent calls of a method.

On Boot 3 it is Spring Retry: `@EnableRetry`, `maxAttempts` (total calls), `@Backoff`, `@Recover`.

## Nullability — Boot 4 only

- **`@NullMarked` on the package** in `package-info.java`; everything inside is non-null by default, and only the exceptions get `@Nullable`.
- **The position matters:** `List<@Nullable String>` is a list with null elements, `@Nullable List<String>` a list that may be null.
- **Annotations alone fail nothing.** NullAway with `JSpecifyMode` enforces them at compile time; Kotlin reads them as real nullability, so a Kotlin module may stop compiling after the upgrade.

## HTTP clients and API versions — Boot 4 only

- **An `@HttpExchange` interface is imported, not implemented:** `@ImportHttpServices(group = "billing", basePackages = …)`. No `HttpServiceProxyFactory` bean per client, no `@Component`.
- **Configuration per group** under `spring.http.serviceclient.<group>.*` (base URL, timeouts); defaults for every client under `spring.http.clients.*`.
- **Server-side API versions** are native: `spring.mvc.apiversion.*` and a `version` on the mapping, not a duplicated `/v2` controller.

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
