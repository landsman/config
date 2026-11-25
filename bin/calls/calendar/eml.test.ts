// What eml.ts would get wrong silently: a calendar left encoded, or the e-mail's own
// text read as one, and the names on the invitation lost or made up.
import { describe, expect, test } from "bun:test";
import { calendarIn } from "@bin/calls/calendar/eml";

const calendar = [
	"BEGIN:VCALENDAR",
	"BEGIN:VEVENT",
	"ORGANIZER;CN=Jana Nováková:mailto:jana@example.com",
	"ATTENDEE;CN=Petr Dvořák:mailto:petr@example.com",
	"END:VEVENT",
	"END:VCALENDAR",
].join("\r\n");

const email = (encoding: string, body: string) => {
	return [
		"From: Jana Nováková <jana@example.com>",
		'Content-Type: multipart/alternative; boundary="b1"',
		"",
		"--b1",
		"Content-Type: text/plain",
		"",
		"ATTENDEE;CN=Not Real:mailto:no@example.com",
		"--b1",
		'Content-Type: text/calendar; charset="utf-8"; method=REQUEST',
		`Content-Transfer-Encoding: ${encoding}`,
		"",
		body,
		"--b1--",
	].join("\r\n");
};

describe("expected use", () => {
	test("the calendar part sent as base64, as Outlook does, comes out as written", () => {
		const base64 = Buffer.from(calendar).toString("base64").replace(/.{76}/g, "$&\r\n");

		expect(calendarIn(email("base64", base64))).toBe(calendar);
	});

	test("quoted-printable, a character split over a soft line break included", () => {
		const quotedPrintable = calendar.replaceAll("á", "=C3=A1").replaceAll("ř", "=C5=\r\n=99");

		expect(calendarIn(email("quoted-printable", quotedPrintable))).toBe(calendar);
	});

	test("a calendar part sent as it is", () => {
		expect(calendarIn(email("8bit", calendar))).toBe(calendar);
	});

	test("a plain .ics is no e-mail and stays as it is", () => {
		expect(calendarIn(calendar)).toBe(calendar);
	});
});

describe("bad input", () => {
	test("an e-mail with no calendar in it holds none, so no names are made from its text", () => {
		const plain = email("8bit", "").replace("text/calendar", "text/html");

		expect(calendarIn(plain)).toBe("");
	});

	test("nothing at all", () => {
		expect(calendarIn("")).toBe("");
	});
});
