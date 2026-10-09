# A relabelled copy of the upstream trivy image — no files added, no command
# changed — for the same reason as bin/semgrep/Dockerfile: the label is what
# ties the GHCR package to this repo.
#
# Why a mirror rather than aquasecurity/trivy-action: in March 2026 an attacker
# force-pushed 76 of trivy-action's 77 tags, all of setup-trivy's, and published
# malicious trivy images (GHSA-69fq-xp46-6x23). A workflow that says
# `trivy-action@v0.x` runs whatever that tag points at today. This line runs a
# digest, bumped by Dependabot after a week's cooldown — longer than any of
# those windows stayed open — and the copy in GHCR does not change after that.
FROM aquasec/trivy:0.75.0@sha256:af6acf9a6b85dfe389a1941505c0ce9efef52a4719635e1a962f022a3d855daa

LABEL org.opencontainers.image.source=https://github.com/landsman/config
LABEL org.opencontainers.image.description="Unmodified mirror of aquasec/trivy, relabelled so it links back to landsman/config. The shared dockerfile and dependencies scans in landsman/config run trivy from here. Published by the mirror workflow in landsman/config, one tag per version bump, for amd64 and arm64. Not a fork: to see what is in it, read trivy's own docs for the version in the tag."
