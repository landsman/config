---
name: doubt-review
description: Load before a non-trivial claim of yours stands that no compiler or test will check — "this is safe", "this is idempotent", "this cannot race", "this is the root cause", "this migration is backwards compatible", "this scales" — and before an irreversible step built on such a claim. Also when I ask to doubt, cross-examine or get a second opinion on a decision. Carries handing a cold subagent the artifact and the contract but never the claim, the adversarial prompt, sorting its findings, and when to stop.
trigger-keywords: doubt*, pochybn*, zpochybn*, adversarial*, second opinion, druhý názor, fresh eyes, prověř to, cross-examin*
---

# Doubt review

**A confident claim gets a cold reviewer that tries to disprove it, before
anything is built on it.** A long session turns its own guesses into facts.
Re-reading them yourself does not help, because you read them with the same
context that produced them. Adapted from Addy Osmani's
[doubt-driven-development](https://github.com/addyosmani/agent-skills/blob/main/skills/doubt-driven-development/SKILL.md).

## When

When the claim is one nothing else will check and being wrong is expensive:

- an argument about concurrency, ordering, idempotency or an invariant;
- an auth, permission, tenant or money path;
- a migration on live data, a public API change, anything already shipped;
- a root-cause diagnosis that a fix is about to rest on;
- code in a system you do not know well.

Not for a rename, a format, a move, a plain instruction from me, or a
one-liner that is obviously right. **When a test can disprove the claim,
write the failing test instead.** A red test is the cheaper doubt.

## How

1. **Claim.** Write down in two lines what you believe and why it matters.
   Keep it to yourself.
2. **Extract.** Collect the artifact (the diff, the function, or the decision
   in five sentences) and the contract it must meet: the spec, my words, the
   invariants, the repo's conventions. Point at files by path. Leave your
   reasoning, your plan and the claim out. If the artifact is too big to
   read in one go, split it first.
3. **Doubt.** Spawn a fresh subagent: a typed agent, **never a fork**, since a
   fork inherits the context you are trying to get away from. Use the default
   model, or the top one when the claim is about concurrency or crosses
   systems, as the [subagents](../../rules/subagents.md) rule says. Prompt:

       Adversarial review. Find what is wrong with this artifact against the
       contract. Assume the author is overconfident. Look for unstated
       assumptions, unhandled edge cases, hidden shared state, ways to break
       the contract, conventions it breaks, failure under unexpected input.
       Do not validate and do not summarise. List the issues, each with the
       input or state that triggers it, or say you found none after a
       thorough look.

       ARTIFACT: <paths or text>
       CONTRACT: <what it must satisfy>

4. **Reconcile.** Read the artifact again against each finding and sort it
   into the first class that fits:
   - **contract misread**: your contract was unclear. Fix the contract.
   - **actionable**: a real issue. Change the artifact.
   - **trade-off**: real, but fixing it costs more than it is worth. Say so to me.
   - **noise**: correct given context the reviewer lacked. Ask whether the
     contract should have carried that context.

   The reviewer's word is not a verdict. Deferring to it is the same failure
   as ignoring it.
5. **Stop** when a round brings only trivial or already-known findings, or
   after three rounds. Then hand it to me rather than grind a fourth. Do not
   re-run an unchanged artifact, which only repeats the findings. Watch for
   **doubt theater**: two rounds of substantive findings with none sorted as
   actionable means you are defending, not doubting.

## Report

One line in the answer: what was doubted, what changed, and which trade-off
stays. Leave the reviewer's transcript out.

A different model as a second reviewer only when I ask for one; do not offer
it every round. A finished diff goes to `/code-review`. This skill is for a
decision still in flight.
