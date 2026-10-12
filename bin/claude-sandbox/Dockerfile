# Claude Code at a pinned version, plus what the sandbox needs to watch it.
# Bumping Claude Code is the one ARG below.
FROM debian:bookworm-slim

ARG CLAUDE_VERSION=2.1.296
ARG TARGETARCH

# The native build from the release bucket, checked against the manifest's
# SHA-256 (the manifest is what Anthropic signs). curl and jq are build-time
# only. perl (the full package: the base has no Time::HiRes) runs the fake API; script(1)
# comes from bsdutils and gives the interactive run its pty.
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl jq perl \
	&& case "$TARGETARCH" in amd64) p=linux-x64 ;; arm64) p=linux-arm64 ;; *) echo "no build for $TARGETARCH"; exit 1 ;; esac \
	&& u=https://downloads.claude.ai/claude-code-releases/$CLAUDE_VERSION \
	&& want=$(curl -fsSL "$u/manifest.json" | jq -r --arg p "$p" '.platforms[$p].checksum') \
	&& curl -fsSL "$u/$p/claude" -o /usr/local/bin/claude \
	&& echo "$want  /usr/local/bin/claude" | sha256sum -c - \
	&& chmod 755 /usr/local/bin/claude \
	&& apt-get purge -y curl jq && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

RUN mkdir /sbx && chmod 1777 /sbx
COPY server.pl stamp entry.sh /opt/sbx/
ENV PATH=/opt/sbx:/usr/local/bin:/usr/bin:/bin
ENTRYPOINT ["/opt/sbx/entry.sh"]
