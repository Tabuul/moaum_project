import { test } from "node:test";
import assert from "node:assert/strict";
import { putmeOnDashboard, scoreOf, scoreReleased, utmeMeetsCutoff } from "./applicant-score.ts";
import type { ScreeningResult, ScreeningSlip } from "./applicant.ts";

const result = (r: Partial<ScreeningResult>): ScreeningResult => ({ utme: 240, utmeScaled: 60, screening: 68, screeningSource: "CBT", weightUtme: 70, weightPutme: 30,
  aggregate: 62.4, cutoff: 180, meritPosition: null, applied: null, places: null, ...r });
const slip = (published: boolean) => ({ published } as ScreeningSlip);
const AT = "2026-10-01T10:00:00Z";

test("a released score is shown with what it is out of, the aggregate and the weighting — before the decision and after it", () => {
  assert.deepEqual(putmeOnDashboard({ result: result({}), scoreReleasedAt: AT, screeningSlip: slip(true), decisionReleasedAt: null, decision: null }),
    { kind: "RELEASED", score: 68, of: "of 100 · computer-based test", aggregate: 62.4, weights: "UTME 70% · Post-UTME 30%" });
  const exam = putmeOnDashboard({ result: result({ screeningSource: "EXAM", screening: 54 }), scoreReleasedAt: AT, screeningSlip: slip(true), decisionReleasedAt: AT, decision: "NOT_OFFERED" });
  assert.equal(exam?.kind === "RELEASED" ? `${exam.score} ${exam.of}` : "", "54 of 100 · the Post-UTME examination");
  assert.equal(putmeOnDashboard({ result: result({}), scoreReleasedAt: AT, screeningSlip: slip(true), decisionReleasedAt: AT, decision: "OFFERED" })?.kind, "RELEASED");
});

test("the decision read with no result given says nothing of a score: screened without the examination, or none released", () => {
  // the API gives no result for an aggregate computed from the O'Level result, and none before the release
  assert.equal(putmeOnDashboard({ result: null, scoreReleasedAt: null, screeningSlip: null, decisionReleasedAt: AT, decision: "NOT_OFFERED" }), null);
  assert.equal(putmeOnDashboard({ result: null, scoreReleasedAt: null, screeningSlip: slip(true), decisionReleasedAt: AT, decision: "WAITING" }), null);
  assert.equal(putmeOnDashboard({ result: null, scoreReleasedAt: null, screeningSlip: null, decisionReleasedAt: AT, decision: "OFFERED" }), null);
  // a result that somehow came without its release is never read
  assert.equal(putmeOnDashboard({ result: result({}), scoreReleasedAt: null, screeningSlip: slip(true), decisionReleasedAt: AT, decision: "NOT_OFFERED" }), null);
  assert.equal(scoreReleased({ result: null, scoreReleasedAt: AT }), false);
  assert.equal(scoreReleased({ result: result({}), scoreReleasedAt: null }), false);
});

test("before the release the score is awaited, and a candidate admitted from the JAMB list hears nothing of one", () => {
  assert.deepEqual(putmeOnDashboard({ result: null, scoreReleasedAt: null, screeningSlip: slip(true), decisionReleasedAt: null, decision: null }),
    { kind: "AWAITED", words: "Shown here once the Academic Office releases the scores" });
  assert.deepEqual(putmeOnDashboard({ result: null, scoreReleasedAt: null, screeningSlip: slip(false), decisionReleasedAt: null, decision: null }), { kind: "AWAITED", words: "After your screening" });
  assert.equal(putmeOnDashboard({ result: null, scoreReleasedAt: null, screeningSlip: null, decisionReleasedAt: AT, decision: null }), null);
  // a result is never read before the release, even if one came
  assert.equal(putmeOnDashboard({ result: result({}), scoreReleasedAt: null, screeningSlip: slip(true), decisionReleasedAt: null, decision: null })?.kind, "AWAITED");
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
