import { test } from "node:test";
import assert from "node:assert/strict";
import {
  STATES, applicantWords, applyBody, applyErrors, canSubmit, countWords, documentChecklist, documentsUnchecked, editableFields, emptyApplyForm, eventWords, feeClosed,
  feeWords, fileProblem, formFromView, forDepartment, hasAcknowledgement, hodMay, isTransferApplicationNo, kindProblem, mayWithdraw, normalPhone, officeActions, officeWords,
  paymentLine, paymentTitle, programmeGroups, publicWindowOf, refundWords, PAYMENT_HEAD, WITHDRAW_WHEN_APPROVED, lineWords, offeredLines, officeFeePill, officeFeeWords,
  officeGuidance, referencePill, stillOwedBack, windowAlert, checkRefusal, lineGone, PAID_DRAFT_ENDED, NO_LEVEL_TO_RECOMMEND,
  placesOf, programmesWithCurrent, stageIndex, studentHere, typedDataUrl, updateBody, verifyApiPath, windowIsOpen, withdrawFromRegistry, zeroDue, WITH_REGISTRY,
  type ApplyForm, type DocumentKind, type IutDocument, type IutView, type PublicProgramme, type PublicUniversity,
} from "./transfer-application.ts";

const KINDS: DocumentKind[] = [
  { code: "TRANSCRIPT", label: "Academic transcript", required: true, imagesAllowed: true },
  { code: "RELEASE_LETTER", label: "Letter of release", required: true, imagesAllowed: false },
  { code: "JAMB_ADMISSION_LETTER", label: "JAMB admission letter", required: true },
  { code: "OLEVEL_RESULT", label: "O'Level result", required: true },
  { code: "OTHER", label: "Any other supporting document", required: false },
];
const doc = (kind: string, status: string, over: Partial<IutDocument> = {}): IutDocument => ({ id: `${kind}-${status}`, kind, filename: `${kind}.pdf`, status, ...over });
const PROGRAMMES: PublicProgramme[] = [
  { code: "C00023", name: "B.Sc. Biochemistry", dept: "BCH", deptName: "Biochemistry", faculty: "SC", facultyName: "Science", levels: [200, 300] },
  { code: "C00101", name: "B.Sc. Accounting", dept: "ACC", deptName: "Accounting", faculty: "MS", facultyName: "Management Sciences", levels: [200] },
];
const UNIVERSITIES: PublicUniversity[] = [{ code: "UNIJOS", name: "University of Jos", country: "Nigeria" }];
const OPTIONS = { programmes: PROGRAMMES, universities: UNIVERSITIES, session: "2026/2027", today: "2026-11-15" };

function good(over: Partial<ApplyForm> = {}): ApplyForm {
  return {
    ...emptyApplyForm(), surname: "Audu", otherNames: "Grace Ene", sex: "F", dateOfBirth: "2004-03-09", email: " Grace@Example.com ", phone: "0803 123 4567",
    jambRegNo: "1234 5678 9012ab", universityCode: "UNIJOS", otherMatricNo: "uj/2023/sc/0042", otherProgramme: "B.Sc. Biochemistry", otherLevel: "300",
    otherEntrySession: "2023/2024", otherCgpa: "3.85", otherCgpaScale: "5", programme: "C00023", level: "200",
    reason: "My family has moved to Makurdi and I wish to continue my studies here.", password: "a-long-secret", password2: "a-long-secret", privacy: true,
    ...over,
  };
}

test("an application number is IUT/APP/YYYY/NNNNNN, never a batch reference", () => {
  assert.equal(isTransferApplicationNo("IUT/APP/2026/000001"), true);
  assert.equal(isTransferApplicationNo(" iut/app/2026/000001 "), true);
  assert.equal(isTransferApplicationNo("IUT/2026/000001"), false);
  assert.equal(isTransferApplicationNo("JUPEB/APP/2026/000001"), false);
  assert.equal(isTransferApplicationNo("IUT/APP/26/000001"), false);
  assert.equal(isTransferApplicationNo(null), false);
});

test("every state has the applicant's and the office's words; the Registry's three states read alike to the applicant", () => {
  for (const s of STATES) {
    const a = applicantWords(s);
    assert.ok(a.stage && a.words && a.words !== s, `${s}: applicant words`);
    const [o, pill] = officeWords(s);
    assert.ok(o && o !== s && pill, `${s}: office words`);
    assert.ok(eventWords(s) !== s.toLowerCase() || s === "DRAFT", `${s}: event words`);
  }
  const same = ["RECOMMENDED", "NOT_RECOMMENDED", "APPROVED"].map((s) => applicantWords(s, { applied: { programmeName: "B.Sc. Biochemistry" }, notice: { kind: "REJECTED", note: "x" } }));
  assert.deepEqual(same[1], same[0]);
  assert.deepEqual(same[2], same[0]);
  assert.equal(same[0].words, "With the Registry for a decision.");
  // the office's words differ between them
  assert.notEqual(officeWords("RECOMMENDED")[0], officeWords("NOT_RECOMMENDED")[0]);
});

test("the applicant's banner says the next step, the date, the note and the admission number (SPEC §6)", () => {
  const draft = { state: "DRAFT", fee: { settled: false, due: 5000 }, kinds: KINDS, documents: [] };
  assert.equal(applicantWords("DRAFT", draft).words, "Not yet submitted. Next: pay the application fee of ₦5,000 first.");
  const paid = { ...draft, fee: { settled: true, basis: "PAID" }, documents: [doc("TRANSCRIPT", "PENDING")] };
  assert.equal(applicantWords("DRAFT", paid).words, "Not yet submitted. Next: upload: Letter of release; JAMB admission letter; O'Level result.");
  const ready = { ...paid, documents: KINDS.filter((k) => k.required).map((k) => doc(k.code, "PENDING")) };
  assert.equal(applicantWords("DRAFT", ready).words, "Not yet submitted. Next: submit.");
  assert.equal(applicantWords("SUBMITTED", { submittedAt: "2026-11-15T09:00:00Z" }).words, "Submitted on 15 November 2026. The Registry is checking your documents.");
  assert.equal(applicantWords("CORRECTION_REQUIRED", { notice: { kind: "CORRECTION", note: "The transcript is not legible." } }).words,
    "Returned to you: The transcript is not legible. Replace the documents marked and submit again.");
  assert.match(applicantWords("WITH_HOD", { applied: { programmeName: "B.Sc. Biochemistry" } }).words, /Head of Department of B\.Sc\. Biochemistry is assessing/);
  assert.equal(applicantWords("ADMITTED", { applied: { programmeName: "B.Sc. Biochemistry" }, session: "2026/2027", student: { admissionNo: "MOAUM/ADM/26/000123", level: 200 } }).words,
    "Admitted to B.Sc. Biochemistry, 200 Level, 2026/2027. Admission number MOAUM/ADM/26/000123. Sign in as a student with it and this password.");
  assert.equal(applicantWords("REJECTED", { notice: { kind: "REJECTED", note: "The release letter could not be verified" } }).words,
    "Not admitted. Reason: The release letter could not be verified.");
  assert.equal(applicantWords("WITHDRAWN", { withdrawnAt: "2026-11-20T10:00:00Z" }).words, "Withdrawn on 20 November 2026.");
});

