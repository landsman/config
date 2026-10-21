// What calendar.ts would get wrong silently: names missed or mangled — folded
// lines, quoted names, an attendee who is only an address — or an event dragged
// out of Calendar whose link or database row is misread.
import { Database } from "bun:sqlite";
import { expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { attendees, calendarAttendees, eventLink } from "@bin/obs/calendar";
import { dropped } from "@bin/obs/transcribe";

test("names come from the organizer and attendees, folded and quoted, no bare addresses", () =>
	expect(attendees([
		"BEGIN:VEVENT",
		"ORGANIZER;CN=Jana Nováková:mailto:jana@example.com",
		'ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;CN="Petr Dvořák";PARTSTAT=ACCEPTED:mai',
		" lto:petr@example.com",
		"ATTENDEE;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;CN=Jana Nováková:mailto:jana@example.com",
		"ATTENDEE;CN=someone@example.com:mailto:someone@example.com",
		"END:VEVENT",
	].join("\r\n"))).toEqual(["Jana Nováková", "Petr Dvořák"]));

test("an event dragged out of Calendar is a link to its UUID", () => {
	const uuid = "55F9EE9B-1377-4F01-A442-79E9AC71B5BC";
	expect(eventLink(dropped(`ical://occurrence/20261020T110000Z/${uuid}\\?method=show\\&options=more`))).toBe(uuid);
	expect(eventLink("/Users/me/a.ics")).toBeUndefined();
});

test("its names come from Calendar's database, in order, no bare addresses", async () => {
	const db = new Database(":memory:");
	db.run("CREATE TABLE CalendarItem (UUID TEXT)");
	db.run("CREATE TABLE Participant (identity_id INTEGER, owner_id INTEGER)");
	db.run("CREATE TABLE Identity (display_name TEXT)");
	db.run("INSERT INTO CalendarItem VALUES ('A'), ('B')");
	db.run("INSERT INTO Identity VALUES ('Jana Nováková'), ('petr@example.com'), ('Petr Dvořák'), (NULL)");
	db.run("INSERT INTO Participant VALUES (3, 1), (1, 1), (2, 1), (4, 1), (1, 2), (3, 2)");
	const path = join(mkdtempSync(join(tmpdir(), "calendar-")), "Calendar.sqlitedb");
	await Bun.write(path, db.serialize());
	expect(calendarAttendees("A", path)).toEqual(["Petr Dvořák", "Jana Nováková"]);
	expect(calendarAttendees("missing", path)).toEqual([]);
	expect(calendarAttendees("A", "/nonexistent.sqlitedb")).toEqual([]);
});
