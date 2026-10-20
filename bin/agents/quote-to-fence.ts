#!/usr/bin/env bun
// MessageDisplay hook: a blockquote is shown as a code block, so it copies without `> `.
//
// A blockquote renders in the terminal with a bar or `> ` on every line, and the
// copy takes it along. This rewrites only what is shown: a run of quoted lines
// loses its markers and is wrapped in a fence, which copies clean and keeps any
// Markdown inside it raw. The transcript and what the model sees stay as written.
//
// Claude Code calls the hook once per batch of completed lines and renders the
// batches as one Markdown text, so a fence opened in one batch is closed in a
// later one. That needs the state of the message so far (is it inside a fence of
// its own, is a quote run of ours still open), handed from batch to batch. The
// calls for one message run concurrently, observed on 2.1.296, so each call
// waits for the previous index to have written its state before reading it. If
// that does not happen in time, the rest of the message is shown as it came.
import { answer, event } from "@lib/hook";
import { awaitTurn, endRelay, passTurn, relayFile } from "@lib/relay";

/** Where the message stands after a batch: its own open fence, and ours around a quote run. */
type State = { fence: string | null; ours: string | null; broken?: boolean };

const QUOTE = /^ {0,3}> ?/;
const FENCE = /^ {0,3}(`{3,}|~{3,})(.*)/;
const WAIT = 5; // seconds; Claude Code's own timeout for this event is 10

const longestTicks = (line: string) => Math.max(0, ...(line.match(/`+/g) ?? []).map((run) => run.length));

/** The batch as it is to be shown, and the state after it. */
function rewrite(delta: string, { fence, ours }: State, final: boolean): [string, State] {
	const out: string[] = [];
	for (const line of delta.match(/[^\n]*\n|[^\n]+$/g) ?? []) {
		const opener = line.match(FENCE);
		if (fence === null && QUOTE.test(line) && !opener) {
			let body = line.replace(QUOTE, "");
			if (!body.endsWith("\n")) body += "\n";
			// Backticks in the quote as long as our fence would close it early: start a longer one.
			if (ours && longestTicks(body) >= ours.length) {
				out.push(`${ours}\n`);
				ours = null;
			}
			if (ours === null) {
				ours = "`".repeat(Math.max(3, longestTicks(body) + 1));
				out.push(`${ours}markdown\n`);
			}
			out.push(body);
			continue;
		}
		if (ours) {
			out.push(`${ours}\n`);
			ours = null;
		}
		if (fence === null) {
			// A backtick in a backtick fence's info string makes it inline code, not a fence.
			if (opener && !(opener[1][0] === "`" && opener[2].includes("`"))) fence = opener[1];
		} else if (opener && opener[1][0] === fence[0] && opener[1].length >= fence.length && !opener[2].trim()) {
			// CommonMark: the closer is the same character, at least as long, with nothing after it.
			fence = null;
		}
		out.push(line);
	}
	if (ours && final) {
		out.push(`${ours}\n`);
		ours = null;
	}
	return [out.join(""), { fence, ours }];
}

/** The batch to show, keeping the message's state across its concurrent batches. */
async function show(delta: string, message: string, index: number, final: boolean): Promise<string> {
	if (!message) return rewrite(delta, { fence: null, ours: null }, true)[0];
	const file = relayFile("claude-quote-to-fence", message);
	const before = index === 0 ? { fence: null, ours: null } : await awaitTurn<State>(file, index, WAIT);
	// Lost track (a batch timed out or failed): show the rest as it came, and tell
	// the later batches so, rather than have each of them wait out WAIT too.
	const broken = !before || before.broken === true;
	const [shown, after] = broken ? [delta, { fence: null, ours: null }] : rewrite(delta, before, final);
	if (final) endRelay(file);
	else passTurn(file, index, { ...after, broken });
	return shown;
}

const input = await event<{ delta?: string; message_id?: unknown; index?: number; final?: boolean }>();
if (input) {
	const delta = input.delta ?? "";
	const message = String(input.message_id ?? "").replace(/[^\p{L}\p{N}_-]/gu, "");
	const shown = await show(delta, message, input.index ?? 0, Boolean(input.final));
	if (shown !== delta) answer({ hookSpecificOutput: { hookEventName: "MessageDisplay", displayContent: shown } });
}