test("the stage runs 0 to 4, and the applicant reads only their own words of the history", () => {
  assert.deepEqual(STATES.map(stageIndex), [0, 1, 0, 2, 3, 3, 3, 4, 4, 4]);
  assert.equal(eventWords("RETURNED", true), "Returned to you for correction");
  assert.equal(eventWords("RETURNED"), "Returned to the applicant for correction");
  assert.equal(eventWords("FEE_PAID", true), "Application fee paid");
});

test("the form's errors come in the page's order, each rule at its edge", () => {
  assert.deepEqual(applyErrors(good(), OPTIONS), {});
  const order = Object.keys(applyErrors(emptyApplyForm(), OPTIONS));
  assert.deepEqual(order, ["surname", "otherNames", "sex", "dateOfBirth", "email", "phone", "jambRegNo", "universityCode", "otherMatricNo", "otherProgramme",
    "otherLevel", "otherEntrySession", "otherCgpaScale", "programme", "reason", "password", "privacy"]);
  // 14 and 70 on the day; a day short of 14, a day past 70 (71)
  assert.equal(applyErrors(good({ dateOfBirth: "2012-11-15" }), OPTIONS).dateOfBirth, undefined);
  assert.match(String(applyErrors(good({ dateOfBirth: "2012-11-16" }), OPTIONS).dateOfBirth), /14 to 70/);
  assert.equal(applyErrors(good({ dateOfBirth: "1955-11-16" }), OPTIONS).dateOfBirth, undefined);
  assert.match(String(applyErrors(good({ dateOfBirth: "1955-11-15" }), OPTIONS).dateOfBirth), /14 to 70/);
  assert.match(String(applyErrors(good({ dateOfBirth: "2004-02-30" }), OPTIONS).dateOfBirth), /date of birth/);
  // the CGPA: at most the scale, at most two decimals
  assert.match(String(applyErrors(good({ otherCgpa: "5.01" }), OPTIONS).otherCgpa), /Above the 5-point scale/);
  assert.equal(applyErrors(good({ otherCgpa: "5.00" }), OPTIONS).otherCgpa, undefined);
  assert.match(String(applyErrors(good({ otherCgpa: "3.999" }), OPTIONS).otherCgpa), /two decimals/);
  assert.match(String(applyErrors(good({ otherCgpa: "4.5", otherCgpaScale: "4" }), OPTIONS).otherCgpa), /4-point/);
  // the session entered: consecutive years, not after the application's session
  assert.match(String(applyErrors(good({ otherEntrySession: "2023/2025" }), OPTIONS).otherEntrySession), /2023\/2024/);
  assert.match(String(applyErrors(good({ otherEntrySession: "2027/2028" }), OPTIONS).otherEntrySession), /cannot be after 2026\/2027/);
  assert.equal(applyErrors(good({ otherEntrySession: "2026/2027" }), OPTIONS).otherEntrySession, undefined);
  // a phone with +234 is a Nigerian number
  assert.equal(applyErrors(good({ phone: "+2348012345678" }), OPTIONS).phone, undefined);
  assert.equal(normalPhone("+2348012345678"), "08012345678");
  assert.equal(normalPhone("8012345678"), "08012345678");
  assert.match(String(applyErrors(good({ phone: "+44 7700 900123" }), OPTIONS).phone), /Nigerian/);
  // names, the JAMB number, a level not open, the reason's length, the password
  assert.match(String(applyErrors(good({ surname: "A" }), OPTIONS).surname), /2 to 60/);
  assert.match(String(applyErrors(good({ surname: "Audu2" }), OPTIONS).surname), /letters/);
  assert.equal(applyErrors(good({ surname: "O'Neil-Ádá" }), OPTIONS).surname, undefined);
  assert.match(String(applyErrors(good({ jambRegNo: "1234567890" }), OPTIONS).jambRegNo), /JAMB/);
  assert.match(String(applyErrors(good({ level: "400" }), OPTIONS).level), /level/);
  assert.match(String(applyErrors(good({ programme: "C99999" }), OPTIONS).programme), /programme/);
  assert.match(String(applyErrors(good({ reason: "Too short a reason" }), OPTIONS).reason), /20 to 2,000/);
  assert.match(String(applyErrors(good({ password: "short", password2: "short" }), OPTIONS).password), /8/);
  assert.match(String(applyErrors(good({ password: "123456789012 ab", password2: "123456789012 ab" }), OPTIONS).password), /JAMB/);
  assert.match(String(applyErrors(good({ password2: "another" }), OPTIONS).password2), /do not match/);
  assert.match(String(applyErrors(good({ privacy: false }), OPTIONS).privacy), /Privacy/);
  // a university not on the list is named instead
  assert.match(String(applyErrors(good({ universityCode: "" }), OPTIONS).universityCode), /not on the list/);
  assert.match(String(applyErrors(good({ notListed: true, universityNamed: "AB" }), OPTIONS).universityNamed), /3 to 200/);
  assert.equal(applyErrors(good({ notListed: true, universityCode: "", universityNamed: "Kampala International University" }), OPTIONS).universityNamed, undefined);
});

test("applying again asks no e-mail, phone, password or privacy box; an edit checks only what the state allows", () => {
  assert.deepEqual(applyErrors(good({ email: "", phone: "", password: "", password2: "", privacy: false }), { ...OPTIONS, again: true }), {});
  const e = applyErrors(good({ email: "nope", surname: "A", programme: "C99999" }), { ...OPTIONS, only: ["email", "phone"] });
  assert.deepEqual(Object.keys(e), ["email"]);
});

