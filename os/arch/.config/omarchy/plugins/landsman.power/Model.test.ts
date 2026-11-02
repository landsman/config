import { describe, expect, test } from "bun:test";
import { packDetail, packFraction, parsePacks } from "./Model.js";

describe("parsePacks", () => {
  test("reads every pack line and ignores the totals around them", () => {
    const raw = "percentage\t16%\npack\tBAT0\t46\t10.2\t22.2\t11.9\tDischarging\t44\npack\tBAT1\t5\t3.1\t57.4\t0.0\tNot charging\t83\nsize\t79Wh\n";

    expect(parsePacks(raw).map((p) => [p.name, p.percent])).toEqual([["BAT0", 46], ["BAT1", 5]]);
  });

  test("keeps an unreported charge apart from an empty battery", () => {
    const [unknown, empty] = parsePacks("pack\tBAT0\t\t\t\t\tUnknown\t\npack\tBAT1\t0\t0.0\t57.4\t0.0\tDischarging\t\n");

    expect(unknown.percent).toBe(-1);
    expect(empty.percent).toBe(0);
  });
});

describe("packDetail", () => {
  test("leaves out a draw of zero and what the firmware did not report", () => {
    expect(packDetail({ energy: "3.1", full: "57.4", watts: "0.0", status: "Not charging", cycles: "" })).toBe("3.1 / 57.4 Wh · Not charging");
  });
});

describe("packFraction", () => {
  test("clamps a gauge reading over 100 %", () => {
    expect(packFraction({ percent: 104 })).toBe(1);
  });
});
