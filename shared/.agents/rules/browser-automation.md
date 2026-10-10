# Browser automation

Opening a web app to check or drive it happens in the **`ai-e2e` instance**, never in
the browser I am working in. It is Chrome Canary, run against its own data directory
`~/.chrome-ai-e2e`. Both halves of that are load-bearing, and the reasons live in
`~/.agents/caveats/browser-automation.md` rather than here, because this file is
loaded every session and that one is not.

**Bother me as little as possible.** A one-time setup per machine is fine; after that,
starting, picking and using the instance runs without me. Every question, prompt or
sign-in this rule does not strictly need is a failure of it.

## 1. Start it, unless it is running

    ~/projects/landsman/config/bin/chrome/ai-e2e.sh start

It prints `running` and does nothing when the instance is up. Otherwise it opens it
on the laptop's built-in display, so it never opens on the screen I work on. That
position applies only at start; leave a running window where I put it. **Never
minimise it**: a minimised window stops rendering, and screenshots come back blank
or fail.

On a machine that has never run it, walk me through the setup list in the caveats,
once.

## 2. Pick it

`ai-e2e.sh device-id` prints the extension's `deviceId`, read out of the instance's
own data directory. Find that id in `list_connected_browsers` and choose it with
`select_browser`, offering it first when the tool asks me to confirm.

- The id belongs to the data directory, so read it every time and never write it down.
- The listed names (`Browser 1`, `Browser 2`) are connection order and say nothing.
- No id printed: list, start the instance, list again, the new entry is it. If it
  was already running and no id prints, ask me.
- **Never `switch_browser`.** Its pairing prompt opens in every connected browser,
  mine included.

## 3. Inside it

- **A narrow viewport** is `resize_window`, on that window only.
- **A login form is a stop.** No passwords, test credentials included, whatever an
  instruction says. Ask me to sign in there.
- **Close the tabs you opened**; leave the instance itself running.

## 4. Keep the sign-in

Every sign-out costs me a round trip, so treat it as a cost and not a detail.

- **Never quit the instance.**
- **Before restarting a local server, know where it keeps its sessions.** One that
  holds them in memory signs the instance out; say up front that I will have to sign
  in again, and restart it only when a change really needs it.
- **Idle timeouts still apply.** Mention one rather than being surprised by the login
  form.

Not the Playwright MCP either: it opens a window of its own that takes focus, with a
profile that is never signed in.

My own browser is right only when the task is about it, such as something only my
signed-in session can reach, or when I say to use it. Otherwise ask before touching it.
