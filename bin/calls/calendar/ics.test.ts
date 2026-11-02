// What ics.ts would get wrong silently: someone on the invitation missed, or one
// person read as two — and every name missed is one whisper spells wrong.
import { describe, expect, test } from "bun:test";
import { attendees } from "@bin/calls/calendar/ics";

const invitation = (...people: string[]) => {
	return ["BEGIN:VCALENDAR", "BEGIN:VEVENT", "SUMMARY:Weekly sync", ...people, "END:VEVENT", "END:VCALENDAR"].join("\r\n");
};

describe("expected use", () => {
	test("the organizer and the attendees, by name, in the order they are listed", () => {
		const people = attendees(invitation(
			"ORGANIZER;CN=Jana Nováková:mailto:jana@example.com",
			"ATTENDEE;ROLE=REQ-PARTICIPANT;PARTSTAT=ACCEPTED;CN=Petr Dvořák:mailto:petr@example.com",
		));

		expect(people).toEqual(["Jana Nováková", "Petr Dvořák"]);
	});

	test("an event with nobody on it has no names", () => {
		expect(attendees(invitation())).toEqual([]);
		expect(attendees("")).toEqual([]);
	});

	test("someone invited by address only is there by address", () => {
		const people = attendees(invitation(
			"ATTENDEE;ROLE=REQ-PARTICIPANT:mailto:someone@example.com",
			"ATTENDEE;CN=other@example.com:mailto:other@example.com",
		));

		expect(people).toEqual(["someone@example.com", "other@example.com"]);
	});

	test("one address twice is one person, under the spelling that came first", () => {
		const people = attendees(invitation(
			"ORGANIZER;CN=Jana Nováková:mailto:jana@example.com",
			"ATTENDEE;CN=Jana Novakova:mailto:jana@example.com",
			"ATTENDEE;CN=Jana Nováková:MAILTO:Jana@Example.com",
		));

		expect(people).toEqual(["Jana Nováková"]);
	});

	test("a name is read whole: folded over lines, quoted with a colon, escaped, doubled spaces", () => {
		const people = attendees(invitation(
			'ATTENDEE;CUTYPE=INDIVIDUAL;CN="Petr Dvořák";PARTSTAT=ACCEPTED:mai',
			" lto:petr@example.com",
			'ATTENDEE;CN="Tomáš Novák: CEO":mailto:tomas@example.com',
			"ATTENDEE;CN=Dvořáková\\, Eva:mailto:eva@example.com",
			"ATTENDEE;CN=Jana  Nováková :mailto:jana@example.com",
		));

		expect(people).toEqual(["Petr Dvořák", "Tomáš Novák: CEO", "Eva Dvořáková", "Jana Nováková"]);
	});

	test("a surname written first, as Outlook does, is turned round, since a comma splits names later", () => {
		const people = attendees(invitation(
			'ATTENDEE;CN="Dvořáková, Eva Marie":mailto:eva@example.com',
			'ATTENDEE;CN="Petr Dvořák, CEO, Example":mailto:petr@example.com',
		));

		expect(people).toEqual(["Eva Marie Dvořáková", "Petr Dvořák, CEO, Example"]);
	});

	test("parameter names in lower case still count, as the standard allows", () => {
		expect(attendees(invitation("attendee;cn=Petr Dvořák:mailto:petr@example.com"))).toEqual(["Petr Dvořák"]);
	});
});

describe("bad input", () => {
	test("a typo in an address is another person, since nothing says it is not", () => {
		const people = attendees(invitation(
			"ATTENDEE;CN=Petr Dvořák:mailto:petr@example.com",
			"ATTENDEE;CN=Petr Dvořák:mailto:petr@exmaple.com",
		));

		expect(people).toEqual(["Petr Dvořák", "Petr Dvořák"]);
	});

	test("lines that only look alike are not people", () => {
		const people = attendees(invitation(
			"DESCRIPTION:ATTENDEE;CN=Not Real:mailto:no@example.com",
			"X-ATTENDEE;CN=Not Real:mailto:no@example.com",
			"ATTENDEE;CN=:",
		));

		expect(people).toEqual([]);
	});
});
