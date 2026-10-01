# How stow picks the packages

How `make stow` decides which `devices/` and `os/` packages a machine gets, and what a device package may hold. What each directory is: the [README](../README.md#layout).

Both packages are detected, so one `make stow` is correct everywhere:

- **device** from DMI `product_version` — `ThinkPad T480` → `t480`
- **os** from `/etc/os-release` `ID` — `ubuntu` / `arch`
- **macOS** has neither file, so it is detected from `hw.model` — `Mac17,8` →
  `macbook-pro-m5-16`, `macos`. That mapping is one `sed` line in the Makefile;
  a second Mac gets a second line.

A name with no matching directory is skipped with a note rather than failing, so
a new machine works before its package exists. Override when the guess is wrong:

```
make stow DEVICE=x1 OS=arch
```

Adding a device or an OS is just `mkdir devices/<name>` or `mkdir os/<name>` —
detection picks it up once the directory is there (on macOS, plus one `sed`
expression in the Makefile to map its `hw.model`).

A device package holds two kinds of thing: the dotfile trees that get symlinked
into `$HOME`, and anything that does not belong there — `docs/`, and the
root-owned `system/` tree installed with `sudo cp`. The latter must be listed in
that package's `.stow-local-ignore`, or stow will link it into the home
directory. `devices/t480/system/` is currently Ubuntu-flavoured (apt, plus a pin
for an Ubuntu kernel regression); the Arch side of the same hardware tuning isn't
tracked.