test("the body the API takes: the confirmation and privacy box stay behind; the numbers in capitals; a university listed or named", () => {
  const b = applyBody(good());
  assert.equal("password2" in b, false);
  assert.equal("privacy" in b, false);
  assert.equal(b.jambRegNo, "123456789012AB");
  assert.equal(b.otherMatricNo, "UJ/2023/SC/0042");
  assert.equal(b.email, "grace@example.com");
  assert.equal(b.phone, "08031234567");
  assert.equal(b.universityCode, "UNIJOS");
  assert.equal(b.universityNamed, null);
  assert.equal(b.level, 200);
  assert.equal(b.otherCgpaScale, 5);
  assert.equal(b.password, "a-long-secret");
  const named = applyBody(good({ notListed: true, universityNamed: " Kampala International University " }));
  assert.equal(named.universityCode, null);
  assert.equal(named.universityNamed, "Kampala International University");
  const again = applyBody(good(), { again: true });
  for (const k of ["email", "phone", "password", "website2"]) assert.equal(k in again, false, k);
});

test("an edit sends the fields changed, of those the state allows", () => {
  const was = good();
  assert.deepEqual(updateBody(good({ phone: "+2348099999999", surname: "Changed" }), was, editableFields("SUBMITTED", true)), { phone: "08099999999" });
  assert.deepEqual(updateBody(good({ notListed: true, universityNamed: "Kampala International University" }), was, editableFields("DRAFT", false)),
    { universityCode: null, universityNamed: "Kampala International University" });
  assert.deepEqual(updateBody(good({ level: "300" }), was, editableFields("DRAFT", false)), {});
  assert.deepEqual(updateBody(good({ level: "300" }), was, editableFields("DRAFT", true)), { level: 300 });
});

test("what is editable follows the state and the window, as iut_update allows it", () => {
  const draftOpen = editableFields("DRAFT", true);
  assert.ok(draftOpen.includes("programme") && draftOpen.includes("level") && draftOpen.includes("reason") && draftOpen.includes("email"));
  const draftClosed = editableFields("DRAFT", false);
  assert.ok(!draftClosed.includes("programme") && !draftClosed.includes("level") && draftClosed.includes("jambRegNo"));
  const correction = editableFields("CORRECTION_REQUIRED", true);
  assert.ok(!correction.includes("programme") && !correction.includes("level") && correction.includes("otherCgpa"));
  for (const s of ["SUBMITTED", "WITH_HOD", "RECOMMENDED", "NOT_RECOMMENDED", "APPROVED"]) assert.deepEqual(editableFields(s, true), ["email", "phone"], s);
  for (const s of ["ADMITTED", "REJECTED", "WITHDRAWN"]) assert.deepEqual(editableFields(s, true), [], s);
});

test("the checklist reads the current documents: a superseded one ignored, a rejected one with its note to replace, an accepted one kept", () => {
  const docs = [
    doc("TRANSCRIPT", "REJECTED", { supersededAt: "2026-11-14T10:00:00Z", note: "old" }),
    doc("TRANSCRIPT", "REJECTED", { id: "t2", note: "Not legible: scan it again" }),
    doc("RELEASE_LETTER", "ACCEPTED"),
    doc("JAMB_ADMISSION_LETTER", "PENDING"),
  ];
  const rows = documentChecklist(KINDS, docs, "CORRECTION_REQUIRED", true);
  const by = (c: string) => rows.find((r) => r.code === c)!;
  assert.equal(rows.length, KINDS.length);
  assert.equal(by("TRANSCRIPT").status, "REJECTED");
  assert.equal(by("TRANSCRIPT").document?.id, "t2");
  assert.equal(by("TRANSCRIPT").note, "Not legible: scan it again");
  assert.equal(by("TRANSCRIPT").canUpload, true);
  assert.equal(by("RELEASE_LETTER").status, "ACCEPTED");
  assert.equal(by("RELEASE_LETTER").canUpload, false);
  assert.equal(by("RELEASE_LETTER").canRemove, false);
  assert.equal(by("RELEASE_LETTER").note, null);
  // returned for correction, a document still being checked is not replaced
  assert.equal(by("JAMB_ADMISSION_LETTER").canUpload, false);
  assert.equal(by("OLEVEL_RESULT").status, "MISSING");
  assert.equal(by("OLEVEL_RESULT").canUpload, true);
  // before the fee nothing is uploaded; once with the University nothing at all
  assert.ok(documentChecklist(KINDS, [], "DRAFT", false).every((r) => !r.canUpload && /fee/.test(String(r.why))));
  assert.ok(documentChecklist(KINDS, docs, "SUBMITTED", true).every((r) => !r.canUpload && !r.canRemove));
  // a document of a kind no longer asked for is still shown
  assert.equal(documentChecklist(KINDS.slice(0, 1), [doc("OTHER", "PENDING", { label: "Other" })]).some((r) => r.code === "OTHER" && !r.canUpload), true);
});

test("submitting needs the fee, every required document and none rejected", () => {
  const base: Pick<IutView, "state" | "fee" | "kinds" | "documents"> = { state: "DRAFT", fee: { settled: false, due: 5000 }, kinds: KINDS, documents: [] };
  const unpaid = canSubmit(base);
  assert.match(unpaid[0], /Pay the application fee of ₦5,000/);
  const paid = { ...base, fee: { settled: true, basis: "PAID" } };
  assert.deepEqual(canSubmit(paid), ["Upload: Academic transcript; Letter of release; JAMB admission letter; O'Level result."]);
  const all = KINDS.filter((k) => k.required).map((k) => doc(k.code, "PENDING"));
  assert.deepEqual(canSubmit({ ...paid, documents: all }), []);
  const rejected = { ...paid, state: "CORRECTION_REQUIRED", documents: [...all.slice(1), doc("TRANSCRIPT", "REJECTED", { note: "Not legible at all" })] };
  assert.deepEqual(canSubmit(rejected), ["Replace: Academic transcript."]);
  assert.equal(canSubmit({ ...paid, documents: all, state: "SUBMITTED" }).length, 1);
});

test("a file is checked for its type and size before it is read", () => {
  const pdfOnly = KINDS[1];
  assert.equal(fileProblem({ type: "application/pdf", size: 812345 }, KINDS[0]), null);
  assert.equal(fileProblem({ type: "image/png", size: 1000 }, KINDS[0]), null);
  assert.match(String(fileProblem({ type: "application/pdf", size: 6 * 1024 * 1024 }, KINDS[0])), /At most 5\.0 MB a file; this one is 6\.0 MB/);
  assert.match(String(fileProblem({ type: "image/gif", size: 1000 }, KINDS[0])), /PDF, JPEG or PNG/);
  assert.match(String(fileProblem({ type: "image/png", size: 1000 }, pdfOnly)), /PDF only/);
  assert.equal(fileProblem({ type: "application/pdf", size: 5 * 1024 * 1024 }, pdfOnly), null);
  assert.match(String(fileProblem({ type: "application/pdf", size: 0 }, pdfOnly)), /empty/);
  // a browser that gives no type: the name says it
  assert.equal(fileProblem({ type: "", size: 10, name: "scan.JPG" }, KINDS[0]), null);
  assert.equal(typedDataUrl("data:application/octet-stream;base64,AAAA", "image/jpeg"), "data:image/jpeg;base64,AAAA");
  assert.equal(typedDataUrl("data:;base64,AAAA", "application/pdf"), "data:application/pdf;base64,AAAA");
});

