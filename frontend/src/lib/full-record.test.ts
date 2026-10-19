import { test } from "node:test";
import assert from "node:assert/strict";
import { activityWord, levelHistory, printBody, resultWord, sectionTables, tabOf, tabsFor, timeline, words, type Progression } from "./full-record.ts";

const progression = (o: Partial<Progression> = {}): Progression => ({ held: [], changes: [], decisions: [], statuses: [], deferments: [], position: null, ...o });

test("the tabs are the sections the server reads, the biodata always, the notifications only where offered", () => {
  assert.deepEqual(tabsFor(["overview", "registrations", "results"], false), ["overview", "biodata", "registrations", "results"]);
  const all = tabsFor(["overview", "admission", "finance", "audit"], true);
  assert.deepEqual(all, ["overview", "biodata", "admission", "finance", "notifications", "audit"]);
  assert.equal(tabOf("finance", all), "finance");
  // a tab the office does not read (or a made-up one) opens the overview
  assert.equal(tabOf("support", all), "overview");
  assert.equal(tabOf(null, all), "overview");
});

test("a missing result is never a zero or a fail: no result, not submitted, or awaiting approval", () => {
  assert.equal(resultWord({ published: true, stage: "PUBLISHED", grade: "B", outcome: "GRADED" }), "B");
  assert.equal(resultWord({ published: true, stage: "PUBLISHED", grade: null, outcome: "ABSENT" }), "F (absent)");
  assert.equal(resultWord({ published: false, stage: "NO_RESULT", grade: null, outcome: null }), "No result");
  assert.equal(resultWord({ published: false, stage: "NO_SHEET", grade: null, outcome: null }), "Not yet submitted");
  assert.equal(resultWord({ published: false, stage: "HOD_APPROVED", grade: null, outcome: null }), "Awaiting approval (HOD approved)");
  // an unpublished result prints no scores
  const [t] = sectionTables("results", { results: [{ session: "2024/2025", semester: 1, course_code: "COM 401", title: "Research", units: 2, entry_type: "CURRENT",
    stage: "NO_SHEET", published: false, published_at: null, ca: 12, exam: 40, total: 52, grade: null, points: null, outcome: null }], semesters: [], owed: [] });
  assert.deepEqual(t.rows[0], [1, "2024/2025", "First", "COM 401", "Research", 2, "", "", "", "Not yet submitted"]);
});

test("the level history holds only the sessions recorded, the enrolment's level first, and a disagreement shown", () => {
  const h = levelHistory({ held: [
    { session: "2024/2025", semester: null, level: 300, source: "ENROLMENT", detail: "FULL_TIME", at: "2024-11-01" },
    { session: "2024/2025", semester: 1, level: 300, source: "REGISTRATION", detail: "APPROVED", at: "2024-11-02" },
    { session: "2022/2023", semester: 2, level: 100, source: "REGISTRATION", detail: "APPROVED", at: "2023-04-01" },
    { session: "2022/2023", semester: 1, level: 200, source: "REGISTRATION", detail: "LOCKED", at: "2022-12-01" },
  ] });
  // 2023/2024 has no record and is not filled in
  assert.deepEqual(h.map((x) => x.session), ["2022/2023", "2024/2025"]);
  assert.equal(h[0].level, null);
  assert.equal(h[0].conflict, true);
  assert.deepEqual(h[0].levels, [100, 200]);
  assert.equal(h[1].level, 300);
  assert.equal(h[1].source, "Enrolment and Course registration");
  assert.equal(h[1].semesters, "First (Approved)");
});

test("the timeline lists each recorded change once, oldest first, with who made it", () => {
  const t = timeline(progression({
    changes: [{ at: "2026-10-16T15:56:52Z", actor_office: "ictagent", actor: "Desk, Officer", reason: "Passed 200 Level", previous_level: 200, new_level: 300,
      previous_programme: "C1", new_programme: "C1", previous_status: "ACTIVE", new_status: "ACTIVE" }],
    statuses: [{ id: 1, from_status: "ACTIVE", to_status: "DEFERRED", instrument: "Senate minute 12", effective_on: "2025-01-10", expires_on: null, reason: null }],
    decisions: [{ decided_at: "2026-10-01T10:00:00Z", rule: "SPILLOVER", previous_status: "ACTIVE", final_status: "ACTIVE", previous_level: 400, new_level: 400,
      previous_cohort: "2020/2021", effective_cohort: "2021/2022", reason: "Deferred a session", batch_ref: "LCB-1", actor_office: "academic", officer: "Head, Unit" }],
  }));
  assert.deepEqual(t.map((e) => e.kind), ["STATUS", "COHORT", "LEVEL"]);
  assert.equal(t[2].text, "Level 200 → 300");
  assert.equal(t[2].by, "Desk, Officer (ictagent)");
  assert.equal(t[1].text, "Cohort decision (Spillover): cohort 2020/2021 → 2021/2022");
  assert.equal(t[0].text, "Status Active → Deferred on Senate minute 12");
});

test("the payments table numbers its rows, keeps the kobo and says each state", () => {
  const [p] = sectionTables("finance", { payments: [
    { id: "1", session: "2025/2026", reference: "MOAUM-1", purpose: "School fees 2025/2026", amount: "121849.80", generated_at: "2025-11-01", expires_at: null,
      confirmed_at: "2025-11-02", channel: "INTERSWITCH", receipt_no: "RCT-1", term: null, status: "PAID", school_fees: true, gateway: null, gateway_ref: null, gateway_outcome: null },
    { id: "2", session: "2025/2026", reference: "MOAUM-2", purpose: "Hostel", amount: 5000, generated_at: "2025-10-01", expires_at: "2025-10-08",
      confirmed_at: null, channel: null, receipt_no: null, term: null, status: "EXPIRED", school_fees: false, gateway: null, gateway_ref: null, gateway_outcome: null },
  ], schoolFees: [], refunds: [] });
  assert.equal(p.headers[0], "S/N");
  assert.equal(p.rows[0][5], 121849.8);
  assert.equal(p.rows[0][6], "Paid");
  assert.equal(p.rows[1][6], "Expired, not paid");
  assert.equal(p.rows[1][0], 2);
});

test("the print escapes what the record holds and says when a section has nothing", () => {
  const html = printBody([{ label: "Results", tables: [{ title: "Results", headers: ["S/N", "Course"], rows: [] }] },
    { label: "Notes <b>", facts: [["Name", "O'Neil & <Sons>"]], tables: [] }]);
  assert.match(html, /None recorded\./);
  assert.match(html, /O'Neil &amp; &lt;Sons&gt;/);
  assert.doesNotMatch(html, /<b>"/);
  assert.equal(activityWord("RECORD_UPDATE", "registration.course_registration"), "Changed a course registration");
  assert.equal(activityWord("SUPPORT_PASSWORD_RESET", "helpdesk.support_action"), "ICT support: Password reset");
  assert.equal(words("UTME"), "UTME");
  assert.equal(words("DIRECT_ENTRY"), "Direct entry");
  assert.equal(words("PART_PAYMENT"), "Part payment");
});
