# Browser automation: why it is set up this way

Background for `~/.agents/rules/browser-automation.md`. Nothing here is needed to
follow that rule, which is why this sits outside `rules/` and is never auto-loaded:
only `rules` and `skills` are linked into `~/.claude`, so nothing scans `caveats`.
Read it when the setup breaks, when a machine is new, or when someone proposes
simplifying one of these away.

## Why not my own browser

Claude in Chrome sees every browser that has the extension, and left alone it drives
the one I work in. Every action pulls focus mid-typing, `resize_window` for a narrow
viewport shrinks the window I am using rather than a tab, and a click lands inside my
signed-in sessions as me.

## Why an instance and not a profile

Profiles of one browser share one process, and the "Claude started debugging this
browser" banner then shows in every window of that process, mine included. Only its
own `--user-data-dir` makes it a process of its own.

## Why a different application, on macOS

Its own `--user-data-dir` is still not enough. LaunchServices routes an `http` URL to
a **bundle id**, not to a process, and the data directory is internal to Chrome, so
the instance and my own browser were one application as far as the system was
concerned. With both running, `open https://…` went to whichever had registered
first, and there is no setting for it:

```
$ lsappinfo find bundleID=com.google.Chrome
ASN:0x0-0xd50d5-"Google_Chrome":   pid 21620   # the instance, registered first
ASN:0x0-0x798798-"Google_Chrome":  pid 36519   # mine, restarted later
```

The instance is long-lived by design, my own browser restarts for updates, and from
that moment every link I clicked in the terminal opened in the browser I am never
meant to look at. Ghostty cannot help: it has `link-url` for detection and hands the
URL to the OS, with no configurable opener.

Chrome Canary is `com.google.Chrome.canary`, a bundle of its own, so the two are
always distinguishable. Same engine, and the profile is what carries the extension and
the sign-ins, so nothing else changed. Verified 2026-09-21: `open <url>` moved a
marked tab from 0 to 1 in my own browser and left the instance at 0.

**Linux does not have this problem.** `xdg-open` runs `google-chrome`, which forwards
the URL to whatever instance holds the default data directory.

## First start on a machine

Chrome Canary comes from the Brewfile, so `make apps` has installed it. In the
instance's window, once:

1. Install the Claude extension:
   <https://chromewebstore.google.com/detail/claude/fcoeoabgfenejglbffodgkkbkcdhcgfn>
2. Sign in to whatever it is going to check.

A machine whose `~/.chrome-ai-e2e` was made by plain Chrome skips both: the extension
and the sign-ins live in the data directory, not in the application, so Canary opens
it as it stands. That is one-way, because Canary writes back a newer profile version
and plain Chrome then refuses the directory. Nothing needs it to.

There used to be a third step, *Settings → On startup → Continue where you left off*.
`--restore-last-session` in the start command does the same and cannot be forgotten,
so the step is gone. Verified by quitting the instance with a marked tab open and
finding it restored after a relaunch.

## Smaller things that cost an hour each

- **`set -- $L` does not word-split in zsh.** The whole geometry lands in `$1` and the
  instance starts with `--window-size=,`, silently, for months. Hence `${=L}`.
- **`google-chrome-canary` is not a cask.** The name is `google-chrome@canary`, and
  `make apps-test` only parses the Brewfile as Ruby, so it does not catch a wrong one.
- **The pairing prompt is a broadcast.** `switch_browser` opens it in every connected
  browser, which is why the rule reads the `deviceId` off disk instead.
- **One connected browser needs no confirmation.** The tool only asks which to use
  when more than one is listed, so with the extension disabled in my own browser the
  choice stops being a question. Suggest that once if I keep being asked.

## Not the profile in git

Backing `~/.chrome-ai-e2e` up into this repo was considered and dropped. It is a
gigabyte of mostly cache, it holds cookies and an encryption key tied to this
machine's Keychain, and this repo is public. It would also not restore what matters,
since those cookies are undecryptable elsewhere. What belongs in the repo is what
makes the instance reproducible, and that is already here: the cask in the Brewfile,
the flags in the start command, and these two documents.
