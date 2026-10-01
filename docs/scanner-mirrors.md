# The scanner mirrors

`make security`, and the shared scans other repos call — `semgrep.yml`,
`dockerfile.yml`, `dependencies.yml` — run their scanners from images in my GHCR,
`ghcr.io/landsman/semgrep-mirror` and `ghcr.io/landsman/trivy-mirror`, not from
Docker Hub (which rate-limits anonymous pulls on the shared IPs CI runners come
from) and not through `aquasecurity/trivy-action`, whose tags were hijacked in
March 2026 to steal CI secrets
([GHSA-69fq-xp46-6x23](https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23)).

Those packages are published from **this** repo and read by all of them. The
address carries no repo name, so any project pulls the same copy with no login
once a package is public; only this repo can push to it, because a `GITHUB_TOKEN`
writes only to packages under its own owner.

Each version lives in one place, the `FROM` line of `bin/<tool>/Dockerfile`, as
`<image>:<tag>@sha256:<digest>`, and everything else reads it from there through
`bin/mirror/image.sh`. The tag names the mirror's tag; the digest is what gets
built, so a tag re-pointed upstream cannot change what runs. Dependabot watches
those files weekly, bumps tag and digest together after a week's cooldown —
longer than any of the March windows stayed open — and opens the pull request.

Merging that pull request is the whole procedure. The mirror workflow triggers on
pushes to `main` touching `bin/*/Dockerfile` and republishes every tool. To bump
by hand, edit the `FROM` line — there is no version to type anywhere else, which
is the point: a version passed on a command line is a version no file records.

Only version tags are pushed. Every scan pins the version this repo last merged,
so a scanner reaches the other repos only after Dependabot proposed it, the
cooldown aged it, and I approved it — and their logs say which version ran. The
cost is real and worth saying: merging here can turn a build red in another repo
with no commit there to point at, and this `git log` is where that explanation
lives. (An older `semgrep-mirror:latest` is still in the package, no longer
pushed; nothing of mine pulls it.)

Each image is an unmodified copy, rebuilt only to carry
`org.opencontainers.image.source` pointing back here — upstream's label names its
own repository, which is what GitHub reads to decide where a package belongs —
for amd64 and arm64, so it runs on a laptop too. `make mirror` does the same from
a laptop, given a `docker login ghcr.io`. **A newly created package is private**,
and a private one is unreadable to the repos that pull it anonymously — flip it
to public once, in the package settings. Until then every scan falls back to the
upstream image by its digest, and says so.
