# BAT1 reports charge it does not have

| Field | Value |
|---|---|
| Status | **Resolved by configuration.** The cells are fine — 55.86 Wh delivered, 99.4 % of the pack's rating. The gauge saturates at 99 % long before the pack is full, so a charge threshold below 100 % stops charging early. Keep the threshold at 100 % |
| Affects | BAT1 only. Avacom `NOLE-T48H-806`, Li-Ion 10.8 V 5200 mAh (56.2 Wh), roughly a year old at 76 cycles — owner's recollection, invoice not checked, and well inside the 24-month warranty either way |
| Reports itself as | `SANYO` / `01AV425` — the original Lenovo part, because replacement packs clone the gauge firmware to satisfy the EC |
| Workaround in place | `charge_control_end_threshold` = 100 on both packs |
| First measured | 2026-08-27 |
| Symptom it was reported as | "the laptop drains overnight in suspend" |

Both packs in this machine are Avacom replacements. BAT0 (24 Wh Li-Pol) is
healthy on every measurement below, so this is one bad unit rather than
anything to conclude about the supplier.

## What actually happens

1. Early in a charge the gauge credits itself roughly **2.6 Wh for every 1 Wh**
   the pack accepts, then **saturates at 99 %** and stops counting entirely
   while the pack goes on filling.
2. So it passes any stop threshold below 100 % while the pack holds a fraction
   of that — 80 %, as this machine was configured.
3. Charging stops there, because the EC believes the gauge.
4. The machine is unplugged holding far less than it is told, and dies quickly.

**The laptop was never draining overnight. It was never charging.** That is the
whole case, and it took four wrong theories to get to.

The cells themselves are sound: charged to genuinely full they return 55.86 Wh,
99.4 % of the pack's rating. See [the round trip](#the-round-trip-which-settles-it).

## What suspend costs, since that was the original suspect

Measured by a `systemd-sleep` hook sampling `energy_now` at `pre` and `post`,
which is the only place the boundary is clean — reading it by hand minutes
after waking charges idle-awake draw to the suspend, and awake on this machine
is 12.7 W against a suspend's fraction of a watt.

| suspended at | hours | Wh | W |
|---|---|---|---|
| 2026-08-27 16:12 | 5.98 | 2.35 | **0.39** |
| 2026-08-27 22:25 | 9.17 | 3.55 | **0.39** |

Two runs, different lengths, same rate to two decimals. **0.39 W is healthy S3**
for a T480, and it is the one number here that was never in doubt.

## The charge measurement, which found the fault

Integrating `power_now` from 9 % to the end of charge, with the threshold
raised to 100 %:

| | |
|---|---|
| **accepted, measured** | **57.70 Wh over 157 min** |
| of the advertised 56.2 Wh | 102.7 % |
| gauge read | 5.34 → 59.86 Wh (9 → 99 %) |

It splits in two, and the split is the finding:

| phase | accepted | what the gauge did |
|---|---|---|
| while it was still climbing | 20.51 Wh | 5.34 → 59.49 Wh, i.e. **2.64× inflation** |
| after it hit its ceiling | 37.19 Wh | frozen at 99 % for 61 minutes |

Note the totals: over the whole charge the gauge credited itself 54.52 Wh
against 57.70 actually accepted — *under* the truth by 6 %. The 2.64× inflation
is real but early; the saturation that follows more than cancels it. Which is
why the net capacity estimate looks almost sane and the fault hides.

70 W into the pack is not physically available — the T480 ships a 65 W supply
and the system runs off the same one. The charger is not lying; the gauge is.

The mechanism is visible in the voltage: 10.159 → 10.867 V while filling, the
steep early rise of a depleted pack. A gauge estimating charge from *voltage*
rather than counting coulombs climbs exactly like that, and voltage-based
estimation is at its worst under charge current. Note also that the pack kept
accepting 37.19 Wh — nearly two thirds of the total — while the gauge insisted
it was at 99 %. The cells were nowhere near full when the reading said so.

## Discharging, the same gauge counts correctly

Which is what made the fault hard to see. Sampling every 30 s through a
discharge, its *rate* is right to a tenth of a watt — 33.85 → 33.71 Wh in 30 s
at 16 W. Only its absolute total is fiction, and when reality catches up it
snaps:

```
epoch        W       energy_now   voltage
1787901885   15.964  33.710 Wh    9.271 V
1787901915   16.589   3.510 Wh    9.273 V   <-- one 30-second sample
```

**30.2 Wh written off in thirty seconds, during which 0.14 Wh was consumed.**
The voltage does not move across the step — 9.271 → 9.273 V — so no energy went
anywhere. `upower` had predicted 2.9 hours to empty at the start of that run;
it lasted six minutes.

At the cutoff the pack was genuinely empty: 9.27 V on a 10.8 V nominal 3S pack
is 3.09 V/cell against a 3.0 V floor. It reported 58 % at that moment.

## The overnight arithmetic, which now closes properly

| | reported |
|---|---|
| 2026-08-26 20:36 → 08-27 11:10 | 14.57 h suspended, one cycle |
| BAT1 | 37.40 → 3.24 Wh |
| BAT0 | 17.68 → 13.66 Wh |
| total | 38.18 Wh, i.e. 2.62 W |

At the measured 0.39 W, 14.57 h costs **5.68 Wh**. BAT0 supplied 4.02 Wh of
that — the power bridge only reaches the internal pack once the external one is
exhausted — leaving BAT1 with about 1.7 Wh at the moment it reported 37.40 Wh.
It had been "charged to 80 %" the previous evening and was very nearly empty.

