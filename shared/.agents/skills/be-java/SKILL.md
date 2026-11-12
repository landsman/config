---
name: java
description: Load before writing, moving or reviewing Java code: a lookup by a value a person typed or pasted (an IBAN, an e-mail, a code), a string normalised or compared, a regex, a date or time parsed from JSON, a record bound by Jackson, an enum or a switch over one, an amount of money, a convenience wrapper over a class, nullability, or a unit test. Carries Unicode spaces that `\s` misses, `Locale.ROOT`, what a null result may mean, refusing an ambiguous match, parsing "date or date-time", records that fail at the boundary, enums inside and outside, money as `BigDecimal` with a currency, where the logic of a wrapper lives, secrets in `toString`, and what a test has to prove. Formatting, Error Prone and NullAway are the build's; this is what they cannot see.
trigger-keywords: java, javy, javě, .java, iban, nbsp
---

# Java

What the formatter, Error Prone and NullAway do not catch. Kotlin has its own
skill (`kotlin`), and so do Spring, JPA and SQL (`spring-boot`, `orm`,
`postgres`).

## Text a person typed

- **`\s` is ASCII only.** A value copied from a PDF, a web page or a banking UI
  carries a no-break space (U+00A0) or a narrow one (U+202F), and `\s` keeps
  them: the lookup finds nothing. Drop every code point that is
  `Character.isWhitespace(c) || Character.isSpaceChar(c)`, or use `(?U)\s`.
  The test feeds it `" "`, `" "` and a tab, not just a space.
- **`toUpperCase` and `toLowerCase` take `Locale.ROOT`.** Without it a Turkish
  default locale turns `i` into `İ`, and an identifier stops matching itself.
- **Strip only what the format never contains.** Spaces in an IBAN are
  presentation; a dash is not part of one, so stripping it would hide a wrong
  value rather than match a right one. The javadoc says exactly what is
  ignored, and a test pins each kind.
- **No regex where a loop over code points does it.** `String.replaceAll`,
  `split` and `matches` compile their pattern on every call; when a regex is
  needed, it is a `private static final Pattern`.

## A lookup

- **Null means one thing: not found.** A caller reads it as an answer ("the
  token no longer sees this account") and acts on it. So input that cannot match
  anything, blank once normalised, is an `IllegalArgumentException`, never a
  null that looks like a revoked account.
- **A key that can match twice refuses rather than guesses.** One IBAN can list
  one account per currency; returning the first reads the wrong currency
  without an error. More than one match is an `IllegalStateException` that names
  the candidates and says how to pick one.
- **A wrapper delegates; the logic lives in the class it wraps.** A convenience
  type (a holder with a token bound, a facade) only forwards, with the javadoc
  `As {@link Client#method(...)}`. Logic written only on the wrapper is out of
  reach for a caller using the class directly, who then copies it.

## Data from outside

- **A JSON record checks what it requires in its compact constructor**
  (`requireNonNull(expiration, "expiration")`), so a missing field fails while
  parsing, as the library's own "unexpected response" exception, and not as a
  `NullPointerException` three calls later.
- **A field documented as "date or date-time" is parsed as either.**
  `OffsetDateTime.parse` for a value with an offset, `LocalDate.parse(...)
  .atStartOfDay(zone)` for a bare date, with the zone named
  (`ZoneId.of("Europe/Prague")`), never the JVM default. A
  `DateTimeParseException` becomes the library's exception with the value in its
  message. Seeing only one form live does not make the other impossible.
- **An enum read from outside has a fallback constant** (`OTHER`) for values the
  code does not know yet, and its javadoc tells callers to keep a `default`
  branch. An enum the code owns is the opposite: a `switch` expression over it
  lists every constant and has no `default`, so a new constant fails to compile
  at every place that must decide what it means.

## Values

- **Money is `BigDecimal` with a `Currency`**, never `double`. Jackson reads
  floats as `BigDecimal` (`USE_BIG_DECIMAL_FOR_FLOATS`), and amounts are
  compared with `compareTo`, since `1` and `1.00` are not `equals`. Stored, it is
  `long` minor units.
- **A record's generated `toString` prints every component.** A token, a raw
  payload, a person's name or account gets left out of an overridden one, so
  logging the object leaks nothing.
- **Catching `InterruptedException` restores the flag**
  (`Thread.currentThread().interrupt()`) before throwing on.

## Files and types

- **One top-level type per file**, and a type that more than one file reads gets
  its own file, named for what it is.
- **`import` at the top, never an inline fully qualified name**, except when two
  imports collide.
- **An enum has one constant per line**, a javadoc on each whose name does not
  say it all, so a new value is a one-line diff.

## Tests

- **Each finding fixed gets the test that fails without the fix.** A review
  comment about NBSP is answered by a test with an NBSP in it.
- **Edge inputs go in a `@ParameterizedTest`**: `""`, spaces, a lone NBSP, mixed
  case, two matches, none.
- **Logic worth testing is a plain method**: values in, a value out, no clock or
  network behind it, so a unit test needs no server.
- **No mocking library the project does not already use.** A local HTTP server
  (the JDK's `HttpServer`) answers fixed JSON better than a mocked client.
