import { test } from "node:test";
import assert from "node:assert/strict";
import {
  HIGH_RISK, STEPS, eventWord, fileProblem, fromDraft, payload, reportRows, statusWord, stepProblems, word, words, ORG_TYPES, RESOURCES, type Answers, type Limits,
} from "./partnerships.ts";

// V658: the collaboration form's own checks (the server checks everything again), the words the desk and the reports use
const lim: Limits = { summary_max: 1000, text_max: 4000, benefits_max: 2000, max_files: 5, max_file_mb: 5 };
const fields = (step: number, a: Answers) => stepProblems(step, a, lim).map((p) => p.field);

test("eight steps, in the order of the University's form", () => {
  assert.equal(STEPS.length, 8);
  assert.equal(STEPS[0], "Applicant details");
  assert.equal(STEPS[7], "Review & submit");
});

test("step 1: the applicant, with the conditional organisation type and a real email", () => {
  assert.deepEqual(fields(1, {}), ["firstName", "lastName", "orgName", "orgType", "email", "country"]);
  const ok: Answers = { firstName: "Ada", lastName: "Okafor", orgName: "Example Research Institute", orgType: "RESEARCH_INSTITUTE", email: "ada@example.org", country: "Ghana" };
  assert.deepEqual(fields(1, ok), []);
  assert.deepEqual(fields(1, { ...ok, orgType: "OTHER" }), ["orgTypeOther"]);
  assert.deepEqual(fields(1, { ...ok, email: "ada@example" }), ["email"]);
  assert.deepEqual(fields(1, { ...ok, phone: "call me" }), ["phone"]);
  assert.deepEqual(fields(1, { ...ok, phone: "+233 (0) 20-123-4567" }), []);
  // every message names its field first, as the error summary lists it
  for (const p of stepProblems(1, {}, lim)) assert.match(p.message, /^[A-Z][^:]+: /);
});

test("step 2: a follow-up needs its reference, a contact its name, a past collaboration its account", () => {
  const base: Answers = { proposalKind: "NEW", hasContact: false, collaboratedBefore: "NO" };
  assert.deepEqual(fields(2, base), []);
  assert.deepEqual(fields(2, { ...base, proposalKind: "FOLLOW_UP" }), ["previousReference"]);
  assert.deepEqual(fields(2, { ...base, hasContact: true }), ["contactName"]);
  assert.deepEqual(fields(2, { ...base, hasContact: true, contactName: "Dr A. Bello", contactEmail: "bello@" }), ["contactEmail"]);
  assert.deepEqual(fields(2, { ...base, collaboratedBefore: "YES" }), ["previousCollaboration"]);
  assert.deepEqual(fields(2, { proposalKind: "NEW", collaboratedBefore: "NO" }), ["hasContact"]);
});

test("step 3: the proposal within its limits; the secondary category not the primary", () => {
  const ok: Answers = { category: "JOINT_RESEARCH", title: "Joint soil research", summary: "A two-year study of soil health.", description: "Field trials across two states with shared data." };
  assert.deepEqual(fields(3, ok), []);
  assert.deepEqual(fields(3, { ...ok, secondaryCategory: "JOINT_RESEARCH" }), ["secondaryCategory"]);
  assert.deepEqual(fields(3, { ...ok, summary: "x".repeat(1001) }), ["summary"]);
  assert.deepEqual(fields(3, { ...ok, title: "Soil" }), ["title"]);
  assert.deepEqual(fields(3, { ...ok, benefitsPartner: "y".repeat(2001) }), ["benefitsPartner"]);
});

test("step 4: a budget in figures with its currency; other resources described", () => {
  const ok: Answers = { fundingStatus: "PARTLY_FUNDED" };
  assert.deepEqual(fields(4, ok), []);
  assert.deepEqual(fields(4, { ...ok, budget: "250,000" }), ["currency"]);
  assert.deepEqual(fields(4, { ...ok, budget: "about 250k", currency: "USD" }), ["budget"]);
  assert.deepEqual(fields(4, { ...ok, budget: "250000.50", currency: "USD" }), []);
  assert.deepEqual(fields(4, { ...ok, resourcesRequested: ["OTHER"] }), ["resourcesOther"]);
});

