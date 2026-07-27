# HP ProDesk 600 G3

Not one machine — 4x ProDesk 600 G3 Mini (i5-6500T, 32 GB DDR4, 240 GB SATA SSD)
running Debian 13 as the **pollos** homelab cluster: `gus`, `mike`, `walter`,
`jesse`.

Nothing is stowed from here. These boxes are not workstations, so they get no
`$HOME` dotfiles from this repo — they are provisioned from their own repo:

**[landsman/homelab → `pollos/`](https://github.com/landsman/homelab/tree/main/pollos)**

| What | Where |
|------|-------|
| Setup scripts (fresh Debian → cluster node) | [`pollos/setup`](https://github.com/landsman/homelab/tree/main/pollos/setup) |
| Per-node hardware, RAM, SSH config, ports | [`pollos/README.md`](https://github.com/landsman/homelab/blob/main/pollos/README.md) |
| Microsite | [www.pollos.cz](https://www.pollos.cz) |

Linked rather than vendored as a submodule: git submodules track a whole
repository, and `pollos/` is a subdirectory of `homelab` — pulling it in would
drag the rest of the homelab along with it.
