// For the tests of the git helpers: every git a test runs ignores this
// machine's config — no hooks, no signing, no identity of mine — so it runs the
// same here and on a CI runner, and never fires the forbidden-names hook.
export function isolateGitConfig() {
	Object.assign(process.env, {
		GIT_CONFIG_GLOBAL: "/dev/null",
		GIT_CONFIG_NOSYSTEM: "1",
		GIT_AUTHOR_NAME: "test",
		GIT_AUTHOR_EMAIL: "test@example.com",
		GIT_COMMITTER_NAME: "test",
		GIT_COMMITTER_EMAIL: "test@example.com",
	});
}
