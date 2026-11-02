---
name: sqlite
description: Load before writing a query against SQLite, opening a SQLite database from code (bun:sqlite, better-sqlite3, Python's sqlite3), reading another app's database such as Apple's Calendar or Contacts, or testing code that does. Carries how parameters are written and bound, the bun:sqlite strict mode that turns a missing value into an error, why a database another app owns is opened read-only through one helper and how a test proves it, what to catch and what to let through when the schema is not yours, and how to build a test database.
trigger-keywords: sqlite*, bun:sqlite, sqlitedb, better-sqlite3, sqlite3
---

# SQLite

A query that gets a value wrong in SQLite rarely fails: a missing value binds as
NULL and the query answers nothing, which reads as "no data", not as a bug. Most
of what follows exists to turn that silence into an error.

The query itself lives in a `.sql` file beside its caller, as the
[SQL is a file](../../rules/sql-files.md) rule says. The worked example is
`bin/calls/macos/` in the config repo: `apple-database.ts`, `queries/`, and their
tests.

## Parameters: `:name`, bound from an object

SQLite accepts `?`, `?NNN`, `:name`, `@name` and `$name`
([lang_expr.html#varparam](https://www.sqlite.org/lang_expr.html#varparam)).
Write `:name`: PDO, Python's sqlite3, Spring's `NamedParameterJdbcTemplate` and
DataGrip read the same form, so one `.sql` file looks alike in every stack. `$name`
is a Tcl-ism, and `$1` in Postgres means something else.

    -- The contact with this email address, whatever its case.
    SELECT person.ZFIRSTNAME AS firstName, person.ZLASTNAME AS lastName
    FROM ZABCDEMAILADDRESS email
    JOIN ZABCDRECORD person ON person.Z_PK = email.ZOWNER
    WHERE lower(email.ZADDRESS) = lower(:email);

Never build a query by concatenating values into it, even one read from a file.

## bun:sqlite: open with `strict: true`, type the values

Measured on Bun 1.4.3, a query with two parameters:

| Values passed | Without `strict` | With `strict: true`, named |
|---|---|---|
| all | the rows | the rows |
| one missing, positional | throws `expected 2 values, received 1` | — |
| none at all, positional | **binds NULL, answers `[]`** | — |
| one missing, named | — | throws `Missing parameter "name"` |
| none at all, named | — | throws `Missing parameter "email"` |
| one extra key | — | ignored |

So:

- **`new Database(path, { strict: true })`**, and named parameters. Strict also
  lets the object's keys go without the prefix: `{ email }` binds `:email`.
- **Type what each query takes**, so the call is checked where it is written:
  `database.query<Contact, { email: string }>(contactQuery).get({ email })`.
  The type cannot see the file; the tests below can.
- **One helper opens the database**, so the options are set in one place and not
  forgotten in the next file.

## A database another app owns: read-only, in one place

Calendar, Contacts, a browser's history: the app keeps writing the file while you
read it, and a byte changed by you is the app's data corrupted.

- **`readonly: true`** — SQLite then refuses every write, whatever the code tries.
  It also refuses to create a missing file, so a wrong path cannot leave an empty
  database where the app expects its own.
- **Only one function opens it** (`readAppleDatabase(path, fallback, read)`),
  closing it after each read.
- **A test proves it**: an `INSERT`, a `DELETE` and a `DROP TABLE` tried through
  the helper, then the file compared byte for byte with the one before. A second
  test fails when any other source file opens a database itself
  (`new Database(` outside the helper).
- **Add data through the app**, never through its file: Contacts through
  AppleScript, with the values as script arguments, never pasted into the script.

## A schema that is not yours: catch it, but not your own bugs

An undocumented schema changes under you with an OS update, so a read that fails
answers a fallback (no event, no name) instead of failing the whole program. That
catch must let one kind of error through: a value the code forgot to pass is a
bug in the code, and swallowed it reads exactly like "the app has no data".

    } catch (error) {
        throwIfOurMistake(error); // "Missing parameter", "expected N values, received M"
        return fallback;
    }

A test calls the helper with a missing value and expects it to throw.

## Tests

- **Build the test database in memory and write it to a file**, with only the
  tables and columns the query touches:

      const database = new Database(":memory:");
      database.run("CREATE TABLE person (name TEXT, email TEXT)");
      await Bun.write(path, database.serialize());

- **Run every query through the code that calls it**, so a renamed column or a
  parameter nobody passes fails the build.
- **Check the query against the real schema where there is one**, read-only, and
  skipped where the file is missing (CI): preparing a statement checks every
  table and column it names without reading a row.

      test.skipIf(!existsSync(calendarDatabase))("the queries still fit the schema", …)

  Opening another app's database may need the terminal to have Full Disk Access
  on macOS; without it SQLite answers `authorization denied`.
- **Group them** `describe("expected use")` and `describe("bad input")`: a broken
  file, a missing value, a folder for a file.

## Dates in an Apple database

Core Data stores time as seconds since 2001-01-01 UTC, not since 1970: add
`978_307_200` to get a Unix time. A repeating event's occurrence often carries no
time of its own; it takes its series' time of day on that day.
