---
name: java
description: Load before writing, moving or reviewing Java code: a lookup by a value a person typed or pasted (an IBAN, an e-mail, a code), a string normalised or compared, a regex, a date or time parsed from JSON, a record bound by Jackson, an enum or a switch over one, an amount of money, a convenience wrapper over a class, nullability, or a unit test. Carries Unicode spaces that `\s` misses and writing them as escapes, `Locale.ROOT`, what a null result may mean, check digits, refusing an ambiguous match, parsing "date or date-time", records that fail at the boundary, enums inside and outside, money as minor units read exactly from a decimal, where the logic of a wrapper lives, secrets in `toString`, and what a test has to prove. Formatting, Error Prone and NullAway are the build's; this is what they cannot see.
trigger-keywords: java, javy, javě, .java, iban, nbsp
---

# Java

What the formatter, Error Prone and NullAway do not catch. Kotlin has its own
skill (`kotlin`), and so do Spring, JPA and SQL (`spring-boot`, `orm`,
`postgres`).

## Text a person typed

- **`\s` is ASCII only.** A value copied from a PDF, a web page or a banking UI
  carries a no-break space (U+00A0), a narrow one (U+202F), and from a web page
  a zero-width space (U+200B) or a byte-order mark (U+FEFF). `\s` keeps all of
  them, and `Character.isWhitespace` or `isSpaceChar` still keep the last two:
  the lookup finds nothing.
- **An identifier made of letters and digits keeps only those.** An IBAN, a
  postcode, a code: `c < 128 && Character.isLetterOrDigit(c)` drops every
  separator at once, zero-width ones, dashes and dots included. Free text
  strips the spaces only and says in its javadoc which ones.
- **Such a character in source or a test is an escape, `"\u00A0"`, never the
  character itself.** A raw one reads as a plain space in review, grep cannot
  find it, and an editor that normalises whitespace replaces it silently. The
  localisation rule against escapes is about translation files; here the code
  point is the point. The test feeds `"\u00A0"`, `"\u202F"`, `"\u200B"`,
  `"\uFEFF"` and a tab, not just a space.
- **`toUpperCase` and `toLowerCase` take `Locale.ROOT`.** Without it a Turkish
  default locale turns `i` into `İ`, and an identifier stops matching itself.
- **No regex where a loop over code points does it.** `replaceAll`, `matches`
  and a `split` with a real regex compile their pattern on every call; when one
  is needed, it is a `private static final Pattern`. A `split` on one plain
  character (`split(",")`) compiles nothing and stays as it is.

## A lookup

- **Null means one thing: not found.** A caller reads it as an answer ("the
  token no longer sees this account") and acts on it. So input that cannot match
  anything, blank once normalised, is an `IllegalArgumentException`, never a
  null that looks like a revoked account.
- **A key that can match twice refuses rather than guesses.** One IBAN can list
  one account per currency; returning the first reads the wrong currency
  without an error. More than one match is an `IllegalStateException` that names
  the candidates and says how to pick one.
- **A key with a check digit is validated before the lookup.** An IBAN's
  mod 97, a card's Luhn: a typo then is an `IllegalArgumentException`, not a
  null that reads as "not found". Blank is the same case, not the only one.
- **The name says which string it takes** when overloads sit side by side:
  `accountByIban(token, iban)` next to `transactions(token, accountId)`, never
  `account(token, iban)`, where an id passed by mistake returns null.
- **A wrapper delegates; the logic lives in the class it wraps.** A convenience
  type (a holder with a token bound, a facade) only forwards, with the javadoc
  `As {@link Client#method(...)}`. Logic written only on the wrapper is out of
  reach for a caller using the class directly, who then copies it.

## Data from outside

- **A JSON record checks what it requires in its compact constructor**
  (`requireNonNull(expiration, "expiration")`), so a missing field fails while
  parsing, not as a `NullPointerException` three calls later. Jackson wraps what
  the constructor throws in a `ValueInstantiationException`, so the one place
  that calls the mapper catches `JacksonException` and rethrows the library's
  own "unexpected response" exception; without that catch the check leaks
  Jackson's type. `@JsonProperty(required = true)` misses an explicit `null`, so
  the constructor check is the default.
- **A field documented as "date or date-time" is parsed as either.** Branch on
  whether the value holds a `T`: `OffsetDateTime.parse(value)` with one,
  `LocalDate.parse(value).atStartOfDay(zone).toOffsetDateTime()` without, the
  zone named (`ZoneId.of("Europe/Prague")`), never the JVM default.
  `atStartOfDay` gives a `ZonedDateTime`, hence the conversion. Parse, catch and
  parse again hides the one real failure, a value that is neither: that
  `DateTimeParseException` becomes the library's exception with the value in its
  message. Seeing only one form live does not make the other impossible.
- **An enum read from outside has a fallback constant** (`OTHER`) for values the
  code does not know yet, and its javadoc tells callers to keep a `default`
  branch. Jackson still throws on an unknown value unless the constant carries
  `@JsonEnumDefaultValue` and `READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE` is
  on (`EnumFeature` in Jackson 3), or the enum is mapped from the string by hand.
  Either way the raw string is kept beside it: `OTHER` alone loses what the API
  sent, the first thing someone debugging asks for. An enum the code owns is the opposite: a `switch` expression over it
  lists every constant and has no `default`, so a new constant fails to compile
  at every place that must decide what it means.

## Values

- **Money is `long` minor units with a currency**, as in `kotlin` and the
  source-of-truth rule. An API that sends decimals is read into a field typed
  `BigDecimal`, which Jackson reads exactly (`USE_BIG_DECIMAL_FOR_FLOATS` matters
  only for `Object`, `Map` or `JsonNode` targets), never `double`. It becomes
  minor units at that boundary, exactly:
  `amount.movePointRight(currency.getDefaultFractionDigits()).longValueExact()`,
  which throws on a third decimal instead of rounding it away. Two `BigDecimal`
  amounts compare with `compareTo`: `1` and `1.00` are not `equals`.
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
