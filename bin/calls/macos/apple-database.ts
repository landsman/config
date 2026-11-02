// The one way into Apple's own databases, Calendar's and Contacts': read-only,
// one read at a time. They belong to the apps, which keep writing them while we
// read, so nothing here may ever change a byte in them. Contacts are added
// through the Contacts app instead (contacts.ts).
import { Database } from "bun:sqlite";

/** Opens the database read-only for one read, and answers `fallback` when it cannot be read:
 *  Apple's schema is undocumented, so a change to it reads as nothing, never as a failure. */
export function readAppleDatabase<Result>(
	databasePath: string,
	fallback: Result,
	read: (database: Database) => Result,
): Result {
	try {
		// readonly: SQLite itself refuses every write, whatever `read` tries.
		// strict: a :name the query uses and the code does not pass throws.
		const database = new Database(databasePath, { readonly: true, strict: true });
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

/** A query not given a value it names, or given the wrong number of `?` values, is a bug in
 *  this code, not Apple changing the schema: it fails loudly instead of reading as nothing.
 *  strict: true is what makes a missing named value throw rather than bind as NULL. */
export function throwIfOurMistake(error: unknown) {
	if (
		error instanceof Error &&
		/expected \d+ values?, received \d+|Missing parameter/.test(error.message)
	) {
		throw error;
	}
}
