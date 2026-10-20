// What cli.ts would get wrong silently: an unknown command running something
// anyway, a failure exiting 0 (make carries on), or the usage losing its lines.
import { afterAll, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const dir = mkdtempSync(join(tmpdir(), "cli-"));
afterAll(() => rmSync(dir, { recursive: true }));
const script = join(dir, "tool.ts");
writeFileSync(script, `// A tool for the test.
//
// usage: tool.ts greet [name]   say hello
//        tool.ts fail           exit with an error
import { cli } from ${JSON.stringify(join(import.meta.dir, "cli.ts"))};
await cli(import.meta.path, {
	greet: async (name = "world") => console.log("hello " + name),
	fail: async () => { throw new Error("it broke"); },
});
`);

async function run(...args: string[]) {
	const proc = Bun.spawn([process.execPath, script, ...args], { stdout: "pipe", stderr: "pipe" });
	const [out, err] = [await new Response(proc.stdout).text(), await new Response(proc.stderr).text()];
	return { code: await proc.exited, out, err };
}

test("a command gets its argument", async () => expect(await run("greet", "Šárka")).toMatchObject({ code: 0, out: "hello Šárka\n" }));
test("a command without one gets its default", async () => expect((await run("greet")).out).toBe("hello world\n"));
test("an unknown command prints the usage and exits 2", async () =>
	expect(await run("nope")).toMatchObject({ code: 2, err: "usage: tool.ts greet [name]   say hello\n       tool.ts fail           exit with an error\n" }));
test("a failure is one line on stderr and exit 1", async () => {
	const r = await run("fail");
	expect(r.code).toBe(1);
	expect(r.err).toContain("it broke");
	expect(r.err).not.toContain("at ");
});