test("the Registry's buttons: send to the department only once every document is checked; approve only when recommended; nothing after approval", () => {
  const checked = KINDS.filter((k) => k.required).map((k) => doc(k.code, "ACCEPTED"));
  const submitted: Pick<IutView, "state" | "kinds" | "documents" | "previous"> = { state: "SUBMITTED", kinds: KINDS, documents: [...checked.slice(1), doc("TRANSCRIPT", "PENDING")], previous: { universityCode: "UNIJOS" } };
  const acts = officeActions(submitted, "academic");
  assert.deepEqual(acts.map((a) => a.action), ["SEND_TO_HOD", "RETURN", "REJECT"]);
  assert.equal(acts[0].enabled, false);
  assert.match(String(acts[0].why), /Academic transcript/);
  assert.equal(officeActions({ ...submitted, documents: checked }, "registrar")[0].enabled, true);
  assert.equal(acts.find((a) => a.action === "RETURN")?.noteMin, 10);
  // approve only in RECOMMENDED, and only with a university from the list
  for (const s of ["SUBMITTED", "CORRECTION_REQUIRED", "WITH_HOD", "NOT_RECOMMENDED", "DRAFT"]) {
    assert.equal(officeActions({ ...submitted, state: s, documents: checked }, "academic").some((a) => a.action === "APPROVE"), false, s);
  }
  const recommended = officeActions({ ...submitted, state: "RECOMMENDED", documents: checked }, "dregistrar");
  assert.deepEqual(recommended.map((a) => a.action), ["APPROVE", "SEND_BACK_TO_HOD", "REJECT"]);
  assert.equal(recommended[0].enabled, true);
  const named = officeActions({ ...submitted, state: "RECOMMENDED", documents: checked, previous: { universityNamed: "Kampala International University" } }, "super");
  assert.equal(named[0].enabled, false);
  assert.match(String(named[0].why), /Kampala International University is not on it/);
  for (const s of ["APPROVED", "ADMITTED", "REJECTED", "WITHDRAWN"]) assert.deepEqual(officeActions({ ...submitted, state: s }, "academic"), [], s);
  // Records reads the desk; it acts on nothing
  assert.deepEqual(officeActions(submitted, "records"), []);
});

test("the Head of Department recommends while the application is with the department", () => {
  assert.equal(hodMay({ state: "WITH_HOD" }), true);
  assert.equal(hodMay({ state: "WITH_HOD" }, "hod"), true);
  assert.equal(hodMay({ state: "WITH_HOD" }, "dean"), true);
  assert.equal(hodMay({ state: "WITH_HOD" }, "academic"), false);
  assert.equal(hodMay({ state: "RECOMMENDED" }, "hod"), false);
});

test("the fee in words, the acknowledgement and withdrawal by state", () => {
  assert.equal(feeWords({ session: "2026/2027", fee: { settled: true, basis: "NONE_DUE" } }), "No application fee is due for 2026/2027.");
  assert.equal(feeWords({ fee: { settled: true, basis: "PAID", references: [{ reference: "MOAUM-IUTAPP-2026-000004", amount: 5000, confirmedAt: "2026-11-15T09:00:00Z", receiptNo: "RCT-2026-00031", settles: true }] } }),
    "Paid ₦5,000 on 15 November 2026, receipt RCT-2026-00031.");
  assert.match(feeWords({ fee: { settled: false, due: 5000 } }), /^₦5,000 to pay/);
  assert.match(feeWords({ fee: null }), /not published/);
  assert.equal(hasAcknowledgement({ state: "DRAFT", submittedAt: null }), false);
  assert.equal(hasAcknowledgement({ state: "CORRECTION_REQUIRED", submittedAt: "2026-11-15T09:00:00Z" }), true);
  assert.equal(hasAcknowledgement({ state: "ADMITTED", submittedAt: "2026-11-15T09:00:00Z" }), true);
  // D11: withdrawn here until the department has assessed it; with the Registry for a decision (the three states the applicant reads
  // alike) it is asked of the Registry in all three, as the API refuses it in all three in the same words (round 2: screens-brief2-2)
  assert.deepEqual(STATES.filter(mayWithdraw), ["DRAFT", "SUBMITTED", "CORRECTION_REQUIRED", "WITH_HOD"]);
  assert.equal(mayWithdraw(WITH_REGISTRY), false);
  assert.deepEqual([...STATES, WITH_REGISTRY].filter(withdrawFromRegistry), ["RECOMMENDED", "NOT_RECOMMENDED", "APPROVED", WITH_REGISTRY]);
});

test("the public window: open by the API's word, and the closed page's shape filled where a key is left out", () => {
  assert.equal(windowIsOpen({ status: "OPEN", open: false }), false);
  assert.equal(windowIsOpen({ status: "OPEN" }), true);
  assert.equal(windowIsOpen(null), false);
  assert.equal(publicWindowOf(null), null);
  assert.deepEqual([publicWindowOf({ session: null })?.session, publicWindowOf({ session: null })?.status], ["", "CLOSED"]);
  const w = publicWindowOf({ session: "2026/2027", window: { status: "SCHEDULED", opensOn: "2026-11-20", closesOn: "2027-01-15", message: null } }, "https://portal.example");
  assert.equal(w?.session, "2026/2027");
  assert.equal(w?.open, false);
  assert.equal(w?.opensAt, "2026-11-20T00:00:00+01:00");
  assert.equal(w?.applicationUrl, "https://portal.example/transfer/apply");
});

test("the programmes are grouped by faculty, then department; a document kind's code and label are checked", () => {
  const g = programmeGroups(PROGRAMMES);
  assert.deepEqual(g.map((x) => x.label), ["Management Sciences · Accounting", "Science · Biochemistry"]);
  assert.equal(kindProblem({ code: "PASSPORT", label: "Passport photograph" }), null);
  assert.match(String(kindProblem({ code: "pp", label: "Passport photograph" })), /capital/);
  assert.match(String(kindProblem({ code: "PASSPORT", label: "P" })), /3 to 160/);
});

