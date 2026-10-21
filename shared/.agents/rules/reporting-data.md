# Reporting data and metrics

A number from a query or a benchmark is a claim, and the method is what makes it
true. Before reporting one, check that the method could not have produced it
spuriously — then say what was measured and how, so it can be challenged instead
of believed.

The recurring ways a confident number turns out wrong:

- **A filter that was never applied.** Rows that look like content but are
  redirects, pointers, soft-deleted, or another type entirely. Group by the
  discriminating column once before trusting a count.
- **A benchmark on unrepresentative input.** Repeated or cached inputs, a warm
  path, a single hot key — that measures the ceiling of the sample, not of the
  system.
- **An aggregate that hides its shape.** A mean over a bimodal set, a rate
  averaged across a ramp-up, a total that double-counts.
- **A reading from the wrong side.** Confirming the component already suspected
  while the constraint sits elsewhere. Check the system's own instrumentation
  before the host's.

When a number decides something, take a second reading that could disagree: a
different query shape, a different tool, or a spot-check of individual rows. Two
methods agreeing is evidence; one method repeated is not.

What the difference looks like in practice — same finding, reported twice:

    "1 800 records are missing content."
    "1 800 records have no content — but that count includes redirects and
     tombstones. Filtered to rows that should carry a body: 40."

    "The service tops out at 400 requests/s."
    "The service tops out at 400 requests/s, measured by replaying the same
     three URLs — so that is the cache ceiling, not the service's."

The second version of each is barely longer, and it is the one that gets
corrected in a minute instead of quietly steering the next day's work.

## An optimisation is kept only when its number moved

A change made for speed is a hypothesis until it is measured again the way the
baseline was: same command, same input, same warm or cold state.

- **Neutral is a revert.** A gain inside the run-to-run spread is a different
  sample, not a win, and the code it added is maintained forever for nothing.
- **One change per measurement.** Three fixes landed together give one number
  nobody can attribute.
- **Correctness gates the metric.** A win that needed a test changed, skipped or
  deleted is a regression.
- **The reverted attempts go into the PR body** — idea, before → after, why it
  went. Git keeps no trace of them, so otherwise the same dead idea gets tried
  again.
