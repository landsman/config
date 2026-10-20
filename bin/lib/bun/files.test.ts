// What copyTree would get wrong silently: a kept file overwritten — OBS's
// user.ini losing what it stored since — or a placeholder left in place.
import { expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { copyTree } from "@lib/files";

test("copies the layout, fills placeholders, leaves a kept file alone", () => {
	const t = mkdtempSync(join(tmpdir(), "files-"));
	mkdirSync(`${t}/src/a/b`, { recursive: true });
	writeFileSync(`${t}/src/a/b/x.ini`, "path=@DIR@/x\n");
	writeFileSync(`${t}/src/user.ini`, "fresh\n");
	mkdirSync(`${t}/dst`);
	writeFileSync(`${t}/dst/user.ini`, "mine\n");
	copyTree(`${t}/src`, `${t}/dst`, { "@DIR@": "/home" }, ["user.ini"]);
	expect(readFileSync(`${t}/dst/a/b/x.ini`, "utf8")).toBe("path=/home/x\n");
	expect(readFileSync(`${t}/dst/user.ini`, "utf8")).toBe("mine\n");
});
