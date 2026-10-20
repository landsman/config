// What transcribe.ts would get wrong silently: the two tracks merged out of
// order, a turn split on every segment, whisper's own notes read as speech,
// and the names from a calendar event missed or mangled — folded lines, quoted
// names, an attendee who is only an address, a typed ~ — and Enter at the
// list of recordings not meaning the newest.
import { expect, test } from "bun:test";
import { homedir } from "node:os";
import { attendees, dropped, merge, pick } from "@bin/obs/transcribe";

test("tracks are merged by time, one line per turn", () =>
	expect(merge([
		{ who: "Them", segments: [{ from: 0, text: " Ahoj." }, { from: 2000, text: " Slyšíš mě?" }, { from: 9000, text: " Super." }] },
		{ who: "Me", segments: [{ from: 5000, text: " Jo, slyším." }, { from: 3_725_000, text: " Čau." }] },
	])).toBe("[00:00] Them: Ahoj. Slyšíš mě?\n[00:05] Me: Jo, slyším.\n[00:09] Them: Super.\n[1:02:05] Me: Čau.\n"));

test("whisper's notes and empty segments are dropped", () =>
	expect(merge([{ who: "Me", segments: [{ from: 0, text: " [BLANK_AUDIO]" }, { from: 1, text: " (hudba)" }, { from: 2, text: " " }] }])).toBe(""));

test("one unlabelled track has no speaker", () =>
	expect(merge([{ who: "", segments: [{ from: 61_000, text: "Hello." }] }])).toBe("[01:01] Hello.\n"));

test("names come from the organizer and attendees, folded and quoted, no bare addresses", () =>
	expect(attendees([
		"BEGIN:VEVENT",
		"ORGANIZER;CN=Jana Nováková:mailto:jana@example.com",
		'ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;CN="Petr Dvořák";PARTSTAT=ACCEPTED:mai',
		" lto:petr@example.com",
		"ATTENDEE;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;CN=Jana Nováková:mailto:jana@example.com",
		"ATTENDEE;CN=someone@example.com:mailto:someone@example.com",
		"END:VEVENT",
	].join("\r\n"))).toEqual(["Jana Nováková", "Petr Dvořák"]));

test("a dragged-in path loses its quotes and escapes", () => {
	expect(dropped("/Users/me/Downloads/Porada\\ Q4.ics ")).toBe("/Users/me/Downloads/Porada Q4.ics");
	expect(dropped("'/Users/me/a b.ics'")).toBe("/Users/me/a b.ics");
	expect(dropped("~/a.ics")).toBe(`${homedir()}/a.ics`);
});

test("Enter picks the newest, a number its line, anything else is refused", () => {
	const list = ["/r/new.m4a", "/r/old.m4a"];
	expect(pick("", list)).toBe("/r/new.m4a");
	expect(pick("2", list)).toBe("/r/old.m4a");
	for (const bad of ["0", "3", "x", "1.5"]) expect(() => pick(bad, list)).toThrow();
});
