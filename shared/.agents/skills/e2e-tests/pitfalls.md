# E2E traps already debugged

**Do not read this file whole.** Open the one section the e2e-tests skill's list
points at:

    awk '/^## P7 /{f=1;print;next} /^## /{f=0} f' pitfalls.md

## P1 Playwright Java: no `Pattern.quote`

Playwright Java sends a `Pattern`'s source string to the browser, where it is
compiled with `RegExp`. JavaScript has no `\Q…\E`, so `\Q` becomes a literal `Q`
and the pattern never matches. Flags carry over only where JavaScript has one:
`CASE_INSENSITIVE`, `DOTALL` and `MULTILINE` become `i`, `s` and `m`, and any
other flag throws. Escape the regex characters by hand in one helper, and build
URL matchers from the route catalog through it.

## P2 Playwright Java: forward every `-D` to the test JVM

A `-Dsomething` on the Gradle command line sets it in the Gradle JVM, not in the
forked test JVM, which inherits environment variables but not system
properties. Forward each one explicitly with `systemProperty(…)`, and declare it
a task input — otherwise switching the viewport or the target serves the previous
run's UP-TO-DATE result, and "the desktop run is a phone run wearing its name".

## P3 Cucumber: tags never in `@ConfigurationParameter`

A `@ConfigurationParameter(key = FILTER_TAGS_PROPERTY_NAME, …)` on the `@Suite`
outranks the `cucumber.filter.tags` system property, so `-Ptags='@login'` quietly
does nothing. Put the default filter in the Gradle task and let the property
override it. The same goes for plugins.

## P4 Cucumber: one engine, one report

- Restrict the test task to `includeEngines("junit-platform-suite")`. With the
  Cucumber engine also discovered, every scenario — and every rerun — ran twice.
- Use the JUnit Platform's per-scenario `TEST-*.xml`, not Cucumber's `junit:`
  plugin, which counts each scenario a second time.
- `@SelectClasspathResource("features")` on the suite; plain discovery missed the
  resources root.
- Step classes are plain classes injected per scenario, never `@Component` —
  cucumber-spring refuses it.

## P5 Gradle: a custom source set is its own world

- A Spring Boot or Jackson BOM applied to `implementation` does not reach
  `testEndToEndImplementation`. A Jackson bump there produced
  `ERR_TOO_MANY_REDIRECTS` on every page. Apply the platform to the source set,
  and check with `dependencyInsight`.
- Naming `resources.srcDir` that is already the default copies every `.feature`
  twice and fails the resources task; drop it or set
  `duplicatesStrategy = EXCLUDE`.
- Never wire the e2e task into `check` or `build`, and mark it
  `outputs.upToDateWhen { false }` when it drives something outside the build.
- Give it a heap: the 512 MB test default ran out partway through a Spring app
  plus a browser.

## P6 Vaadin: attributes land on the host element

A `data-testid` set on a text field ends up on `<vaadin-text-field>`, not on the
`<input>` inside its shadow DOM. Treat test ids on Vaadin fields as container
handles: `getByTestId("x").locator("input").fill(…)`, or the id on the component
root plus `getByLabel` inside it. A raw `aria-label` attribute on the host is an
accessibility bug — use the component's `setAriaLabel`.

## P7 Vaadin: `ValueChangeMode.ON_CHANGE`

`fill()` sets the value without the blur that `ON_CHANGE` waits for, so the
server never hears it and the submit button stays disabled. It was a real UX bug
too: use `EAGER` (or `LAZY`) on fields that enable an action.

## P8 Vaadin: grids recycle their cells

- Cells are pooled. `vaadin-grid-cell-content` matches stale cells off screen;
  use `vaadin-grid-cell-content:visible` (`:visible` means "has a layout box").
- `Locator.click()` scrolls the row under the sticky header, and the click lands
  on the header and re-sorts. Wait for two equal bounding boxes, then click by
  mouse coordinates.
- With bulk selection on, the first column is the checkbox.
- `setItems` after a lazy search left a null item under the click; keep one list
  and filter it in place.
- A picker dialog in single-select marks a row on click and applies it on its
  button; waiting for the dialog to close after the click waits forever.

## P9 Vaadin: wait for the client to be idle

A combo-box value is client-side until the round trip ends; clicking the next
control too early loses it. Wait on
`window.Vaadin.Flow.clients[…].isActive()` being false. Combo options render as
empty placeholders before their text arrives, so `count()` reports ready on an
empty list — wait for the text.

## P10 Vaadin: an overlay that is still closing

On a phone, a select's overlay keeps a `closing` attribute through its
animation, and the next pick on it times out. Wait for
`not().hasAttribute("closing", Pattern.compile(".*"))` before the second
selection; Java has no one-argument `hasAttribute`.

## P11 Transactions: rollback and teardown

Wrapping a scenario in a transaction does not isolate it: the Vaadin servlet
thread runs its own transactions. Teardown deletes for real — and a hard delete
of a user raced an autosave on a loaded CI container only, failing on a foreign
key. Soft-delete in teardown, and give the teardown helper its own scenario: it
is exactly the code nobody tests.

## P12 Waiting: snapshots are not waits

- `isVisible()` answers immediately, "no" while a drawer is still rendering — and
  calling it on a menu mid-open closed the drawer on desktop.
- Reading a database row straight after a UI toggle reads it as it was; poll
  with a deadline.
- "Wait until the count changes" must not be an assertion: a search can end on
  the same count. Make it best-effort with a short limit, and where a later step
  deletes or edits a row, assert the row's identity first — a non-failing wait
  once let a step delete a row from someone else's data on a shared environment.
- A "saved" toast fires for an unchanged form too; it proves nothing about what
  was persisted.

## P13 Hydration: what only the dev build reports

React's production build reports element and text mismatches but stays silent on
attribute mismatches. A second Playwright project against the dev server, limited
to a hydration spec, catches those. The console-error check has to allow the
browser's own line for a page that deliberately answers 404.

## P14 Animations

- axe reading a dialog or hero mid-fade reports low contrast on a slow runner.
  Use `reducedMotion: "reduce"`, or wait for every finite animation to finish.
- `Animation.finished` rejects with `AbortError` when the animation is cancelled;
  treat that as settled.
- A value read once before the first `requestAnimationFrame` is `undefined`; use
  `expect.poll` until it exists, then assert on it.

## P15 Init scripts fail silently

An `addInitScript` that touches `document.documentElement` can run before it
exists. One threw, had already set its "installed" flag, and every toast after it
went unrecorded with no error anywhere. Guard on the element and set the flag
last. Log `page.onPageError` with its stack: console entries in a trace have
none, and that cost a day.

## P16 Lifecycle: capture before teardown

JUnit fires `TestWatcher.testFailed` after every `@AfterEach`, so artefacts taken
there show the tidied page. Use `AfterTestExecutionCallback`, or in Cucumber an
`@After(order = Int.MAX_VALUE)` that checks `scenario.isFailed`. If the artefacts
look empty, suspect the lifecycle before the pipeline.

## P17 CI shell around the suite

The notifier, the rerun list, the "new vs. still failing" report — the shell
that runs when something is already broken. Inline in the pipeline YAML, a bug in
choosing a webhook URL silenced three nightlies. Each lives in a script with a
test next to it, run as a blocking check (see the shell-in-config rule). On Azure
DevOps, `$(macros)` do not expand inside an extracted script: pass values through
`env:`.
