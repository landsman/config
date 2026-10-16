# Where to look, per ecosystem

**Not to be read whole.** Open your ecosystem, and `Cross-ecosystem` with it:

    awk '/^## npm/{f=1;print;next} /^## /{f=0} f' ~/.agents/skills/dependencies/sources.md

**Read the API, not the page.** Page marks were measured on 2026-10-16 with a
plain HTTP client, which is what a web-fetch tool is: ✅ the page carries its
data, ⚠️ thin or rendered in JavaScript, ❌ blocked. The commands under npm,
Gradle and Maven come from the research of that day; the others are standard
usage it did not reach (its answer was cut off there). Work in a throwaway
directory, URL-encode scoped names, and record tool versions.

## Cross-ecosystem

| Source | Gives | For an agent | Page |
|---|---|---|---|
| deps.dev | versions, graph, licenses, advisories, links | `https://api.deps.dev/v3/systems/{system}/packages/{name}` | ⚠️ |
| OSV | vulnerabilities by version range | `POST https://api.osv.dev/v1/query`, `/v1/querybatch` | ✅ |
| GitHub Advisory Database | GHSA and CVE records | `gh api /advisories -f ecosystem=… -f affects=…` | ✅ |
| OpenSSF Scorecard | repo security practices, per check | `https://api.securityscorecards.dev/projects/github.com/{owner}/{repo}`, or the `scorecard` CLI | ⚠️ |
| endoflife.date | support windows — corroboration only, the vendor's policy decides | `https://endoflife.date/api/v1/products/{product}` | ✅ |
| GitHub REST | repo state, releases, tags, contributors | `gh api repos/{owner}/{repo}` — 60 requests an hour without a token | ✅ |

```bash
curl -fsS "https://api.deps.dev/v3/systems/npm/packages/%40scope%2Fpackage" | jq .
curl -fsS https://api.osv.dev/v1/query -H 'content-type: application/json' \
  -d '{"version":"1.2.3","package":{"ecosystem":"npm","name":"@scope/package"}}' | jq .
gh api --method GET /advisories -f ecosystem=npm -f affects='@scope/package' --paginate
gh api repos/OWNER/REPO --jq '{full_name,archived,disabled,pushed_at,license,owner: .owner.login}'
gh api repos/OWNER/REPO/releases --paginate
scorecard --repo=github.com/OWNER/REPO --format=json | jq '.checks[] | {name,score,reason}'
osv-scanner scan source -r .
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

```bash
npm view "$PKG@$VERSION" name version time license repository maintainers \
  engines peerDependencies dependencies optionalDependencies scripts dist --json
