---
paths:
  - "**/*.tsx"
  - "**/*.jsx"
  - "**/*.vue"
  - "**/*.svelte"
  - "**/*.astro"
  - "**/*.html"
  - "**/*.svg"
---

# SVG icons are files

**An icon is an `.svg` file on disk, never SVG markup in a component, a
template or a string, whatever the stack.** Markup inside a component ships in
the JS bundle, so it is downloaded again with every deploy that touches the
bundle, parsed on every render, and never cached on its own. A file is
fetched once, served `immutable` under a hashed name, and shared by every page.

- **An icon with colours of its own**, a logo, is an `<img src>` on the file,
  with `alt` or `alt=""` beside a label that already names it.
- **An icon in the text colour** is a CSS mask over the file, so it follows
  the colour scheme and the hover like a glyph, and the file's own colour does
  not matter:

  ```html
  <span class="icon icon-scissors" aria-hidden="true"></span>
  ```

  ```css
  .icon {
    display: inline-block;
    width: 1.5em;
    height: 1.5em;
    background: currentColor;
    mask: var(--icon) center / contain no-repeat;
  }

  .icon-scissors {
    --icon: url(icons/scissors.svg);
  }

  @media (forced-colors: active) {
    .icon {
      forced-color-adjust: none;
      background: CanvasText;
    }
  }
  ```

  An `<img>` cannot do this: CSS does not reach into the file, and a `filter`
  only approximates a colour. Forced colours drop the background, hence the
  last block.
- **A typed list of icons stays typed**: map each key to its file and label,
  not to its drawing — `Record<ServiceIcon, { label; file }>` fails the build
  on a missing icon just the same.
- **Check the build, not the source.** A bundler may inline a small asset back
  into the bundle (Vite's `build.assetsInlineLimit`, an SVGR-style import that
  turns the file into a component). The icon must be its own request in the
  Network tab, not a `data:` URL.
- **Preload an icon that appears without warning**, such as a dialog's `×`: a
  mask is fetched only once its element is shown. Native
  `<link rel="preload" href="…" as="image" crossorigin>` in the `<head>`,
  `crossorigin` because a mask is fetched in CORS mode.

**Not an icon:** an SVG drawn from data — a chart, a progress ring whose
geometry is state. That is markup by nature and stays in the component.

A worked example:
[svg-icons](https://github.com/landsman/frontend-playground/tree/master/svg-icons).