test("step 5: every high-risk activity answered; countries for an international proposal; a conflict described", () => {
  const risk = Object.fromEntries(HIGH_RISK.map(([k]) => [k, "NO"]));
  const ok: Answers = { international: false, personalData: "NO", ethics: "NOT_SURE", highRisk: risk, coi: "NO", ownDueDiligence: "IN_PROGRESS" };
  assert.deepEqual(fields(5, ok), []);
  assert.deepEqual(fields(5, { ...ok, international: true }), ["countries"]);
  assert.deepEqual(fields(5, { ...ok, personalData: "YES" }), ["sensitiveData"]);
  assert.deepEqual(fields(5, { ...ok, coi: "YES" }), ["coiDetail"]);
  assert.deepEqual(fields(5, { ...ok, highRisk: { ...risk, ANIMALS: "" } }), ["highRisk.ANIMALS"]);
});

test("step 7: the five declarations, never assumed; marketing consent optional", () => {
  assert.deepEqual(fields(7, {}), ["declaredAccurate", "declaredAuthorised", "declaredNoCommitment", "declaredPrivacy", "consentContact"]);
  assert.deepEqual(fields(7, { declaredAccurate: true, declaredAuthorised: true, declaredNoCommitment: true, declaredPrivacy: true, consentContact: true }), []);
});

test("a resumed draft never carries the declarations over", () => {
  const a = fromDraft({ first_name: "Ada", consent_marketing: true, high_risk: '{"ANIMALS":"YES"}', countries: ["Ghana"], has_contact: false });
  assert.equal(a.firstName, "Ada");
  assert.equal(a.consentMarketing, true);
  assert.deepEqual(a.highRisk, { ANIMALS: "YES" });
  assert.deepEqual(a.countries, ["Ghana"]);
  assert.equal(a.hasContact, false);
  for (const k of ["declaredAccurate", "declaredAuthorised", "declaredNoCommitment", "declaredPrivacy", "consentContact"] as const) assert.equal(a[k], false);
});

test("the payload sends the budget without separators", () => {
  assert.equal(payload({ budget: "1,250 000" }).budget, "1250000");
});

test("files: only PDF, DOCX, XLSX and PPTX within the size; an executable refused by name", () => {
  assert.equal(fileProblem("concept.pdf", 1024, 5), null);
  assert.equal(fileProblem("Budget.XLSX", 1024, 5), null);
  assert.match(fileProblem("setup.exe", 1024, 5) ?? "", /PDF, DOCX, XLSX or PPTX/);
  assert.match(fileProblem("macro.docm", 1024, 5) ?? "", /PDF, DOCX, XLSX or PPTX/);
  assert.match(fileProblem("noextension", 1024, 5) ?? "", /PDF, DOCX, XLSX or PPTX/);
  assert.match(fileProblem("big.pdf", 6 * 1048576, 5) ?? "", /at most 5 MB/);
  assert.match(fileProblem("empty.pdf", 0, 5) ?? "", /empty/);
});

test("words for statuses, options, events and the report's rows", () => {
  assert.equal(statusWord("PENDING_APPROVAL"), "Pending approval");
  assert.equal(statusWord(null), "—");
  assert.equal(word(ORG_TYPES, "NGO"), "NGO/Civil Society");
  assert.equal(word(ORG_TYPES, "UNLISTED"), "UNLISTED");
  assert.equal(word(ORG_TYPES, undefined), "—");
  assert.equal(words(RESOURCES, []), "—");
  assert.equal(eventWord("ACCEPT"), "Accept for review");
  assert.equal(eventWord("AGREEMENT_LEGAL_CLEAR"), "Agreement cleared by the Legal Officer");
  assert.equal(eventWord("SOMETHING_NEW"), "Something new");
  const [row] = reportRows([{ reference: "PTN/2026/000001", org_name: "Example Institute", country: "Ghana", category_label: "Joint research", title: "Soil",
    status: "UNDER_REVIEW", owner_name: null, received_at: "2026-10-25T09:00:00Z", due_on: null }]);
  assert.equal(row[0], "PTN/2026/000001");
  assert.equal(row[7], "Under review");
  assert.equal(row[8], "Unassigned");
  assert.equal(row[10], "");
});
