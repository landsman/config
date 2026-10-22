// The names on an event dragged out of Apple Calendar into a terminal, for
// whisper's prompt. It arrives as an ical:// link rather than a file, so the
// names are read from Calendar's own database, read-only.
import { Database } from "bun:sqlite";
import { homedir } from "node:os";

/** The event's UUID in a link dragged out of Calendar: ical://occurrence/<start>/<UUID>?method=show. */
export const appleEventId = (s: string) => s.match(/^ical:\/\/[^/]+\/[^/]+\/([0-9A-F-]{36})\b/i)?.[1];

export const calendarDb = `${homedir()}/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb`;

/** The names on an event in Calendar's database, bare addresses included. Its schema is
 *  Apple's and undocumented, so a change to it reads as no names, never as a failed transcript. */
export function appleCalendarAttendees(uuid: string, path = calendarDb): string[] {
	try {
		const db = new Database(path, { readonly: true });
		try {
			return db.query<{ name: string }, [string]>(attendeesSql).all(uuid).map((r) => r.name.trim());
		} finally {
			db.close();
		}
	} catch {
		return [];
	}
}

export const attendeesSql = `
	SELECT i.display_name AS name FROM CalendarItem c
	JOIN Participant p ON p.owner_id = c.ROWID JOIN Identity i ON i.ROWID = p.identity_id
	WHERE c.UUID = ? AND i.display_name IS NOT NULL ORDER BY p.ROWID`;

/** A call's event as it was when the call ended: saved beside the recording, so the
 *  transcript still knows it once the event moves or is deleted. people leaves me out. */
export type CallEvent = { uuid: string; title: string; start: string; end: string; me: string | null; people: string[] };

/** The timed events overlapping [from, to], the closest fit first — overlap over union, so a
 *  meeting beats a two-day conference around it — and none when the schema changed. */
export function eventsDuring(from: Date, to: Date, path = calendarDb): CallEvent[] {
	try {
		const db = new Database(path, { readonly: true });
		try {
			const a = from.getTime() / 1000 - epoch, b = to.getTime() / 1000 - epoch;
			const seen = new Set<string>();
			return db.query<Occurrence, [number, number]>(occurrencesSql).all(a - 86_400, b)
				.map((r) => ({ r, ...window(r) }))
				.map((x) => ({ ...x, overlap: Math.min(x.end, b) - Math.max(x.start, a), union: Math.max(x.end, b) - Math.min(x.start, a) }))
				.filter((x) => x.overlap > 0 && !seen.has(`${x.r.id}@${x.start}`) && seen.add(`${x.r.id}@${x.start}`))
				.sort((x, y) => y.overlap / y.union - x.overlap / x.union)
				.map(({ r, start, end }) => ({ uuid: r.uuid, title: r.title ?? "", start: iso(start), end: iso(end), ...people(db, r.id) }));
		} finally {
			db.close();
		}
	} catch {
		return [];
	}
}

// Calendar counts seconds from 2001-01-01, Core Data's epoch.
const epoch = 978_307_200;
const iso = (s: number) => new Date((s + epoch) * 1000).toISOString();

type Occurrence = { id: number; uuid: string; title: string | null; rec: number; s: number; e: number; day: number; os: number | null; oe: number | null };

// One row per day an event happens on. An occurrence's own times are mostly empty, so a
// one-off or a moved repeat takes its event's times, and a plain repeat its series' time of day.
export const occurrencesSql = `
	SELECT c.ROWID id, c.UUID uuid, c.summary title, c.has_recurrences rec, c.start_date s, c.end_date e,
	       o.day day, o.occurrence_start_date os, o.occurrence_end_date oe
	FROM OccurrenceCache o JOIN CalendarItem c ON c.ROWID = o.event_id
	WHERE o.day BETWEEN ? AND ? AND c.all_day = 0 AND c.entity_type = 2`;

function window(r: Occurrence) {
	if (r.os != null && r.oe != null) return { start: r.os, end: r.oe };
	if (!r.rec) return { start: r.s, end: r.e };
	// ponytail: this Mac's time zone; a series set in another one lands off by the difference
	const d = new Date((r.s + epoch) * 1000);
	const start = r.day + d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds();
	return { start, end: start + r.e - r.s };
}

/** Me and everyone else on the event, the organizer included unless that is me. */
function people(db: Database, id: number) {
	const rows = db.query<{ name: string; address: string | null; me: number }, [number]>(peopleSql).all(id);
	const mine = rows.find((p) => p.me);
	const others = rows.filter((p) => !p.me && !(mine?.address && p.address === mine.address)).map((p) => p.name.trim());
	return { me: mine?.name.trim() ?? null, people: [...new Set(others)] };
}

export const peopleSql = `
	SELECT coalesce(i.display_name, replace(i.address, 'mailto:', '')) name, i.address address, p.ROWID = c.self_attendee_id me
	FROM Participant p JOIN Identity i ON i.ROWID = p.identity_id JOIN CalendarItem c ON c.ROWID = p.owner_id
	WHERE p.owner_id = ? AND coalesce(i.display_name, i.address) IS NOT NULL ORDER BY p.ROWID`;
