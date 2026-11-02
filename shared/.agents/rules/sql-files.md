---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.kt"
  - "**/*.java"
  - "**/*.php"
  - "**/*.go"
  - "**/*.py"
  - "**/*.sql"
---

# SQL is a file

**SQL written by hand goes into a `.sql` file beside the code that runs it,
never into a string in the code, whatever the stack.** No standard tells an
editor that a string holds SQL: JetBrains wants a `// language=SQL` comment or
`@Language("SQL")`, Zed a `/* sql */`, VS Code an extension, and a tag such as
`sql\`` is read by some and not others. A `.sql` file is SQL in every editor:
highlighted, formatted, checked against the database in DataGrip, runnable
there as it is.

- **One query per file, in a `queries/` folder next to its caller**, named after
  what it returns: `queries/people-on-event.sql`, not `query3.sql`. It opens with
  a `--` line saying that.
- **Parameters are named, `:email`**, the form SQLite, PDO, Python's sqlite3,
  Spring's `NamedParameterJdbcTemplate` and DataGrip all read, bound by the
  driver from an object — the file then says what it takes, and a missing one is
  missed by name rather than by position. Loading from a file is no reason to
  build SQL by concatenating strings.
- **Read once, when the module or class loads**, by a short named helper:

  | Stack | Read with |
  |---|---|
  | Bun, Node | `readFileSync(join(import.meta.dir, "queries", file), "utf8")` |
  | Kotlin, Java | `src/main/resources/queries/`, `ClassPathResource("queries/$file").getContentAsString(UTF_8)` |
  | PHP | `file_get_contents(__DIR__ . "/queries/$file")` |
  | Go | `//go:embed queries/people-on-event.sql` on a `string` |

- **A test runs every query through its caller** against the schema it
  targets, so a renamed column or a placeholder nobody fills fails the build,
  not the first run. The file and the code that binds its values are apart now,
  and nothing else ties them.
- **A database another app owns is opened read-only, in one place.** One
  helper opens it, a test proves a write through it changes nothing on disk,
  and another that no other file opens a database. `bin/calls/macos/apple-database.ts`.
- **A missing value fails loudly.** A driver may read it as NULL and answer
  nothing: bun:sqlite does unless opened with `strict: true`, then it throws
  `Missing parameter "email"`. Never let a catch meant for something else swallow
  that, and type the values where the language can, as bun:sqlite's
  `query<Row, { email: string }>`.

**Not SQL written by hand:** a query builder or an ORM (jOOQ, Exposed,
Doctrine's DQL builder, Prisma), and a framework that only takes the query in
its own place — Spring Data's `@Query`, a Liquibase changeset, which is already
a file. Those stay as the framework wants them; IntelliJ reads `@Query` as SQL
on its own. A project that keeps native SQL out altogether keeps doing so: this
says where SQL goes once it is written, not that it should be.

The worked example is `bin/calls/macos/queries/` in this repo. For SQLite —
parameters, strict binding, another app's database — load the `sqlite` skill.
