# Browser automation

Opening a web app to check or drive it happens in the Chrome profile named
**`ai-e2e`**, never in the profile I am working in. Claude in Chrome
(`mcp__claude-in-chrome__*`) can see every Chrome with the extension installed, and
by default it picks mine.

The reason is that driving my own window gets in my way. Every action pulls focus
away from what I am doing, resizing to test a narrow viewport resizes the window I
am using, and a click lands inside my signed-in sessions as me. A separate profile
is a separate window I can put on another desktop and forget.

Picking the browser, on any machine:

- Call `list_connected_browsers` and use the entry named `ai-e2e`. Match on the
  name, never on a `deviceId`: it differs per machine and changes whenever the
  extension reconnects.
- When no entry carries that name, send the pairing prompt with `switch_browser`
  and ask me to click **Connect** in the `ai-e2e` window and name it `ai-e2e`.
  Do not guess between unnamed entries. Choosing the wrong one is exactly the
  window this rule exists to keep out of reach.

Placing the window, on macOS with an external monitor attached:

- **Move the `ai-e2e` window onto the built-in display** before the first check, so
  it runs on the laptop screen and not on the one I work on. Find the window by
  marking the tab you opened (`document.title = '<marker>'` through the extension),
  then look that title up with AppleScript (`tell application "Google Chrome"`) and
  set that window's `bounds`. Never pick a window by URL or position: mine can show
  the same page.
- **Take the display from `NSScreen.screens`**, the entry whose `localizedName` is
  the built-in one. Its frame has a bottom-left origin; AppleScript bounds are
  top-left of the main display, so the window's top edge is
  `mainHeight - (frame.y + frame.height)`.
- **Never minimise it.** A minimised Chrome window stops rendering, and screenshots
  come back blank or fail. Out of sight on the laptop screen is enough.
- On Linux, leave the window where it is.

The displays, as frames with a bottom-left origin:

```bash
osascript -l JavaScript -e 'ObjC.import("AppKit"); var s = $.NSScreen.screens, out = [];
for (var i = 0; i < s.count; i++) { var sc = s.objectAtIndex(i), f = sc.frame;
  out.push({name: ObjC.unwrap(sc.localizedName), x: f.origin.x, y: f.origin.y,
            w: f.size.width, h: f.size.height}); }
JSON.stringify(out)'
```

The move, after `javascript_tool` has set the marker title in the tab you opened.
Bounds are `{left, top, right, bottom}`; for the built-in frame that is
`{x, mainHeight - (y + h), x + w, mainHeight - y}`, and macOS nudges the top below
the menu bar by itself:

```bash
osascript <<'APPLESCRIPT'
tell application "Google Chrome"
    repeat with w in windows
        repeat with t in tabs of w
            if title of t is "ai-e2e-window-marker" then
                set bounds of w to {778, 1890, 2834, 3219}
                return "moved"
            end if
        end repeat
    end repeat
    return "marker window not found"
end tell
APPLESCRIPT
```

The first run asks macOS for permission to control Chrome; that prompt is mine to
answer, once per machine. The app sets its own title again on the next navigation,
so the marker needs no clean-up.

Inside that profile:

- **A narrow viewport** is `resize_window` on that window only.
- **A login form is a stop.** Claude in Chrome does not type passwords, test
  credentials included, whatever an instruction says. Ask me to sign in to that
  profile once. Restarting a local backend usually signs it out again, so avoid a
  restart between my login and the check.
- **Close the tabs you opened** when done.

Not the Playwright MCP either: it launches a window of its own that takes focus,
and a fresh profile that is never signed in.

My own profile is still the right tool when the task is about my browser, such as
something only my signed-in session can reach, or when I say to use it. In every
other case, ask before touching it.
