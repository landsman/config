# E2E traps already debugged

**Do not read this file whole.** Open the one section the e2e-tests skill's list
points at:

    awk '/^## P7 /{f=1;print;next} /^## /{f=0} f' ~/.agents/skills/e2e-tests/pitfalls.md

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

## P18 Behat: an undefined step exits 0

Without `--strict`, Behat reports a step no context defines as "undefined" and
exits 0. A typo in a `.feature`, or a definition renamed under it, then tests
nothing and CI stays green. Run the suite with `--strict`, and check in the fast
lane that every step binds: `behat --dry-run` matches each step to its definition
with no browser and no fixture, in under a second.

Keep `--strict` off that dry run, and so out of the config file the dry run reads.
Strict fails anything not explicitly passed, and a dry run skips every step, so it
always exits 1. Fail on the word `undefined` in its output instead, and keep its
exit code for a config or context that does not load. With more than one context,
`--snippets-for='Ns\Context'` skips the prompt and prints the definition to add.
Checked on Behat 4 with a throwaway step: the real run and the dry run both
failed on it, and both passed without it.

## P19 Cucumber-JVM: strict already, and the dry run is a Gradle task

Unlike Behat (P18), Cucumber-JVM has had no `--strict` since 7.0: an undefined or
ambiguous step fails its scenario, in the real run and in a dry run alike. A dry
run reports a step that binds as passed (`ExecutionMode.DRY_RUN`), where Behat
reports it skipped and its strict fails that, so here strict costs the dry run
nothing. So no grep. `cucumber.execution.dry-run=true` binds every step without hooks or a
browser, and the task's exit code is the check.

```kotlin
val unused = layout.buildDirectory.file("cucumber/unused-steps.txt")
tasks.register<Test>("e2eDryRun") {
    testClassesDirs = sourceSets["e2eTest"].output.classesDirs
    classpath = sourceSets["e2eTest"].runtimeClasspath
    useJUnitPlatform { includeEngines("junit-platform-suite") }
    systemProperty("cucumber.filter.tags", "not @wip")
    systemProperty("cucumber.execution.dry-run", "true")
    systemProperty("cucumber.plugin", "unused:${unused.get().asFile.path}")
    outputs.file(unused)
    testLogging { events("failed"); exceptionFormat = TestExceptionFormat.FULL }
    doLast {
        val report = unused.get().asFile.readText().trim()
        // 7.31+ writes this line when nothing is unused, older versions nothing
        if (report.isNotEmpty() && report != "0 unused step definition(s)") {
            throw GradleException("Step definitions no scenario uses:\n$report")
        }
    }
}
```

- **CI calls it by name.** The e2e source set sits outside `check` (P5), so a
  green `build` never compiled it. This one task compiles and binds.
- **With cucumber-spring, set `cucumber.object-factory` to
  `io.cucumber.core.backend.DefaultObjectFactory`.** A dry run still starts the
  object factory for every scenario (`Runner.runPickle`), and Spring's boots the
  whole `@SpringBootTest` app, containers included, to instantiate nothing.
- **A `JavaExec` on `io.cucumber.core.cli.Main --dry-run` works as well:** no
  JUnit report and no `@Suite` to outrank its options, but it repeats the glue
  package and the features path.
- **Filtering the CI step on the suite's paths** misses a main-code change the
  steps compile against, unless the suite is a module with no project dependency.
- **Its own tag filter, wider than the nightly's,** so the scenarios the nightly
  leaves out are still bound. P3 applies: a filter or a plugin pinned on the
  `@Suite` outranks the task's.
- **An unused definition fails too.** The `unused:` plugin only writes the list;
  the `doLast` fails on it. Since 7.31 it writes `0 unused step definition(s)`
  when there are none, so a plain `isNotEmpty()` fails every run. A definition
  only a `@wip` scenario uses counts as unused. Behat has no such report.
- **The test report shows every scenario as passed:** bound, not run.
- **`usage-json:<file>` (7.31+) is worth uploading from the same run:** every
  definition with the steps it binds, where to look before writing a near-duplicate.
- **`exceptionFormat = FULL`,** or the snippet for the missing step stays out of
  the log.

Checked on Cucumber 7.18 in a work Kotlin suite: about 340 scenarios bound in
1.6 s after the compile. With `@wip` let in, it failed on that scenario's six
undefined steps, and a throwaway definition no scenario used failed it by name.
A second suite, on cucumber-spring and Cucumber 7.34, runs it as that `JavaExec`
with the default object factory: 244 scenarios green, and a throwaway unused
definition failed it by name.
