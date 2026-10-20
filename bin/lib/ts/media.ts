// What a media file is, in the words a person reads: "12.3 MB · 4:05".
import { $ } from "bun";
import { statSync } from "node:fs";

export async function describe(path: string): Promise<string> {
	const mb = (statSync(path).size / 1e6).toFixed(1);
	const probe = await $`ffprobe -v error -show_entries format=duration -of csv=p=0 ${path}`.nothrow().text();
	const s = Math.round(Number(probe) || 0);
	return `${mb} MB · ${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}
