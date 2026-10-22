---
name: kotlin-enums
description: Load before writing, moving or reviewing an `enum class` in Kotlin — a new one, a constant added to one, or a `when` that branches on one. Carries where the enum goes (its own file or nested in its owner), how it is laid out (one constant per line, a KDoc each, never a one-liner), and the `when` that makes a new constant a compile error.
trigger-keywords: enum, enum class, kotlin enum, enumy
---

# Enums in Kotlin

## Where it goes

1. **Used by more than one file: its own file**, named for what it is —
   `PasswordChangeOutcome`, not `Outcome` nested in `PasswordChangeService`. A
   service's result that a view or a controller branches on is the usual case,
   and so is anything persisted or sent over an API.
2. **Used only inside its owner: nested**, next to the code that uses it. A
   private state machine's states, a parser's token kinds.

The test is a grep for the name outside the owning file. One hit elsewhere moves
it out. `Owner.Outcome` read from another layer couples that layer to the
owner's class just to name a value, and the nested name (`Outcome`, `State`,
`Kind`) says nothing once it is imported on its own.

A one-type-per-file lint (detekt's `MultipleClassesInFile`) does not catch this:
it counts top-level types only, so a nested enum passes it.

## How it is laid out

**One constant per line, never `enum class X { A, B, C }`.** A new value is then
a one-line diff, not a rewrite of the whole line, and each constant has room to
say when it happens:

```kotlin
enum class PasswordChangeOutcome {
    CHANGED,

    /** The current password did not match. Counted as a guess. */
    WRONG_CURRENT,

    /** Too many wrong guesses; the right one is refused too, for a while. */
    TOO_MANY_ATTEMPTS,
}
```

- **A KDoc on every constant whose name does not say it all.** `CHANGED` needs
  none; `TOO_MANY_ATTEMPTS` needs the consequence a caller has to handle.
- **A trailing comma after the last constant**, so adding one touches one line.
- **A blank line between documented constants**, so the KDoc visibly belongs to
  the constant under it.

## Branching on it

**A `when` over an enum lists every constant and has no `else`.** Used as an
expression, it then fails to compile when a constant is added, at every place
that has to decide what the new one means. An `else` turns that compile error
into a silent default.

## Persisted

With JPA's `@Enumerated(EnumType.STRING)` the constant's name is the stored
value: renaming a constant breaks every row already written, and the name must
match the column's `CHECK (... IN (...))` list exactly. Rename by adding the new
constant and migrating the rows, never in place.
