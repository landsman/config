// What pick.ts would get wrong silently: the names from a calendar event missed
// or mangled — folded lines, quoted names, a name listed twice — a dragged path
// left quoted or a typed ~ unexpanded, and names typed by hand split wrong.
import { expect, test } from "bun:test";
import { homedir } from "node:os";
import { attendees, dropped, typedNames } from "@bin/calls/event/pick";

test("names come from the organizer and attendees, folded and quoted, once each", () =>
	expect(attendees([
		"BEGIN:VEVENT",
		"ORGANIZER;CN=Jana Nováková:mailto:jana@example.com",
		'ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;CN="Petr Dvořák";PARTSTAT=ACCEPTED:mai',
		" lto:petr@example.com",
		"ATTENDEE;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;CN=Jana Nováková:mailto:jana@example.com",
		"ATTENDEE;CN=someone@example.com:mailto:someone@example.com",
		"END:VEVENT",
	].join("\r\n"))).toEqual(["Jana Nováková", "Petr Dvořák", "someone@example.com"]));

test("a dragged-in path loses its quotes and escapes", () => {
	expect(dropped("/Users/me/Downloads/Porada\\ Q4.ics ")).toBe("/Users/me/Downloads/Porada Q4.ics");
	expect(dropped("'/Users/me/a b.ics'")).toBe("/Users/me/a b.ics");
	expect(dropped("~/a.ics")).toBe(`${homedir()}/a.ics`);
});

test("names typed by hand are split on commas or semicolons, spaces collapsed, without blanks or repeats", () => {
	expect(typedNames(" Jana Nováková, Petr Dvořák,, Jana  Nováková ")).toEqual(["Jana Nováková", "Petr Dvořák"]);
	expect(typedNames("Jana Nováková; Petr\tDvořák ;Tomáš Novák")).toEqual(["Jana Nováková", "Petr Dvořák", "Tomáš Novák"]);
	expect(typedNames("")).toEqual([]);
});
