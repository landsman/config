// For the tests of the hook scripts under bin/agents/: a hook run the way Claude
// Code runs it, a process with the event on stdin and the answer on stdout.

/** The hook's answer as parsed JSON, or undefined when it printed nothing. An
 *  `env` value of undefined unsets the variable: a test run inside a Claude Code
 *  session would otherwise inherit that session's CLAUDE_PROJECT_DIR. */
export async function runHook(script: string, event: object, env: Record<string, string | undefined> = {}) {
	const merged = { ...process.env, ...env };
	for (const [key, value] of Object.entries(env)) if (value === undefined) delete merged[key];
	const proc = Bun.spawn([process.execPath, script], { stdin: new Blob([JSON.stringify(event)]), env: merged });
	const out = await new Response(proc.stdout).text();
	if ((await proc.exited) !== 0) throw new Error(`${script} exited ${proc.exitCode}`);
	return out.trim() ? JSON.parse(out) : undefined;
}
