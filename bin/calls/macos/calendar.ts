// Events and the people on them, read from the database of Calendar.app,
// read-only. Every account added to Calendar (iCloud, Google, Exchange) is in
// that one database. Its schema is Apple's and undocumented, so a change to it
// reads as no event and no names, never as a failed transcript.
import { Database } from "bun:sqlite";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export const calendarDatabase = `${homedir()}/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb`;

/** A call's event as it was when the call ended: saved beside the recording, so the
 *  transcript still knows it once the event moves or is deleted. people leaves me out.
 *  The field names are what .event.json files already hold. */
export type CallEvent = {
	uuid: string;
	title: string;
	start: string;
	end: string;
	me: string | null;
	people: string[];
};

/** The event's id in a link dragged out of Calendar: ical://occurrence/<start>/<id>?method=show. */
export function eventIdInLink(link: string): string | undefined {
	return link.match(/^ical:\/\/[^/]+\/[^/]+\/([0-9A-F-]{36})\b/i)?.[1];
}

/** The names on an event, bare addresses included. */
export function attendeesOfEvent(eventId: string, databasePath = calendarDatabase): string[] {
	return readCalendar(databasePath, [], (database) => {
		const attendees = database.query<{ name: string }, [string]>(attendeesQuery).all(eventId);
		return attendees.map((attendee) => attendee.name.trim());
	});
}

export const attendeesQuery = readQuery("attendees-of-event.sql");

/** The events that overlap a call, the closest fit first: how much they share over how much
 *  they cover together, so a meeting beats a two-day conference around it. */
export function eventsDuring(
	callStart: Date,
	callEnd: Date,
	databasePath = calendarDatabase,
): CallEvent[] {
	return readCalendar(databasePath, [], (database) => {
		const from = toCalendarSeconds(callStart);
		const to = toCalendarSeconds(callEnd);
		const closestFit = (meeting: Meeting) => {
			const shared = Math.min(meeting.end, to) - Math.max(meeting.start, from);
			const covered = Math.max(meeting.end, to) - Math.min(meeting.start, from);
			return shared / covered;
		};
		return meetingsBetween(database, from - secondsInDay, to)
			.filter((meeting) => meeting.start < to && meeting.end > from)
			.sort((first, second) => closestFit(second) - closestFit(first))
			.map((meeting) => toCallEvent(database, meeting));
	});
}

/** The last events that started before now, the newest first, for a recording that saved none. */
export function recentEvents(
	now = new Date(),
	count = 10,
	databasePath = calendarDatabase,
): CallEvent[] {
	return readCalendar(databasePath, [], (database) => {
		const until = toCalendarSeconds(now);
		// ponytail: a month back; ten meetings older than that are not worth a list
		return meetingsBetween(database, until - 31 * secondsInDay, until)
			.filter((meeting) => meeting.start <= until)
			.sort((first, second) => second.start - first.start)
			.slice(0, count)
			.map((meeting) => toCallEvent(database, meeting));
	});
}

/** Opens the database read-only for one read, and answers `fallback` when it cannot be read. */
function readCalendar<T>(databasePath: string, fallback: T, read: (database: Database) => T): T {
	try {
		const database = new Database(databasePath, { readonly: true });
		try {
			return read(database);
		} finally {
			database.close();
		}
	} catch {
		return fallback;
	}
}

// Calendar counts seconds from 2001-01-01, Core Data's epoch.
const calendarEpoch = 978_307_200;
const secondsInDay = 86_400;
const toCalendarSeconds = (date: Date) => date.getTime() / 1000 - calendarEpoch;
const toIsoDate = (calendarSeconds: number) =>
	new Date((calendarSeconds + calendarEpoch) * 1000).toISOString();

/** One timed event on one day, at the time it really happens. */
type Meeting = { occurrence: Occurrence; start: number; end: number };

/** Every timed event on the days between `from` and `to`, each once. */
function meetingsBetween(database: Database, from: number, to: number): Meeting[] {
	const seen = new Set<string>();
	const occurrences = database.query<Occurrence, [number, number]>(occurrencesQuery).all(from, to);
	return occurrences
		.map((occurrence) => ({ occurrence, ...whenItHappens(occurrence) }))
		.filter((meeting) => {
			const key = `${meeting.occurrence.eventRow}@${meeting.start}`;
			if (seen.has(key)) return false;
			seen.add(key);
			return true;
		});
}

function toCallEvent(database: Database, { occurrence, start, end }: Meeting): CallEvent {
	return {
		uuid: occurrence.uuid,
		title: occurrence.title ?? "",
		start: toIsoDate(start),
		end: toIsoDate(end),
		...peopleOnEvent(database, occurrence.eventRow),
	};
}

type Occurrence = {
	eventRow: number;
	uuid: string;
	title: string | null;
	repeats: number;
	eventStart: number;
	eventEnd: number;
	day: number;
	occurrenceStart: number | null;
	occurrenceEnd: number | null;
};

export const occurrencesQuery = readQuery("occurrences.sql");

/** An occurrence's own times are mostly empty, so a one-off or a moved repeat takes its
 *  event's times, and a plain repeat its series' time of day on that day. */
function whenItHappens(occurrence: Occurrence): { start: number; end: number } {
	if (occurrence.occurrenceStart != null && occurrence.occurrenceEnd != null) {
		return { start: occurrence.occurrenceStart, end: occurrence.occurrenceEnd };
	}
	if (!occurrence.repeats) return { start: occurrence.eventStart, end: occurrence.eventEnd };

	// ponytail: this Mac's time zone; a series set in another one lands off by the difference
	const firstTime = new Date((occurrence.eventStart + calendarEpoch) * 1000);
	const timeOfDay =
		firstTime.getHours() * 3600 + firstTime.getMinutes() * 60 + firstTime.getSeconds();
	const start = occurrence.day + timeOfDay;
	return { start, end: start + occurrence.eventEnd - occurrence.eventStart };
}

/** Me, and everyone else on the event, the organizer included unless that is me. */
function peopleOnEvent(database: Database, eventRow: number) {
	const participants = database.query<Participant, [number]>(peopleQuery).all(eventRow);
	const me = participants.find((participant) => participant.isMe);
	// The organizer can be me a second time, under the same address.
	const isMeAgain = (participant: Participant) => {
		return Boolean(me?.address && participant.address === me.address);
	};
	const others = participants
		.filter((participant) => !participant.isMe && !isMeAgain(participant))
		.map((participant) => participant.name.trim());
	return { me: me?.name.trim() ?? null, people: [...new Set(others)] };
}

type Participant = { name: string; address: string | null; isMe: number };

export const peopleQuery = readQuery("people-on-event.sql");

function readQuery(file: string): string {
	return readFileSync(join(import.meta.dir, "queries", file), "utf8");
}
