# A relabelled copy of the upstream semgrep image — no files added, no command
# changed. It exists because `docker tag` cannot rewrite labels, and the label
# is the whole point: upstream ships
#   org.opencontainers.image.source = github.com/semgrep/semgrep-proprietary
# and GitHub reads that field to decide which repository a GHCR package belongs
# to. Pushed unchanged, the package would sit in my account pointing at a repo
# I do not own, with nothing to say why it is there.
#
# The version is written here, literally, and nowhere else. It used to arrive as
# a --build-arg from the workflow's dispatch input, which meant the only record
# of what to mirror was a box someone typed into. Dependabot cannot read that,
# and cannot read `FROM image:${ARG}` either — its tag pattern is [\w][\w.-]*,
# so a `${` makes it skip the line without a word. A literal tag is the one form
# it does read, so this line is what it opens pull requests against, and the
# Makefile reads the version back out of it rather than keeping a second copy.
FROM semgrep/semgrep:1.172.0

LABEL org.opencontainers.image.source=https://github.com/landsman/config
LABEL org.opencontainers.image.description="Unmodified mirror of semgrep/semgrep, relabelled so it links back to landsman/config. Every repo of mine that runs `make security` pulls the scanner from here instead of Docker Hub, which rate-limits anonymous pulls on the shared IPs CI runners use. Published by the semgrep-mirror workflow in landsman/config, one tag per version bump. Not a fork: to see what is in it, read semgrep's own docs for the version in the tag."

# There was an image.base.name label here saying docker.io/semgrep/semgrep at the
# same version. It went with the ARG: Dependabot rewrites the FROM line and only
# the FROM line, so a second copy of the version would sit here going stale on
# its own. The FROM above says the same thing and cannot drift from itself.