## Four wrong theories, and what killed each

Kept in full. The order they died in is the useful part, because three of them
looked solid at the time.

1. **s2idle.** The premise the whole investigation started from: the machine
   was suspending to idle rather than S3 and burning power in a shallow
   C-state. It never was — 241 of 243 logged suspends entered `deep`, on boots
   whose cmdline carried no `mem_sleep_default` at all. See
   [`system/etc/default/grub.d/99-mem-sleep-deep.cfg`](../../system/etc/default/grub.d/99-mem-sleep-deep.cfg),
   kept as a pin, not as a fix.
2. **Thunderbolt left powered.** The whole Alpine Ridge tree (`04:00.0`,
   `05:00.x`, `06:00.0`, `3c:00.0`) sits in D0 with `power/control=on` and
   nothing plugged in, and its USB half throws `xhci_hcd 0000:3c:00.0: xHC
   error in resume` on wake. A good suspect until suspend measured 0.39 W,
   which leaves it nothing to explain. Deliberately not touched first —
   changing it before measuring would have meant never learning which variable
   mattered.
3. **A worn-out pack.** Written into this file as *"Confirmed — the pack is
   dead"* on the strength of it delivering 0.87 Wh against a claimed 34.14.
   That measured the gauge's error at one instant, **not the pack's capacity** —
   the cells really were empty then. The capacity test is full-to-empty, which
   this file had already named as the necessary step before jumping past it.
   The pack went on to accept 57.70 Wh and return 55.86. Retracted.
4. **A drifted gauge, fixable by calibration.** Plausible while only the
   discharge side had been measured, since discharging it counts correctly.
   Wrong for a duller reason than the one first given here: `energy_full` reads
   60.17 Wh against 55.86 actually delivered, which is 8 % optimistic — there
   was never much drift to relearn. Calibration corrects a capacity estimate.
   The fault is *when the gauge declares itself full*, and no amount of
   relearning changes that.

Two smaller ones:

- **`energy_full` above design.** BAT1 reads 60.17 Wh against a 57.72 Wh
  design, 104.2 %, and that was called evidence of a drifted gauge. On a pack
  this young it is unremarkable — a fresh cell routinely beats a conservative
  factory rating. It is a gauge's own estimate of itself and proves nothing in
  either direction.
- **The 80 % stop.** Read as a conservation threshold someone had configured.
  `charge_control_end_threshold` reads 100, TLP is not installed, KDE sets
  nothing. It was the gauge's fiction reaching 80 %, which turned out to be the
  fault itself rather than a red herring.

## Consequences

- **Charge to 100 %, not 80 %.** With the threshold raised the pack takes
  57.70 Wh instead of stopping at a fictional fraction. This is a workaround
  for a broken gauge, not battery care — the usual reason to stop at 80 % does
  not apply when 80 % is not 80 %.
- The battery indicator cannot be trusted on this machine at all. It reads
  comfortable numbers, freezes at 99 % while genuinely filling, and collapses
  without warning on the way down.
- **The desktop grades the faulty pack higher than the good one.** KDE's
  battery widget shows *Battery Health 100 %* for BAT1 and *98 %* for BAT0.
  That figure is `energy_full / energy_full_design`, so it asks the gauge to
  report on itself: BAT1's 60.17 / 57.72 is 104 %, clipped to 100. The healthy
  pack, whose gauge is honest about a little wear, looks worse. Any health
  reading derived this way inverts exactly when it is most needed.
- Any power measurement crossing BAT1's near-empty region is worthless — the
  gauge dumps its accumulated error there and it books as consumption. Measure
  in the upper part of the range, as the two suspend runs did.

## The round trip, which settles it

Charged to genuinely full, then run flat. The `power_now` logger died an hour
in, so the discharge is reconstructed from `/var/lib/upower/history-rate-*`,
integrated the same way — and the hour that *was* logged agrees with the
gauge's own reading to 4 %, which is the cross-check that makes the
reconstruction usable.

| | |
|---|---|
| BAT1, 12:26 → 17:43 | 98 % → 21 %, **delivered 55.86 Wh** |
| BAT0, 17:43 → 19:14 | 99 % → 4 %, delivered 19.79 Wh |

| BAT1 | |
|---|---|
| accepted charging | 57.70 Wh |
| **delivered** | **55.86 Wh** |
| round-trip efficiency | 96.8 % |
| **against the 56.2 Wh rating** | **99.4 %** |

**The cells are fine.** The pack returns essentially its full rated capacity
and ran the machine for five and a quarter hours before handing over.

The fault is narrower than any of the four theories: the gauge **saturates at
99 % long before the pack is full**. Today it sat there for 54 minutes while
26.76 Wh — nearly half the pack — went in. Set a stop threshold below 100 % and
charging ends at whatever fraction the gauge has already claimed.

## Resolution

**Keep `charge_control_end_threshold` at 100 on BAT1.** That is the whole fix.
The usual argument for stopping at 80 % to spare the cells cannot apply here,
because 80 % on this gauge is not 80 % of anything.

One defect remains and is not worth a claim, only awareness: at the handover
the gauge read **21 %** on an empty pack. The last quarter of the indicator is
fiction. It is a smaller error than the 30 Wh seen earlier only because a full
charge leaves less of it accumulated.

Not raised with Avacom. A pack that delivers 99.4 % of its rating is not a
capacity fault, and the gauge behaviour is invisible to anyone charging to
100 % — which is the default.

## Still to do

Re-measure suspend, now that the pack behind every earlier number is
understood. **0.39 W** is the figure to reproduce, and it is the one that was
never in doubt.
