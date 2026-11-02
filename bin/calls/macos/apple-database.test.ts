// What apple-database.ts would get wrong silently: a byte written into Calendar's
// or Contacts' own database, which the apps keep writing too — or a bug of ours
// read as Apple changing the schema, and so as "no event".
import { Database } from "bun:sqlite";
import { describe, expect, test } from "bun:test";
import { mkdtempSync, readdirSync, readFileSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { readAppleDatabase } from "@bin/calls/macos/apple-database";

async function personDatabase(): Promise<string> {
	const database = new Database(":memory:");
	database.run("CREATE TABLE person (name TEXT, email TEXT)");
	database.run("INSERT INTO person VALUES ('Jana Nováková', 'jana@example.com')");
	const path = join(mkdtempSync(join(tmpdir(), "apple-database-")), "People.sqlitedb");
	await Bun.write(path, database.serialize());
	return path;
}

describe("expected use", () => {
	test("a read answers what the query returns", async () => {
		const path = await personDatabase();
		const names = readAppleDatabase(path, [], (database) => {
			return database.query<{ name: string }, []>("SELECT name FROM person").all();
		});

		expect(names).toEqual([{ name: "Jana Nováková" }]);
	});
});

describe("bad input", () => {
	test("a write tried inside a read changes nothing on disk", async () => {
		const path = await personDatabase();
		const before = readFileSync(path);

		const answer = readAppleDatabase(path, "refused", (database) => {
			database.run("INSERT INTO person VALUES ('Intruder', 'no@example.com')");
			database.run("DELETE FROM person");
			database.run("DROP TABLE person");
			return "written";
		});

		expect(answer).toBe("refused");
		expect(readFileSync(path).equals(before)).toBe(true);
		const after = new Database(path, { readonly: true });
		expect(after.query("SELECT name FROM person").all()).toEqual([{ name: "Jana Nováková" }]);
		after.close();
	});

	test("a database that is not there is nothing, and is not created", () => {
		const path = join(mkdtempSync(join(tmpdir(), "apple-database-")), "Missing.sqlitedb");

		expect(readAppleDatabase(path, "nothing", () => "read")).toBe("nothing");
		expect(readdirSync(join(path, ".."))).toEqual([]);
	});

	test("a schema Apple changed reads as nothing", async () => {
		const path = await personDatabase();
		const answer = readAppleDatabase<unknown>(path, "nothing", (database) => {
			return database.query("SELECT column_apple_removed FROM person").all();
		});

		expect(answer).toBe("nothing");
	});

	test("a value the query names but the code leaves out is our bug, and fails loudly", async () => {
		const path = await personDatabase();
		const read = (values: Record<string, string>) => {
			return () => {
				return readAppleDatabase(path, [], (database) => {
					return database
						.query("SELECT name FROM person WHERE email = $email AND name = $name")
						.all(values);
				});
			};
		};

		expect(read({ email: "jana@example.com" })).toThrow('Missing parameter "name"');
		expect(read({})).toThrow('Missing parameter "email"');
	});

	test("no other code in bin/calls opens a database, so every read goes through here", () => {
		const callsFolder = join(import.meta.dir, "..");
		const sourceFiles = readdirSync(callsFolder, { recursive: true, encoding: "utf8" })
			.filter((path) => path.endsWith(".ts") && !path.endsWith(".test.ts"))
			.filter((path) => statSync(join(callsFolder, path)).isFile());
		const opening = sourceFiles.filter((path) => {
			const source = readFileSync(join(callsFolder, path), "utf8");
			return /new Database\(/.test(source);
		});

		expect(opening).toEqual(["macos/apple-database.ts"]);
	});
});
