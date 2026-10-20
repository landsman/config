import { expect, test } from "bun:test";
import { fold, frontmatter, slug } from "@lib/text";

test("accents are dropped, spaces and symbols become one dash", () =>
	expect(slug("  Porada s Šárkou: Q4 plán!  ")).toBe("porada-s-sarkou-q4-plan"));
test("nothing usable is an empty name, for the caller's fallback", () => expect(slug(" !? ")).toBe(""));
test("fold drops diacritics and keeps the rest", () => expect(fold("Rešerše, ÚČET, naïve 42")).toBe("Reserse, UCET, naive 42"));
test("frontmatter reads top-level keys only", () =>
	expect(frontmatter("---\nname: pg\nmetadata:\n  type: x\nurl: a:b\n---\nbody: no")).toEqual({ name: "pg", metadata: "", url: "a:b" }));
