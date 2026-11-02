// What an .ics file says, read on any platform: a calendar export carries no
// platform of its own. Only the people are read, as RFC 5545 writes them:
//   ORGANIZER;CN=Jana Nováková:mailto:jana@example.com
//   ATTENDEE;ROLE=REQ-PARTICIPANT;CN="Dvořák, Petr":mailto:petr@example.com
//   ATTENDEE:mailto:someone@example.com

/** The people on a calendar event, organizer and attendees, each once: by name, or by
 *  address when the invitation gives none. One address listed twice under two spellings
 *  of a name is one person, under the spelling that came first. */
export function attendees(calendarFile: string): string[] {
	const nameByAddress = new Map<string, string>();
	for (const line of unfoldedLines(calendarFile)) {
		const person = personOnLine(line);
		if (!person) {
			continue;
		}
		const sameAs = (person.address ?? person.name).toLowerCase();
		if (!nameByAddress.has(sameAs)) {
			nameByAddress.set(sameAs, person.name || person.address || "");
		}
	}
	return [...nameByAddress.values()].filter(Boolean);
}

/** A long line goes on in the next one, which starts with a space or a tab. */
function unfoldedLines(calendarFile: string): string[] {
	return calendarFile
		.replace(/\r?\n[ \t]/g, "")
		.split(/\r?\n/);
}

type Person = { name: string; address?: string };

function personOnLine(line: string): Person | undefined {
	// The property, its parameters (a quoted one may hold a colon), then its value.
	const property = line.match(/^(?:ATTENDEE|ORGANIZER)((?:;[^:;"]+=(?:"[^"]*"|[^:;"]*))*):(.*)$/i);
	if (!property) {
		return undefined;
	}
	const [, parameters, value] = property;

	const address = value.match(/^mailto:(.+)$/i)?.[1].trim();
	const commonName = parameters.match(/;CN=(?:"([^"]*)"|([^;]*))/i);
	const name = cleanName(commonName?.[1] ?? commonName?.[2] ?? "");
	if (!name && !address) {
		return undefined;
	}
	return { name, address };
}

/** Doubled spaces collapsed, a backslash before a comma or semicolon dropped, and
 *  "Dvořáková, Eva" turned to "Eva Dvořáková": the names are later edited on one line
 *  split by commas, where a surname first would read as two people. */
function cleanName(name: string): string {
	const cleaned = name
		.replace(/\\([,;\\])/g, "$1")
		.replace(/\s+/g, " ")
		.trim();
	const surnameFirst = cleaned.match(/^([^\s,]+), ([^,]+)$/);
	if (surnameFirst) {
		const [, surname, givenNames] = surnameFirst;
		return `${givenNames} ${surname}`;
	}
	return cleaned;
}