test("the form is filled back from an application, to edit it or apply again", () => {
  const v: IutView = {
    id: "x", applicationNo: "IUT/APP/2026/000001", session: "2026/2027", state: "REJECTED",
    applicant: { surname: "AUDU", otherNames: "Grace Ene", sex: "F", dateOfBirth: "2004-03-09", jambRegNo: "123456789012AB" },
    previous: { universityNamed: "Kampala International University", matricNo: "KIU/23/001", programme: "B.Sc. Biochemistry", level: 300, entrySession: "2023/2024", cgpa: 4, cgpaScale: 5 },
    applied: { programme: "C00023", level: 200 }, reason: "My family has moved to Makurdi and I wish to continue my studies here.",
  };
  const f = formFromView(v, { email: "grace@example.com", phone: "08031234567" });
  assert.equal(f.notListed, true);
  assert.equal(f.otherCgpa, "4.00");
  assert.equal(f.otherCgpaScale, "5");
  assert.equal(f.email, "grace@example.com");
  assert.deepEqual(applyErrors(f, { ...OPTIONS, again: true }), {});
});

test("the department's desk is given no contact, fee, transfer, Registry note or transfer check", () => {
  const v = forDepartment({ id: "x", applicationNo: "IUT/APP/2026/000001", session: "2026/2027", state: "WITH_HOD",
    applicant: { surname: "AUDU", email: "grace@example.com", phone: "08031234567" }, fee: { settled: true }, registry: { note: "n" }, transfer: { id: "t" },
    transferCheck: { status: "VALID" } });
  assert.deepEqual(v.applicant, { surname: "AUDU" });
  for (const k of ["fee", "registry", "transfer", "transferCheck"] as const) assert.equal(v[k], undefined, k);
});

test("the department's history: no fee step and none of the Registry's own words; its notes to the department kept; no notice", () => {
  const v = forDepartment({ id: "x", applicationNo: "IUT/APP/2026/000001", session: "2026/2027", state: "REJECTED",
    notice: { kind: "REJECTED", note: "The CGPA is below what the University admits" },
    history: [
      { at: "t1", action: "FEE_PAID", note: "MOAUM-IUTAPP-2026-000001 · RCT-2026-00001" },
      { at: "t2", action: "RETURNED", note: "Replace the transcript marked", byName: "OFFICER, One", office: "academic" },
      { at: "t3", action: "SENT_TO_HOD", note: "Look closely at the second-year results" },
      { at: "t4", action: "SENT_BACK_TO_HOD", note: "Look again (was: not recommended)" },
      { at: "t5", action: "APPROVED", note: "Batch IUT/2026/000014 — Senate" },
      { at: "t6", action: "REJECTED", note: "The CGPA is below what the University admits", toState: "REJECTED" },
    ] });
  assert.equal(v.notice, undefined);
  assert.deepEqual(v.history?.map((h) => h.action), ["RETURNED", "SENT_TO_HOD", "SENT_BACK_TO_HOD", "APPROVED", "REJECTED"]);
  assert.deepEqual(v.history?.map((h) => h.note ?? null), [null, "Look closely at the second-year results", "Look again (was: not recommended)", null, null]);
  assert.equal(v.history?.[0].byName, "OFFICER, One");   // the step and who took it stay
  assert.doesNotMatch(JSON.stringify(v), /MOAUM-IUTAPP-|RCT-|below what the University admits|Replace the transcript/);
});

// ── the review's findings ──────────────────────────────────────────────────────────────────────────────────────────────

test("D11: the applicant's data reads WITH_REGISTRY for a recommendation, a decline and an approval; read as the three are", () => {
  const ctx = { applied: { programmeName: "B.Sc. Biochemistry" } };
  assert.deepEqual(applicantWords(WITH_REGISTRY, ctx), applicantWords("RECOMMENDED", ctx));
  assert.equal(applicantWords(WITH_REGISTRY).words, "With the Registry for a decision.");
  assert.equal(stageIndex(WITH_REGISTRY), 3);
  assert.deepEqual(editableFields(WITH_REGISTRY, true), ["email", "phone"]);
});

test("admitted: the banner states the level of the API's student (admitted at), not the level applied for", () => {
  // the API's own shape (iut_view): student {id, admissionNo, matricNo, level}; applied at 300, admitted at 200
  const v = { applied: { programmeName: "B.Sc. Chemistry", level: 300 }, session: "2026/2027",
    student: { id: "s", admissionNo: "MOAUM/ADM/26/000123", matricNo: null, level: 200 } };
  assert.equal(applicantWords("ADMITTED", v).words,
    "Admitted to B.Sc. Chemistry, 200 Level, 2026/2027. Admission number MOAUM/ADM/26/000123. Sign in as a student with it and this password.");
  // a student without a level states none, never the level applied for
  assert.doesNotMatch(applicantWords("ADMITTED", { ...v, student: { admissionNo: "MOAUM/ADM/26/000123" } }).words, /300 Level/);
});

test("a fee of nothing published after registering: nothing to pay, confirmed by asking for the reference", () => {
  const v = { session: "2026/2027", fee: { settled: false, due: "0.00" } };
  assert.equal(zeroDue(v), true);
  assert.equal(zeroDue({ fee: { settled: false, due: 5000 } }), false);
  assert.equal(zeroDue({ fee: { settled: true, basis: "NONE_DUE" } }), false);
  assert.equal(zeroDue({ fee: { settled: false } }), false);
  assert.equal(feeWords(v), "No application fee is due for 2026/2027: confirm it below, then upload your documents.");
  assert.deepEqual(canSubmit({ state: "DRAFT", fee: v.fee, kinds: KINDS, documents: KINDS.filter((k) => k.required).map((k) => doc(k.code, "PENDING")) }),
    ["Confirm that no application fee is due first."]);
  assert.equal(documentChecklist(KINDS, [], "DRAFT", false, true)[0].why, "Confirm that no application fee is due first; documents are uploaded after it");
});

test("an edit of a draft keeps the application's own programme and level among the choices once its line stops taking new ones", () => {
  const applied = { programme: "C00101", programmeName: "B.Sc. Accounting", level: 300 };
  const open = PROGRAMMES.filter((p) => p.code === "C00023");     // the Accounting line no longer offered
  const choices = programmesWithCurrent(open, applied);
  assert.deepEqual(choices.map((p) => `${p.code}:${p.levels.join("+")}`), ["C00023:200+300", "C00101:300"]);
  // a phone-only edit is not refused for the programme it does not change
  const was = good({ programme: "C00101", level: "300" });
  const only = editableFields("DRAFT", true);
  assert.deepEqual(applyErrors({ ...was, phone: "08030000002" }, { ...OPTIONS, programmes: choices, only }), {});
  assert.deepEqual(updateBody({ ...was, phone: "08030000002" }, was, only), { phone: "08030000002" });
  // its programme kept, its level added where the programme is still offered at others
  assert.deepEqual(programmesWithCurrent(PROGRAMMES, { programme: "C00101", level: 300 }).find((p) => p.code === "C00101")?.levels, [200, 300]);
  assert.equal(programmesWithCurrent(PROGRAMMES, null).length, PROGRAMMES.length);
});

