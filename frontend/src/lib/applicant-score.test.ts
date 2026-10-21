import { test } from "node:test";
import assert from "node:assert/strict";
import { putmeOnDashboard, scoreOf, scoreReleased, screeningResultOpen, utmeMeetsCutoff } from "./applicant-score.ts";
import type { ScreeningResult } from "./applicant.ts";

const result = (r: Partial<ScreeningResult>): ScreeningResult => ({ utme: 240, utmeScaled: 60, screening: 68, screeningSource: "CBT", weightUtme: 70, weightPutme: 30,
  aggregate: 62.4, cutoff: 180, meritPosition: null, applied: null, places: null, ...r });
const AT = "2026-10-01T10:00:00Z";

test("with the decision read, a released score is shown with what it is out of, the aggregate and the weighting", () => {
  assert.deepEqual(putmeOnDashboard({ result: result({}), scoreReleasedAt: AT, decision: "OFFERED" }),
    { score: 68, of: "of 100 · computer-based test", aggregate: 62.4, weights: "UTME 70% · Post-UTME 30%" });
  const exam = putmeOnDashboard({ result: result({ screeningSource: "EXAM", screening: 54 }), scoreReleasedAt: AT, decision: "NOT_OFFERED" });
  assert.equal(exam ? `${exam.score} ${exam.of}` : "", "54 of 100 · the Post-UTME examination");
  assert.notEqual(putmeOnDashboard({ result: result({}), scoreReleasedAt: AT, decision: "WAITING" }), null);
});

test("before the admission is decided nothing is said of a score, released or not (V617)", () => {
  // the API gives no result before a decision the applicant may read; a result that somehow came is not read either
  assert.equal(putmeOnDashboard({ result: result({}), scoreReleasedAt: AT, decision: null }), null);
  assert.equal(putmeOnDashboard({ result: null, scoreReleasedAt: null, decision: null }), null);
});

test("the decision read with no result given says nothing of a score: screened without the examination, or none released", () => {
  // the API gives no result for an aggregate computed from the O'Level result, and none before the release
  assert.equal(putmeOnDashboard({ result: null, scoreReleasedAt: null, decision: "NOT_OFFERED" }), null);
  assert.equal(putmeOnDashboard({ result: null, scoreReleasedAt: null, decision: "OFFERED" }), null);
  // a result that somehow came without its release is never read
  assert.equal(putmeOnDashboard({ result: result({}), scoreReleasedAt: null, decision: "OFFERED" }), null);
  assert.equal(scoreReleased({ result: null, scoreReleasedAt: AT }), false);
  assert.equal(scoreReleased({ result: result({}), scoreReleasedAt: null }), false);
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

test("the score and the Screening result screen wait for the admission decision: offered, waiting list or not offered, once the applicant may read it", () => {
  // the API gives the decision only once it is the applicant's to read (released and, under Admission Status Checking, checked)
  assert.equal(screeningResultOpen({ decision: null }), false);
  assert.equal(screeningResultOpen({ decision: "OFFERED" }), true);
  assert.equal(screeningResultOpen({ decision: "WAITING" }), true);
  assert.equal(screeningResultOpen({ decision: "NOT_OFFERED" }), true);
});
