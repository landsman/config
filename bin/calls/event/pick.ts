// Which meeting a recording was and who was on it, for whisper's prompt and the
// transcript's header: the event record.ts found in Calendar when the call stopped
// (<recording>.event.json), else one of Calendar's last ten picked in television,
// else an .ics file or an event dragged out of Apple Calendar (apple-calendar.ts).
// Its names are then shown on a line to edit, since someone invited along is on
// no event; PEOPLE=… adds to them instead. One known only by address is named in
// contacts.ts.
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { appleCalendarAttendees, appleEventId, type CallEvent, recentEvents } from "@bin/calls/event/apple-calendar";
import { realNames } from "@bin/calls/event/contacts";
import { ask, edit, hint, pick, warn } from "@lib/term";

/** The event a recording was, if known, and the others on the call by name. */
export async function callEvent(file: string): Promise<{ event?: CallEvent; names: string[] }> {
	// The one saved when the call was stopped; asked for only when there is none.
	let event = existsSync(eventFile(file)) ? (JSON.parse(readFileSync(eventFile(file), "utf8")) as CallEvent) : undefined;
	let ics = event ? "" : dropped(process.env.ICS ?? "");
	let save = false;
	if (!event && !ics && process.stdin.isTTY) {
		const picked = await pickRecent();
		if (picked && picked !== "none") [event, save] = [picked, true];
		else if (!picked) ics = dropped(await ask("Calendar event, drag it here from Calendar or as .ics", "[Enter = none]"));
	}
	// A mistyped path costs the names, not the transcript.
	const apple = appleEventId(ics);
	let people = event?.people ?? (apple ? appleCalendarAttendees(apple) : ics && existsSync(ics) ? attendees(readFileSync(ics, "utf8")) : []);
	if (apple && !people.length) warn("no such event in Calendar, going on without names");
	else if (ics && !apple && !existsSync(ics)) warn(`no such file, going on without names: ${ics}`);
	// The event's names, to fix, cross out or add to: someone invited along is on no event.
	const before = people.join(", ");
	if (process.env.PEOPLE) people = [...new Set([...people, ...typedNames(process.env.PEOPLE)])];
	else if (process.stdin.isTTY) people = typedNames(await edit("Who was on the call, besides me?", "[edit, add after a comma or semicolon; Enter = done]", people.length ? `${before}, ` : ""));
	if (event && people.join(", ") !== before) [event, save] = [{ ...event, people }, true];
	// Saved as record.ts would have, with the names as edited, so the next run has them too.
	if (event && save) await Bun.write(eventFile(file), `${JSON.stringify(event, null, "\t")}\n`);
	const names = await realNames(people);
	if (event) hint(`Event: ${event.title}`);
	if (names.length) hint(`Names: ${names.join(", ")}`);
	return { event, names };
}

/** The event a recording was, picked from Calendar's last ten, since dragging one into a
 *  terminal does not always work. Esc = none. Undefined too when there is nothing to pick from. */
async function pickRecent(): Promise<CallEvent | "none" | undefined> {
	const events = recentEvents();
	if (!events.length || !Bun.which("tv")) return undefined;
	const byLine = new Map(events.map((e) => [`${day(e.start)} ${hm(e.start)}  ${e.title || "untitled"}${e.people.length ? `  · ${e.people.join(", ")}` : ""}`, e]));
	return byLine.get(await pick("Which meeting was it? Esc = none", [...byLine.keys()])) ?? "none";
}

/** The people on a calendar event, its organizer and attendees: a name, or an address when it has none. */
export function attendees(ics: string): string[] {
	const unfolded = ics.replace(/\r?\n[ \t]/g, ""); // a long line goes on after a newline and a space
	return [...new Set([...unfolded.matchAll(/^(?:ATTENDEE|ORGANIZER)[^:\n]*?;CN=("?)([^";:\n]+)\1/gm)].map((m) => m[2].trim()))];
}

/** A path dragged into a terminal arrives quoted or with escaped spaces; a typed one may start with ~. */
export const dropped = (s: string) =>
	s.trim().replace(/^'(.*)'$/, "$1").replace(/^"(.*)"$/, "$1").replace(/\\(.)/g, "$1").replace(/^~(?=\/)/, homedir());

/** Names typed as "Jana Nováková, Petr Dvořák" or with semicolons: spaces collapsed, without blanks or repeats. */
export const typedNames = (s: string) => [...new Set(s.split(/[,;]/).map((n) => n.replace(/\s+/g, " ").trim()).filter(Boolean))];

export const eventFile = (recording: string) => recording.replace(/\.[^.]*$/, ".event.json");

const pad = (n: number) => String(n).padStart(2, "0");
export const day = (iso: string) => { const d = new Date(iso); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; };
export const hm = (iso: string) => { const d = new Date(iso); return `${pad(d.getHours())}:${pad(d.getMinutes())}`; };
