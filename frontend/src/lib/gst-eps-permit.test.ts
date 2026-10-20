import { test } from "node:test";
import assert from "node:assert/strict";
import { courseSchedule, paymentRemedy, permitSections, permitStatusLabel, permitSummary, permitVerifyPath, registrationRemedy, rosterStatusLabel, slotDate, slotTime, slotVenue, TO_BE_SCHEDULED, type PermitCourse, type PermitState } from "./gst-eps-permit.ts";

const gst = (code: string, extra: Partial<PermitCourse> = {}): PermitCourse => ({ course_code: code, title: code, units: 2, course_type: "GST", ...extra });
const eps = (code: string, extra: Partial<PermitCourse> = {}): PermitCourse => ({ course_code: code, title: code, units: 2, course_type: "EPS", ...extra });

test("a student with GST only sees a GST section and no empty EPS section", () => {
  const s = permitSections([gst("GST 101"), gst("GST 103")]);
  assert.deepEqual(s.map((x) => x.title), ["GST COURSES"]);
  assert.equal(s[0].courses.length, 2);
});

test("a student with EPS only sees an EPS section and no empty GST section", () => {
  assert.deepEqual(permitSections([eps("EPS 201")]).map((x) => x.title), ["EPS COURSES"]);
});

test("a student with both sees GST first, then EPS, each with only its own courses", () => {
  const s = permitSections([eps("EPS 401"), gst("GST 101"), gst("GST 112")]);
  assert.deepEqual(s.map((x) => [x.title, x.courses.map((c) => c.course_code)]), [["GST COURSES", ["GST 101", "GST 112"]], ["EPS COURSES", ["EPS 401"]]]);
  assert.deepEqual(permitSections([]), []);
});

test("an examination with no slot reads TO BE SCHEDULED, never an invented date, time or venue", () => {
  const c = gst("GST 101");
  assert.equal(slotDate(c), TO_BE_SCHEDULED);
  assert.equal(slotTime(c), TO_BE_SCHEDULED);
  assert.equal(slotVenue(c), TO_BE_SCHEDULED);
  const t = gst("GST 101", { held_on: "2026-11-16", starts_at: "09:00:00", ends_at: "11:00:00", venue: "Main Hall" });
  assert.equal(slotDate(t), "Mon 16 Nov 2026");
  assert.equal(slotTime(t), "09:00–11:00");
  assert.equal(slotTime(t, "-"), "09:00-11:00");
  assert.equal(slotVenue(t), "Main Hall");
  assert.equal(slotVenue(gst("GST 101", { held_on: "2026-11-16", starts_at: "09:00:00", venue: "CBT Centre 2", seat_no: 14 })), "CBT Centre 2, seat 14");
  assert.equal(slotTime(gst("GST 101", { held_on: "2026-11-16", starts_at: "09:00:00" })), "09:00");
  assert.equal(slotVenue(gst("GST 101", { held_on: "2026-11-16", starts_at: "09:00:00" })), TO_BE_SCHEDULED);
});

test("the permit's state reads as a word, and a refusal names its remedy", () => {
  const base: PermitState = { available: true, session: "2026/2027", semester: 1, student: { name: "A" }, courses: [], gstCount: 0, epsCount: 0, units: 0 };
  assert.equal(permitStatusLabel(base), "Available");
  assert.equal(permitStatusLabel({ ...base, available: false, code: "GST_EPS_PERMIT_NO_COURSES" }), "Not available");
  assert.equal(permitStatusLabel({ ...base, permit: { reference: "GST-EPS/2026/000001", status: "PRINTED", generatedAt: "", lastIssuedAt: "", viewed: 1, downloaded: 0, printed: 1 } }), "Printed");
  assert.equal(permitStatusLabel({ ...base, available: false, permit: { reference: "GST-EPS/2026/000001", status: "REVOKED", generatedAt: "", lastIssuedAt: "", viewed: 1, downloaded: 0, printed: 0 } }), "Withdrawn");
  assert.equal(registrationRemedy("GST_EPS_PERMIT_NO_COURSES"), true);
  assert.equal(registrationRemedy("GST_EPS_PERMIT_NOT_SUBMITTED"), true);
  assert.equal(registrationRemedy("GST_EPS_PERMIT_GST_PAYMENT"), false);
  assert.equal(registrationRemedy("GST_EPS_PERMIT_NOT_PAID"), false);
  assert.equal(paymentRemedy("GST_EPS_PERMIT_GST_PAYMENT"), "GST");
  // V589: the school fees, as the examination card asks them — no clearance scheme, approval or release stands between
  assert.equal(paymentRemedy("GST_EPS_PERMIT_NOT_PAID"), "FEES");
  assert.equal(paymentRemedy("GST_EPS_PERMIT_NOT_CLEARED"), null);
  assert.equal(paymentRemedy("GST_EPS_PERMIT_REVOKED"), null);
});

test("the summary counts papers, units and each kind; the QR path carries the reference and code encoded", () => {
  assert.equal(permitSummary({ courses: [gst("GST 101"), gst("GST 112"), eps("EPS 401")], units: 6, gstCount: 2, epsCount: 1 }), "3 papers · 6 credit units · GST 2 · EPS 1");
  assert.equal(permitSummary({ courses: [gst("GST 101")], units: 1, gstCount: 1, epsCount: 0 }, "|"), "1 paper | 1 credit unit | GST 1");
  assert.equal(permitVerifyPath("GST-EPS/2026/000001", "ABC123DEF456"), "/verify/gst-eps-permit?r=GST-EPS%2F2026%2F000001&c=ABC123DEF456");
  assert.equal(rosterStatusLabel(null), "Not generated");
  assert.equal(rosterStatusLabel("REVOKED"), "Withdrawn");
  assert.equal(courseSchedule({ course_code: "GST 111", title: "x", units: 2, course_type: "GST", registered: 4 }), TO_BE_SCHEDULED);
  assert.equal(courseSchedule({ course_code: "GST 111", title: "x", units: 2, course_type: "GST", registered: 4, held_on: "2026-11-16", starts_at: "09:00:00", ends_at: "11:00:00", venue: "Main Hall" }), "Mon 16 Nov 2026 · 09:00–11:00 · Main Hall");
});
