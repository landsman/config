// Names for the attendees a calendar event knows only by address, which an
// invitation from outside often does. Looked up in Contacts first; otherwise
// guessed from the address, offered to edit, and offered to save to Contacts
// so the next call already knows them. Contacts is read from its own databases,
// read-only, and written through the Contacts app.
import { $ } from "bun";
import { Database } from "bun:sqlite";
import { readdirSync } from "node:fs";
import { homedir } from "node:os";
import { ask, hint, warn } from "@lib/term";

/** The attendees as names for whisper: an address becomes the name in Contacts,
 *  or on a terminal the one confirmed by me, or else the one guessed from it. */
export async function realNames(attendees: string[], books = addressBooks()): Promise<string[]> {
	const names: string[] = [], fresh: { name: string; email: string }[] = [];
	for (const a of new Set(attendees)) {
		if (!a.includes("@")) {
			names.push(a);
			continue;
		}
		const known = contactName(a, books);
		if (known) {
			names.push(known);
			continue;
		}
		const guess = guessName(a);
		const name = process.stdin.isTTY ? edited(await ask(`Name for ${a}`, guess ? `[Enter = ${guess}, - = skip]` : "[Enter = skip]"), guess) : guess;
		if (!name) continue;
		names.push(name);
		if (process.stdin.isTTY) fresh.push({ name, email: a });
	}
	if (fresh.length && ["y", "yes"].includes((await ask(`Save ${fresh.map((f) => f.name).join(", ")} to Contacts?`, "[y/N]")).toLowerCase())) {
		for (const f of fresh) await saveContact(f.name, f.email);
		hint(`Saved to Contacts: ${fresh.length}`);
	}
	return [...new Set(names)];
}

/** Every Contacts database on this Mac: the local one and one per account. */
function addressBooks(): string[] {
	const root = `${homedir()}/Library/Application Support/AddressBook`;
	const file = "AddressBook-v22.abcddb";
	try {
		return [`${root}/${file}`, ...readdirSync(`${root}/Sources`).map((s) => `${root}/Sources/${s}/${file}`)];
	} catch {
		return [];
	}
}

/** The name of the contact with this address. The schema is Apple's and undocumented,
 *  so a change to it reads as not found, and the name is asked for instead. */
export function contactName(email: string, books: string[]): string | undefined {
	for (const path of books) {
		try {
			const db = new Database(path, { readonly: true });
			try {
				const row = db.query<{ first: string | null; last: string | null }, [string]>(`
					SELECT r.ZFIRSTNAME AS first, r.ZLASTNAME AS last FROM ZABCDEMAILADDRESS e
					JOIN ZABCDRECORD r ON r.Z_PK = e.ZOWNER WHERE lower(e.ZADDRESS) = lower(?)`).get(email);
				const name = [row?.first, row?.last].filter(Boolean).join(" ").trim();
				if (name) return name;
			} finally {
				db.close();
			}
		} catch {}
	}
}

/** jan.novak@, jan_novak@ or jan-novak@ → Jan Novak; a single word such as info@ is no name. */
export function guessName(email: string): string | undefined {
	const words = email.split("@")[0].split(/[._-]+/).filter((w) => /^\p{L}+$/u.test(w));
	if (words.length < 2) return;
	return words.map((w) => w[0].toUpperCase() + w.slice(1).toLowerCase()).join(" ");
}

/** What I typed over the guess: Enter keeps it, "-" drops it, anything else replaces it. */
export const edited = (answer: string, guess?: string) => (answer === "-" ? undefined : answer || guess);

/** A new contact: the last word is the surname. Values go in as arguments, never into the script. */
async function saveContact(name: string, email: string) {
	const [last, ...first] = name.split(" ").reverse();
	const script = `on run argv
		tell application "Contacts"
			set p to make new person with properties {first name:item 1 of argv, last name:item 2 of argv}
			make new email at end of emails of p with properties {label:"work", value:item 3 of argv}
			save
		end tell
	end run`;
	const r = await $`osascript -e ${script} ${first.reverse().join(" ")} ${last} ${email}`.nothrow().quiet();
	if (r.exitCode) warn(`not saved to Contacts: ${name}, ${r.stderr.toString().trim()}`);
}
