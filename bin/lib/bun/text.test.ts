import { expect, test } from "bun:test";
import { slug } from "./text";

test("accents are dropped, spaces and symbols become one dash", () =>
	expect(slug("  Porada s Šárkou: Q4 plán!  ")).toBe("porada-s-sarkou-q4-plan"));
test("nothing usable is an empty name, for the caller's fallback", () => expect(slug(" !? ")).toBe(""));
