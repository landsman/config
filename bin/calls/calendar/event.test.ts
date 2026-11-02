// What event.ts would get wrong silently: a dragged path left quoted or a typed ~
// unexpanded, a link taken for a path, names typed by hand split wrong — and,
// with bad input, a transcript that fails or an event read from the wrong file:
// a saved event cut short or edited by hand, a folder dragged in, a dot in a
// folder's name, a link that is not quite one.
import { afterEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { callEvent, draggedPath, eventFilePath, eventFromText, Origin, typedNames } from "@bin/calls/calendar/event";

// bun test runs without a terminal, so callEvent asks nothing and takes ICS and PEOPLE.
afterEach(() => {
	delete process.env.ICS;
	delete process.env.PEOPLE;
});

const callFolder = () => mkdtempSync(join(tmpdir(), "call-"));

const invitation = (...people: string[]) => {
	return ["BEGIN:VCALENDAR", "BEGIN:VEVENT", ...people, "END:VEVENT", "END:VCALENDAR"].join("\r\n");
};

const savedEventJson = {
	uuid: "SYNC",
	title: "Weekly sync",
	start: "2026-11-02T09:00:00.000Z",
	end: "2026-11-02T09:30:00.000Z",
	me: "Me",
	people: ["Jana Nováková"],
};

describe("expected use", () => {
	test("a dragged-in path loses its quotes and escapes", () => {
		expect(draggedPath("/Users/me/Downloads/Porada\\ Q4.ics ")).toBe("/Users/me/Downloads/Porada Q4.ics");
		expect(draggedPath("'/Users/me/a b.ics'")).toBe("/Users/me/a b.ics");
		expect(draggedPath("~/a.ics")).toBe(`${homedir()}/a.ics`);
	});

	test("names typed by hand are split on commas or semicolons, spaces collapsed, without blanks or repeats", () => {
		expect(typedNames(" Jana Nováková, Petr Dvořák,, Jana  Nováková ")).toEqual(["Jana Nováková", "Petr Dvořák"]);
		expect(typedNames("Jana Nováková; Petr\tDvořák ;Tomáš Novák")).toEqual(["Jana Nováková", "Petr Dvořák", "Tomáš Novák"]);
		expect(typedNames("")).toEqual([]);
	});

	test("what is dragged in is a link to an event, an .ics there, one that is not, or nothing", () => {
		const uuid = "55F9EE9B-1377-4F01-A442-79E9AC71B5BC";
		expect(eventFromText(`ical://occurrence/20261020T110000Z/${uuid}\\?method=show`)).toEqual({ kind: Origin.Dragged, eventId: uuid });
		expect(eventFromText(import.meta.path)).toEqual({ kind: Origin.Ics, path: import.meta.path });
		expect(eventFromText("/nowhere/a\\ b.ics")).toEqual({ kind: Origin.Missing, path: "/nowhere/a b.ics" });
		expect(eventFromText("  ")).toEqual({ kind: Origin.None });
	});

	test("the saved event sits beside the recording, whatever dots the folders have", () => {
		expect(eventFilePath("/Users/me/Recordings/20261102-sync/20261102-sync.m4a")).toBe("/Users/me/Recordings/20261102-sync/20261102-sync.event.json");
		expect(eventFilePath("/Users/me/Rec.2026/call")).toBe("/Users/me/Rec.2026/call.event.json");
	});

	test("an .ics given in ICS is read, and PEOPLE adds to its names", async () => {
		const folder = callFolder();
		const calendarFile = join(folder, "event.ics");
		writeFileSync(calendarFile, invitation("ORGANIZER;CN=Jana Nováková:mailto:jana@example.com"));
		process.env.ICS = calendarFile;
		process.env.PEOPLE = "Tomáš Novák, jana nováková";

		const { event, names } = await callEvent(join(folder, "call.m4a"));

		expect(event).toBeUndefined();
		expect(names).toEqual(["Jana Nováková", "Tomáš Novák"]);
	});

	test("a saved event comes first, and names added to it are saved with it", async () => {
		const folder = callFolder();
		const recording = join(folder, "call.m4a");
		writeFileSync(eventFilePath(recording), JSON.stringify(savedEventJson));
		process.env.ICS = "/somewhere/else.ics";
		process.env.PEOPLE = "Petr Dvořák";

		const { event, names } = await callEvent(recording);

		expect(event?.title).toBe("Weekly sync");
		expect(names).toEqual(["Jana Nováková", "Petr Dvořák"]);
		expect(JSON.parse(await Bun.file(eventFilePath(recording)).text()).people).toEqual(["Jana Nováková", "Petr Dvořák"]);
	});
});

describe("bad input", () => {
	test("names typed badly: only separators, or one name twice in another case", () => {
		expect(typedNames(" , ;; ,")).toEqual([]);
		expect(typedNames("Jana Nováková, jana nováková, JANA NOVÁKOVÁ")).toEqual(["Jana Nováková"]);
	});

	test("dragged in badly: a folder, or a link cut short, is no event", () => {
		const folder = callFolder();
		expect(eventFromText(folder)).toEqual({ kind: Origin.Missing, path: folder });
		expect(eventFromText("ical://occurrence/20261020T110000Z/55F9EE9B")).toEqual({
			kind: Origin.Missing,
			path: "ical://occurrence/20261020T110000Z/55F9EE9B",
		});
	});

	test("a saved event cut short or edited badly costs the event, not the transcript", async () => {
		const folder = callFolder();
		const broken = [
			'{"uuid": "SYNC", "title": "Weekly',
			"[]",
			"null",
			JSON.stringify({ ...savedEventJson, title: 42 }),
		];
		for (const [index, content] of broken.entries()) {
			const recording = join(folder, `call-${index}.m4a`);
			writeFileSync(eventFilePath(recording), content);
			expect(await callEvent(recording)).toEqual({ event: undefined, names: [] });
		}
	});

	test("a saved event without people, or with something else in them, keeps only the names", async () => {
		const folder = callFolder();
		const recording = join(folder, "call.m4a");
		const { people: _, ...withoutPeople } = savedEventJson;
		writeFileSync(eventFilePath(recording), JSON.stringify(withoutPeople));
		expect((await callEvent(recording)).names).toEqual([]);

		writeFileSync(eventFilePath(recording), JSON.stringify({ ...savedEventJson, people: ["Jana Nováková", null, 7] }));
		expect((await callEvent(recording)).names).toEqual(["Jana Nováková"]);
	});

	test("an ICS that is a folder, missing, or not a calendar at all gives no names and no failure", async () => {
		const folder = callFolder();
		const notACalendar = join(folder, "notes.txt");
		writeFileSync(notACalendar, "just some notes\nATTENDEE is a word here");
		mkdirSync(join(folder, "event.ics"));

		for (const given of [join(folder, "event.ics"), join(folder, "missing.ics"), notACalendar]) {
			process.env.ICS = given;
			expect(await callEvent(join(folder, "call.m4a"))).toEqual({ event: undefined, names: [] });
		}
	});
});
