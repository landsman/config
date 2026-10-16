# Where to look, per ecosystem

**Not to be read whole.** Open your ecosystem, and `Cross-ecosystem` with it:

    awk '/^## npm/{f=1;print;next} /^## /{f=0} f' ~/.agents/skills/dependencies/sources.md

**Read the API, not the page.** Page marks were measured on 2026-10-16 with a
plain HTTP client, which is what a web-fetch tool is: ✅ the page carries its
data, ⚠️ thin or rendered in JavaScript, ❌ blocked. Commands come from two
researches of that day, on choosing and on vulnerabilities. Flags change between
versions: record each tool's `--version` with its output, work in a throwaway
directory, URL-encode scoped names.

## Cross-ecosystem

| Source | Gives | For an agent | Page |
|---|---|---|---|
| deps.dev | versions, graph, licenses, advisories, links | `https://api.deps.dev/v3/systems/{system}/packages/{name}` | ⚠️ |
| OSV | vulnerabilities and `MAL-` malicious records by version range | `POST https://api.osv.dev/v1/query`, `/v1/querybatch`, `GET /v1/vulns/{id}` | ✅ |
| GitHub Advisory Database | GHSA and CVE records, reviewed and not, malware | `gh api /advisories -f ecosystem=… -f affects=…` — 60 requests an hour without a token | ✅ |
| CISA KEV | exploited in the wild, with `dateAdded`, `dueDate` | `https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json` | ✅ |
| FIRST EPSS | probability of exploitation in 30 days, with a date | `https://api.first.org/data/v1/epss?cve={CVE}` | — |
| NVD | CVE enrichment — only prioritised CVEs since 2026-04-15 | `https://services.nvd.nist.gov/rest/json/cves/2.0?cveId={CVE}`, 5 requests per 30 s without a key | — |
| OpenSSF Scorecard | repo security practices, per check | `https://api.securityscorecards.dev/projects/github.com/{owner}/{repo}`, or the `scorecard` CLI | ⚠️ |
| endoflife.date | support windows — corroboration only, the vendor's policy decides | `https://endoflife.date/api/v1/products/{product}` | ✅ |
| GitHub REST | repo state, releases, tags, repository advisories | `gh api repos/{owner}/{repo}` | ✅ |

```bash
curl -fsS "https://api.deps.dev/v3/systems/npm/packages/%40scope%2Fpackage" | jq .
# the exact version — a package-only query is discovery, not evidence
jq -n --arg e npm --arg n "$PKG" --arg v "$VERSION" '{package:{ecosystem:$e,name:$n},version:$v}' |
  curl -fsS https://api.osv.dev/v1/query -H 'content-type: application/json' --data-binary @- |
  jq '.vulns[]? | {id,aliases,published,withdrawn,affected}'
gh api --method GET /advisories -f ecosystem=npm -f affects="$PKG" --paginate |
  jq '.[] | {ghsa_id,cve_id,type,severity,published_at,vulnerabilities}'
curl -fsS https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json |
  jq --arg c "$CVE" '.vulnerabilities[] | select(.cveID == $c)'
curl -fsS "https://api.first.org/data/v1/epss?cve=$CVE" | jq '.data[] | {cve,epss,percentile,date}'
scorecard --repo=github.com/OWNER/REPO --format=json | jq '.checks[] | {name,score,reason}'
osv-scanner --version
osv-scanner scan source --recursive --format json --output osv.json .
```

## npm and Bun

| Source | Gives | For an agent | Page |
|---|---|---|---|
| registry | existence, versions, maintainers, repository, engines, scripts, integrity | `https://registry.npmjs.org/{name}` or `/{name}/{version}`; `npm view` | npmjs.com ❌ |
| downloads | counts over a period — popularity only | `https://api.npmjs.org/downloads/range/last-year/{name}` | npmtrends ❌ |
| provenance | registry signatures and Sigstore attestations | `npm audit signatures` | — |
| publint, arethetypeswrong | how the package is published, types and exports | `npx publint`, `npx -p @arethetypeswrong/cli attw` | ⚠️ |
| bundlephobia | estimated bundle size — a lead, the local build decides | `https://bundlephobia.com/api/size?package={name}@{version}` | ⚠️ |
| socket.dev | supply-chain behaviour | API needs an account — a person's check | ❌ |

Bun installs from the npm registry, so identity checks are the same; test with
the real Bun version, it does not resolve or run scripts exactly like npm.
`bun audit` reads `bun.lock` and asks the npm advisory endpoint; `--ignore` and
`--audit-level` change only the exit code.

```bash
npm view "$PKG@$VERSION" name version time deprecated license repository maintainers \
  engines peerDependencies dependencies optionalDependencies scripts dist --json
npm owner ls "$PKG"
# fetch without installing or running anything
npm pack "$PKG@$VERSION" --json && tar -xzf ./*.tgz
jq '{name,version,license,repository,scripts,dependencies,bin}' package/package.json
# resolve the graph without lifecycle scripts
npm install --ignore-scripts --package-lock-only --save-exact "$PKG@$VERSION"
npm ls --all --json > npm-tree.json
npm explain "$TRANSITIVE"
npm audit --json     # .vulnerabilities[] .via .range .nodes .fixAvailable
npm audit signatures
npx --yes publint package
npx --yes -p @arethetypeswrong/cli attw --pack package
bun audit --json
```

