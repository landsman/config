---
name: liquibase
description: Load before writing, editing, reviewing or resolving a merge conflict in a Liquibase changelog or changeset — YAML, XML or formatted SQL, including `sqlFile` changes, labels and contexts. Carries what makes a changeset immutable, the traps that pass review as a pure addition (stolen attributes, split dollar-quoted bodies, moved files), environment filtering, and how to prove a changelog applies before it ships.
---

# Liquibase

A changeset that has run anywhere is history. Every trap below either rewrites that history or lets a broken changeset through review, because the diff looks harmless.

**Follow the project first.** Folder layout, file naming, changeset ids, labels and the lint it runs are already decided in the repo; read the last few changesets before writing one.

## An applied changeset is immutable

- **Its identity is `id` + `author` + file path, and its content is checksummed.** Editing an applied changeset fails validation on every database that ran it. The fix goes into a new changeset.
- **Never add `validCheckSum` to make an edit pass.** It hides from every environment that the changeset now does something else.
- **Moving or renaming a changelog file changes the identity.** Liquibase then re-runs everything in it, and fails on "already exists". Set `logicalFilePath` before moving it.
- **Views, functions and procedures** are the exception: one `create or replace` changeset with `runOnChange: true`, edited in place.
- **The author is a person**, taken from the git identity, not a placeholder shared by the whole team.

## Traps that look like a pure addition

- **Insert after the *last* line of the previous changeset.** In YAML, a changeset pasted between another one's `path:` and its trailing `splitStatements:` / `stripComments:` steals those attributes. Git shows only added lines, so nobody sees the old changeset lose anything. This happens most often while resolving a merge conflict, so re-read the neighbours after every one.
- **Dollar-quoted bodies need `splitStatements: false`.** Liquibase splits SQL at every `;` by default, which cuts a `do $$ … $$` block or a function body apart. The tag can be `$func$` or any other name, not only `$$`. The changeset then fails on the first database that has not run it yet.
- **`stripComments: false`** keeps a comment inside a string or a function body intact.

## One change, one transaction

- **PostgreSQL runs DDL inside the transaction**, so a failed changeset rolls back whole.
- **MySQL and MariaDB commit implicitly after every DDL statement.** A changeset with two DDL statements can fail halfway and cannot be re-run. Keep it to one statement per changeset there.
- **`create index concurrently` cannot run in a transaction**, so it needs `runInTransaction: false` on its own changeset.
- **A large data migration** updates in chunks rather than locking the table in one statement. It never shares a changeset with the DDL it depends on.
- **Rollback:** `sql` and `sqlFile` changes generate none. Write the `rollback` (`--rollback` in formatted SQL), or say the changeset is forward-only.

## Environments

- **Labels and contexts decide what runs where:** test data only locally, a data migration only where the legacy data exists.
- **Permanent DDL is never filtered.** A schema change hidden behind a label or context makes the schema differ between environments. Anything that moves data between them, an export or an import, fails on the missing column.
- **Seed and test data are idempotent** (`on conflict do nothing`), and never reach production through a missing filter.
- **A conditional change** uses `preConditions` with `onFail: MARK_RAN`, not a changeset that fails where it does not apply.

## Prove it applies

- **Apply the whole changelog to a throwaway database** (Testcontainers) in CI. That is the only thing that catches a changeset broken for a database that has not run it yet.
- **`update-sql`** previews what will actually execute.
- **Run the project's changelog lint** after every hand edit and every conflict resolution, if there is one.
- **An application stuck on "Waiting for changelog lock"** is usually a deploy that was killed mid-migration. Only once no other instance is migrating, `release-locks` frees it.

## Review checklist

- No applied changeset edited, no `validCheckSum` added, no changelog file moved without `logicalFilePath`?
- New changeset after the last line of the previous one, with the neighbours unchanged?
- `splitStatements: false` wherever a dollar-quoted body appears?
- One DDL statement per changeset on MySQL/MariaDB, concurrent indexes outside a transaction?
- Permanent DDL unfiltered, test data labelled and idempotent?
- Rollback written, or forward-only stated?
- Whole changelog applied to a fresh database in CI?
