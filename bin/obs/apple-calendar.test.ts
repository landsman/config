// What apple-calendar.ts would get wrong silently: the UUID misread out of the
// link, or the names of another event, or none, read out of the database.
import { Database } from "bun:sqlite";
import { expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { appleCalendarAttendees, appleEventId } from "@bin/obs/apple-calendar";
import { dropped } from "@bin/obs/transcribe";

test("an event dragged out of Calendar is a link to its UUID", () => {
	const uuid = "55F9EE9B-1377-4F01-A442-79E9AC71B5BC";
	expect(appleEventId(dropped(`ical://occurrence/20261020T110000Z/${uuid}\\?method=show\\&options=more`))).toBe(uuid);
	expect(appleEventId("/Users/me/a.ics")).toBeUndefined();
});

test("its names come from Calendar's database, that event's only, in order", async () => {
	const db = new Database(":memory:");
	db.run("CREATE TABLE CalendarItem (UUID TEXT)");
	db.run("CREATE TABLE Participant (identity_id INTEGER, owner_id INTEGER)");
	db.run("CREATE TABLE Identity (display_name TEXT)");
	db.run("INSERT INTO CalendarItem VALUES ('A'), ('B')");
	db.run("INSERT INTO Identity VALUES ('Jana Nováková'), ('Petr Dvořák'), (NULL)");
	db.run("INSERT INTO Participant VALUES (2, 1), (1, 1), (3, 1), (1, 2)");
	const path = join(mkdtempSync(join(tmpdir(), "calendar-")), "Calendar.sqlitedb");
	await Bun.write(path, db.serialize());
	expect(appleCalendarAttendees("A", path)).toEqual(["Petr Dvořák", "Jana Nováková"]);
	expect(appleCalendarAttendees("missing", path)).toEqual([]);
	expect(appleCalendarAttendees("A", "/nonexistent.sqlitedb")).toEqual([]);
});
