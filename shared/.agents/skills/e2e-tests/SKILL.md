---
name: e2e-tests
description: Load before adding, changing, reviewing or speeding up a browser end-to-end suite — Playwright (Java or TypeScript), Cucumber scenarios over it, the CI job that runs it, or a failing or flaky e2e run. Carries my defaults (Chromium only, as fast as CI allows), where the app under test should run, test data and teardown, locators and waiting, what a failed run must leave behind, and how CI installs and caches the browser and its OS packages. Framework traps (Vaadin, Playwright Java, Cucumber, React hydration) are in pitfalls.md.
trigger-keywords: e2e, end-to-end, playwright*, cucumber*, gherkin*, chromi*, install-deps, testEndToEnd, flaky*
---

# Browser end-to-end tests

**Chromium only, and CI as fast as it can be.** A rich pass through one browser is enough in almost every project; Firefox, WebKit or a browser matrix only when the project says it needs one. Every minute a run repeats — a download, an install, a boot — is a cost to remove, not to accept.

## Defaults

- **One browser.** `playwright install chromium`, never a bare `install`. In a headless CI job `install --only-shell chromium`: it skips the full Chromium build, 393 MB on disk next to the headless shell's 261, which only a headed run or `channel: 'chromium'` uses. Playwright Java runs a bare `install` on every `Playwright.create()`, all three browsers plus ffmpeg: install Chromium in its own task and set `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` on the test task, which depends on it.
- **One Playwright version per repo.** Two suites (a Java app and a TypeScript site) pin the same version and are bumped in one Renovate group, so they share one browser directory and one package list.
- **Headless in CI, headed locally on request** — a `make e2e-head` with slow-mo and one worker, never the default.
- **Phone first.** Default viewport 390×844, a second pass at 1280×720; reuse those two sizes. A desktop default hides phone bugs: every assertion passes at 1280 against broken phone code. The phone viewport still has no address bar, notch or keyboard; the mobile-first skill's item 13 says what to assert instead.

## CI: install and cache

