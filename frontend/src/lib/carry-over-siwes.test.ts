import { test } from "node:test";
import assert from "node:assert/strict";
import { gstHeld, groupRows, selection, siwesHeld, siwesRefused, siwesRowWords, siwesWaitNotes, tickable, type CarryResult, type CarryRow } from "./carry-over.ts";
import { SIWES_LOCK_PILL, SIWES_LOCK_TITLE } from "./siwes.ts";

const row = (code: string, extra: Partial<CarryRow> = {}): CarryRow => ({
  course_id: `id-${code}`, course_code: code, shown_code: code, title: `Title ${code}`, units: 2, level: 300, course_semester: 1, both_semesters: false,
  course_group: code.startsWith("EPS") ? "EPS" : code.startsWith("GST") ? "GST" : "OTHER", status: "OUTSTANDING", origin_session: null, origin_semester: null,
  last_grade: null, offering_id: null, selectable: true, reason: "", ...extra,
});

const UNPAID = "SIWES_UNPAID: the SIWES registration fee for 2025/2026 is not paid; CMP 360 is registered once it is";
const UNSET = "SIWES_FEE_NOT_SET: the Bursary has not published the SIWES registration fee for 2025/2026";
const NO_REACH = "SIWES_NOT_IN_REACH: CMP 360 is a SIWES course; your programme carries none at your level";

const held = (code: string, gate: string | null = UNPAID) => row(code, { siwes_held: true, siwes_gate: gate });

test("V777: a SIWES course the SIWES fee holds cannot be ticked, whatever holds it; the others can", () => {
  assert.equal(tickable(held("CMP 360", UNPAID)), false);
  assert.equal(tickable(held("CMP 361", UNSET)), false);
  assert.equal(tickable(held("CMP 362", NO_REACH)), false);
  // the hold is the flag's: words alone, or a flag that is false, hold nothing
  assert.equal(tickable(row("CMP 363", { siwes_held: false, siwes_gate: null })), true);
  assert.equal(tickable(row("CMP 364", { siwes_gate: UNPAID })), true);
  assert.equal(tickable(row("CSC 301")), true);
  // a course the student may not add stays so; the GST hold still holds
  assert.equal(tickable(row("CMP 365", { selectable: false, siwes_held: false })), false);
  assert.equal(tickable(row("CMP 366", { selectable: false, siwes_held: true, siwes_gate: UNPAID })), false);
  assert.equal(tickable(row("EPS 302", { gst_held: true, gst_to_pay: 4000 })), false);
  assert.equal(tickable(row("EPS 303", { gst_held: false, siwes_held: false })), true);
});

test("V777: the SIWES courses held are counted by what holds them, once", () => {
  assert.equal(siwesHeld([row("CSC 301"), row("GST 311", { gst_held: true, gst_to_pay: 4000 })]), null);
  assert.deepEqual(siwesHeld([held("CMP 360"), held("CMP 361"), row("CSC 301")]), { count: 2, unpaid: 2, notPublished: 0, notOpen: 0 });
  assert.deepEqual(siwesHeld([held("CMP 360", UNPAID), held("CMP 361", UNSET), held("CMP 362", NO_REACH), held("CMP 363", UNSET)]), { count: 4, unpaid: 1, notPublished: 2, notOpen: 1 });
  // words the screen does not know are the fee's: it is what holds a SIWES course
  assert.deepEqual(siwesHeld([held("CMP 360", null), held("CMP 361", "SOMETHING_NEW: words")]), { count: 2, unpaid: 2, notPublished: 0, notOpen: 0 });
  // a row held for the SIWES fee is not counted as waiting for the GST fee, nor the reverse
  assert.equal(gstHeld([held("CMP 360")]), null);
  assert.equal(siwesHeld([row("EPS 302", { gst_held: true, gst_to_pay: 4000 })]), null);
});

