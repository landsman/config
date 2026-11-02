// What event.ts would get wrong silently: a dragged path
// left quoted or a typed ~ unexpanded, a link taken for a path, and names typed
// by hand split wrong.
import { expect, test } from "bun:test";
import { homedir } from "node:os";
import { dropped, given, typedNames } from "@bin/calls/calendar/event";

test("a dragged-in path loses its quotes and escapes", () => {
	expect(dropped("/Users/me/Downloads/Porada\\ Q4.ics ")).toBe("/Users/me/Downloads/Porada Q4.ics");
	expect(dropped("'/Users/me/a b.ics'")).toBe("/Users/me/a b.ics");
	expect(dropped("~/a.ics")).toBe(`${homedir()}/a.ics`);
});

test("names typed by hand are split on commas or semicolons, spaces collapsed, without blanks or repeats", () => {
	expect(typedNames(" Jana Nováková, Petr Dvořák,, Jana  Nováková ")).toEqual(["Jana Nováková", "Petr Dvořák"]);
	expect(typedNames("Jana Nováková; Petr\tDvořák ;Tomáš Novák")).toEqual(["Jana Nováková", "Petr Dvořák", "Tomáš Novák"]);
	expect(typedNames("")).toEqual([]);
});

test("what is dragged in is a link to an event, an .ics there, one that is not, or nothing", () => {
	const uuid = "55F9EE9B-1377-4F01-A442-79E9AC71B5BC";
	expect(given(`ical://occurrence/20261020T110000Z/${uuid}\\?method=show`)).toEqual({ kind: "dragged", uuid });
	expect(given(import.meta.path)).toEqual({ kind: "ics", path: import.meta.path });
	expect(given("/nowhere/a\\ b.ics")).toEqual({ kind: "missing", path: "/nowhere/a b.ics" });
	expect(given("  ")).toEqual({ kind: "none" });
});