No free reachability tool exists here; for a serious finding, search the code for
the advisory's functions (`rg`). On Workers, decide from the execution path, not
from the word "edge".

## Gradle and Maven

| Source | Gives | For an agent | Page |
|---|---|---|---|
| Maven Central | POMs, checksums, signatures, versions | `https://repo1.maven.org/maven2/{group/path}/{artifact}/maven-metadata.xml` and the `.pom` | central.sonatype.com ⚠️, mvnrepository ❌ |
| Central search | coordinate discovery and release timestamps — verify against the repository | `https://search.maven.org/solrsearch/select?q=g:{group}+AND+a:{artifact}&wt=json` | — |
| Gradle Plugin Portal | plugin coordinates and versions | plugin marker artifacts in the portal's Maven repository | ✅ |
| Spring Boot | the versions Boot already manages | [managed coordinates](https://docs.spring.io/spring-boot/appendix/dependency-versions/coordinates.html); prefer them unless an override is deliberate and tested | ✅ |
| OWASP Dependency-Check | NVD matching through CPEs | weaker since NVD stopped enriching every CVE; check its evidence, not its gate | — |

```bash
GROUP_PATH="${GROUP//./\/}"
curl -fsS "https://repo1.maven.org/maven2/$GROUP_PATH/$ARTIFACT/maven-metadata.xml"
curl -fsS "https://repo1.maven.org/maven2/$GROUP_PATH/$ARTIFACT/$VERSION/$ARTIFACT-$VERSION.pom"
./gradlew -q dependencies --configuration runtimeClasspath
./gradlew -q dependencyInsight --dependency "$GROUP:$ARTIFACT" --configuration runtimeClasspath
./gradlew -q buildEnvironment          # plugins: a trust boundary of their own
# verification metadata: what was fetched, not independent trust — review the diff
./gradlew --write-verification-metadata pgp,sha256 --export-keys help
mvn -Dverbose dependency:tree
mvn -q dependency:get -Dartifact="$GROUP:$ARTIFACT:$VERSION" -Dtransitive=false
# reachability on the built JAR, if the installed OSV-Scanner supports it
./gradlew clean bootJar
osv-scanner scan source --recursive --call-analysis=jar --format json --output osv-jvm.json .
```

## Composer

| Source | Gives | For an agent | Page |
|---|---|---|---|
| Packagist | versions, repository, maintainers, downloads, dependents, `abandoned` (with its replacement) | `https://packagist.org/packages/{vendor}/{name}.json` — cached 12 h; at most 10 concurrent requests, 20 for static files | ✅ |
| Packagist static metadata | Composer 2 version data | `https://repo.packagist.org/p2/{vendor}/{name}.json` | — |
| Packagist advisories | PHP advisories Composer uses | `https://packagist.org/api/security-advisories/?packages[]={vendor}/{name}` | — |
| FriendsOfPHP | an open advisory set behind them | `github.com/FriendsOfPHP/security-advisories` | — |

```bash
curl -fsS "https://packagist.org/packages/$PKG.json" | jq '.package | {name,repository,abandoned,downloads,maintainers}'
curl -fsS --get https://packagist.org/api/security-advisories/ --data-urlencode "packages[]=$PKG" | jq .
composer show --all "$PKG"
composer update --no-install --no-plugins --no-scripts
composer audit --locked --format=json
composer audit --locked --no-dev --format=json
composer why "$TRANSITIVE"
composer licenses --format=json
```

`composer audit` matches ranges; it says nothing about reachability, and it also
reports abandoned and malware-flagged packages — separate conditions from a CVE.

## Go

| Source | Gives | For an agent | Page |
|---|---|---|---|
| module proxy | immutable version info, `go.mod`, source zip, version list | `https://proxy.golang.org/{module}/@latest`, `/@v/list`, `/@v/{version}.info` | — |
| checksum database | the logged checksum of a public module version | `https://sum.golang.org/lookup/{module}@{version}` | — |
| Go vulnerability database | advisories with vulnerable symbols | `https://vuln.go.dev`, read by `govulncheck` | — |
| pkg.go.dev | docs, versions, "Imported by", license | no stable JSON API | ✅ |

A new malicious version is checksummed as validly as a good one; the checksum
database proves only that nobody changed a version after it was logged.

```bash
curl -fsS "https://proxy.golang.org/$MODULE/@v/list"
curl -fsS "https://proxy.golang.org/$MODULE/@latest"
curl -fsS "https://sum.golang.org/lookup/$MODULE@$VERSION"
go mod download -json "$MODULE@$VERSION"
go list -m -json all > go-modules.json
go mod why -m "$MODULE"
govulncheck -json ./...
# the binary actually shipped, with its real tags and target
govulncheck -mode=binary -json ./app
```

## PyPI

| Source | Gives | For an agent | Page |
|---|---|---|---|
| PyPI JSON | metadata, releases, files with digests, `requires_python`, yanked | `https://pypi.org/pypi/{name}/json`, `/{name}/{version}/json` | ✅ |
| Integrity API | PEP 740 provenance per file | `https://pypi.org/integrity/{name}/{version}/{filename}/provenance` | — |
| PyPA advisory database | Python advisories in OSV format | `github.com/pypa/advisory-database`, through OSV | — |
| pypistats | download counts, CI included | `https://pypistats.org/api/packages/{name}/recent` | ⚠️ |

```bash
curl -fsS "https://pypi.org/pypi/$PKG/$VERSION/json" | jq '.info | {name,version,license,requires_python,project_urls}'
# a wheel only, so nothing is built or run
pip download --no-deps --only-binary=:all: "$PKG==$VERSION" -d ./wheel
pip-audit --requirement requirements.txt --format json --output pip-audit.json
pip-audit --requirement requirements.txt --ignore-vuln "$ID"   # reviewed, in versioned CI config
```

## Homebrew

| Source | Gives | For an agent | Page |
|---|---|---|---|
| formulae API | versions, source URLs, hashes, dependencies, license, deprecated or disabled, install analytics | `https://formulae.brew.sh/api/formula/{name}.json`, `/api/cask/{token}.json` | ✅ |
| brew | the same locally, and the formula's own install block | `brew info --json=v2`, `brew cat` | — |

Compare `install_on_request`, not total installs, which count dependencies.
`brew audit` checks the formula's style, not vulnerabilities: map the upstream
product and version to its advisories, or scan the installed prefix.

```bash
curl -fsS "https://formulae.brew.sh/api/formula/$NAME.json" | jq '{name,license,deprecated,disabled,analytics}'
brew info --json=v2 "$NAME"
brew deps --tree "$NAME"
brew cat "$NAME"
syft "dir:$(brew --prefix "$NAME")" -o cyclonedx-json=brew-sbom.json
grype sbom:brew-sbom.json -o json
```

## Actions

An action is build code holding the workflow's credentials: stricter than a
library, and C6, C8, C10 and C15 come first. A tag such as `@v4` is a name, not
an identity — pin the reviewed full commit SHA with the version as a comment.
On Forgejo, the `forgejo-workflows` rule says where actions come from.

| Source | Gives | For an agent |
|---|---|---|
| the action's repo | `action.yml`, entrypoints, bundled code, the commit behind a tag, repository advisories | `gh api repos/{owner}/{repo}/commits/{tag}`, `contents/action.yml?ref={sha}`, `security-advisories` |
| GitHub advisories | the `actions` ecosystem | `gh api /advisories -f ecosystem=actions -f affects={owner}/{repo}` |
| Scorecard | dangerous workflows, token permissions, pinned dependencies | the Scorecard API or CLI |
| Forgejo API | the same on a Forgejo host | `https://{host}/api/v1/repos/{owner}/{repo}/tags/{tag}` |

```bash
SHA=$(gh api "repos/$OWNER/$REPO/commits/$TAG" --jq .sha)
gh api "repos/$OWNER/$REPO/contents/action.yml?ref=$SHA" --jq .content | base64 -d
gh api --method GET /advisories -f ecosystem=actions -f affects="$OWNER/$REPO" --paginate
gh api "repos/$OWNER/$REPO/security-advisories" --paginate
gh api "repos/$OWNER/$REPO/tarball/$SHA" > action.tar.gz     # read offline, never run
# uses: OWNER/REPO@<SHA> # <TAG>
```

Read `runs.using`, `main`, `pre` and `post`, bundled JavaScript against its
source, a Dockerfile's base digest, composite steps' shell, and which inputs reach
a shell, git or the network.

## Container images

Select by digest, never by tag. Judge the update cadence, the distribution's
support window, the user it runs as, its entrypoint, the architectures, an SBOM
and provenance — a low vulnerability count alone does not make a better base.
Where a distribution backports fixes, its own advisory beats an upstream version
comparison.

| Source | Gives | For an agent |
|---|---|---|
| the registry | manifests, digests, platforms, config | `skopeo inspect`, `docker buildx imagetools inspect` |
| cosign | signatures and attestations | `cosign verify {image}@{digest} --certificate-identity=… --certificate-oidc-issuer=…` |
| syft, grype, trivy, OSV-Scanner | SBOM, vulnerabilities, licenses | local CLIs |

```bash
skopeo inspect "docker://$IMAGE@$DIGEST" | jq '{Digest,Created,Architecture,Os,Env,Labels}'
syft "$IMAGE@$DIGEST" -o cyclonedx-json=image-sbom.json
trivy image --format json --output trivy-image.json "$IMAGE@$DIGEST"
grype "$IMAGE@$DIGEST" -o json
osv-scanner scan image --format json --output osv-image.json "$IMAGE@$DIGEST"
```
