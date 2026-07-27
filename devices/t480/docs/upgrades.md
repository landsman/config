# T480 — upgrades and things to consider

Hardware changes that are decided, being weighed, or deliberately parked. The
reasoning lives in the linked issue — this page is the index, so it doesn't drift
out of sync with it.

## Open

| Upgrade | Status | Tracked in |
|---------|--------|------------|
| Replace the fingerprint reader with Framework's Goodix module (`27c6:609c`) | Researched and decided, not bought yet — needs the part and the connector wiring | [#18](https://github.com/landsman/config/issues/18) |

## Parked

| Idea | Why not, for now |
|------|------------------|
| Newer kernel than 7.0.0-22 | Pinned because of the [resume regression](issues/internal-panel-black-on-resume.md). Retest when [Launchpad #2161881](https://bugs.launchpad.net/ubuntu/+source/linux/+bug/2161881) moves |

## Adding to this page

One row per idea, with the detail in a GitHub issue rather than here. If
something turns into an ongoing defect rather than a change to make, it belongs
in [`docs/issues/`](issues) instead.
