// Files the scripts import that are not TypeScript. Bun reads them at run time
// as the import attribute says; this tells `bun check` and the editors the same,
// so a query or a script is a real import the editor jumps to, not a name in a string.

/** import query from "…/x.sql" with { type: "text" }: the query's text. */
declare module "*.sql" {
	const query: string;
	export default query;
}

/** import script from "…/x.applescript" with { type: "file" }: the file's path, for osascript. */
declare module "*.applescript" {
	const path: string;
	export default path;
}
