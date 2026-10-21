// What contacts.ts would get wrong silently: a contact not found by an address
// written in other case, a guess made of a word that is no name, Enter or "-"
// read the wrong way, an address left in whisper's prompt, a contact saved
// without asking or with first and last name swapped — or Apple changing the
// schema of Contacts, which the code reads as "not found".
import { $ } from "bun";
import { Database } from "bun:sqlite";
import { expect, test } from "bun:test";
import { existsSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { addressBooks, contactName, contactScript, contactSql, edited, guessName, realNames, saveContact } from "@bin/obs/contacts";

async function book() {
	const db = new Database(":memory:");
	db.run("CREATE TABLE ZABCDRECORD (Z_PK INTEGER PRIMARY KEY, ZFIRSTNAME TEXT, ZLASTNAME TEXT)");
	db.run("CREATE TABLE ZABCDEMAILADDRESS (ZOWNER INTEGER, ZADDRESS TEXT)");
	db.run("INSERT INTO ZABCDRECORD VALUES (1, 'Jan', 'Purkrábek')");
	db.run("INSERT INTO ZABCDEMAILADDRESS VALUES (1, 'Jan.Purkrabek@example.com')");
	const path = join(mkdtempSync(join(tmpdir(), "contacts-")), "AddressBook-v22.abcddb");
	await Bun.write(path, db.serialize());
	return path;
}

test("a contact is found by its address, whatever the case, in any of the books", async () => {
	const books = ["/nonexistent.abcddb", await book()];
	expect(contactName("jan.purkrabek@example.com", books)).toBe("Jan Purkrábek");
	expect(contactName("petr@example.com", books)).toBeUndefined();
});

test("a name is guessed from first.last, first_last or first-last, never from one word", () => {
	expect(guessName("pavel.teichman@example.com")).toBe("Pavel Teichman");
	expect(guessName("JAN_NOVAK@example.com")).toBe("Jan Novak");
	expect(guessName("anna-marie.dvorak@example.com")).toBe("Anna Marie Dvorak");
	expect(guessName("info@example.com")).toBeUndefined();
	expect(guessName("jan.novak2@example.com")).toBeUndefined();
});

test("Enter keeps the guess, - drops it, anything typed replaces it", () => {
	expect(edited("", "Jan Novak")).toBe("Jan Novak");
	expect(edited("-", "Jan Novak")).toBeUndefined();
	expect(edited("Jan Novák", "Jan Novak")).toBe("Jan Novák");
	expect(edited("")).toBeUndefined();
});

test("without a terminal, an address becomes its contact, its guess, or nothing", async () =>
	expect(await realNames(["Michal Landsman", "jan.purkrabek@example.com", "pavel.teichman@example.com", "info@example.com"], [await book()]))
		.toEqual(["Michal Landsman", "Jan Purkrábek", "Pavel Teichman"]));

test("on a terminal each guess is offered, edited or skipped, and saved only on yes", async () => {
	const run = async (answers: string[]) => {
		const asked: string[] = [], saved: string[][] = [];
		const ask = async (q: string, hint: string) => (asked.push(`${q} ${hint}`), answers.shift() ?? "");
		const save = async (name: string, email: string) => void saved.push([name, email]);
		const names = await realNames(["Michal Landsman", "jan.purkrabek@example.com", "pavel.teichman@example.com", "eva.mala@example.com", "info@example.com"],
			[await book()], { tty: true, ask, save });
		return { names, asked, saved };
	};
	const yes = await run(["", "Eva Malá", "", "y"]);
	expect(yes.asked).toEqual([
		"Name for pavel.teichman@example.com [Enter = Pavel Teichman, - = skip]",
		"Name for eva.mala@example.com [Enter = Eva Mala, - = skip]",
		"Name for info@example.com [Enter = skip]",
		"Save Pavel Teichman, Eva Malá to Contacts? [y/N]",
	]);
	expect(yes.names).toEqual(["Michal Landsman", "Jan Purkrábek", "Pavel Teichman", "Eva Malá"]);
	expect(yes.saved).toEqual([["Pavel Teichman", "pavel.teichman@example.com"], ["Eva Malá", "eva.mala@example.com"]]);

	const no = await run(["-", "", "", ""]);
	expect(no.names).toEqual(["Michal Landsman", "Jan Purkrábek", "Eva Mala"]);
	expect(no.saved).toEqual([]);
});

test("a contact is saved with the last word as its surname, values as arguments", async () => {
	const calls: [string, string[]][] = [];
	await saveContact("Anna Marie Dvořák", "anna@example.com", async (script, args) => (calls.push([script, args]), ""));
	expect(calls).toEqual([[contactScript, ["Anna Marie", "Dvořák", "anna@example.com"]]]);
});

test.skipIf(!Bun.which("osacompile"))("the script that saves a contact compiles", async () => {
	const dir = mkdtempSync(join(tmpdir(), "contact-script-"));
	await Bun.write(`${dir}/save.applescript`, contactScript);
	expect((await $`osacompile -o ${dir}/save.scpt ${dir}/save.applescript`.nothrow().quiet()).exitCode).toBe(0);
});

// Only on a Mac with Contacts, and read-only: preparing a query checks every
// table and column it names against the real schema without reading a row.
const books = addressBooks().filter((b) => existsSync(b));
test.skipIf(!books.length)("the query still fits the schema of Contacts on this Mac", () => {
	for (const path of books) {
		const db = new Database(path, { readonly: true });
		try {
			expect(() => db.query(contactSql)).not.toThrow();
		} finally {
			db.close();
		}
	}
});
