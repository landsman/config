// The names on an event dragged out of Apple Calendar into a terminal, for
// whisper's prompt. It arrives as an ical:// link rather than a file, so the
// names are read from Calendar's own database, read-only.
import { Database } from "bun:sqlite";
import { homedir } from "node:os";

/** The event's UUID in a link dragged out of Calendar: ical://occurrence/<start>/<UUID>?method=show. */
export const appleEventId = (s: string) => s.match(/^ical:\/\/[^/]+\/[^/]+\/([0-9A-F-]{36})\b/i)?.[1];

const calendarDb = `${homedir()}/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb`;

/** The names on an event in Calendar's database, bare addresses included. Its schema is
 *  Apple's and undocumented, so a change to it reads as no names, never as a failed transcript. */
export function appleCalendarAttendees(uuid: string, path = calendarDb): string[] {
	try {
		const db = new Database(path, { readonly: true });
		try {
			return db.query<{ name: string }, [string]>(`
				SELECT i.display_name AS name FROM CalendarItem c
				JOIN Participant p ON p.owner_id = c.ROWID JOIN Identity i ON i.ROWID = p.identity_id
				WHERE c.UUID = ? AND i.display_name IS NOT NULL ORDER BY p.ROWID`).all(uuid).map((r) => r.name.trim());
		} finally {
			db.close();
		}
	} catch {
		return [];
	}
}
