// What saveDocument and loadDocument would get wrong silently: a signed-out op
// read as "no item yet" (a duplicate), an item outside the vault, a second copy
// instead of an edit, a load that fails on a fresh install or leaves a
// half-written file behind. op is a stub first on PATH that records its calls.
import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import {
	chmodSync,
	existsSync,
	mkdirSync,
	mkdtempSync,
	readFileSync,
	rmSync,
	statSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { loadDocument, saveDocument } from "@lib/1password";

const scratch = mkdtempSync(`${tmpdir()}/1password-`);
const calls = `${scratch}/op-calls`;
const listing = `${scratch}/op-items.json`;
const opStub = `#!/bin/sh
printf '%s\\n' "$*" >> '${calls}'
case "$1" in
whoami) [ "$OP_SIGNED_IN" = no ] && exit 1; exit 0 ;;
item) cat '${listing}'; exit 0 ;;
esac
if [ "$1 $2" = "document get" ]; then
	[ "$OP_GET_FAILS" = yes ] && { echo "no such item" >&2; exit 1; }
	prev=; for a in "$@"; do [ "$prev" = --out-file ] && echo restored > "$a"; prev=$a; done
fi
exit 0
`;
mkdirSync(`${scratch}/stubs`);
writeFileSync(`${scratch}/stubs/op`, opStub);
chmodSync(`${scratch}/stubs/op`, 0o755);
process.env.PATH = `${scratch}/stubs:${process.env.PATH}`;
afterAll(() => rmSync(scratch, { recursive: true, force: true }));

let home: string;
beforeEach(() => {
	rmSync(calls, { force: true });
	writeFileSync(listing, "[]");
	delete process.env.OP_SIGNED_IN;
	delete process.env.OP_GET_FAILS;
	home = mkdtempSync(`${scratch}/home-`);
});

const opCalls = () => (existsSync(calls) ? readFileSync(calls, "utf8") : "");
const mode = (path: string) => (statSync(path).mode & 0o777).toString(8);
const listed = (...items: { id: string; title: string }[]) =>
	writeFileSync(listing, JSON.stringify(items));

describe("expected use", () => {
	test("a new item is created in dev-homelab, with its tags", async () => {
		writeFileSync(`${home}/config`, "Host x\n");
		expect(
			await saveDocument({
				title: "ssh-config-box",
				file: `${home}/config`,
				tags: ["ssh", "dotfiles"],
			}),
		).toBe("created");
		expect(opCalls()).toContain("item list --vault dev-homelab --categories Document");
		expect(opCalls()).toContain(
			`document create ${home}/config --title ssh-config-box --vault dev-homelab --tags ssh,dotfiles`,
		);
	});
	test("an existing item is edited by its id, not created again", async () => {
		writeFileSync(`${home}/config`, "Host x\n");
		listed({ id: "abc", title: "ssh-config-box" }, { id: "other", title: "ssh-config-another" });
		expect(await saveDocument({ title: "ssh-config-box", file: `${home}/config` })).toBe("updated");
		expect(opCalls()).toContain(`document edit abc ${home}/config --vault dev-homelab`);
		expect(opCalls()).not.toContain("document create");
	});
	test("a named vault is used for the lookup and the write", async () => {
		writeFileSync(`${home}/config`, "Host x\n");
		await saveDocument({ title: "t", file: `${home}/config`, vault: "Private" });
		expect(opCalls()).toContain("item list --vault Private");
		expect(opCalls()).toContain("--title t --vault Private");
	});
	test("a load replaces the file, owner-only, with no partial left", async () => {
		writeFileSync(`${home}/config`, "old\n", { mode: 0o644 });
		listed({ id: "abc", title: "ssh-config-box" });
		expect(await loadDocument({ title: "ssh-config-box", file: `${home}/config` })).toBe("loaded");
		expect(readFileSync(`${home}/config`, "utf8")).toBe("restored\n");
		expect(mode(`${home}/config`)).toBe("600");
		expect(opCalls()).toContain("document get abc --vault dev-homelab --out-file");
		expect(existsSync(`${home}/config.loading`)).toBe(false);
	});
	test("a load on a fresh install creates the folder, owner-only", async () => {
		listed({ id: "abc", title: "ssh-config-box" });
		await loadDocument({ title: "ssh-config-box", file: `${home}/.ssh/config` });
		expect(readFileSync(`${home}/.ssh/config`, "utf8")).toBe("restored\n");
		expect(mode(`${home}/.ssh`)).toBe("700");
	});
});

describe("bad input", () => {
	test("signed out, a save is refused and nothing is created", async () => {
		writeFileSync(`${home}/config`, "Host x\n");
		process.env.OP_SIGNED_IN = "no";
		await expect(saveDocument({ title: "t", file: `${home}/config` })).rejects.toThrow(
			"not signed in",
		);
		expect(opCalls()).not.toContain("document create");
	});
	test("two items with the title are an error, not a guess", async () => {
		writeFileSync(`${home}/config`, "Host x\n");
		listed({ id: "a", title: "t" }, { id: "b", title: "t" });
		await expect(saveDocument({ title: "t", file: `${home}/config` })).rejects.toThrow(
			"2 items titled t",
		);
	});
	test("a missing file is refused before op is asked anything", async () => {
		await expect(saveDocument({ title: "t", file: `${home}/nothing` })).rejects.toThrow("no ");
		expect(opCalls()).toBe("");
	});
	test("an item never saved is missing, and nothing is written", async () => {
		expect(await loadDocument({ title: "t", file: `${home}/.claude/settings.local.json` })).toBe(
			"missing",
		);
		expect(existsSync(`${home}/.claude`)).toBe(false);
		expect(opCalls()).not.toContain("document get");
	});
	test("a failed download leaves the file as it was, with op's reason", async () => {
		writeFileSync(`${home}/config`, "old\n");
		listed({ id: "abc", title: "t" });
		process.env.OP_GET_FAILS = "yes";
		await expect(loadDocument({ title: "t", file: `${home}/config` })).rejects.toThrow(
			"no such item",
		);
		expect(readFileSync(`${home}/config`, "utf8")).toBe("old\n");
		expect(existsSync(`${home}/config.loading`)).toBe(false);
	});
});
