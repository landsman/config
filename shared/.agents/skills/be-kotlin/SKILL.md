---
name: kotlin
description: Load before writing, moving or reviewing Kotlin code — a new file or class, an `enum class` or a `when` over one, a wrapper around an imported function, an amount of money, a property name passed as a string, or a unit test. Carries where a type goes (its own file or nested), how an enum is laid out, imports, the member that silently shadows an import, money as `Long`, property paths from references, and what gets a unit test. Formatting is ktlint's; this is what it cannot see.
trigger-keywords: kotlin, kotlinu, .kt, enum, enum class, enumy, when, ktlint, detekt
---

# Kotlin

What ktlint and detekt do not catch. Spring, JPA and SQL have their own skills
(`spring-boot`, `orm`, `postgres`).

## Files and types

- **One top-level type per file.** Sealed members nest inside their sealed
  interface; unrelated siblings get files of their own. detekt's
  `MultipleClassesInFile` enforces it where a project enables it.
- **A type read by more than one file gets its own file**, named for what it is
  — `PasswordChangeOutcome`, not `Outcome` nested in `PasswordChangeService`. A
  service's result that a view or a controller branches on is the usual case,
  and so is anything persisted or sent over an API. Nest it only when nothing
  outside the owning file names it. The test is a grep for the name outside that
  file; `MultipleClassesInFile` counts top-level types only, so it never catches
  a nested one read from another layer.
- **`import` at the top, never an inline fully qualified name** (`com.foo.Bar()`,
  `org.x.Y::class.java`). The only exception is two imports that collide, where
  one is aliased or qualified.
- **No catch-all `Utils.kt` or `Extensions.kt`.** A helper lives with its owner.

## Enums

**One constant per line, never `enum class X { A, B, C }`.** A new value is then
a one-line diff, and each constant has room to say when it happens:

```kotlin
enum class PasswordChangeOutcome {
    CHANGED,

    /** The current password did not match. Counted as a guess. */
    WRONG_CURRENT,

    /** Too many wrong guesses; the right one is refused too, for a while. */
    TOO_MANY_ATTEMPTS,
}
```

- **A KDoc on every constant whose name does not say it all**, a blank line
  before each documented one, a trailing comma after the last.
- **A `when` over an enum lists every constant and has no `else`.** As an
  expression it then fails to compile when a constant is added, at every place
  that has to decide what the new one means; an `else` turns that into a silent
  default.
- **Persisted by name** (JPA `@Enumerated(EnumType.STRING)`, a JSON field): the
  constant's name is the stored value, and must match a database `CHECK (... IN
  (...))` exactly. A rename is a new constant plus a data migration, never an
  edit in place.

## A member that shadows an import

**Never name a wrapper after the function it wraps.** Inside a class a member
wins over an import, so

```kotlin
private fun notifyError(key: String) = notifyError(getTranslation(key))
```

calls itself, and the compiler says nothing: a `StackOverflowError` on the
first failure. Call the imported function directly, or give the wrapper its own
name (`showErrorKey`). A top-level function in the same package needs no
import, so a lint that looks for a shadowed import cannot see that case either.

## Values

- **Money is `Long` minor units with a currency**, `BIGINT` in the database.
  Never `.toInt()` an amount on the way anywhere: above `Int.MAX_VALUE` it
  silently wraps.
- **A property name passed as a string comes from a reference**:
  `Sort.by(Payment::createdAt.name)`, not `Sort.by("createdAt")`. A rename then
  breaks the build instead of a query at run time.

## Tests

- **Logic worth testing is a pure function**, in a companion or at top level:
  plain values in, a plain value out, no repository or clock behind it. The
  service calls it; a unit test calls it with no Spring context and no database.
- **One runnable check for every non-trivial piece** — a branch, a loop, a
  parser, a money or security path. Not a suite per function.
- **No mocking framework the project does not already use.**
- **Sample text in a test is English** — fixture values, payloads, anything an
  assertion compares — unless the test is about a translation. A failure message
  has to be readable by whoever debugs it.
