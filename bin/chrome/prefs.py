#!/usr/bin/env python3
"""Patch the Chrome settings Google does not sync into Default/Preferences.

Driven by prefs.sh, which is the entry point `make chrome` calls: it owns the
platform's profile path and the refusals that have to happen before this runs
at all — Chrome not running, the file readable, the flag recognised. By the time
this starts, the only thing left is the edit.

A file of its own rather than a heredoc inside prefs.sh, so it is editable with
indentation that means something, greppable, and parsed by `make lint` like
every other source here.

usage: prefs.py [--dry-run] <path to Preferences>
"""

import json
import os
import sys
import tempfile

# The settings this repo owns: dotted key -> the value Chrome stores.
#
# Native values rather than a string to re-parse, which is the point of being a
# real module: `240` is an int because `vertical_tabs.uncollapsed_width` is
# registered as an integer pref, and a string value would need no quoting rules
# of its own. See prefs.sh's header for how to find a new key.
PREFS = {
    "vertical_tabs.enabled": True,
    "vertical_tabs.collapsed_state": False,
    "vertical_tabs.uncollapsed_width": 240,
    "side_panel.is_right_aligned": False,
}


def described():
    """The lines both the dry run and the real run print, so they cannot drift."""
    return ["set %s = %s" % (key, json.dumps(value)) for key, value in PREFS.items()]


def patched(prefs):
    """Set each key in place, creating missing parents, touching nothing else.

    A leaf at a time and never a whole subtree: Preferences is one blob, and
    replacing `vertical_tabs` wholesale would take `enabled_first_time` with it
    — or, a level up, every site permission on the machine.
    """
    for key, value in PREFS.items():
        *parents, leaf = key.split(".")
        node = prefs
        for parent in parents:
            node = node.setdefault(parent, {})
        node[leaf] = value
    return prefs


def main(argv):
    args = argv[1:]
    dry_run = bool(args) and args[0] == "--dry-run"
    if dry_run:
        args = args[1:]
    if len(args) != 1:
        return "usage: prefs.py [--dry-run] <path to Preferences>"
    path = args[0]

    if dry_run:
        print("\n".join(described()))
        print("file %s" % path)
        return 0

    with open(path, encoding="utf-8") as f:
        prefs = patched(json.load(f))

    # Temp file plus rename, so an interrupted run leaves the old Preferences
    # intact rather than half a JSON document. mkstemp lands in the same
    # directory, because os.replace is only atomic within one filesystem.
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        # Compact and unescaped, which is how Chrome writes it. The separators
        # are the obvious half; ensure_ascii=False is the half that bites. Its
        # default rewrites every non-ASCII character as \uXXXX, and a real
        # profile has a handful - six in mine, in keys this never touches. That
        # made the file grow by 20 bytes and broke the one promise the script
        # makes, that everything outside PREFS is left as the machine has it.
        json.dump(prefs, f, separators=(",", ":"), ensure_ascii=False)
    # mkstemp is 0600 and so is Chrome's own file, but carry the mode over
    # rather than rely on the two agreeing forever.
    os.chmod(tmp, os.stat(path).st_mode & 0o777)
    os.replace(tmp, path)

    # After the rename, not before: nothing is set until the file is in place.
    print("\n".join(described()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
