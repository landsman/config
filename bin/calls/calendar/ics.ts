// What an .ics file says, read on any platform: a calendar export carries no
// platform of its own.

/** The people on a calendar event, its organizer and attendees: a name, or an address when it has none. */
export function attendees(ics: string): string[] {
	const unfolded = ics.replace(/\r?\n[ \t]/g, ""); // a long line goes on after a newline and a space
	return [...new Set([...unfolded.matchAll(/^(?:ATTENDEE|ORGANIZER)[^:\n]*?;CN=("?)([^";:\n]+)\1/gm)].map((m) => m[2].trim()))];
}
