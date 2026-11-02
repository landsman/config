// Which meeting a recording was and who was on it, for whisper's prompt and the
// transcript's header. The event comes from, in this order:
//   - <recording>.event.json, saved by ../record/record.ts when the call stopped;
//   - ICS=…, an .ics file or an ical:// link dragged out of Apple Calendar;
//   - one of Calendar's last ten, picked in television;
//   - an .ics file or a link dragged in when asked, when there is nothing to pick.
// Its names are then shown on a line to edit, since someone invited along is on
// no event; PEOPLE=… adds to them instead. One known only by address is named in
// ../macos/contacts.ts.
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { match } from "ts-pattern";
import { attendees } from "@bin/calls/calendar/ics";
import { appleCalendarAttendees, appleEventId, type CallEvent, recentEvents } from "@bin/calls/macos/calendar";
import { realNames } from "@bin/calls/macos/contacts";
import { ask, edit, hint, pick, warn } from "@lib/term";

/** The event a recording was, if known, and the others on the call by name. */
export async function callEvent(file: string): Promise<{ event?: CallEvent; names: string[] }> {
	const source = await findEvent(file);
	const found = await peopleOn(source);
	const people = await confirmPeople(found.people);

	let event = found.event;
	if (event) {
		const edited = people.join(", ") !== found.people.join(", ");
		event = { ...event, people };
		// Saved as record.ts would have, with the names as edited, so the next run has them too.
		if (source.kind === Origin.Picked || edited) await saveEvent(file, event);
		hint(`Event: ${event.title}`);
	}

	const names = await realNames(people);
	if (names.length) hint(`Names: ${names.join(", ")}`);
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
	| { kind: Origin.Dragged; uuid: string }
	| { kind: Origin.Ics; path: string }
	| { kind: Origin.Missing; path: string }
	| { kind: Origin.None };

async function findEvent(file: string): Promise<Source> {
	if (existsSync(eventFile(file))) {
		return { kind: Origin.Saved, event: JSON.parse(readFileSync(eventFile(file), "utf8")) };
	}
	if (process.env.ICS) return given(process.env.ICS);
	if (!process.stdin.isTTY) return { kind: Origin.None };

	const picked = await pickRecent();
	if (picked) return picked;
	return given(await ask("Calendar event, drag it here from Calendar or as .ics", "[Enter = none]"));
}

/** What was typed or dragged in: a link to an event in Calendar, or a path to an .ics. */
export function given(text: string): Source {
	const path = dropped(text);
	if (!path) return { kind: Origin.None };

	const uuid = appleEventId(path);
	if (uuid) return { kind: Origin.Dragged, uuid };

	return existsSync(path) ? { kind: Origin.Ics, path } : { kind: Origin.Missing, path };
}

/** One of Calendar's last ten, since dragging one into a terminal does not always work.
 *  Esc is no event; undefined when there is nothing to pick from. */
async function pickRecent(): Promise<Source | undefined> {
	const events = recentEvents();
	if (!events.length || !Bun.which("tv")) return undefined;

	const byLine = new Map(events.map((event) => [label(event), event]));
	const line = await pick("Which meeting was it? Esc = none", [...byLine.keys()]);
	const event = byLine.get(line);
	return event ? { kind: Origin.Picked, event } : { kind: Origin.None };
}

/** 2026-11-02 10:00  Weekly sync  · Jana Nováková, Petr Dvořák */
function label(event: CallEvent): string {
	const title = event.title || "untitled";
	const people = event.people.length ? `  · ${event.people.join(", ")}` : "";
	return `${localDate(event.start)} ${localTime(event.start)}  ${title}${people}`;
}

/** The names on the event. A mistyped path or a vanished event costs the names, not the transcript. */
async function peopleOn(source: Source): Promise<{ event?: CallEvent; people: string[] }> {
	return match(source)
		.with({ kind: Origin.Saved }, { kind: Origin.Picked }, ({ event }) => ({ event, people: event.people }))
		.with({ kind: Origin.Dragged }, ({ uuid }) => {
			const people = appleCalendarAttendees(uuid);
			if (!people.length) warn("no such event in Calendar, going on without names");
			return { people };
		})
		.with({ kind: Origin.Ics }, ({ path }) => ({ people: attendees(readFileSync(path, "utf8")) }))
		.with({ kind: Origin.Missing }, ({ path }) => {
			warn(`no such file, going on without names: ${path}`);
			return { people: [] };
		})
		.with({ kind: Origin.None }, () => ({ people: [] }))
		.exhaustive();
}

/** The event's names, to fix, cross out or add to: someone invited along is on no event.
 *  PEOPLE=… adds to them without asking. */
async function confirmPeople(people: string[]): Promise<string[]> {
	if (process.env.PEOPLE) return [...new Set([...people, ...typedNames(process.env.PEOPLE)])];
	if (!process.stdin.isTTY) return people;

	const prefill = people.length ? `${people.join(", ")}, ` : "";
	const answer = await edit("Who was on the call, besides me?", "[edit, add after a comma or semicolon; Enter = done]", prefill);
	return typedNames(answer);
}

/** Names typed as "Jana Nováková, Petr Dvořák" or with semicolons: spaces collapsed, without blanks or repeats. */
export function typedNames(text: string): string[] {
	const names = text
		.split(/[,;]/)
		.map((name) => name.replace(/\s+/g, " ").trim())
		.filter(Boolean);
	return [...new Set(names)];
}

async function saveEvent(file: string, event: CallEvent) {
	await Bun.write(eventFile(file), `${JSON.stringify(event, null, "\t")}\n`);
}

export const eventFile = (recording: string) => recording.replace(/\.[^.]*$/, ".event.json");

/** A path dragged into a terminal arrives quoted or with escaped spaces; a typed one may start with ~. */
export function dropped(text: string): string {
	return text
		.trim()
		.replace(/^'(.*)'$/, "$1")
		.replace(/^"(.*)"$/, "$1")
		.replace(/\\(.)/g, "$1")
		.replace(/^~(?=\/)/, homedir());
}

export function localDate(iso: string): string {
	const date = new Date(iso);
	return `${date.getFullYear()}-${twoDigits(date.getMonth() + 1)}-${twoDigits(date.getDate())}`;
}

export function localTime(iso: string): string {
	const date = new Date(iso);
	return `${twoDigits(date.getHours())}:${twoDigits(date.getMinutes())}`;
}

const twoDigits = (number: number) => String(number).padStart(2, "0");
