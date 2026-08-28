# BAT1 reports charge it does not have

| Field | Value |
|---|---|
| Status | Open — pack suspect, calibration cycle not yet attempted |
| Affects | BAT1 only (SANYO 01AV425, external/hot-swap pack, 76 cycles) |
| First measured | 2026-08-27 |
| Symptom it was reported as | "the laptop drains overnight in suspend" |

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

## The independent confirmation

Nothing above depends on the gauge being trusted; this does not either.

```
BAT1  voltage_now 9.875 V   voltage_min_design 11.100 V   capacity 62 %   76 cycles
BAT0  voltage_now 11.682 V  voltage_min_design 11.400 V   capacity 79 %   41 cycles
```

BAT1 sits **below its own minimum design voltage** while claiming 62 % charge.
For a 3S pack that is 3.29 V per cell — somewhere near 15 %, not 62 %. BAT0, on
the same machine at the same moment, is comfortably above its floor.

The other tell is in the capacity estimate itself:

| | `energy_full` | `energy_full_design` | ratio |
|---|---|---|---|
| BAT0 | 22.23 Wh | 22.80 Wh | 97.5 % |
| BAT1 | 60.17 Wh | 57.72 Wh | **104.2 %** |

A five-year-old pack at 76 cycles does not hold 104 % of its factory capacity.
That figure is what a gauge reports when it has never completed a learning
cycle and its estimate has drifted upward — and every percentage the desktop
shows is derived from it.

## Consequences

- The battery indicator cannot be trusted on this machine. It will read
  comfortable numbers and then the machine will die, because BAT1's share of
  the total is largely fictional.
- Any power measurement that crosses BAT1's near-empty region is worthless —
  the gauge dumps its accumulated error there and it books as consumption.
  Measure in the upper part of the range, as the two runs above did.

## Next

1. **Calibration cycle.** Charge to 100 % — which means lifting the 80 % stop
   threshold this machine normally runs — then discharge to cutoff and charge
   to 100 % again, so the gauge relearns `energy_full`. This is the cheap
   remedy and it is not yet tried.
2. If `energy_full` still reads above design afterwards, or the voltage is
   still below the floor at a claimed 60 %, the pack is done and wants
   replacing. It is the external one, so this is a purchase, not a teardown.
3. Re-measure suspend afterwards either way. 0.39 W is the number to reproduce.

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
