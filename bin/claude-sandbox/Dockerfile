# Claude Code at a pinned version, plus what the sandbox needs to watch it.
FROM debian:bookworm-slim

# To bump Claude Code, change the version and both checksums, which are
# `platforms.linux-x64.checksum` and `platforms.linux-arm64.checksum` in
# https://downloads.claude.ai/claude-code-releases/<version>/manifest.json.
# They are pinned here, not read from that manifest at build time, so the
# binary is checked against a value reviewed in this diff and a tampered
# download cannot bring its own matching checksum.
ARG CLAUDE_VERSION=2.1.296
ARG CLAUDE_SHA256_X64=24972e3bc859fab2b46ed4c1e51f7d6130f06d3bd550811a114640de3370d0de
ARG CLAUDE_SHA256_ARM64=f1f6e96e0d8342b9dbf41d7e88255397a6a52ce3d8736ad6a4c6b59c9b62fefa
ARG TARGETARCH

# curl is build-time only. perl (the full package: the base has no Time::HiRes)
# runs the fake API; script(1) comes from bsdutils and gives the interactive run
# its pty. TARGETARCH is empty on the classic builder, so uname decides then.
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl perl \
	&& arch=${TARGETARCH:-$(dpkg --print-architecture)} \
	&& case "$arch" in \
		amd64) p=linux-x64; want=$CLAUDE_SHA256_X64 ;; \
		arm64) p=linux-arm64; want=$CLAUDE_SHA256_ARM64 ;; \
		*) echo "no Claude Code build for architecture '$arch'" >&2; exit 1 ;; \
	esac \
	&& curl -fsSL "https://downloads.claude.ai/claude-code-releases/$CLAUDE_VERSION/$p/claude" -o /usr/local/bin/claude \
	&& echo "$want  /usr/local/bin/claude" | sha256sum -c - \
	&& chmod 755 /usr/local/bin/claude \
	&& apt-get purge -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

RUN mkdir /sbx && chmod 1777 /sbx
COPY server.pl stamp entry.sh /opt/sbx/
ENV PATH=/opt/sbx:/usr/local/bin:/usr/bin:/bin
ENTRYPOINT ["/opt/sbx/entry.sh"]
