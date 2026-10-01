# macOS settings

What `make macos` and `make macos-touchid` write, and why none of it is a stowed file.

**macOS System Settings are written, not stowed.** macOS keeps them in `defaults`
(binary plists that `cfprefsd` rewrites on its own schedule, mixed in with window
frames and analytics stamps), so there is no file to symlink. `bin/macos/defaults.sh`
writes only the keys this repo names and leaves the rest of the machine alone.
To add one: change it in System Settings, then diff what moved —

```
defaults read > /tmp/before   # …click the thing…   defaults read > /tmp/after
diff /tmp/before /tmp/after
```

and paste the key into the script with the type `defaults read-type <domain> <key>`
reports. `./bin/macos/defaults.sh --dry-run` prints every write without doing any.

One domain is committed whole instead: `bin/macos/symbolichotkeys.plist` is the
keyboard shortcuts, 16 of the 21 system ones turned off. That is a nested dict of
numeric IDs, so it is exported as XML and `defaults import`ed — readable as a diff,
where sixteen `-dict-add` lines would not be. One of the five left on is id 60,
*Select the previous input source*, on its stock `⌃Space` — the Czech/U.S. switch
is otherwise the left `fn` key, which an external keyboard does not have.
Re-export it with:

```
defaults export com.apple.symbolichotkeys bin/macos/symbolichotkeys.plist
plutil -convert xml1 bin/macos/symbolichotkeys.plist
```

**Which app opens what is a third shape again.** `make macos` also runs
`bin/macos/file-associations.sh`, which owns the *Open with… > Change All*
choices: `.sql` in Sublime Text, `.mp4` and `.m4a` in VLC, `.doc`, `.docx`,
`.xlsx` and `.csv` in LibreOffice, a saved `.html` in Chrome. The list is
`bin/macos/file-associations.conf`, a file of its own because it is the part
worth reading — three columns, and the first says which of the three keys macOS
matches on (`ext` an extension, `uti` a content type, `scheme` a URL scheme;
Finder picks, so copy what it wrote).

They all live in one `LSHandlers` array in
`~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist`,
but writing that file is only half of it, and for a while it was the wrong half.
LaunchServices keeps its own copy of the content-type and URL-scheme bindings and
does not re-read the plist when its database is rebuilt, so an app that already
claims a type keeps it: Pages stayed the default for `.docx` while the plist said
LibreOffice. Those two kinds go through `LSSetDefaultRoleHandlerForContentType`
and `LSSetDefaultHandlerForURLScheme` instead, reached through `osascript`'s ObjC
bridge — the API `duti` wraps, without installing `duti`.

The plist is still written by hand for the `ext` kind, because that is the one
the API cannot express: for an extension no app claims a UTI for, it derives a
dynamic UTI and LaunchServices rejects it with `-50`, while Finder writes an
`LSHandlerContentTag` entry. The merge also leaves every other entry alone — the
rest of that array is a URL-scheme entry for every app the machine happens to
have installed, which is noise, not a choice. To add one: set it in Finder or
System Settings, read back what it wrote, and copy it into the list.

```
/usr/libexec/PlistBuddy -c 'Print :LSHandlers' ~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist
```

The default browser is deliberately not in the list. It is the one association
macOS reserves for the user: `https` comes back `-54`, `http` is accepted and
then ignored, and the *Default web browser* dropdown is not a content type at all
(`-50`). Set it in System Settings > Desktop & Dock, once per machine.

`--dry-run` prints the merged plist and writes nothing. Applying rebuilds the
LaunchServices database, which takes a few seconds; without that an extension
would only arrive at the next login.

**Touch ID for `sudo` has no GUI switch.** The Touch ID pane in System Settings
covers the login window, Apple Pay and password autofill; `sudo` is PAM only.
Since macOS 14 Apple ships `/etc/pam.d/sudo_local.template` with the line
commented out, in a file that survives OS updates — `make macos-touchid`
uncomments it, checks the result before installing it, and leaves the terminal
open so a broken `sudo` can still be undone.

It does not work inside `tmux`: a tmux pane is not attached to the session that
owns the Touch ID prompt. `pam_reattach` fixes that, and is deliberately not here
— it would put a `/opt/homebrew` object into root's authentication stack, and
Homebrew's prefix is writable by the user it would be granting root to.
