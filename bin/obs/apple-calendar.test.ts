// What apple-calendar.ts would get wrong silently: the UUID misread out of the
// link, the names of another event, or none, read out of the database; the event
// a call was found at the wrong time, a conference taken for the meeting inside
// it, or me counted among the others — or Apple changing the schema of Calendar,
// which the code reads as "no names" and "no event".
import { Database } from "bun:sqlite";
import { expect, test } from "bun:test";
import { existsSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { appleCalendarAttendees, appleEventId, attendeesSql, calendarDb, eventsDuring, occurrencesSql, peopleSql } from "@bin/obs/apple-calendar";
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

test("the event a call was is the one fitting its time best, at that day's time for a repeat, without me", async () => {
	const s = (d: Date) => d.getTime() / 1000 - 978_307_200; // Calendar's epoch
	const at = (h: number, m = 0, day = 27) => new Date(2026, 9, day, h, m);
	const db = new Database(":memory:");
	db.run("CREATE TABLE CalendarItem (UUID TEXT, summary TEXT, has_recurrences INTEGER, start_date REAL, end_date REAL, all_day INTEGER, entity_type INTEGER, self_attendee_id INTEGER)");
	db.run("CREATE TABLE OccurrenceCache (event_id INTEGER, day REAL, occurrence_start_date REAL, occurrence_end_date REAL)");
	db.run("CREATE TABLE Participant (identity_id INTEGER, owner_id INTEGER)");
	db.run("CREATE TABLE Identity (display_name TEXT, address TEXT)");
	const item = db.prepare("INSERT INTO CalendarItem VALUES (?, ?, ?, ?, ?, 0, 2, ?)");
	// 1: a weekly sync, first held in June at 10:00; 2: a conference around it; 3: a call later that day
	item.run("SYNC", "Sync", 1, s(new Date(2026, 5, 2, 10)), s(new Date(2026, 5, 2, 10, 30)), 2);
	item.run("CONF", "Conference", 0, s(at(8)), s(at(18, 0, 28)), null);
	item.run("LATER", "Later", 0, s(at(15)), s(at(16)), null);
	for (const [id, day] of [[1, 27], [2, 27], [2, 28], [3, 27]]) db.run("INSERT INTO OccurrenceCache VALUES (?, ?, NULL, NULL)", [id, s(at(0, 0, day))]);
	db.run("INSERT INTO Identity VALUES ('Jana Nováková', 'mailto:jana@example.com'), ('Me', 'mailto:me@example.com'), (NULL, 'mailto:petr@example.com'), ('Me again', 'mailto:me@example.com')");
	// the sync: Jana organizes, me, Petr by address only, and me once more as an organizer copy
	db.run("INSERT INTO Participant VALUES (1, 1), (2, 1), (3, 1), (4, 1)");
	const path = join(mkdtempSync(join(tmpdir(), "calendar-")), "Calendar.sqlitedb");
	await Bun.write(path, db.serialize());

	const found = eventsDuring(at(10, 2), at(10, 25), path);
	expect(found.map((e) => e.title)).toEqual(["Sync", "Conference"]);
	expect(found[0]).toEqual({
		uuid: "SYNC", title: "Sync", start: at(10).toISOString(), end: at(10, 30).toISOString(),
		me: "Me", people: ["Jana Nováková", "petr@example.com"],
	});
	expect(eventsDuring(at(12), at(13), path).map((e) => e.title)).toEqual(["Conference"]);
	expect(eventsDuring(at(10), at(11), "/nonexistent.sqlitedb")).toEqual([]);
});

// Only on a Mac with Calendar, and read-only: preparing the query checks every
// table and column it names against the real schema without reading a row.
test.skipIf(!existsSync(calendarDb))("the queries still fit the schema of Calendar on this Mac", () => {
	const db = new Database(calendarDb, { readonly: true });
	try {
		for (const sql of [attendeesSql, occurrencesSql, peopleSql]) expect(() => db.query(sql)).not.toThrow();
	} finally {
		db.close();
	}
});
