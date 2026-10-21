# Spring Boot 4

Read when the project builds on Boot 4, or the task is an upgrade to it.

## What moved

Boot 4 is Spring Framework 7, Jakarta EE 11, Servlet 6.1, Jackson 3.

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

Within Boot 4:

- **4.1 removes what 4.0 deprecated.** Code that compiled on 4.0 with deprecation warnings may not compile on 4.1.
- **4.1 binds an `Optional` constructor parameter** of `@ConfigurationProperties` to `Optional.empty()`, not `null`.
- **4.1 Maven:** `-DskipTests` no longer skips AOT processing of tests; only `maven.test.skip` does.

An upgrade runs from the latest 3.5 with `spring-boot-properties-migrator` as a runtime dependency, which reports every renamed property at startup. Remove it before the release.

## Retry

Spring Framework 7 has retry in core, no extra dependency:

- **`@EnableResilientMethods`** on a `@Configuration` class; without it the annotations are ignored, silently.
- **`@Retryable`** from `org.springframework.resilience.annotation`, not `org.springframework.retry.annotation`.
- **`maxRetries` counts retries, not calls:** `maxRetries = 3` is up to four invocations. There is no `maxAttempts`.
- **Backoff is flat attributes** — `delay`, `multiplier`, `maxDelay`, `jitter` — no nested `@Backoff`.
- **There is no `@Recover`.** The caller catches the last exception.
- **`@ConcurrencyLimit(n)`** caps concurrent calls of a method.

## Nullability

- **`@NullMarked` on the package** in `package-info.java`; everything inside is non-null by default, and only the exceptions get `@Nullable`.
- **The position matters:** `List<@Nullable String>` is a list with null elements, `@Nullable List<String>` a list that may be null.
- **Annotations alone fail nothing.** NullAway with `JSpecifyMode` enforces them at compile time; Kotlin reads them as real nullability, so a Kotlin module may stop compiling after the upgrade.

## HTTP clients and API versions

- **An `@HttpExchange` interface is imported, not implemented:** `@ImportHttpServices(group = "billing", basePackages = …)`. No `HttpServiceProxyFactory` bean per client, no `@Component`.
- **Configuration per group** under `spring.http.serviceclient.<group>.*` (base URL, timeouts); defaults for every client under `spring.http.clients.*`.
- **Server-side API versions** are native: `spring.mvc.apiversion.*` and a `version` on the mapping, not a duplicated `/v2` controller.
