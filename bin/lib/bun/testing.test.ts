// What would go wrong silently: a script that imports a test or a test helper,
// and so ships a fake database, a stub or a fixture into what runs for real.
// Test code is a *.test.ts file, or testing.ts, the helper the tests share;
// everything else under bin/ is production code and may import neither.
import { describe, expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const binFolder = join(import.meta.dir, "../..");

describe("expected use", () => {
	test("no script under bin/ imports a test or a test helper", () => {
		const productionFiles = readdirSync(binFolder, { recursive: true, encoding: "utf8" })
			.filter((path) => path.endsWith(".ts") && !path.includes("node_modules"))
			.filter((path) => !isTestCode(path));
		const offending = productionFiles.filter((path) => {
			const source = readFileSync(join(binFolder, path), "utf8");
			return importsTestCode(source);
		});

		expect(offending).toEqual([]);
	});
});

describe("bad input", () => {
	test("an import of a test file or of the test helper is caught, however it is written", () => {
		expect(importsTestCode('import { book } from "@bin/calls/macos/contacts.test";')).toBe(true);
		expect(importsTestCode('import { runHook } from "@lib/testing";')).toBe(true);
		expect(importsTestCode('import { runHook } from "./testing";')).toBe(true);
		expect(importsTestCode('const helpers = await import("./relay.test.ts");')).toBe(true);
	});

	test("a word that only looks alike is not an import of test code", () => {
		expect(importsTestCode('import { cli } from "@lib/cli";')).toBe(false);
		expect(importsTestCode('// tested by hand, see testing notes')).toBe(false);
		expect(importsTestCode('import { latest } from "@lib/latest-testing-tools";')).toBe(false);
	});
});

function isTestCode(path: string): boolean {
	return path.endsWith(".test.ts") || path.endsWith("/testing.ts");
}

/** An import or a dynamic import() whose path ends in .test, .test.ts or /testing. */
function importsTestCode(source: string): boolean {
	return /(?:from\s+|import\()\s*["'][^"']*(?:\.test(?:\.ts)?|[/@]lib\/testing|\/testing)["']/.test(source);
}
