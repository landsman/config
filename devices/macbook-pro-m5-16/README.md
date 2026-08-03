# MacBook Pro 16" M5 Pro

Runs only macOS, so unlike the [T480](../t480) there is no OS split for this
machine — the userland half lives in [`os/macos/`](../../os/macos).

## Hardware

|          |                                                                                      |
| -------- | ------------------------------------------------------------------------------------ |
| Model id | `Mac17,8` — from `sysctl -n hw.model`, this is what `make stow` maps to this package |
| Chip     | Apple M5 Pro — 18-core CPU (6 performance + 12 efficiency), 20-core GPU              |
| Memory   | 64 GB unified                                                                        |
| Storage  | 1 TB                                                                                 |
| Display  | 16", 3456 × 2234 Retina                                                              |
| OS       | macOS 26                                                                             |

Re-read with `sysctl -n hw.model machdep.cpu.brand_string hw.memsize` and
`system_profiler SPDisplaysDataType`. Don't paste `SPHardwareDataType` in here
wholesale — it carries the serial number and hardware UUID.

## What lives where

| Path                                        | What                                                            |
| ------------------------------------------- | --------------------------------------------------------------- |
| `devices/macbook-pro-m5-16/` (this package) | Nothing stowed yet — only for config that needs _this_ hardware |
| [`os/macos/`](../../os/macos)               | The macOS userland: `~/.zshrc` — PATH, mise, completion         |
| [`shared/`](../../shared)                   | Portable bits: aliases, tmux, JetBrains                         |

Nothing needs `sudo` here, so there is no `system/` tree like the T480 has.

## Adding to this package

Files here are symlinked into `$HOME` by `make stow`, so anything that must
_not_ land there — a `docs/` directory, say — has to be listed in a
`.stow-local-ignore`, see [the T480 one](../t480/.stow-local-ignore). A local
ignore file replaces stow's whole default list rather than extending it.
`README.md` is covered by those defaults, which is why this package has no
ignore file yet.
