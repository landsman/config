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

Inside that profile:

- **A narrow viewport** is `resize_window` on that window only.
- **A login form is a stop.** Say so and wait for me to sign in there; never type
  credentials, not even for localhost. Restarting a local backend usually signs the
  profile out again, so avoid a restart between my login and the check.
- **Close the tabs you opened** when done.

Not the Playwright MCP either: it launches a window of its own that takes focus,
and a fresh profile that is never signed in.

My own profile is still the right tool when the task is about my browser, such as
something only my signed-in session can reach, or when I say to use it. In every
other case, ask before touching it.
