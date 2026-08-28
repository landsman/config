# BAT1 reports charge it does not have

| Field | Value |
|---|---|
| Status | **Confirmed — the pack is dead.** Delivered 3 % of what it reported, measured 2026-08-28. Warranty claim, not a repair |
| Affects | BAT1 only. Avacom `NOLE-T48H-806`, Li-Ion 10.8 V 5200 mAh (56.2 Wh), roughly a year old at 76 cycles — owner's recollection, invoice not checked, and well inside the 24-month warranty either way |
| Reports itself as | `SANYO` / `01AV425` — the original Lenovo part, because replacement packs clone the gauge firmware to satisfy the EC |
| First measured | 2026-08-27 |
| Symptom it was reported as | "the laptop drains overnight in suspend" |

Both packs in this machine are Avacom replacements. BAT0 (24 Wh Li-Pol) is
healthy on every measurement below, so this is one bad unit rather than
anything to conclude about the supplier.

## Symptom

The machine is left suspended overnight and is nearly flat in the morning,
having apparently spent ~38 Wh. Suspend was the obvious suspect. Suspend turned
out to have nothing to do with it.

## What suspend actually costs

Measured by a `systemd-sleep` hook sampling `energy_now` at `pre` and `post`,
which is the only place the boundary is clean — reading it by hand minutes
after waking charges idle-awake draw to the suspend, and awake on this machine
is 12.7 W against a suspend's fraction of a watt.

| suspended at | hours | Wh | W |
|---|---|---|---|
| 2026-08-27 16:12 | 5.98 | 2.35 | **0.39** |
| 2026-08-27 22:25 | 9.17 | 3.55 | **0.39** |

Two runs, different lengths, same rate to two decimals. **0.39 W is healthy S3**
for a T480 — nothing is staying powered, and no configuration was changed
between the runs or before them.

## What the gauge claims instead

The overnight run that started this, read by hand:

| | reported |
|---|---|
| 2026-08-26 20:36 → 08-27 11:10 | 14.57 h suspended, one cycle |
| BAT1 | 37.40 → 3.24 Wh |
| BAT0 | 17.68 → 13.66 Wh |
| total | 38.18 Wh, i.e. 2.62 W |

At the measured 0.39 W, 14.57 h costs **5.68 Wh**. BAT0 supplied 4.02 Wh of
that — the T480 power bridge only draws on the internal pack once the external
one is exhausted — which leaves **BAT1 holding about 1.7 Wh at the moment it
reported 37.40 Wh**. The arithmetic closes to within measurement noise, and it
closes only if the gauge is wrong by a factor of roughly twenty near the bottom
of its range.

## Caught in the act

The above is arithmetic. On 2026-08-28 the same collapse was recorded live,
sampling `power_now`, `energy_now` and `voltage_now` every 30 s through a
discharge, with the machine in performance mode to reach the cliff in minutes
rather than hours:

```
epoch        W       energy_now   voltage
1787901885   15.964  33.710 Wh    9.271 V
1787901915   16.589   3.510 Wh    9.273 V   <-- one 30-second sample
```

**30.2 Wh written off in thirty seconds, during which 0.14 Wh was actually
consumed.** The voltage does not move across the step — 9.271 → 9.273 V — so
no energy went anywhere. The estimate simply met the pack's real state of
charge and snapped to it.

Integrated over the whole run, from the gauge reading 34.14 Wh (58 %) to the
power bridge handing over to BAT0:

| | |
|---|---|
| claimed at start | 34.14 Wh |
| **actually delivered** | **0.87 Wh — 3 %** |
| still claimed at handover | 3.29 Wh, which it never delivered either |

`upower` predicted 2.9 hours to empty at the start of that run. It lasted six
minutes.

## It inflates on the way up, which is where the fiction comes from

The discharge above showed the gauge's *rate* to be right and only its
*remaining total* wrong — 33.85 → 33.71 Wh in 30 s at 16 W is accurate to a
tenth of a watt. That is a gauge worth calibrating.

Charging is the broken half. Integrating `power_now` while the pack refills:

| | |
|---|---|
| accepted, measured | 8.19 Wh over 17 min |
| gauge claimed over the same 17 min | +21.19 Wh (5.34 → 26.53 Wh, 9 → 44 %) |
| **inflation** | **2.59×, steady from the first sample** |

Seventy watts into the pack is not physically available — the T480 ships a
65 W supply and the system is running off the same one. The charger is not
lying; the gauge is.

The likely mechanism is in the voltage column: 10.159 → 10.867 V as it fills,
the steep early rise of a depleted pack. A gauge that has fallen back to
estimating charge from voltage, rather than counting coulombs, climbs exactly
like this — and voltage-based estimation is at its worst under charge current.

**This is what makes calibration futile, and it is worth being precise about
why.** A calibration cycle relearns capacity by measuring one full charge and
discharge *with the pack's own counter*. Here that counter is accurate
discharging and 2.6× optimistic charging, so the cycle would relearn from the
broken half and arrive at another fiction. Calibration fixes a drifted
estimate. It cannot fix a broken measurement.

