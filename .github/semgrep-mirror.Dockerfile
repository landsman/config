# A relabelled copy of the upstream semgrep image — no files added, no command
# changed. It exists because `docker tag` cannot rewrite labels, and the label
# is the whole point: upstream ships
#   org.opencontainers.image.source = github.com/semgrep/semgrep-proprietary
# and GitHub reads that field to decide which repository a GHCR package belongs
# to. Pushed unchanged, the package would sit in my account pointing at a repo
# I do not own, with nothing to say why it is there.
# Deliberately without a default, which is why buildkit warns
# InvalidDefaultArgInFrom on every build. Do not silence it by defaulting to
# `latest`: a forgotten --build-arg would then quietly mirror a moving tag under
# a pinned name. Failing is the correct behaviour here.
ARG SEMGREP_VERSION
FROM semgrep/semgrep:${SEMGREP_VERSION}

# Repeated after FROM on purpose: an ARG declared before it is only in scope for
# the FROM line itself.
ARG SEMGREP_VERSION

LABEL org.opencontainers.image.source=https://github.com/landsman/config
LABEL org.opencontainers.image.base.name=docker.io/semgrep/semgrep:${SEMGREP_VERSION}
LABEL org.opencontainers.image.description="Unmodified mirror of semgrep/semgrep, relabelled so it links back to landsman/config. Every repo of mine that runs `make security` pulls the scanner from here instead of Docker Hub, which rate-limits anonymous pulls on the shared IPs CI runners use. Published by the semgrep-mirror workflow in landsman/config, one dispatch per version. Not a fork: to see what is in it, read semgrep's own docs for the version in the tag."
