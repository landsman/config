// The names of the people on a calendar event, for whisper's prompt: from an
// .ics file, or from an event dragged out of Calendar, which arrives as an
// ical:// link and is read from Calendar's own database.
import { Database } from "bun:sqlite";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { warn } from "@lib/term";

/** The names on the event a path or a Calendar link points at. A mistyped one costs the names, not the transcript. */
export function participants(event: string): string[] {
	if (!event) return [];
	const uuid = eventLink(event);
	if (uuid) {
		const names = calendarAttendees(uuid);
		if (!names.length) warn("no names on that event in Calendar, going on without them");
		return names;
	}
	if (existsSync(event)) return attendees(readFileSync(event, "utf8"));
	warn(`no such file, going on without names: ${event}`);
	return [];
}

/** The event's UUID in a link dragged out of Calendar: ical://occurrence/<start>/<UUID>?method=show. */
export const eventLink = (s: string) => s.match(/^ical:\/\/[^/]+\/[^/]+\/([0-9A-F-]{36})\b/i)?.[1];

const calendarDb = `${homedir()}/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb`;

/** The names on an event in Calendar's database. Its schema is Apple's and undocumented,
 *  so a change to it reads as no names, never as a failed transcript. */
export function calendarAttendees(uuid: string, path = calendarDb): string[] {
	try {
		const db = new Database(path, { readonly: true });
		try {
			const rows = db.query<{ name: string }, [string]>(`
				SELECT i.display_name AS name FROM CalendarItem c
				JOIN Participant p ON p.owner_id = c.ROWID JOIN Identity i ON i.ROWID = p.identity_id
				WHERE c.UUID = ? AND i.display_name IS NOT NULL ORDER BY p.ROWID`).all(uuid);
			return named(rows.map((r) => r.name.trim()));
		} finally {
			db.close();
		}
	} catch {
		return [];
	}
}

/** The names of the people on an .ics event: its organizer and attendees. */
export function attendees(ics: string): string[] {
	const unfolded = ics.replace(/\r?\n[ \t]/g, ""); // a long line goes on after a newline and a space
	return named([...unfolded.matchAll(/^(?:ATTENDEE|ORGANIZER)[^:\n]*?;CN=("?)([^";:\n]+)\1/gm)].map((m) => m[2].trim()));
}

const named = (names: string[]) => [...new Set(names)].filter((n) => !n.includes("@"));
