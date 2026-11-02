// Names for the attendees a calendar event knows only by address, which an
// invitation from outside often does. Looked up in Contacts first; otherwise
// guessed from the address, offered to edit, and offered to save to Contacts
// so the next call already knows them. Contacts is read from its own databases,
// read-only, and written through the Contacts app.
import { $ } from "bun";
import { readdirSync } from "node:fs";
import { homedir } from "node:os";
import { readAppleDatabase } from "@bin/calls/macos/apple-database";
import contactQuery from "@bin/calls/macos/queries/contact-by-email.sql" with { type: "text" };
import saveContactScript from "@bin/calls/macos/save-contact.applescript" with { type: "file" };
import { ask, hint, warn } from "@lib/term";

type NewContact = { name: string; email: string };

/** The attendees as names for whisper: an address becomes the name in Contacts,
 *  or on a terminal the one confirmed by me, or else the one guessed from it. */
export async function realNames(
	attendees: string[],
	books = addressBooks(),
	terminal = { interactive: !!process.stdin.isTTY, ask, save: saveContact },
): Promise<string[]> {
	const names: string[] = [];
	const newContacts: NewContact[] = [];

	for (const attendee of new Set(attendees)) {
		if (!attendee.includes("@")) {
			names.push(attendee);
			continue;
		}
		const email = attendee;

		const known = contactName(email, books);
		if (known) {
			names.push(known);
			continue;
		}

		const guess = guessName(email);
		const name = terminal.interactive ? await askForName(email, guess, terminal.ask) : guess;
		if (!name) {
			continue;
		}
		names.push(name);
		if (terminal.interactive) {
			newContacts.push({ name, email });
		}
	}

	if (newContacts.length) {
		const who = newContacts.map((contact) => contact.name).join(", ");
		const answer = await terminal.ask(`Save ${who} to Contacts?`, "[y/N]");
		if (["y", "yes"].includes(answer.toLowerCase())) {
			for (const contact of newContacts) {
				await terminal.save(contact.name, contact.email);
			}
			hint(`Saved to Contacts: ${newContacts.length}`);
		}
	}

	return [...new Set(names)];
}

async function askForName(email: string, guess: string | undefined, askQuestion: typeof ask) {
	const choices = guess ? `[Enter = ${guess}, - = skip]` : "[Enter = skip]";
	const answer = await askQuestion(`Name for ${email}`, choices);
	return typedOverGuess(answer, guess);
}

/** Every Contacts database on this Mac: the local one and one per account. */
export function addressBooks(): string[] {
	const addressBookFolder = `${homedir()}/Library/Application Support/AddressBook`;
	const databaseFile = "AddressBook-v22.abcddb";
	try {
		const accounts = readdirSync(`${addressBookFolder}/Sources`);
		return [
			`${addressBookFolder}/${databaseFile}`,
			...accounts.map((account) => `${addressBookFolder}/Sources/${account}/${databaseFile}`),
		];
	} catch {
		return [];
	}
}

/** The name of the contact with this address. The schema is Apple's and undocumented,
 *  so a change to it reads as not found, and the name is asked for instead. */
export function contactName(email: string, books: string[]): string | undefined {
	for (const bookPath of books) {
		const name = readAppleDatabase(bookPath, undefined, (database) => {
			const contact = database
				.query<{ firstName: string | null; lastName: string | null }, { email: string }>(
					contactQuery,
				)
				.get({ email });
			return [contact?.firstName, contact?.lastName].filter(Boolean).join(" ").trim();
		});
		// A book that cannot be read, or has no such contact, is skipped; the next one may have it.
		if (name) {
			return name;
		}
	}
	return undefined;
}

/** jan.novak@, jan_novak@ or jan-novak@ → Jan Novak; a single word such as info@ is no name. */
export function guessName(email: string): string | undefined {
	const mailbox = email.split("@")[0];
	const words = mailbox.split(/[._-]+/).filter((word) => /^\p{L}+$/u.test(word));
	if (words.length < 2) {
		return undefined;
	}
	return words.map((word) => word[0].toUpperCase() + word.slice(1).toLowerCase()).join(" ");
}

/** What I typed over the guess: Enter keeps it, "-" drops it, anything else replaces it. */
export function typedOverGuess(answer: string, guess?: string): string | undefined {
	if (answer === "-") {
		return undefined;
	}
	return answer || guess;
}

/** A new contact: the last word is the surname. Values go in as arguments, never into the script. */
export async function saveContact(name: string, email: string, runScript = runAppleScript) {
	const words = name.split(" ");
	const lastName = words.pop() ?? "";
	const firstName = words.join(" ");
	const error = await runScript(saveContactScript, [firstName, lastName, email]);
	if (error) {
		warn(`not saved to Contacts: ${name}, ${error}`);
	}
}

/** Runs an AppleScript file with its arguments; its error, or "" when it went through. */
async function runAppleScript(scriptFile: string, scriptArguments: string[]): Promise<string> {
	const result = await $`osascript ${scriptFile} ${scriptArguments}`.nothrow().quiet();
	if (!result.exitCode) {
		return "";
	}
	return result.stderr.toString().trim() || `osascript exited ${result.exitCode}`;
}

// Exported for the tests: the query against the real schema, the script compiled.
export { contactQuery, saveContactScript };
