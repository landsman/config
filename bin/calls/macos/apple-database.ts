// The one way into Apple's own databases, Calendar's and Contacts': read-only,
// one read at a time. They belong to the apps, which keep writing them while we
// read, so nothing here may ever change a byte in them. Contacts are added
// through the Contacts app instead (contacts.ts).
import { Database } from "bun:sqlite";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/** Opens the database read-only for one read, and answers `fallback` when it cannot be read:
 *  Apple's schema is undocumented, so a change to it reads as nothing, never as a failure. */
export function readAppleDatabase<Result>(
	databasePath: string,
	fallback: Result,
	read: (database: Database) => Result,
): Result {
	try {
		// readonly: SQLite itself refuses every write, whatever `read` tries.
		const database = new Database(databasePath, { readonly: true });
		try {
			return read(database);
		} finally {
			database.close();
		}
	} catch (error) {
		throwIfOurMistake(error);
		return fallback;
	}
}

/** A query from queries/, read once when the module loads. */
export function appleQuery(file: string): string {
	return readFileSync(join(import.meta.dir, "queries", file), "utf8");
}

/** A query given more or fewer values than it has placeholders is a bug in this code, not
 *  Apple changing the schema: it fails loudly instead of reading as nothing. */
export function throwIfOurMistake(error: unknown) {
	if (error instanceof Error && /expected \d+ values?, received \d+/.test(error.message)) {
		throw error;
	}
}
