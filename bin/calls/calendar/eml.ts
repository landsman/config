// An invitation saved from a mail app as .eml: the calendar rides in it as one MIME
// part, and Outlook sends that part as base64, so its people cannot be read where
// they lie. Only that part is taken out; the rest of the e-mail is not read.
import { match } from "ts-pattern";

/** The calendar inside an e-mail, or the file as it is when it is no e-mail, as a plain
 *  .ics is not. An e-mail with no calendar in it holds none: its text is not read, where a
 *  line could look like an attendee. Each MIME part is headers, a blank line, then the body. */
export function calendarIn(file: string): string {
	if (!/^Content-Type:/im.test(file)) {
		return file;
	}
	for (const part of file.split(/^--\S+[ \t]*\r?$/m)) {
		const [headers, ...body] = part.replace(/^\r?\n/, "").split(/\r?\n\r?\n/);
		if (!/^Content-Type:[ \t]*text\/calendar/im.test(headers)) {
			continue;
		}
		const encoding = headers.match(/^Content-Transfer-Encoding:[ \t]*(\S+)/im)?.[1];
		// ponytail: read as UTF-8 whatever charset the part names; every invitation seen so far is.
		// The line break before the next boundary is the boundary's, not the part's.
		const partBody = body.join("\r\n\r\n").replace(/\r?\n$/, "");
		return decoded(partBody, encoding?.toLowerCase());
	}
	return "";
}

function decoded(body: string, encoding: string | undefined): string {
	return match(encoding)
		.with("base64", () => {
			return Buffer.from(body, "base64").toString("utf8");
		})
		.with("quoted-printable", () => {
			return body.replace(/=\r?\n/g, "").replace(/(?:=[0-9A-F]{2})+/gi, (bytes) => {
				return Buffer.from(bytes.replaceAll("=", ""), "hex").toString("utf8");
			});
		})
		.otherwise(() => {
			return body;
		});
}
