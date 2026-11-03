// Files kept in 1Password as Document items, for the scripts under bin/: what
// stays out of this public repo, such as a config naming a client's network,
// but still needs a copy off the machine. Needs the 1Password CLI signed in.
import { $ } from "bun";
import { chmodSync, existsSync, mkdirSync, renameSync, rmSync } from "node:fs";
import { dirname } from "node:path";

/** The vault an item goes to unless the caller names another. */
export const defaultVault = "dev-homelab";

/** Uploads `file` as the Document `title`, editing the item when it is already
 *  there, so a machine keeps one item and not a pile of copies. */
export async function saveDocument(request: SaveRequest): Promise<"created" | "updated"> {
	const vault = request.vault ?? defaultVault;
	if (!existsSync(request.file)) {
		throw new Error(`no ${request.file} to save`);
	}
	await requireSignedIn();
	const existing = await findDocument(request.title, vault);
	if (existing) {
		await op(["document", "edit", existing, request.file, "--vault", vault]);
		return "updated";
	}
	const tags = request.tags?.length ? ["--tags", request.tags.join(",")] : [];
	await op([
		"document",
		"create",
		request.file,
		"--title",
		request.title,
		"--vault",
		vault,
		...tags,
	]);
	return "created";
}

export type SaveRequest = DocumentRequest & { tags?: string[] };

export type DocumentRequest = {
	title: string;
	file: string;
	/** defaultVault when left out. */
	vault?: string;
};

/** Writes the Document `title` to `file`, readable by its owner only, or says
 *  it is missing and touches nothing. The download lands beside the file and is
 *  moved over it, so a failed one leaves the file as it was; a missing folder is
 *  created, owner-only too. */
export async function loadDocument(request: DocumentRequest): Promise<"loaded" | "missing"> {
	const vault = request.vault ?? defaultVault;
	await requireSignedIn();
	const existing = await findDocument(request.title, vault);
	if (!existing) {
		return "missing";
	}
	const folder = dirname(request.file);
	if (!existsSync(folder)) {
		mkdirSync(folder, { recursive: true, mode: 0o700 });
	}
	const partial = `${request.file}.loading`;
	try {
		await op(["document", "get", existing, "--vault", vault, "--out-file", partial]);
		chmodSync(partial, 0o600);
		renameSync(partial, request.file);
	} finally {
		rmSync(partial, { force: true });
	}
	return "loaded";
}

/** Signed out, every lookup fails, and a save would read that as "no item yet"
 *  and create a duplicate. */
async function requireSignedIn() {
	if (!Bun.which("op")) {
		throw new Error("op (1Password CLI) not found - run: make apps");
	}
	const whoami = await $`op whoami`.nothrow().quiet();
	if (whoami.exitCode !== 0) {
		throw new Error('op is not signed in - run: eval "$(op signin)"');
	}
}

/** The id of the one Document titled `title` in the vault, or undefined. Listed
 *  and matched here rather than `op item get`, whose failure for any reason
 *  would read as "not there"; two of them is an error, not a guess. */
async function findDocument(title: string, vault: string) {
	const listed = await op([
		"item",
		"list",
		"--vault",
		vault,
		"--categories",
		"Document",
		"--format",
		"json",
	]);
	const items: { id: string; title: string }[] = JSON.parse(listed || "[]");
	const matches = items.filter((item) => item.title === title);
	if (matches.length > 1) {
		throw new Error(`${matches.length} items titled ${title} in ${vault} - delete all but one`);
	}
	return matches[0]?.id;
}

/** Runs op, and throws with its own error text instead of an exit code. */
async function op(args: string[]) {
	const result = await $`op ${args}`.nothrow().quiet();
	if (result.exitCode !== 0) {
		throw new Error(`op ${args.slice(0, 2).join(" ")}: ${result.stderr.toString().trim()}`);
	}
	return result.stdout.toString().trim();
}
