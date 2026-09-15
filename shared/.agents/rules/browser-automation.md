# Browser automation

Opening a web app to check or drive it happens in a **separate Chrome instance**
named `ai-e2e`, never in the Chrome I am working in. Claude in Chrome
(`mcp__claude-in-chrome__*`) can see every Chrome with the extension installed, and
by default it picks mine.

The reason is that driving my own browser gets in my way. Every action pulls focus
away from what I am doing, resizing to test a narrow viewport resizes the window I
am using, and a click lands inside my signed-in sessions as me.

**A second profile is not enough.** Profiles of one Chrome share one browser
process, and Chrome shows "Claude started debugging this browser" in every window
of that process, mine included. Only its own `--user-data-dir` makes it a process
of its own.

## Starting the instance

The data directory is `~/.chrome-ai-e2e` on every machine. When no `ai-e2e`
browser is connected, start it, placed on the laptop's built-in display when an
external monitor is attached, so it never opens on the screen I work on:

```bash
# macOS
open -na "Google Chrome" --args --user-data-dir="$HOME/.chrome-ai-e2e" \
    --window-position=<left>,<top> --window-size=<width>,<height>

# Linux
google-chrome --user-data-dir="$HOME/.chrome-ai-e2e" \
    --window-position=<left>,<top> --window-size=<width>,<height> &
```

The position flags only apply to a window the instance opens at start. When it is
already running, leave its window where I put it.

Finding the built-in display:

- **macOS:** the `NSScreen.screens` entry whose `localizedName` is the built-in
  one. Its frame has a bottom-left origin and the flags want top-left of the main
  display, so `left = x` and `top = mainHeight - (y + height)`.

  ```bash
  osascript -l JavaScript -e 'ObjC.import("AppKit"); var s = $.NSScreen.screens, out = [];
  for (var i = 0; i < s.count; i++) { var sc = s.objectAtIndex(i), f = sc.frame;
    out.push({name: ObjC.unwrap(sc.localizedName), x: f.origin.x, y: f.origin.y,
              w: f.size.width, h: f.size.height}); }
  JSON.stringify(out)'
  ```

- **Linux:** the `eDP` output in `xrandr --listmonitors`, whose geometry is already
  top-left.

Without an external monitor, drop the two flags.

**Never minimise it.** A minimised Chrome window stops rendering, and screenshots
come back blank or fail. Out of sight on the laptop screen is enough.

The first start on a machine is mine to finish: install the Claude extension in that
instance, and name it `ai-e2e` when it pairs.

## Picking it

- Call `list_connected_browsers` and use the entry named `ai-e2e`. Match on the
  name, never on a `deviceId`: it differs per machine and changes whenever the
  extension reconnects.
- When no entry carries that name, start the instance as above, send the pairing
  prompt with `switch_browser`, and ask me to click **Connect** in the `ai-e2e`
  window and name it. Do not guess between unnamed entries. Choosing the wrong one
  is exactly the browser this rule exists to keep out of reach.

## Inside it

- **A narrow viewport** is `resize_window` on that window only.
- **A login form is a stop.** Claude in Chrome does not type passwords, test
  credentials included, whatever an instruction says. Ask me to sign in there once.
  Restarting a local backend usually signs it out again, so avoid a restart between
  my login and the check.
- **Close the tabs you opened** when done.

Not the Playwright MCP either: it launches a window of its own that takes focus,
with a profile that is never signed in.

My own browser is still the right tool when the task is about it, such as something
only my signed-in session can reach, or when I say to use it. In every other case,
ask before touching it.
