// What calendar.ts would get wrong silently: the UUID misread out of the
// link, the names of another event, or none, read out of the database; the event
// a call was found at the wrong time, a conference taken for the meeting inside
// it, or me counted among the others — or Apple changing the schema of Calendar,
// which the code reads as "no names" and "no event".
import { Database } from "bun:sqlite";
import { expect, test } from "bun:test";
import { existsSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
	attendeesOfEvent,
	eventIdInLink,
	attendeesQuery,
	calendarDatabase,
	eventsDuring,
	occurrencesQuery,
	peopleQuery,
	recentEvents,
	throwIfOurMistake,
} from "@bin/calls/macos/calendar";
import { draggedPath } from "@bin/calls/calendar/event";

test("an event dragged out of Calendar is a link to its UUID", () => {
	const uuid = "55F9EE9B-1377-4F01-A442-79E9AC71B5BC";
	expect(
		eventIdInLink(
			draggedPath(`ical://occurrence/20261020T110000Z/${uuid}\\?method=show\\&options=more`),
		),
	).toBe(uuid);
	expect(eventIdInLink("/Users/me/a.ics")).toBeUndefined();
});

test("its names come from Calendar's database, that event's only, in order", async () => {
	const database = new Database(":memory:");
	database.run("CREATE TABLE CalendarItem (UUID TEXT)");
	database.run("CREATE TABLE Participant (identity_id INTEGER, owner_id INTEGER)");
	database.run("CREATE TABLE Identity (display_name TEXT)");
	database.run("INSERT INTO CalendarItem VALUES ('A'), ('B')");
	database.run("INSERT INTO Identity VALUES ('Jana Nováková'), ('Petr Dvořák'), (NULL)");
	database.run("INSERT INTO Participant VALUES (2, 1), (1, 1), (3, 1), (1, 2)");
	const path = join(mkdtempSync(join(tmpdir(), "calendar-")), "Calendar.sqlitedb");
	await Bun.write(path, database.serialize());
	expect(attendeesOfEvent("A", path)).toEqual(["Petr Dvořák", "Jana Nováková"]);
	expect(attendeesOfEvent("missing", path)).toEqual([]);
	expect(attendeesOfEvent("A", "/nonexistent.sqlitedb")).toEqual([]);
});

test("the event a call was is the one fitting its time best, at that day's time for a repeat, without me", async () => {
	const calendarSeconds = (date: Date) => date.getTime() / 1000 - 978_307_200; // Calendar's epoch
	const october = (hour: number, minute = 0, day = 27) => new Date(2026, 9, day, hour, minute);
	const database = new Database(":memory:");
	database.run(
		"CREATE TABLE CalendarItem (UUID TEXT, summary TEXT, has_recurrences INTEGER, start_date REAL, end_date REAL, all_day INTEGER, entity_type INTEGER, self_attendee_id INTEGER)",
	);
	database.run(
		"CREATE TABLE OccurrenceCache (event_id INTEGER, day REAL, occurrence_start_date REAL, occurrence_end_date REAL)",
	);
	database.run("CREATE TABLE Participant (identity_id INTEGER, owner_id INTEGER)");
	database.run("CREATE TABLE Identity (display_name TEXT, address TEXT)");
	const insertEvent = database.prepare("INSERT INTO CalendarItem VALUES (?, ?, ?, ?, ?, 0, 2, ?)");
	// 1: a weekly sync, first held in June at 10:00; 2: a conference around it; 3: a call later that day
	insertEvent.run(
		"SYNC",
		"Sync",
		1,
		calendarSeconds(new Date(2026, 5, 2, 10)),
		calendarSeconds(new Date(2026, 5, 2, 10, 30)),
		2,
	);
	insertEvent.run(
		"CONF",
		"Conference",
		0,
		calendarSeconds(october(8)),
		calendarSeconds(october(18, 0, 28)),
		null,
	);
	insertEvent.run(
		"LATER",
		"Later",
		0,
		calendarSeconds(october(15)),
		calendarSeconds(october(16)),
		null,
	);
	for (const [eventRow, day] of [
		[1, 27],
		[2, 27],
		[2, 28],
		[3, 27],
	]) {
		database.run("INSERT INTO OccurrenceCache VALUES (?, ?, NULL, NULL)", [
			eventRow,
			calendarSeconds(october(0, 0, day)),
		]);
	}
	database.run(
		"INSERT INTO Identity VALUES ('Jana Nováková', 'mailto:jana@example.com'), ('Me', 'mailto:me@example.com'), (NULL, 'mailto:petr@example.com'), ('Me again', 'mailto:me@example.com')",
	);
	// the sync: Jana organizes, me, Petr by address only, and me once more as an organizer copy
	database.run("INSERT INTO Participant VALUES (1, 1), (2, 1), (3, 1), (4, 1)");
	const path = join(mkdtempSync(join(tmpdir(), "calendar-")), "Calendar.sqlitedb");
	await Bun.write(path, database.serialize());

	const found = eventsDuring(october(10, 2), october(10, 25), path);
	expect(found.map((event) => event.title)).toEqual(["Sync", "Conference"]);
	expect(found[0]).toEqual({
		uuid: "SYNC",
		title: "Sync",
		start: october(10).toISOString(),
		end: october(10, 30).toISOString(),
		me: "Me",
		people: ["Jana Nováková", "petr@example.com"],
	});
	expect(eventsDuring(october(12), october(13), path).map((event) => event.title)).toEqual([
		"Conference",
	]);
	expect(eventsDuring(october(10), october(11), "/nonexistent.sqlitedb")).toEqual([]);

	// the last ones before 15:30 that day, newest first: one not started yet is left out
	expect(recentEvents(october(15, 30), 2, path).map((event) => event.title)).toEqual([
		"Later",
		"Sync",
	]);
	expect(recentEvents(october(12), 10, path).map((event) => event.title)).toEqual([
		"Sync",
		"Conference",
	]);
	expect(recentEvents(october(12), 10, "/nonexistent.sqlitedb")).toEqual([]);
});

// Only on a Mac with Calendar, and read-only: preparing the query checks every
// table and column it names against the real schema without reading a row.
test.skipIf(!existsSync(calendarDatabase))(
	"the queries still fit the schema of Calendar on this Mac",
	() => {
		const database = new Database(calendarDatabase, { readonly: true });
		try {
			for (const query of [attendeesQuery, occurrencesQuery, peopleQuery]) {
				expect(() => database.query(query)).not.toThrow();
			}
		} finally {
			database.close();
		}
	},
);

test("a query given the wrong number of values fails loudly, anything else from the database reads as nothing", () => {
	const database = new Database(":memory:");
	database.run("CREATE TABLE person (name TEXT, email TEXT)");
	const wrongCount = () =>
		database.query("SELECT name FROM person WHERE email = ? AND name = ?").all("jana@example.com");
	const schemaChanged = () => database.query("SELECT missing_column FROM person").all();

	expect(() => {
		try {
			wrongCount();
		} catch (error) {
			throwIfOurMistake(error);
		}
	}).toThrow(/expected 2 values, received 1/);
	expect(() => {
		try {
			schemaChanged();
		} catch (error) {
			throwIfOurMistake(error);
		}
	}).not.toThrow();
});
