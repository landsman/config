// What addExtensions would get wrong silently: a missing comma (Zed then
// ignores the whole settings file), an entry set to false flipped back on,
// or a duplicate key.
import { describe, expect, test } from "bun:test";
import { addExtensions } from "@bin/zed/extensions";

const settings = `// a comment JSON.parse would refuse
{
  "auto_install_extensions": {
    "make": true,
    "emmet": false
  },
  "theme": { "dark": "x" }
}
`;

describe("expected use", () => {
	test("a missing extension is added after the last entry, commas right", () => {
		expect(addExtensions(settings, ["emmet", "make", "php", "toml"])).toEqual({
			added: ["php", "toml"],
			text: settings.replace(
				'"emmet": false\n',
				'"emmet": false,\n    "php": true,\n    "toml": true\n',
			),
		});
	});
	test("a listed extension, false included, is left alone", () => {
		expect(addExtensions(settings, ["emmet", "make"])).toEqual({ added: [], text: settings });
	});
	test("a second run changes nothing", () => {
		const once = addExtensions(settings, ["php"]).text;
		expect(addExtensions(once, ["php"]).text).toBe(once);
	});
});

describe("bad input", () => {
	test("a file without the block is refused, not written", () => {
		expect(() => addExtensions('{ "theme": "x" }', ["php"])).toThrow("no auto_install_extensions");
	});
	test("nothing installed changes nothing", () => {
		expect(addExtensions(settings, [])).toEqual({ added: [], text: settings });
	});
});
