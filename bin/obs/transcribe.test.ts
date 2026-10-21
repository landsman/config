// What transcribe.ts would get wrong silently: the two tracks merged out of
// order, a turn split on every segment or never, whisper's own notes read as speech,
// and the names from a calendar event missed or mangled — folded lines, quoted
// names, a name listed twice, a typed ~ — and Enter not
// meaning the quick model.
import { expect, test } from "bun:test";
import { homedir } from "node:os";
import { attendees, dropped, merge, speed } from "@bin/obs/transcribe";

test("tracks are merged by time, one line per turn", () =>
	expect(merge([
		{ who: "Them", segments: [{ from: 0, text: " Ahoj." }, { from: 2000, text: " Slyšíš mě?" }, { from: 9000, text: " Super." }] },
		{ who: "Me", segments: [{ from: 5000, text: " Jo, slyším." }, { from: 3_725_000, text: " Čau." }] },
	])).toBe("[00:00] Them: Ahoj. Slyšíš mě?\n[00:05] Me: Jo, slyším.\n[00:09] Them: Super.\n[1:02:05] Me: Čau.\n"));

test("whisper's notes and empty segments are dropped", () =>
	expect(merge([{ who: "Me", segments: [{ from: 0, text: " [BLANK_AUDIO]" }, { from: 1, text: " (hudba)" }, { from: 2, text: " " }] }])).toBe(""));

test("a long turn starts a new line every minute", () =>
	expect(merge([{ who: "Them", segments: [{ from: 0, text: "A." }, { from: 59_000, text: "B." }, { from: 60_000, text: "C." }] }]))
		.toBe("[00:00] Them: A. B.\n[01:00] Them: C.\n"));

test("one unlabelled track has no speaker", () =>
	expect(merge([{ who: "", segments: [{ from: 61_000, text: "Hello." }] }])).toBe("[01:01] Hello.\n"));

test("names come from the organizer and attendees, folded and quoted, once each", () =>
	expect(attendees([
		"BEGIN:VEVENT",
		"ORGANIZER;CN=Jana Nováková:mailto:jana@example.com",
		'ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;CN="Petr Dvořák";PARTSTAT=ACCEPTED:mai',
		" lto:petr@example.com",
		"ATTENDEE;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;CN=Jana Nováková:mailto:jana@example.com",
		"ATTENDEE;CN=someone@example.com:mailto:someone@example.com",
		"END:VEVENT",
	].join("\r\n"))).toEqual(["Jana Nováková", "Petr Dvořák", "someone@example.com"]));

test("a dragged-in path loses its quotes and escapes", () => {
	expect(dropped("/Users/me/Downloads/Porada\\ Q4.ics ")).toBe("/Users/me/Downloads/Porada Q4.ics");
	expect(dropped("'/Users/me/a b.ics'")).toBe("/Users/me/a b.ics");
	expect(dropped("~/a.ics")).toBe(`${homedir()}/a.ics`);
});

test("Enter means quick, p precise, anything else is refused", () => {
	expect(speed("")).toBe("quick");
	expect(speed("p")).toBe("precise");
	expect(() => speed("x")).toThrow();
});
