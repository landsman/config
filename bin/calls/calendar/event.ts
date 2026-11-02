// Which meeting a recording was and who was on it, for whisper's prompt and the
// transcript's header. The event comes from, in this order:
//   - <recording>.event.json, saved by ../record/record.ts when the call stopped;
//   - ICS=…, an .ics file or an ical:// link dragged out of Apple Calendar;
//   - one of Calendar's last ten, picked in television;
//   - an .ics file or a link dragged in when asked, when there is nothing to pick.
// Its names are then shown on a line to edit, since someone invited along is on
// no event; PEOPLE=… adds to them instead. One known only by address is named in
// ../macos/contacts.ts.
import { existsSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { match } from "ts-pattern";
import { attendees } from "@bin/calls/calendar/ics";
import { attendeesOfEvent, type CallEvent, eventIdInLink, recentEvents } from "@bin/calls/macos/calendar";
import { realNames } from "@bin/calls/macos/contacts";
import { ask, edit, hint, pick, warn } from "@lib/term";

/** The event a recording was, if known, and the others on the call by name. */
export async function callEvent(recording: string): Promise<{ event?: CallEvent; names: string[] }> {
	const source = await findEvent(recording);
	const found = peopleFrom(source);
	const people = await confirmPeople(found.people);

	let event = found.event;
	if (event) {
		const edited = people.join(", ") !== found.people.join(", ");
		event = { ...event, people };
		// Saved as record.ts would have, with the names as edited, so the next run has them too.
		if (source.kind === Origin.Picked || edited) {
			await saveEvent(recording, event);
		}
		hint(`Event: ${event.title}`);
	}

	const names = await realNames(people);
	if (names.length) {
		hint(`Names: ${names.join(", ")}`);
	}
	return { event, names };
}

/** Where the event came from. */
export enum Origin {
	Saved = "saved",
	Picked = "picked",
	Dragged = "dragged",
	Ics = "ics",
	Missing = "missing",
	None = "none",
}

type Source =
	| { kind: Origin.Saved; event: CallEvent }
	| { kind: Origin.Picked; event: CallEvent }
	| { kind: Origin.Dragged; eventId: string }
	| { kind: Origin.Ics; path: string }
	| { kind: Origin.Missing; path: string }
	| { kind: Origin.None };

async function findEvent(recording: string): Promise<Source> {
	const saved = savedEvent(recording);
	if (saved) {
		return { kind: Origin.Saved, event: saved };
	}
	if (process.env.ICS) {
		return eventFromText(process.env.ICS);
	}
	if (!process.stdin.isTTY) {
		return { kind: Origin.None };
	}

	const picked = await pickRecentMeeting();
	if (picked) {
		return picked;
	}
	const typed = await ask("Calendar event, drag it here from Calendar or as .ics", "[Enter = none]");
	return eventFromText(typed);
}

/** The event saved beside the recording. One that cannot be read, edited by hand or cut
 *  short, is left where it is and treated as none, rather than costing the transcript. */
function savedEvent(recording: string): CallEvent | undefined {
	const path = eventFilePath(recording);
	if (!existsSync(path)) {
		return undefined;
	}
	try {
		const saved = JSON.parse(readFileSync(path, "utf8"));
		if (typeof saved?.title !== "string" || typeof saved?.start !== "string" || typeof saved?.end !== "string") {
			throw new Error("not an event");
		}
		const people = Array.isArray(saved.people) ? saved.people.filter((person: unknown) => typeof person === "string") : [];
		return { ...saved, people };
	} catch {
		warn(`cannot read the saved event, going on as if there were none: ${path}`);
		return undefined;
	}
}

/** What was typed or dragged in: a link to an event in Calendar, or a path to an .ics. */
export function eventFromText(text: string): Source {
	const path = draggedPath(text);
	if (!path) {
		return { kind: Origin.None };
	}

	const eventId = eventIdInLink(path);
	if (eventId) {
		return { kind: Origin.Dragged, eventId };
	}

	// A folder dragged in by mistake is no calendar file either.
	if (existsSync(path) && statSync(path).isFile()) {
		return { kind: Origin.Ics, path };
	}
	return { kind: Origin.Missing, path };
}

/** One of Calendar's last ten, since dragging one into a terminal does not always work.
 *  Esc is no event; undefined when there is nothing to pick from. */
async function pickRecentMeeting(): Promise<Source | undefined> {
	const meetings = recentEvents();
	if (!meetings.length || !Bun.which("tv")) {
		return undefined;
	}

	const meetingByLine = new Map(meetings.map((meeting) => [menuLine(meeting), meeting]));
	const pickedLine = await pick("Which meeting was it? Esc = none", [...meetingByLine.keys()]);
	const meeting = meetingByLine.get(pickedLine);
	if (!meeting) {
		return { kind: Origin.None };
	}
	return { kind: Origin.Picked, event: meeting };
}

/** 2026-11-02 10:00  Weekly sync  · Jana Nováková, Petr Dvořák */
function menuLine(meeting: CallEvent): string {
	const title = meeting.title || "untitled";
	const people = meeting.people.length ? `  · ${meeting.people.join(", ")}` : "";
	return `${localDate(meeting.start)} ${localTime(meeting.start)}  ${title}${people}`;
}

/** The names on the event. A mistyped path or a vanished event costs the names, not the transcript. */
function peopleFrom(source: Source): { event?: CallEvent; people: string[] } {
	return match(source)
		.with({ kind: Origin.Saved }, { kind: Origin.Picked }, ({ event }) => {
			return { event, people: event.people };
		})
		.with({ kind: Origin.Dragged }, ({ eventId }) => {
			const people = attendeesOfEvent(eventId);
			if (!people.length) {
				warn("no such event in Calendar, going on without names");
			}
			return { people };
		})
		.with({ kind: Origin.Ics }, ({ path }) => {
			const calendarFile = readFileSync(path, "utf8");
			return { people: attendees(calendarFile) };
		})
		.with({ kind: Origin.Missing }, ({ path }) => {
			warn(`no such file, going on without names: ${path}`);
			return { people: [] };
		})
		.with({ kind: Origin.None }, () => {
			return { people: [] };
		})
		.exhaustive();
}

/** The event's names, to fix, cross out or add to: someone invited along is on no event.
 *  PEOPLE=… adds to them without asking. */
async function confirmPeople(people: string[]): Promise<string[]> {
	if (process.env.PEOPLE) {
		const added = typedNames(process.env.PEOPLE);
		return uniqueNames([...people, ...added]);
	}
	if (!process.stdin.isTTY) {
		return people;
	}

	const prefilled = people.length ? `${people.join(", ")}, ` : "";
	const answer = await edit(
		"Who was on the call, besides me?",
		"[edit, add after a comma or semicolon; Enter = done]",
		prefilled,
	);
	return typedNames(answer);
}

/** Names typed as "Jana Nováková, Petr Dvořák" or with semicolons: spaces collapsed,
 *  without blanks, and one name typed twice in another case kept once, as first typed. */
export function typedNames(text: string): string[] {
	const names = text
		.split(/[,;]/)
		.map((name) => name.replace(/\s+/g, " ").trim())
		.filter(Boolean);
	return uniqueNames(names);
}

/** Each name once, one written twice in another case kept as it came first. */
function uniqueNames(names: string[]): string[] {
	const nameByLowerCase = new Map<string, string>();
	for (const name of names) {
		if (!nameByLowerCase.has(name.toLowerCase())) {
			nameByLowerCase.set(name.toLowerCase(), name);
		}
	}
	return [...nameByLowerCase.values()];
}

async function saveEvent(recording: string, event: CallEvent) {
	const json = JSON.stringify(event, null, "\t");
	await Bun.write(eventFilePath(recording), `${json}\n`);
}

/** <recording>.event.json, beside the recording: its extension swapped, never a dot in a folder's name. */
export function eventFilePath(recording: string): string {
	const withoutExtension = recording.replace(/\.[^./]*$/, "");
	return `${withoutExtension}.event.json`;
}

/** A path dragged into a terminal arrives quoted or with escaped spaces; a typed one may start with ~. */
export function draggedPath(text: string): string {
	return text
		.trim()
		.replace(/^'(.*)'$/, "$1")
		.replace(/^"(.*)"$/, "$1")
		.replace(/\\(.)/g, "$1")
		.replace(/^~(?=\/)/, homedir());
}

export function localDate(isoDate: string): string {
	const date = new Date(isoDate);
	return `${date.getFullYear()}-${twoDigits(date.getMonth() + 1)}-${twoDigits(date.getDate())}`;
}

export function localTime(isoDate: string): string {
	const date = new Date(isoDate);
	return `${twoDigits(date.getHours())}:${twoDigits(date.getMinutes())}`;
}

const twoDigits = (number: number) => String(number).padStart(2, "0");
