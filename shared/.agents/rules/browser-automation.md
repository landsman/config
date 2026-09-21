# Browser automation

Opening a web app to check or drive it happens in a **separate browser instance**,
`ai-e2e`, never in the Chrome I am working in. Claude in Chrome
(`mcp__claude-in-chrome__*`) can see every Chrome with the extension installed, and
by default it picks mine.

The reason is that driving my own browser gets in my way. Every action pulls focus
away from what I am doing, resizing to test a narrow viewport resizes the window I
am using, and a click lands inside my signed-in sessions as me.

**The goal is to bother me as little as possible.** A one-time setup per machine is
fine; after that, starting, picking and using the instance runs without me. Every
question, prompt or sign-in this rule does not strictly need is a failure of it.

**A second profile is not enough.** Profiles of one Chrome share one browser
process, and Chrome shows "Claude started debugging this browser" in every window
of that process, mine included. Only its own `--user-data-dir` makes it a process
of its own.

**On macOS, its own `--user-data-dir` is not enough either.** LaunchServices routes
an `http` URL to a **bundle id**, not to a process, and `--user-data-dir` is
internal to Chrome, so from the system's side the instance and my own Chrome are one
application. With both running, `open https://…` goes to whichever registered first,
and every link I click in the terminal can land in the instance. Nothing configures
that: `lsappinfo find bundleID=com.google.Chrome` simply lists two entries, and the
first one wins.

So the instance is **Chrome Canary**, whose bundle is `com.google.Chrome.canary`.
A separate app is what makes the two distinguishable; a separate data directory
never was. It is the same browser engine, and the profile is what carries the
extension and the sign-ins, so nothing else in this rule changes.

Linux does not have this problem: `xdg-open` runs `google-chrome`, which hands the
URL to whatever instance holds the default data directory. Keep plain Chrome there.

## 1. Start it, unless it is running

The data directory is `~/.chrome-ai-e2e` on every machine, whichever app opens it.

```bash
pgrep -f "user-data-dir=$HOME/.chrome-ai-e2e" >/dev/null && echo running
```

When it is not running, start it on the laptop's built-in display if an external
monitor is attached, so it never opens on the screen I work on:

```bash
# macOS: the built-in display as "left top width height", empty without a second screen
L=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); var s = $.NSScreen.screens,
  main = s.objectAtIndex(0).frame, out = "";
  for (var i = 0; i < s.count; i++) { var sc = s.objectAtIndex(i), f = sc.frame;
    if (s.count > 1 && /Built-in/.test(ObjC.unwrap(sc.localizedName)))
      out = [f.origin.x, main.size.height - (f.origin.y + f.size.height),
             f.size.width, f.size.height].join(" "); }
  out')
# ${=L}, not $L: zsh does not word-split an unquoted expansion, so `set -- $L` puts
# the whole geometry in $1 and the instance starts with --window-size=, and no size.
if [ -n "$L" ]; then set -- ${=L}
  open -na "Google Chrome Canary" --args --user-data-dir="$HOME/.chrome-ai-e2e" \
      --window-position="$1,$2" --window-size="$3,$4"
else
  open -na "Google Chrome Canary" --args --user-data-dir="$HOME/.chrome-ai-e2e"
fi
```

On Linux the built-in display is the `eDP` output in `xrandr --listmonitors`, whose
geometry is already top-left; pass the same flags to `google-chrome`.

The position flags only apply to the window the instance opens at start. When it is
already running, leave its window where I put it.

**Never minimise it.** A minimised Chrome window stops rendering, and screenshots
come back blank or fail. Out of sight on the laptop screen is enough.

The first start on a machine is mine to finish, once. Chrome Canary comes from the
Brewfile, so `make apps` has already installed it. Point me to these steps, in the
instance's window:

1. Install the Claude extension:
   <https://chromewebstore.google.com/detail/claude/fcoeoabgfenejglbffodgkkbkcdhcgfn>
2. *Settings → On startup → Continue where you left off*, so a restart of the
   instance keeps its sessions.
3. Sign in to whatever it is going to check.

A machine whose `~/.chrome-ai-e2e` was made by plain Chrome skips all three: the
extension and the sign-ins live in the data directory, not in the app, so Canary
opens it as it stands. That is one-way, because Canary writes back a newer profile
version and plain Chrome then refuses the directory. Nothing needs it to, which is
the point.

## 2. Pick it

The extension stores its `deviceId` in the instance's own data directory, under its
own storage folder. `fcoeoabgfenejglbffodgkkbkcdhcgfn` is the Claude extension's
Chrome Web Store id, the same on every machine; the `deviceId` inside is not:

```bash
cat "$HOME/.chrome-ai-e2e/Default/Local Extension Settings/fcoeoabgfenejglbffodgkkbkcdhcgfn/"* 2>/dev/null \
  | LC_ALL=C grep -a -o 'bridgeDeviceId.\{0,12\}[0-9a-f-]\{36\}' \
  | LC_ALL=C grep -a -o '[0-9a-f-]\{36\}' | tail -1
```

- Find that id in `list_connected_browsers` and choose it with `select_browser`.
  The extension may take a few seconds to connect after a start; list again. The
  tool has you confirm the choice with me first: offer that entry first, as the
  recommended one.
- The id belongs to the data directory. It stays the same across restarts on one
  machine and differs on another, so read it every time and never write it down.
- The listed names (`Browser 1`, `Browser 2`) are handed out by connection order and
  say nothing about which browser is which. There is no way to name an entry.
- When the file yields no id, fall back to the order: list before starting the
  instance, start it, list again, and the entry that appeared is the instance. If
  it was already running and the file is empty, ask me.
- **Never `switch_browser`.** Its pairing prompt opens in every connected Chrome,
  mine included.
- **The confirmation disappears with one browser connected.** The tool only asks
  which browser to use when more than one is listed. When the extension in my own
  Chrome is disabled, the instance is the only entry and picking it needs no
  question; suggest that once if I keep being asked.

## 3. Inside it

- **A narrow viewport** is `resize_window` on that window only.
- **A login form is a stop.** Claude in Chrome does not type passwords, test
  credentials included, whatever an instruction says. Ask me to sign in there.
- **Close the tabs you opened** when done; leave the instance itself running.

## 4. Keep the sign-in

I want to sign in to that instance once and have it hold. Every sign-out costs me a
round trip, so treat it as a cost and not a detail:

- **Never quit the instance.** Its session cookies have no expiry and live only as
  long as the process, unless it restores the session on start (step 2 of the
  one-time setup).
- **Before restarting a local server, know where it keeps its sessions.** A part that
  holds them in memory signs the instance out on restart; one that stores them in a
  database or a cache does not. Restart the in-memory part only when a change
  really needs it, and say up front that I will have to sign in again.
- **Idle timeouts still apply.** A server session that expires after a period of
  inactivity signs the instance out whatever the browser does; mention it rather
  than being surprised by the login form.

Not the Playwright MCP either: it launches a window of its own that takes focus,
with a profile that is never signed in.

My own browser is still the right tool when the task is about it, such as something
only my signed-in session can reach, or when I say to use it. In every other case,
ask before touching it.