- **OS libraries: `install-deps chromium`, never a bare `install-deps`.** The bare call installs every browser's libraries: 268 packages and 161 MB of download on Ubuntu 22.04, against 70 and 73 MB for Chromium's, which is all a headless Chromium needs. [chromium-deps.sh](chromium-deps.sh) measures both in the Forgejo runner image, pinned by digest; re-run it on a Playwright bump.
- **A "missing dependencies" warning naming `libgtk-3-0 libxcursor1` is Firefox's,** printed by a bare `install` — Playwright Java runs one on every start unless told not to. Remove the install, not the warning: with the two packages added, the next warning names WebKit's, because the check stops at the first browser that fails. Its silence proves nothing for Chromium: in 1.63 the check looks in `chrome-linux`, and the build unpacks to `chrome-linux64`.
- **Take the list from the Playwright the tests run** (its CLI, through Gradle or npx), never a hand-copied `apt-get` line that goes stale at the next bump.
- **Where nothing is installed yet, check the image first.** A hosted `ubuntu-latest` on GitHub already has the libraries: install the browser only. A self-hosted VM agent gets them once at provisioning — apt's `needrestart` hook restarted the agent service mid-run.
- **Keep the browser and the downloads where the runner keeps them.** A throwaway job container loses `~/.cache/ms-playwright` and `/var/cache/apt`: point `PLAYWRIGHT_BROWSERS_PATH` and apt's `Dir::Cache::Archives` into the bind-mounted directory. A hosted runner has no such disk, and Playwright's CI guide finds a cache restore about as slow as the download ([Caching browsers](https://playwright.dev/docs/ci#caching-browsers)): measure before adding `actions/cache`.
- **apt into a shared directory goes under `flock`.** apt fails a second process on a busy archive directory instead of waiting, and `DPkg::Lock::Timeout` does not cover that lock. `apt-get autoclean` after the install, never before `apt-get update`.
- **A job timeout on every e2e job.** A dead apt mirror hung one for 14 minutes; the default holds a runner for hours.
- **The remaining floor** is `apt-get update` (~50 MB) and the unpacking. Only a runner image with the libraries baked in removes it.

## CI: when it runs

- **A static site or a stateless SPA:** the whole suite on every pull request that touches it, `fullyParallel`, against the build that gets deployed.
- **A server-side-state app (Vaadin) or a slow suite:** nightly plus `workflow_dispatch` with a tags input. Pull requests run only a compile and binding check (`--dry-run`), only when the suite changed, and when the diff cannot be read the check runs anyway.
- **A nightly failure opens or comments on one rolling issue** (scheduled runs only). A suite once stayed red for a month with nobody noticing.
- **Retries:** Playwright Test `retries: process.env.CI ? 1 : 0`, `forbidOnly` in CI. A Cucumber suite reruns failed scenarios once in a fresh JVM, capped (ten is a broken environment, not flakiness), and reports what passed only on rerun as flaky — never silently green.

## Where the app runs

- **In the test JVM when you can** (`@SpringBootTest(RANDOM_PORT)`, one context for the suite, Testcontainers for the database, mail catcher and the rest). Steps then seed through the real repositories and services, with no fixtures API and no SQL.
- **Third parties are faked in-process:** WireMock, or a `@Primary` fake bean under the e2e profile. Requests to any other host are aborted (`page.route`), so a result never depends on someone else being up.
- **Connect as the application's database role, not the owner.** The owner bypasses row-level security and grants, so the suite passes and the first real deploy crash-loops.
- **A deployed target is an optional mode** (`BASE_URL`), not the default. Only what goes through the browser tests that environment's code. Compile before any credential exists in the job, and refuse anything not named as dev.
- **A shared deployed environment as the only target** costs ordering between scenarios, no parallelism, provisioning through the UI and a two-hour nightly. It is what to move away from, not to copy.
- **A static site:** test the built output, served by something that reproduces the host's routing (redirects, 404 status, headers), and ask the real host the same questions after each deploy to catch drift. Add a dev-server project only for what the dev build alone reports, such as React's attribute hydration mismatches.

## Test data and isolation

- **A scenario owns its data.** Create it, assert on it, register its teardown on the next line (`world.cleanUpLater { }`). Teardown runs newest first, also after a failure; a failing cleanup is reported, and the rest still run.
- **Unique and prefix-free names:** a run token plus a zero-padded sequence (`-002`, not `-2`, which a contains-search matches inside `-21`). Mail on a non-resolving subdomain of `example.com` — validators reject `.test`.
- **Never assume ambient data.** An empty grid, a seed user or a count from earlier is a "broken selector" at 4 am.
- **A per-user setting the suite changes gets a throwaway user,** not a reset hook: cleanup needs a working app at exactly the moment it is not.
- **Fixtures through builders over the real code** — no SQL, no hardcoded password hashes, no dev seed user.
- **One browser per run, a fresh `BrowserContext` per scenario.** A second user in one scenario is a second context.
- **Parallel when nothing is shared.** A server-side UI on one shared database runs serially by design; making it parallel is a redesign, not a flag.

## Writing a test

- **Cucumber when the suite is the spec:** Gherkin says the behaviour in the domain's words, Kotlin or TypeScript holds locators and waits. Step text and hooks are global — reuse a step or phrase it for its screen, no untagged `@Before`.
- **Locators:** role or label first, then a test id, then CSS. A test id is kebab-case English, never translated, and comes from a constant shared by the production view and the step, so a rename breaks both at compile time. Add one only where role and label cannot do it.
- **Routes come from the app's route catalog,** never a literal path in a test.
- **Wait on the web-first assertion,** not a snapshot read. A value that needs a server round trip is polled with a deadline. Gate a click on an indicator that changes with the state being waited for. Assert presence before absence: an empty page passes every `isHidden`.
- **A click before the client app takes over is a plain page load** — wait for something only the client renders.
- **Accessibility belongs in the suite:** axe at WCAG 2.2 AA on every route and open dialog, in both themes, after animations settle (`reducedMotion: "reduce"`).
- **Production invariants become harness guards:** zero console errors and `pageerror`s, one pooled connection per thread — recorded during the scenario, failed at teardown.

## What a failed run leaves behind

- **Per failed scenario:** a full-page screenshot taken before teardown, `page.html`, `trace.zip`, the video. A passing scenario leaves nothing.
- **The failure message in the log.** For a Playwright assertion it is the diagnosis — the locator, the expectation, the call log. Gradle prints one frame unless `exceptionFormat = FULL`.
- **A count even when green:** "N scenarios, F failed, S skipped" — a run that found nothing is green too.
- **The artefact name is stamped before the suite runs** (a step after a failure is skipped) and uploaded `if: failure()`.
- **Read in this order:** clear old results, the failure message and its call log, the screenshot, the trace. Assume the app is broken before assuming the test is.

## Traps already debugged

One section each in [pitfalls.md](pitfalls.md), never read whole:

    awk '/^## P7 /{f=1;print;next} /^## /{f=0} f' pitfalls.md

- P1 Playwright Java: a regex is compiled in the browser, so no `Pattern.quote`.
- P2 Playwright Java: a `-D` reaches the Gradle JVM, not the test JVM.
- P3 Cucumber: tags in `@ConfigurationParameter` silence `-Ptags`.
- P4 Cucumber: two engines run every scenario twice; its JUnit plugin double-counts.
- P5 Gradle: a custom source set misses the BOM, and a named `srcDir` copies resources twice.
- P6 Vaadin: a test id or aria-label on a field lands on the host, not the input.
- P7 Vaadin: an `ON_CHANGE` field never reaches the server under `fill()`.
- P8 Vaadin: grid cells are recycled; a click re-sorts under the sticky header.
- P9 Vaadin: a value is client-side until the client is idle.
- P10 Vaadin: an overlay still `closing` swallows the next pick.
- P11 Transactions: rollback does not reach the servlet thread; a hard-delete teardown races an autosave.
- P12 Waiting: `isVisible()` does not wait, and a count change is not an assertion.
- P13 Hydration: the production build is silent on attribute mismatches.
- P14 Animations: axe mid-fade reports low contrast; a cancelled animation rejects.
- P15 Init scripts: one that runs before `documentElement` exists fails silently.
- P16 Lifecycle: JUnit's `TestWatcher` fires after teardown.
- P17 CI shell: inline pipeline shell silenced three nightlies.
