/** Text without its diacritics, everything else kept: "rešerše" -> "reserse". */
export const fold = (text: string) => text.normalize("NFKD").replace(/\p{M}/gu, "");

/** The `key: value` lines of a Markdown file's leading `---` block; nested lines are skipped. */
export function frontmatter(markdown: string): Record<string, string> {
	const block = markdown.match(/^---\n([\s\S]*?)\n---/)?.[1] ?? "";
	return Object.fromEntries(block.split("\n")
		.filter((line) => line.includes(":") && !line.startsWith(" "))
		.map((line) => [line.slice(0, line.indexOf(":")), line.slice(line.indexOf(":") + 1).trim()]));
}

// A name as it goes into a file name: "Porada s Šárkou!" -> porada-s-sarkou.
// Accents are dropped, not mangled, and only a-z, 0-9 and single dashes remain.
export const slug = (name: string) =>
	name.normalize("NFKD").replace(/[^\x00-\x7f]/g, "").toLowerCase()
		.replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