npm owner ls "$PKG"
# fetch without installing or running anything
npm pack "$PKG@$VERSION" --json && tar -xzf ./*.tgz
jq '{name,version,license,repository,scripts,dependencies,bin}' package/package.json
# resolve the graph without lifecycle scripts
npm install --ignore-scripts --package-lock-only "$PKG@$VERSION"
npm ls --all --json > npm-tree.json
npm audit --json
npm audit signatures
npx --yes publint package
npx --yes -p @arethetypeswrong/cli attw --pack package
```

## Gradle and Maven

| Source | Gives | For an agent | Page |
|---|---|---|---|
| Maven Central | POMs, checksums, signatures, versions | `https://repo1.maven.org/maven2/{group/path}/{artifact}/maven-metadata.xml` and the `.pom` | central.sonatype.com ⚠️, mvnrepository ❌ |
| Central search | coordinate discovery — verify against the repository | `https://search.maven.org/solrsearch/select?q=g:{group}+AND+a:{artifact}&wt=json` | — |
| Gradle Plugin Portal | plugin coordinates and versions | plugin marker artifacts in the portal's Maven repository | ✅ |
| Spring Boot | the versions Boot already manages | [managed coordinates](https://docs.spring.io/spring-boot/appendix/dependency-versions/coordinates.html); prefer them unless an override is deliberate and tested | ✅ |

```bash
GROUP_PATH="${GROUP//./\/}"
curl -fsS "https://repo1.maven.org/maven2/$GROUP_PATH/$ARTIFACT/maven-metadata.xml"
curl -fsS "https://repo1.maven.org/maven2/$GROUP_PATH/$ARTIFACT/$VERSION/$ARTIFACT-$VERSION.pom"
./gradlew -q dependencies --configuration runtimeClasspath
./gradlew -q dependencyInsight --dependency "$GROUP:$ARTIFACT" --configuration runtimeClasspath
# verification metadata: what was fetched, not independent trust — review the diff
./gradlew --write-verification-metadata pgp,sha256 --export-keys help
mvn -Dverbose dependency:tree
```

## Composer

| Source | Gives | For an agent | Page |
|---|---|---|---|
| Packagist | versions, repository, maintainers, downloads, dependents, `abandoned` (with its replacement) | `https://packagist.org/packages/{vendor}/{name}.json` — cached 12 h; at most 10 concurrent requests, 20 for static files | ✅ |
| Packagist static metadata | Composer 2 version data | `https://repo.packagist.org/p2/{vendor}/{name}.json` | — |
| Packagist advisories | PHP advisories Composer uses | `https://packagist.org/api/security-advisories/?packages[]={vendor}/{name}` | — |

```bash
curl -fsS "https://packagist.org/packages/$PKG.json" | jq '.package | {name,repository,abandoned,downloads,maintainers}'
curl -fsSg "https://packagist.org/api/security-advisories/?packages[]=$PKG" | jq .
composer show --all "$PKG"
composer require "$PKG:$VERSION" --dry-run --no-scripts --no-plugins
composer audit
composer licenses --format=json
```

## Go

| Source | Gives | For an agent | Page |
|---|---|---|---|
| module proxy | immutable version info, `go.mod`, source zip, version list | `https://proxy.golang.org/{module}/@latest`, `/@v/list`, `/@v/{version}.info` | — |
| checksum database | the logged checksum of a public module version | `https://sum.golang.org/lookup/{module}@{version}` | — |
| pkg.go.dev | docs, versions, "Imported by", license | no stable JSON API | ✅ |
| govulncheck | vulnerabilities your code actually reaches | `govulncheck ./...` | — |

A new malicious version is checksummed as validly as a good one; the checksum
database proves only that nobody changed a version after it was logged.

```bash
curl -fsS "https://proxy.golang.org/$MODULE/@v/list"
curl -fsS "https://proxy.golang.org/$MODULE/@latest"
curl -fsS "https://sum.golang.org/lookup/$MODULE@$VERSION"
go mod graph
go mod why -m "$MODULE"
govulncheck ./...
```

## PyPI

| Source | Gives | For an agent | Page |
|---|---|---|---|
| PyPI JSON | metadata, releases, files with digests, `requires_python`, yanked | `https://pypi.org/pypi/{name}/json`, `/{name}/{version}/json` | ✅ |
| Integrity API | PEP 740 provenance per file | `https://pypi.org/integrity/{name}/{version}/{filename}/provenance` | — |
| pypistats | download counts, CI included | `https://pypistats.org/api/packages/{name}/recent` | ⚠️ |
| pip-audit | advisories for an environment or requirements | `pip-audit -r requirements.txt` | — |

```bash
curl -fsS "https://pypi.org/pypi/$PKG/$VERSION/json" | jq '.info | {name,version,license,requires_python,project_urls}'
# a wheel only, so nothing is built or run
pip download --no-deps --only-binary=:all: "$PKG==$VERSION" -d ./wheel
pip-audit -r requirements.txt
```

## Homebrew

| Source | Gives | For an agent | Page |
|---|---|---|---|
| formulae API | versions, source URLs, hashes, dependencies, license, deprecated or disabled, install analytics | `https://formulae.brew.sh/api/formula/{name}.json`, `/api/cask/{token}.json` | ✅ |
| brew | the same locally, and the formula's own install block | `brew info --json=v2`, `brew cat` | — |

Compare `install_on_request`, not total installs, which count dependencies.

```bash
curl -fsS "https://formulae.brew.sh/api/formula/$NAME.json" | jq '{name,license,deprecated,disabled,analytics}'
brew info --json=v2 "$NAME"
brew deps --tree "$NAME"
brew cat "$NAME"
```

## Actions

An action is build code holding the workflow's credentials: stricter than a
library, and C6, C8, C10 and C15 come first. A tag such as `@v4` is a name, not
an identity — pin the reviewed full commit SHA with the version as a comment.
On Forgejo, the `forgejo-workflows` rule says where actions come from.

| Source | Gives | For an agent |
|---|---|---|
| the action's repo | `action.yml`, entrypoint, bundled code, the commit behind a tag | `gh api repos/{owner}/{repo}/commits/{tag}`, `contents/action.yml?ref={sha}` |
| Scorecard | dangerous workflows, token permissions, pinned dependencies | the Scorecard API or CLI |
| Forgejo API | the same on a Forgejo host | `https://{host}/api/v1/repos/{owner}/{repo}/tags/{tag}` |

```bash
SHA=$(gh api "repos/$OWNER/$REPO/commits/$TAG" --jq .sha)
gh api "repos/$OWNER/$REPO/contents/action.yml?ref=$SHA" --jq .content | base64 -d
# uses: OWNER/REPO@<SHA> # <TAG>
```

## Container images

Select by digest, never by tag. Judge the update cadence, the distribution's
support window, the user it runs as, its entrypoint, the architectures, an SBOM
and provenance — a low vulnerability count alone does not make a better base.

| Source | Gives | For an agent |
|---|---|---|
| the registry | manifests, digests, platforms | `docker buildx imagetools inspect {image}:{tag}` |
| cosign | signatures and attestations | `cosign verify {image}@{digest} --certificate-identity=… --certificate-oidc-issuer=…` |
| syft, grype, trivy | SBOM, vulnerabilities, licenses | local CLIs |

```bash
docker buildx imagetools inspect "$IMAGE:$TAG"
syft "$IMAGE@$DIGEST"
trivy image "$IMAGE@$DIGEST"
```
