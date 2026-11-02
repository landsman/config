// What event.ts would get wrong silently: a dragged path
// left quoted or a typed ~ unexpanded, and names typed by hand split wrong.
import { expect, test } from "bun:test";
import { homedir } from "node:os";
import { dropped, typedNames } from "@bin/calls/calendar/event";

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
