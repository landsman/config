---
name: tanstack-start
description: Load before adding or changing a TanStack Start route, its loader, its prerender or build config (`tanstackStart()` in the Vite config), a lazy dialog or feature, fonts, images or CSS imports in a Start app — and when its PageSpeed or Lighthouse score drops. Carries how to measure a Start build without fooling yourself, content in the first HTML, generated data kept out of shared chunks, the lazy-dialog trap, fonts, hidden images, deferred JS, and what Start's CSS inlining, critical CSS and deferred hydration did and did not buy.
trigger-keywords: tanstack start, tanstack, createFileRoute, prerender, pagespeed, lighthouse
---

# TanStack Start, fast by default

The fastest request is the one the browser never makes. A prerendered Start page
usually has its HTML on time; what delays LCP is the JavaScript, fonts and
images around it. So the order is: cut what loads, then tune what is left.

For the audit itself — a trace, Core Web Vitals, the LCP breakdown — load
`web-perf`. This skill is what is specific to Start. Its source, with the
numbers behind each claim, is the brain's *TanStack Start performance* page; it
is one author's site measured with single PageSpeed runs, so every "did not pay
off" below is a thing to measure, not a rule.

## Measure first

1. **A production build, compressed.** Dev mode measures work no visitor gets,
   and an uncompressed `vite preview` scores several points below the live site
   (165 KiB HTML against 28 KiB with Brotli: 94 against 99).
2. **Medians, not one run.** The same build scored 91, 95 and 92 within minutes.
   PageSpeed Insights can serve a cached audit under a new link — check the
   capture time.
3. **Find the LCP element before fixing anything.** When it is a paragraph,
   image work does nothing.
4. **One change per measurement**, as the reporting-data rule says; a pile of
   changes between two runs proves the pile, not any one of them.

## Cut what loads

1. **Content in the first HTML.** Search the document response in the Network
   panel, not the hydrated DOM. Data comes from a route loader, never a client
   effect. A loader runs on the server *and* in the browser: an import inside it
   is not server-only, so server code goes behind `createServerFn` (an RPC) or
   `createServerOnlyFn` (throws when called on the client). Public pages
   prerender through `tanstackStart({ prerender: { enabled: true, … }, pages })`;
   `crawlLinks` and `autoStaticPathsDiscovery` default to on, so turn them off
   when `pages` already lists the set.
2. **Generated data stays out of shared chunks.** A manifest, a content index or
   an image map imported by a shared component ships to every route. Each route
   collects what it renders in its loader; check the serialized loader output
   *and* the emitted bundle, since moving data from one to the other is not a
   saving.
3. **A closed feature is unmounted, not hidden.** Search, a menu, a lightbox, a
   confirm dialog: `React.lazy` at module scope, rendered only after the first
   open. A lazy component downloads when it renders, so a dialog that keeps
   its children mounted while closed (`<Dialog open={false}><LazyForm/>`)
   downloads it on page load — check that the chunk is not requested until the
   first click.
   Suspense for the load, an error boundary for a failed chunk, and unmount only
   after the close animation and focus return finish (see `modal-dialogs`).
4. **A hidden image still downloads.** `display: none` does not stop an eager
   `<img>`; mark it `loading="lazy"` or mount it after a media check. A deferred
   video player defers its poster too.

## Tune what is left

1. **The LCP image**: in the initial HTML, `loading="eager"`,
   `fetchpriority="high"`, `srcset` with a `sizes` that describes the layout,
   not the file; width and height set.
2. **Fonts**: WOFF2 subsets (Fontsource), unused axes dropped; preload only the
   face the LCP text uses, with `type` and `crossorigin` matching the real
   request or it downloads twice. A faster font exposes its swap — a local
   fallback `@font-face` with `size-adjust` and the `*-override` metrics,
   measured for that pair, keeps CLS down.
3. **Deferred JS by trigger**: an embed near the viewport, a dialog or editor on
   first use, decoration after `load` plus an idle slot — and an animation loop
   stops at rest. Analytics after the first interaction loses the shortest
   visits; say so when proposing it.
4. **CSS**: tokens and base styles global, feature styles imported by their
   route or component. Start's route manifest tracks side-effect CSS imports and
   CSS modules, not a `?url` link returned from `head().links`.

## Measure before keeping

- **`server.build.inlineCss`** (experimental, production builds only, and only
  manifest-managed CSS) inlines the route's stylesheets into every document.
  Trimming the global sheet came first and mattered more.
- **Critical CSS** (Beasties, deferred sheets): render-blocking CSS fell by half,
  the score did not move measurably, and it dropped dark mode, CSS-variable font
  families and form-control states. It needs every page checked in both themes,
  at both widths and without JavaScript, on every change after.
- **Deferred hydration**: try a `<Hydrate when={visible()}>` boundary
  (`Hydrate` from `@tanstack/react-start`; `visible`, `idle`, `interaction`,
  `media` and others from `@tanstack/react-start/hydration`) around a section
  that can wait; check the installed version has it. Delaying the whole app's startup broke early
  scroll and scored inconclusively.
- **React Compiler** changes bundle size (+10–14 KiB per route there) and barely
  timing; measure it apart from loading work.

## Keep it fast

Put a budget in CI from measured routes — render-blocking CSS, all stylesheets,
initial JS, module preload count, the shared content chunk, in gzip bytes — and
count deferred downloads in it, or moving a tag reads as a saving. The browser
tests worth having: main content present before hydration, hidden assets not
requested, dialogs returning focus, an early scroll surviving hydration.
