// What ics.ts would get wrong silently: names missed or mangled — folded lines,
// quoted names, a name listed twice.
import { expect, test } from "bun:test";
import { attendees } from "@bin/calls/calendar/ics";

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