test("a line's places: blank is no limit, a whole number of one or more is kept, anything else is never sent", () => {
  assert.equal(placesOf(""), null);
  assert.equal(placesOf("  "), null);
  assert.equal(placesOf(" 5 "), 5);
  for (const bad of ["5o", "0", "2.5", "-1", "five"]) assert.equal(placesOf(bad), undefined, bad);
});

test("the verification page asks the API with the number in the query: no encoded slash in the path", () => {
  const path = verifyApiPath("IUT/APP/2026/000001", "AB12CD");
  assert.equal(path, "/api/v1/verify/transfer-application?no=IUT%2FAPP%2F2026%2F000001&t=AB12CD");
  assert.equal(path.split("?")[0].includes("%2F"), false);
});

test("a kind no longer asked for (the view's active false) offers no upload", () => {
  const rows = documentChecklist([...KINDS.filter((k) => k.code !== "OTHER"), { code: "OTHER", label: "Any other supporting document", required: false, active: false }],
    [doc("OTHER", "PENDING")], "DRAFT", true);
  const other = rows.find((r) => r.code === "OTHER");
  assert.equal(other?.canUpload, false);
  assert.equal(other?.why, "No longer asked for");
});

test("the Registry's Approve is closed when V763's check would record the transfer on a student already here", () => {
  const v = { state: "RECOMMENDED", kinds: KINDS, documents: KINDS.filter((k) => k.required).map((k) => doc(k.code, "ACCEPTED")), previous: { universityCode: "UNIJOS" } };
  assert.equal(officeActions(v, "academic").find((x) => x.action === "APPROVE")?.enabled, true);
  const here = officeActions({ ...v, transferCheck: { status: "WARNING", action: "RECORD_ON_EXISTING" } }, "academic").find((x) => x.action === "APPROVE");
  assert.equal(here?.enabled, false);
  assert.match(here?.why ?? "", /already on the register/);
  assert.equal(studentHere({ action: "CREATE" }), false);
});

test("the window's applications by state read in the offices' words, in the states' order, never as codes", () => {
  assert.equal(countWords({ WITH_HOD: 2, NOT_RECOMMENDED: 1, CORRECTION_REQUIRED: 3, DRAFT: 0 }),
    "Returned to the applicant · 3; With the Head of Department · 2; Not recommended: for the Registry's decision · 1");
  for (const s of STATES) assert.equal(countWords({ [s]: 1 }), `${officeWords(s)[0]} · 1`, s);
  assert.doesNotMatch(countWords(Object.fromEntries(STATES.map((s) => [s, 1]))), /[A-Z]{2,}_|_[A-Z]/);
  assert.equal(countWords({}), "");
  assert.equal(countWords(undefined), "");
});

// ── the second review's findings ───────────────────────────────────────────────────────────────────────────────────────

test("a kind made required after the department had the application never closes Approve (api-access2-1, screens-brief2-1)", () => {
  // the four required documents accepted, then the identity card made required while the application is RECOMMENDED: the API approves
  // it (admissions.iut_unchecked(app, false)), and nothing lets the applicant upload the card by then
  const kinds: DocumentKind[] = [...KINDS, { code: "STUDENT_ID_CARD", label: "Identity card of your present university", required: true, active: true }];
  const v = { state: "RECOMMENDED", kinds, documents: KINDS.filter((k) => k.required).map((k) => doc(k.code, "ACCEPTED")), previous: { universityCode: "UNIJOS" } };
  const approve = officeActions(v, "academic").find((x) => x.action === "APPROVE");
  assert.equal(approve?.enabled, true, approve?.why ?? "");
  assert.equal(documentsUnchecked(v, false), null);
  // sending to the department still asks every kind required now (the application is returned to its applicant for it)
  assert.match(String(documentsUnchecked(v)), /A required document is missing: Identity card of your present university/);
  assert.equal(officeActions({ ...v, state: "SUBMITTED" }, "academic").find((x) => x.action === "SEND_TO_HOD")?.enabled, false);
  // a document still pending or rejected closes Approve, as the API refuses it
  const pending = { ...v, documents: [...v.documents.slice(1), doc("TRANSCRIPT", "PENDING")] };
  assert.equal(officeActions(pending, "academic").find((x) => x.action === "APPROVE")?.enabled, false);
});

test("a draft withdrawn unpaid owes nothing; a payment that came after it is owed back, not a 'second' payment (screens-brief2-4)", () => {
  // the API gives no fee due outside a draft (iut_view)
  const withdrawn: Pick<IutView, "state" | "fee" | "session"> = { state: "WITHDRAWN", session: "2026/2027", fee: { settled: false, references: [] } };
  assert.equal(feeClosed(withdrawn), true);
  assert.equal(feeWords(withdrawn), "No application fee is taken on a withdrawn application.");
  assert.equal(feeClosed({ state: "DRAFT", fee: { settled: false, due: 5000 } }), false);
  assert.equal(feeClosed({ state: "WITHDRAWN", fee: { settled: true, basis: "PAID" } }), false);
  const late = { reference: "MOAUM-IUTAPP-2026-000009", amount: 5000, confirmedAt: "2026-11-15T09:00:00Z", receiptNo: "RCT-2026-00040", settles: false };
  assert.equal(paymentTitle(late, { fee: { settled: false, references: [late] } }), "A payment owed back to you by the Bursary");
  const first = { ...late, reference: "MOAUM-IUTAPP-2026-000008", settles: true };
  assert.equal(paymentTitle(first, { fee: { settled: true, references: [late, first] } }), "Application fee receipt");
  assert.equal(paymentTitle(late, { fee: { settled: true, references: [late, first] } }), "A second payment: owed back to you by the Bursary");
  // the documents of a closed application say why nothing is uploaded
  assert.ok(documentChecklist(KINDS, [], "WITHDRAWN", false).every((r) => r.why === "The application is withdrawn" && !r.canUpload));
  assert.ok(documentChecklist(KINDS, [], "REJECTED", true).every((r) => r.why === "The application is decided"));
  assert.ok(documentChecklist(KINDS, [], "ADMITTED", true).every((r) => r.why === "The application is decided"));
  assert.ok(documentChecklist(KINDS, [], WITH_REGISTRY, true).every((r) => r.why === "Your application is with the University"));
});

