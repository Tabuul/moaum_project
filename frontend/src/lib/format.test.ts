import { test } from "node:test";
import assert from "node:assert/strict";

import { ageAt, day, isoDay, readDate } from "./format.ts";

const iso = (d: Date | null) => (d ? d.toISOString().slice(0, 10) : null);

test("V717: a date is read day first, as JAMB and the old portal write it — 12-09-2003 is 12 September 2003", () => {
  assert.equal(iso(readDate("12-09-2003")), "2003-09-12");
  assert.equal(iso(readDate("12/09/2003")), "2003-09-12");
  assert.equal(iso(readDate("12.09.2003")), "2003-09-12");
  assert.equal(iso(readDate("12 09 2003")), "2003-09-12");
  assert.equal(iso(readDate("12-09-03")), "2003-09-12");
  assert.equal(iso(readDate("31-08-75")), "1975-08-31");
  assert.equal(iso(readDate("2003-09-12")), "2003-09-12");
  assert.equal(iso(readDate("2003/9/12")), "2003-09-12");
  assert.equal(iso(readDate("2003-09-12T00:00:00Z")), "2003-09-12");
  assert.equal(iso(readDate("12 Sep 2003")), "2003-09-12");
  assert.equal(iso(readDate("12th September 2003")), "2003-09-12");
  assert.equal(iso(readDate("12-Sep-2003")), "2003-09-12");
  assert.equal(iso(readDate("September 12, 2003")), "2003-09-12");
  assert.equal(iso(readDate("Sep 12 2003")), "2003-09-12");
  assert.equal(iso(readDate("09-13-2003")), "2003-09-13", "month first only when the figures allow nothing else");
  assert.equal(iso(readDate("13-09-2003")), "2003-09-13");
  assert.equal(readDate("31-02-2003"), null, "no such day");
  assert.equal(readDate("last year"), null);
  assert.equal(readDate(""), null);
  assert.equal(readDate(null), null);
  assert.equal(readDate("Foo 12 2003"), null, "not a month");
});

test("V717: the formatters print the day JAMB meant", () => {
  assert.equal(day("12-09-2003"), new Date(Date.UTC(2003, 8, 12)).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" }));
  assert.notEqual(day("12-09-2003"), day("2003-12-09"), "never 9 December");
  assert.equal(day("2026-10-12"), "12 Oct 2026");
  assert.equal(day("2026-10-12", false), "12 Oct");
  assert.equal(day("not a date"), "not a date");
  assert.equal(day(null), "—");
  assert.equal(isoDay("12-09-2003"), "2003-09-12");
  assert.equal(isoDay("nothing"), "");
});

test("V717: the age counts full years from the day read day first", () => {
  const on = new Date(Date.UTC(2026, 10, 1));   // 1 November 2026
  assert.equal(ageAt("12-09-2003", on), 23, "12 September 2003 → 23 on 1 November 2026; read month first it would be 22");
  assert.equal(ageAt("2003-11-02", on), 22, "the birthday is tomorrow");
  assert.equal(ageAt("2003-11-01", on), 23, "the birthday is today");
  assert.equal(ageAt("1800-01-01", on), null, "absurd");
  assert.equal(ageAt("soon", on), null);
  assert.equal(ageAt(null, on), null);
});