test("V777: the notes over the picker say how many wait, one note for each kind of hold, the fee unpaid first and the only one that links", () => {
  assert.deepEqual(siwesWaitNotes(null), []);
  const one = siwesWaitNotes(siwesHeld([held("CMP 360")]));
  assert.equal(one.length, 1);
  assert.equal(one[0].title, "SIWES fee first");
  assert.equal(one[0].kind, "bad");
  assert.equal(one[0].pay, true);
  assert.match(one[0].words, /^A SIWES course below is added once the SIWES fee is paid\./);
  assert.match(one[0].words, /once a session, on your SIWES page, whichever SIWES course you add/);
  const three = siwesWaitNotes(siwesHeld([held("CMP 360"), held("CMP 361"), held("CMP 362")]));
  assert.match(three[0].words, /^3 SIWES courses below are added once the SIWES fee is paid\./);
  const all = siwesWaitNotes(siwesHeld([held("CMP 360", NO_REACH), held("CMP 361", UNSET), held("CMP 362", UNPAID), held("CMP 363", UNPAID), held("CMP 364", NO_REACH)]));
  assert.deepEqual(all.map((n) => n.title), ["SIWES fee first", "SIWES fee not published yet", "SIWES course not open to you"]);
  assert.deepEqual(all.map((n) => n.pay), [true, false, false]);
  assert.deepEqual(all.map((n) => n.kind), ["bad", "info", "info"]);
  assert.match(all[0].words, /^2 SIWES courses below are added/);
  assert.equal(all[1].words, "The Bursary has not published the SIWES fee for this session; a SIWES course below is added once it is published and paid.");
  assert.match(siwesWaitNotes(siwesHeld([held("CMP 360", UNSET), held("CMP 361", UNSET)]))[0].words, /; 2 SIWES courses below are added once it is published and paid\.$/);
  assert.match(all[2].words, /^2 SIWES courses below cannot be added: your programme carries no SIWES course at your level, so the fee cannot be paid for them\. Ask the Academic Office\.$/);
  assert.match(siwesWaitNotes(siwesHeld([held("CMP 360", NO_REACH)]))[0].words, /^A SIWES course below cannot be added: .* so the fee cannot be paid for it\./);
  // never a code
  for (const n of all) assert.doesNotMatch(n.words + n.title, /SIWES_[A-Z_]+|[A-Z]{3,}_[A-Z_]+/);
});

test("V777: a held row says so in plain words — a pill and a line, never a code", () => {
  assert.equal(siwesRowWords(row("CSC 301")), null);
  assert.equal(siwesRowWords(row("CSC 301", { siwes_held: false, siwes_gate: UNPAID })), null);
  assert.deepEqual(siwesRowWords(held("CMP 360", UNPAID)), { pill: "SIWES fee first", line: "Pay the SIWES fee on your SIWES page, then add this course." });
  assert.deepEqual(siwesRowWords(held("CMP 360", null)), { pill: "SIWES fee first", line: "Pay the SIWES fee on your SIWES page, then add this course." });
  // the other holds read as Course Registration's own rows do (lib/siwes)
  assert.deepEqual(siwesRowWords(held("CMP 361", UNSET)), { pill: SIWES_LOCK_PILL.FEE_NOT_SET, line: `${SIWES_LOCK_TITLE.FEE_NOT_SET}.` });
  assert.deepEqual(siwesRowWords(held("CMP 362", NO_REACH)), { pill: SIWES_LOCK_PILL.NOT_IN_REACH, line: `${SIWES_LOCK_TITLE.NOT_IN_REACH}.` });
  for (const g of [UNPAID, UNSET, NO_REACH]) {
    const w = siwesRowWords(held("CMP 360", g))!;
    assert.doesNotMatch(w.pill + w.line, /[A-Z]{3,}_[A-Z_]+/);
  }
});

test("V777: a SIWES course picked before the fee was asked is not counted in what is ticked, nor in what a level has to add", () => {
  const rows = [held("CMP 360"), row("CSC 301")];
  const s = selection(rows, new Set(["id-CMP 360", "id-CSC 301"]));
  assert.equal(s.count, 1);
  assert.equal(s.units, 2);
  assert.deepEqual(s.byLevel, [[300, 1]]);
  // the level's "to add" count (the picker reads tickable over each group's rows) leaves the held course out
  const g = groupRows(rows);
  assert.equal(g[0].semesters.reduce((n, x) => n + x.rows.filter(tickable).length, 0), 1);
  assert.equal(g[0].semesters.reduce((n, x) => n + x.rows.length, 0), 2);
});

test("V777: the SIWES courses an add refused for the fee are counted from its answers", () => {
  const res = (code: string, added: boolean, c?: string): CarryResult => ({ courseId: `id-${code}`, courseCode: code, added, code: c });
  assert.equal(siwesRefused([]), null);
  assert.equal(siwesRefused([res("CSC 301", true), res("CSC 302", false, "CARRY_CLEARED"), res("EPS 302", false, "GST_PAYMENT_REQUIRED")]), null);
  assert.deepEqual(siwesRefused([res("CMP 360", false, "SIWES_UNPAID"), res("CMP 361", false, "SIWES_UNPAID"), res("CSC 301", true)]), { count: 2, unpaid: 2, notPublished: 0, notOpen: 0 });
  assert.deepEqual(siwesRefused([res("CMP 360", false, "SIWES_UNPAID"), res("CMP 361", false, "SIWES_FEE_NOT_SET"), res("CMP 362", false, "SIWES_NOT_IN_REACH")]), { count: 3, unpaid: 1, notPublished: 1, notOpen: 1 });
  // a course added carries no refusal, whatever its code says
  assert.equal(siwesRefused([res("CMP 360", true, "SIWES_UNPAID")]), null);
  assert.deepEqual(siwesWaitNotes(siwesRefused([res("CMP 360", false, "SIWES_UNPAID")])).map((n) => [n.title, n.pay]), [["SIWES fee first", true]]);
});
