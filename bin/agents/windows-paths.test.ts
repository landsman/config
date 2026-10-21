// What windows.yml would get wrong silently: a lib it leaves out of its path
// filter, as macOS-only, imported by a hook that runs on Windows, or by a lib
// such a hook imports. A change to it would then never reach the Windows job.
import { expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "../..");

test("no hook reaches a lib the Windows job ignores", () => {
	const workflow = readFileSync(join(root, ".github/workflows/windows.yml"), "utf8");
	const ignored = [...workflow.matchAll(/'!bin\/lib\/bun\/([\w-]+)\*\.ts'/g)].map((m) => m[1]);
	expect(ignored.length).toBeGreaterThan(0);
	const sources = (dir: string) =>
		readdirSync(join(root, dir)).filter((f) => f.endsWith(".ts") && !f.endsWith(".test.ts")).map((f) => `${dir}/${f}`);
	const onWindows = [...sources("bin/agents"), ...sources("bin/lib/bun").filter((f) => !ignored.some((l) => f === `bin/lib/bun/${l}.ts`))];
	const reaching = onWindows.flatMap((f) =>
		ignored.filter((l) => readFileSync(join(root, f), "utf8").includes(`"@lib/${l}"`)).map((l) => `${f} imports @lib/${l}`));
	expect(reaching).toEqual([]);
});