test("the department reads a rejected document by its name, never the Registry's words to the applicant (api-access2-4)", () => {
  const v = forDepartment({ id: "x", applicationNo: "IUT/APP/2026/000001", session: "2026/2027", state: "WITH_HOD", kinds: KINDS,
    documents: [doc("TRANSCRIPT", "ACCEPTED", { note: "Original sighted at the Registry" })],
    superseded: [doc("TRANSCRIPT", "REJECTED", { note: "SECRET: the transcript looks altered", supersededAt: "t2" })],
    history: [
      { at: "t1", action: "DOCUMENT_REJECTED", note: "Academic transcript: SECRET: the transcript looks altered" },
      { at: "t2", action: "DOCUMENT_REJECTED", note: "Academic transcript" },
      { at: "t3", action: "DOCUMENT_ACCEPTED", note: "Academic transcript" },
    ] });
  assert.doesNotMatch(JSON.stringify(v), /SECRET/);
  assert.deepEqual(v.history?.map((h) => h.note ?? null), [null, "Academic transcript", "Academic transcript"]);
  assert.equal(v.documents?.[0].note, "Original sighted at the Registry");
  assert.equal(v.superseded?.[0].status, "REJECTED");
});

test("a payment owed back and given back by the refund desk (db-money2-1, api-access2-2)", () => {
  assert.equal(refundWords({ amount: 5000, refunded: 0, owedBack: true }), null);
  assert.equal(refundWords({ amount: 5000, refunded: 2000, owedBack: true }), "₦2,000 refunded; ₦3,000 still owed back");
  assert.equal(refundWords({ amount: 5000, refunded: "5000.00", owedBack: false }), "Refunded ₦5,000");
  const line = paymentLine({ reference: "MOAUM-IUTAPP-2026-000001", amount: 5000, state: "PAID", owedBack: false, refunded: 5000, settles: false }, 0);
  assert.equal(line.length, PAYMENT_HEAD.length);
  assert.equal(line[PAYMENT_HEAD.indexOf("Refunded")], 5000);
  assert.equal(line[PAYMENT_HEAD.indexOf("Owed back")], "");
});

// ── the third review (round 3) ──────────────────────────────────────────────────────────────────────────────────────────

test("a payment the refund desk gave back reads so on the portal and on the Registry's desk, never still owed (screens-brief3-2)", () => {
  const first = { reference: "MOAUM-IUTAPP-2026-000008", amount: 5000, confirmedAt: "2026-11-15T09:00:00Z", receiptNo: "RCT-2026-00039", settles: true, refunded: 0 };
  const late = { reference: "MOAUM-IUTAPP-2026-000009", amount: 5000, confirmedAt: "2026-11-15T10:00:00Z", receiptNo: "RCT-2026-00040", settles: false, refunded: "5000.00" };
  const part = { ...late, refunded: 2000 };
  const owed = { ...late, refunded: 0 };
  const paid = { fee: { settled: true, references: [late, first] } };
  assert.equal(paymentTitle(late, paid), "A second payment: refunded to you by the Bursary");
  assert.equal(paymentTitle(part, { fee: { settled: true, references: [part, first] } }), "A second payment: ₦2,000 refunded to you, ₦3,000 still owed back by the Bursary");
  assert.equal(paymentTitle(owed, { fee: { settled: true, references: [owed, first] } }), "A second payment: owed back to you by the Bursary");
  assert.equal(paymentTitle(late, { fee: { settled: false, references: [late] } }), "A payment: refunded to you by the Bursary");
  assert.equal(paymentTitle(first, paid), "Application fee receipt");
  // the Registry's table: the settling payment, one owed back, one given back in part, one given back whole, one not paid
  assert.deepEqual(referencePill(first), ["Settles the fee", "ok"]);
  assert.deepEqual(referencePill(owed), ["Owed back", "bad"]);
  assert.deepEqual(referencePill(part), ["₦3,000 still owed back", "bad"]);
  assert.deepEqual(referencePill(late), ["Refunded", "grey"]);
  assert.equal(referencePill({ amount: 5000, settles: false, confirmedAt: null }), null);
  assert.deepEqual([first, owed, part, late].map(stillOwedBack), [0, 5000, 3000, 0]);
});

test("the Registry's desk reads the fee in its own words, never the applicant's (screens-brief3-5)", () => {
  const draft = { state: "DRAFT", session: "2026/2027", fee: { settled: false, due: 5000, references: [] } };
  assert.equal(officeFeeWords(draft), "₦5,000, not yet paid.");
  assert.deepEqual(officeFeePill(draft), ["Not paid", "warn"]);
  const restated = { state: "DRAFT", session: "2026/2027", fee: { settled: false, due: 0, references: [] } };
  assert.equal(officeFeeWords(restated), "No fee is due; the applicant has not yet confirmed it on the portal.");
  assert.deepEqual(officeFeePill(restated), ["None due", "info"]);
  const withdrawn = { state: "WITHDRAWN", session: "2026/2027", fee: { settled: false, references: [] } };
  assert.equal(officeFeeWords(withdrawn), "None taken: withdrawn before the fee was paid.");
  assert.deepEqual(officeFeePill(withdrawn), ["Not taken", "grey"]);
  assert.equal(officeFeeWords({ ...withdrawn, state: "REJECTED" }), "None taken: the application ended before the fee was paid.");
  assert.equal(officeFeeWords({ session: "2026/2027", state: "SUBMITTED", fee: { settled: true, basis: "NONE_DUE" } }), "No application fee was due for 2026/2027.");
  const settled = { state: "SUBMITTED", fee: { settled: true, basis: "PAID", references: [{ reference: "MOAUM-IUTAPP-2026-000004", amount: 5000, confirmedAt: "2026-11-15T09:00:00Z",
    receiptNo: "RCT-2026-00031", settles: true }] } };
  assert.equal(officeFeeWords(settled), "Paid ₦5,000 on 15 November 2026, receipt RCT-2026-00031.");
  assert.deepEqual(officeFeePill(settled), ["Paid", "ok"]);
  // nothing of the applicant's own instructions reaches the desk
  for (const v of [draft, restated, withdrawn, settled]) assert.doesNotMatch(officeFeeWords(v), /your|below|upload/i);
});

