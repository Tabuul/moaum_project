import { test } from "node:test";
import assert from "node:assert/strict";
import { putmeOnDashboard, scoreOf, scoreReleased, utmeMeetsCutoff } from "./applicant-score.ts";
import type { ScreeningResult, ScreeningSlip } from "./applicant.ts";

const result = (r: Partial<ScreeningResult>): ScreeningResult => ({ utme: 240, utmeScaled: 60, screening: 68, screeningSource: "CBT", weightUtme: 70, weightPutme: 30,
  aggregate: 62.4, cutoff: 180, meritPosition: null, applied: null, places: null, ...r });
const slip = (published: boolean) => ({ published } as ScreeningSlip);

test("a released score is shown with what it is out of, the aggregate and the weighting", () => {
  assert.deepEqual(putmeOnDashboard({ result: result({}), scoreReleasedAt: "2026-10-01T10:00:00Z", screeningSlip: slip(true), decisionReleasedAt: null }),
    { kind: "RELEASED", score: 68, of: "of 100 · computer-based test", aggregate: 62.4, weights: "UTME 70% · Post-UTME 30%" });
  // screened from the O'Level results, with no examination batch: the release alone shows it
  const olevel = putmeOnDashboard({ result: result({ screeningSource: "OLEVEL", screening: 72 }), scoreReleasedAt: "2026-10-01T10:00:00Z", screeningSlip: null, decisionReleasedAt: null });
  assert.equal(olevel?.kind === "RELEASED" ? `${olevel.score} ${olevel.of}` : "", "72 of 100 · from your O’Level results");
});

test("a score not yet released is awaited, and a candidate admitted from the JAMB list hears nothing of one", () => {
  assert.deepEqual(putmeOnDashboard({ result: null, scoreReleasedAt: null, screeningSlip: slip(true), decisionReleasedAt: null }),
    { kind: "AWAITED", words: "Shown here once the Academic Office releases the scores" });
  assert.deepEqual(putmeOnDashboard({ result: null, scoreReleasedAt: null, screeningSlip: slip(false), decisionReleasedAt: null }), { kind: "AWAITED", words: "After your screening" });
  assert.equal(putmeOnDashboard({ result: null, scoreReleasedAt: null, screeningSlip: null, decisionReleasedAt: "2026-10-01T10:00:00Z" }), null);
  // a result is never read before the release, even if one came
  assert.equal(putmeOnDashboard({ result: result({}), scoreReleasedAt: null, screeningSlip: slip(true), decisionReleasedAt: null })?.kind, "AWAITED");
  assert.equal(scoreReleased({ result: null, scoreReleasedAt: "2026-10-01T10:00:00Z" }), false);
});

test("the cut-off is a UTME cut-off: read against the UTME score, never the aggregate", () => {
  assert.equal(utmeMeetsCutoff(result({ utme: 240, cutoff: 180, aggregate: 62.4 })), true);
  assert.equal(utmeMeetsCutoff(result({ utme: 170, cutoff: 180 })), false);
  assert.equal(utmeMeetsCutoff(result({ cutoff: null })), null);
  assert.equal(utmeMeetsCutoff(result({ utme: null })), null);
});

test("what a score is out of, by where it came from", () => {
  assert.equal(scoreOf("EXAM"), "of 100 · the Post-UTME examination");
  assert.equal(scoreOf("NONE"), "no screening component");
});
