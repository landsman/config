# Skills

One folder per skill, flat: Codex and Claude Code look exactly one level deep
for `<folder>/SKILL.md`, so a skill in a subfolder never loads. The folder's
prefix is its area and sorts a listing; this index adds what each one is for.
A row's text is the skill's `name:`, which is its `/command`. `make
skills-index-test` fails when a skill has no row.

## UI and UX

| Skill | For |
|-------|-----|
| [calm-ui](ui-calm/SKILL.md) | what a UI does around an action: one loading state, no toasts, Enter submits |
| [modal-dialogs](ui-modal-dialogs/SKILL.md) | the one modal design every project shares |
| [optical-centre](ui-optical-centre/SKILL.md) | a lone block in a large empty area, placed above the middle |
| [mobile-first](ui-mobile-first/SKILL.md) | layout with the phone as the base case |
| [react](ui-react/SKILL.md) | where the logic of a component goes, and its tests |

## Backend and data

| Skill | For |
|-------|-----|
| [spring-boot](be-spring-boot/SKILL.md) | Boot 3 against Boot 4, transactions, error handling |
| [orm](be-orm/SKILL.md) | Hibernate, JPA and Doctrine: N+1, fetch plans, batches |
| [postgres](be-postgres/SKILL.md) | tables, indexes, upserts, contended writes, live migrations |
| [liquibase](be-liquibase/SKILL.md) | changelogs and what makes a changeset immutable |
| [caching](be-caching/SKILL.md) | when a cache is justified, keys, invalidation |
| [kotlin-enums](be-kotlin-enums/SKILL.md) | an enum's own file or nested, one constant per line, an exhaustive `when` |

## Testing

| Skill | For |
|-------|-----|
| [e2e-tests](test-e2e/SKILL.md) | browser end-to-end suites and the CI job that runs them |

## Review

| Skill | For |
|-------|-----|
| [doubt-review](review-doubt/SKILL.md) | a cold subagent tries to disprove a claim before anything rests on it |

## Git, forges and CI

| Skill | For |
|-------|-----|
| [commit-messages](git-commit-messages/SKILL.md) | commit subjects and PR titles |
| [forgejo](git-forgejo/SKILL.md) | anything on git.insuit.cz |
| [forgejo-workflows](git-forgejo-workflows/SKILL.md) | writing or porting a Forgejo Actions workflow |

## Dependencies and research

| Skill | For |
|-------|-----|
| [dependencies](research-dependencies/SKILL.md) | choosing a new dependency, checking its vulnerabilities |
| [perplexity-research](research-perplexity/SKILL.md) | a deep-research prompt, and taking its answer back |
| [brain](research-brain/SKILL.md) | reading from and writing to the long-term notes |

## Writing

| Skill | For |
|-------|-----|
| [terse-prose](write-terse-prose/SKILL.md) | comments, PR bodies, error messages cut to their core |
| [bro](write-bro/SKILL.md) | the last answer again, in plain language |

## Not a skill

`mcp-servers/` is a Claude Code plugin (`.claude-plugin/`, `.mcp.json`) that
sits here; no loader reads it as a skill.