test("the admitted applicant's password opens the student door only until its first sign-in there (screens-brief3-3)", () => {
  const v = { applied: { programmeName: "B.Sc. Biochemistry" }, session: "2026/2027", student: { admissionNo: "MOAUM/ADM/26/000123", level: 200, portalOpened: false } };
  assert.match(applicantWords("ADMITTED", v).words, /Sign in as a student with it and this password\.$/);
  assert.match(applicantWords("ADMITTED", { ...v, student: { ...v.student, portalOpened: true } }).words, /Sign in as a student with it and your student portal's own password\.$/);
});

test("the Registry is told how to honour a withdrawal asked for after its approval (screens-brief3-4)", () => {
  assert.deepEqual(officeActions({ state: "APPROVED", kinds: KINDS, documents: [] }, "registrar"), []);
  const words = officeGuidance({ state: "APPROVED" }) ?? "";
  assert.equal(words, WITHDRAW_WHEN_APPROVED);
  assert.match(words, /ask the deciding officer to reject the transfer on Inter-University Transfer/);
  assert.match(words, /reject it here with the applicant's request as the reason/);
  assert.match(officeGuidance({ state: "NOT_RECOMMENDED" }) ?? "", /approval needs the department's recommendation and level/);
  for (const s of ["SUBMITTED", "CORRECTION_REQUIRED", "WITH_HOD", "RECOMMENDED", "ADMITTED", "REJECTED", "WITHDRAWN"]) assert.equal(officeGuidance({ state: s }), null, s);
});

test("the Registry ends a draft made under another person's JAMB number (db-money3-1)", () => {
  const draft = { state: "DRAFT", kinds: KINDS, documents: [] };
  const acts = officeActions(draft, "academic");
  assert.deepEqual(acts.map((a) => [a.action, a.enabled, a.note, a.noteMin]), [["REJECT", true, "required", 10]]);
  assert.match(acts[0].noteLabel, /account that made the draft reads/);
  assert.deepEqual(officeActions(draft, "records"), []);
  assert.match(officeGuidance(draft) ?? "", /another person's JAMB number/);
});

test("a line on a programme archived since offers nothing, and a window set open on none reads closed (db-money3-3, screens-brief3-1)", () => {
  assert.deepEqual(lineWords({ accepting: true, programmeInUse: false }), ["Programme archived: not offered", "warn"]);
  assert.deepEqual(lineWords({ accepting: true, programmeInUse: true }), ["Accepting", "ok"]);
  assert.deepEqual(lineWords({ accepting: false }), ["Closed to new", "grey"]);
  const lines = [{ accepting: true, programmeInUse: false }, { accepting: false, programmeInUse: true }, { accepting: true, programmeInUse: true }];
  assert.equal(offeredLines(lines), 1);
  assert.equal(offeredLines([{ accepting: true, programmeInUse: true, offered: false }]), 0);
  assert.match(windowAlert({ state: "OPEN", offered: 0 }) ?? "", /read it as closed/);
  assert.match(windowAlert({ state: "OPEN", lines: [lines[0], lines[1]] }) ?? "", /set open, but no programme in use/);
  assert.equal(windowAlert({ state: "OPEN", offered: 1 }), null);
  assert.equal(windowAlert({ state: "CLOSED", offered: 0 }), null);
});

// ── the fourth review (round 4) ─────────────────────────────────────────────────────────────────────────────────────────

test("a line whose level the programme no longer has offers nothing, and says why (db-money4-2)", () => {
  const gone = { accepting: true, programmeInUse: true, levelInUse: false };
  assert.deepEqual(lineWords(gone), ["No longer a level of the programme: not offered", "warn"]);
  assert.equal(lineGone(gone), true);
  assert.equal(lineGone({ programmeInUse: true, levelInUse: true }), false);
  assert.equal(offeredLines([gone, { accepting: true, programmeInUse: true, levelInUse: true }]), 1);
  assert.equal(offeredLines([gone]), 0);
  assert.match(windowAlert({ state: "OPEN", lines: [gone] }) ?? "", /a level the programme no longer has/);
  // the Head of Department's Accept with no level left to offer says why, and what to do
  assert.match(NO_LEVEL_TO_RECOMMEND, /ask the Academic Office to add one, or decline/);
});

test("Approve is closed while V763's check refuses the transfer, the university first when it is not on the list (api-screens4-3)", () => {
  const v = { state: "RECOMMENDED", kinds: KINDS, documents: KINDS.filter((k) => k.required).map((k) => doc(k.code, "ACCEPTED")), previous: { universityCode: "UNIJOS" } };
  const approve = (over: object) => officeActions({ ...v, ...over }, "academic").find((x) => x.action === "APPROVE");
  const archived = approve({ transferCheck: { status: "INVALID", problems: [{ code: "TARGET_ARCHIVED", text: "B.Sc. Biochemistry is archived" }] } });
  assert.equal(archived?.enabled, false);
  assert.equal(archived?.why, "The transfer check refuses this transfer: B.Sc. Biochemistry is archived");
  const pending = approve({ transferCheck: { status: "INVALID", problems: [{ code: "TRANSFER_PENDING" }] } });
  assert.equal(pending?.enabled, false);
  assert.match(pending?.why ?? "", /TRANSFER_PENDING/);
  // the university not on the list: its own reason first, as the API refuses it first (IUT_UNIVERSITY_NOT_LISTED)
  const named = approve({ previous: { universityNamed: "Kampala International University" },
    transferCheck: { status: "INVALID", problems: [{ code: "UNIVERSITY_UNKNOWN", text: "The university is not on the list" }] } });
  assert.match(named?.why ?? "", /^Set the university from the list first: Kampala International University is not on it/);
  // a check that only warns, or passes, leaves it open
  assert.equal(approve({ transferCheck: { status: "WARNING", warnings: [{ code: "NAME_DIFFERS" }] } })?.enabled, true);
  assert.equal(approve({ transferCheck: { status: "VALID" } })?.enabled, true);
  assert.equal(checkRefusal(null), null);
  assert.equal(checkRefusal({ status: "INVALID" }), "The transfer check refuses this transfer");
});

test("a draft is ended only when it holds another person's number, and a paid one is warned of (api-screens4-4)", () => {
  const words = officeGuidance({ state: "DRAFT" }) ?? "";
  assert.match(words, /another person's JAMB number/);
  assert.match(words, /never because it is unfinished/);
  assert.doesNotMatch(words, /or one left unfinished/);
  const reject = (fee: object | undefined) => officeActions({ state: "DRAFT", kinds: KINDS, documents: [], ...(fee ? { fee } : {}) }, "registrar")[0];
  assert.equal(reject({ settled: true, basis: "PAID" }).warning, PAID_DRAFT_ENDED);
  assert.equal(reject({ settled: true, basis: "PAID" }).enabled, true);
  assert.match(PAID_DRAFT_ENDED, /not refunded/);
  assert.match(PAID_DRAFT_ENDED, /cannot apply again in this window/);
  // unpaid, or nothing was due: nothing is lost
  assert.equal(reject({ settled: false, due: 5000 }).warning ?? null, null);
  assert.equal(reject({ settled: true, basis: "NONE_DUE" }).warning ?? null, null);
  assert.equal(reject(undefined).warning ?? null, null);
});
