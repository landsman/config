// What media.ts would get wrong silently: minutes and seconds miscounted, or a
// file ffprobe cannot read throwing instead of showing a zero length. ffprobe
// is a stub on PATH that answers what FFPROBE_SAYS holds.
import { afterAll, expect, test } from "bun:test";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe } from "@lib/media";

const dir = mkdtempSync(join(tmpdir(), "media-"));
afterAll(() => rmSync(dir, { recursive: true }));
writeFileSync(join(dir, "ffprobe"), '#!/bin/sh\necho "$FFPROBE_SAYS"\n');
chmodSync(join(dir, "ffprobe"), 0o755);
process.env.PATH = `${dir}:${process.env.PATH}`;
const file = join(dir, "call.m4a");
writeFileSync(file, Buffer.alloc(12_345_678));

test("size and length as a person reads them", async () => {
	process.env.FFPROBE_SAYS = "245.4";
	expect(await describe(file)).toBe("12.3 MB · 4:05");
});
test("seconds are rounded, and a full minute carries over", async () => {
	process.env.FFPROBE_SAYS = "59.6";
	expect(await describe(file)).toBe("12.3 MB · 1:00");
});
test("a length ffprobe cannot tell is 0:00", async () => {
	process.env.FFPROBE_SAYS = "N/A";
	expect(await describe(file)).toBe("12.3 MB · 0:00");
});
