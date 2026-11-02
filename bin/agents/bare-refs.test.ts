// What bare-refs.ts would get wrong silently: letting `#1011` through without a link,
// or holding a reply whose number does carry one, or a draft meant for the forge.
import { expect, test } from "bun:test";
import { bare } from "./bare-refs";

const url = "https://git.insuit.cz/owner/repo/pulls/1011";

test("a bare #number is caught", () =>
	expect(bare("Mergnuto v #1011, viz výše.")).toEqual(["#1011"]));
test("PR and run with a number are caught", () =>
	expect(bare("PR 177 a run #6201 spadly")).toEqual(["PR 177", "run #6201"]));
test("a number beside its URL passes", () => expect(bare(`#1011: ${url}`)).toEqual([]));
test("a GitHub pull URL counts", () =>
	expect(bare("#33 https://github.com/o/r/pull/33")).toEqual([]));
test("a Forgejo run URL counts", () =>
	expect(bare("run 6179 https://git.insuit.cz/o/r/actions/runs/6179")).toEqual([]));
test("a run number unlike its URL id is caught", () =>
	expect(bare("run #6201: https://git.insuit.cz/o/r/actions/runs/6179")).toEqual(["run #6201"]));
test("a fenced draft keeps its #number", () =>
	expect(bare("```markdown\nFollows #1011.\n```")).toEqual([]));
test("inline code passes", () => expect(bare("barva `#000` a `#12`")).toEqual([]));
test("an HTML entity and a URL fragment pass", () =>
	expect(bare("&#123; a /docs/#42")).toEqual([]));
test("a heading mark is not a number", () => expect(bare("## Co se spouští")).toEqual([]));