### Prediction, written before the run finished

From 5.34 Wh claimed, reaching a claimed "full" of ~60 Wh means adding 54.7 Wh
of *claimed* charge. At 2.6× that is **~21 Wh actually accepted**, in **45-50
minutes** at the observed 26-29 W. If it lands there, the pack takes 21 Wh of
its advertised 56.2 — 37 % — and no reset makes 21 Wh into 60.

## The 80 % that was not a threshold

Both packs appeared to stop charging at 80 %, and that was read as a
conservation limit. It was not: `charge_control_end_threshold` reads 100 for
both, TLP is not installed, and KDE sets nothing. One more number from this
gauge that meant nothing.

## The voltage, read against the right pack

An earlier draft made this argument against `voltage_min_design` = 11.1 V and
called the pack "below its own minimum". That floor is the *original's*, copied
in with the cloned firmware. The real cells are Avacom's 10.8 V nominal — a 3S
Li-Ion pack whose cutoff is around 9.0 V, i.e. 3.0 V/cell.

```
BAT1  voltage_now 9.27 V   -> 3.09 V/cell against a 3.0 V floor   capacity said 58 %
BAT0  voltage_now 11.68 V  -> comfortably above its own floor      capacity said 79 %
```

Measured against the pack it actually is, BAT1 was **empty** at the moment it
reported 58 %. The conclusion survives the correction; the earlier framing was
sloppier than it needed to be.

`energy_full` is **not** evidence here, and an earlier draft of this file
wrongly said it was:

| | `energy_full` | `energy_full_design` | ratio |
|---|---|---|---|
| BAT0 | 22.23 Wh | 22.80 Wh | 97.5 % |
| BAT1 | 60.17 Wh | 57.72 Wh | 104.2 % |

Reading above the design rating looks damning until you know the pack's age.
Both of these are a few months old, and a fresh cell routinely beats a
conservative factory number — so 104.2 % is unremarkable on its own. The
voltage above is what carries the finding. Recorded because the wrong version
was written first, from the machine's age rather than the battery's.

What the ratio does mean is that `energy_full` cannot be used to *rule the
pack out* either. It is a gauge's own estimate of itself.

## Consequences

- The battery indicator cannot be trusted on this machine. It will read
  comfortable numbers and then the machine will die, because BAT1's share of
  the total is largely fictional.
- Any power measurement that crosses BAT1's near-empty region is worthless —
  the gauge dumps its accumulated error there and it books as consumption.
  Measure in the upper part of the range, as the two runs above did.

## Next

A calibration cycle was the first plan and is dropped twice over. It cannot put
cells back that are not there, and — see the charge measurement above — it would
have to learn from a counter that is 2.6× wrong in the direction it learns from.
What is left is the warranty claim, and that wants one more number.

1. **Full-capacity measurement, for Avacom.** Charge BAT1 to 100 %, then
   discharge to cutoff integrating `power_now`. That yields delivered
   watt-hours against the **56.2 Wh advertised**, which is the comparison a
   claim rests on — not against the 57.72 Wh the cloned firmware reports, which
   is somebody else's spec. Both packs already permit it:
   `charge_control_end_threshold` reads 100 for BAT0 and BAT1, though something
   in userspace has been stopping them at 80 % and that needs finding first.
2. **Claim it.** Bought new a few months ago at 76 cycles, from a supplier
   giving 24 months. A pack returning 3 % of its indicated charge is not wear.
3. Re-measure suspend once a replacement is in. **0.39 W** is the number to
   reproduce, and it is the one figure here that was never in doubt.

## Dead ends

Recorded with what killed them, so they are not chased again.

- **s2idle** — the premise the investigation started from: that the machine was
  suspending to idle rather than S3 and burning power in a shallow C-state. It
  never was. 241 of 243 logged suspends entered `deep`, on boots whose cmdline
  carried no `mem_sleep_default` at all. See
  [`system/etc/default/grub.d/99-mem-sleep-deep.cfg`](../../system/etc/default/grub.d/99-mem-sleep-deep.cfg),
  which is kept as a pin, not as a fix.
- **Thunderbolt left powered** — the whole Alpine Ridge tree (`04:00.0`,
  `05:00.x`, `06:00.0`, `3c:00.0`) sits in D0 with `power/control=on` and
  nothing plugged in, and its USB half throws `xhci_hcd 0000:3c:00.0: xHC error
  in resume` on wake. A good suspect until suspend was measured at 0.39 W,
  which leaves it nothing to explain. `control=on` is stock Ubuntu behaviour
  and the resume error is a wake-path symptom, not sleep consumption. Not
  touched, deliberately — changing it before the measurement would have meant
  never learning which variable mattered.
- **Wake-on-WLAN, wake-on-LAN, a device left on USB** — WoWLAN is disabled,
  nothing external was attached, and the night was a single suspend cycle with
  no spurious wakeups.
