// What contacts.ts would get wrong silently: a contact not found by an address
// written in other case, a guess made of a word that is no name, Enter or "-"
// read the wrong way, or an address left in whisper's prompt.
import { Database } from "bun:sqlite";
import { expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { contactName, edited, guessName, realNames } from "@bin/obs/contacts";

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
