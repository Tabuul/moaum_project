import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { MENUS } from "./menus.ts";
import {
  BLOOD_GROUPS, COMPLETION_READERS, bloodGroupOf, canSaveBloodGroup, codeOf, completionTab, completionTabs, contactPromptBody, contactPromptPlan, countsOf, dashboardPrompts,
  describeRecord, emailOutcome, emailProblem, enhancementSteps, noticesAwaitEmail, NOTICES_AWAIT_EMAIL,
  faceWords, field, flagWords, missingItems, pageOf, photoFileProblem, photoStateWord, qualityWord, staffEmailWord, staffPhotoWord, staffRowOf,
  studentRowOf, submissionOf, bloodWord, choicesOf, STAFF_COUNTS, STUDENT_COUNTS, PHOTO_MAX_BYTES,
} from "./identity.ts";
import { OFFICE_HOME, homePaths, isHomePath, officeHome } from "./home-routes.ts";

test("the eight blood groups, and a value offered only when it is exactly one of them (V749)", () => {
  assert.deepEqual([...BLOOD_GROUPS], ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]);
  assert.equal(bloodGroupOf(" ab+ "), "AB+");
  assert.equal(bloodGroupOf("O positive"), "");
  assert.equal(bloodGroupOf(null), "");
  // SAVE BLOOD GROUP waits on a group and the confirmation both
  assert.equal(canSaveBloodGroup("", true), false);
  assert.equal(canSaveBloodGroup("O+", false), false);
  assert.equal(canSaveBloodGroup("O+", true), true);
  assert.equal(canSaveBloodGroup("O positive", true), false);
});

test("the dashboard is the acting office's home: '/', or its own desk, or the student's two", () => {
  assert.equal(officeHome("hrm"), "/");
  assert.equal(officeHome(null), "/");
  assert.equal(officeHome("library"), "/credentials/idcards");
  assert.equal(officeHome("admin"), "/admin");
  assert.deepEqual(homePaths("student"), ["/student", "/college/student"]);
  assert.equal(isHomePath("hrm", "/"), true);
  assert.equal(isHomePath("hrm", "/me/identity"), false);
  assert.equal(isHomePath("library", "/credentials/idcards"), true);
  assert.equal(isHomePath("library", "/credentials/idcards/staff"), false);
  assert.equal(isHomePath("admin", "/"), false);
  assert.equal(isHomePath("student", "/student"), true);
  assert.equal(isHomePath("student", "/student/"), true);
  assert.equal(isHomePath("student", "/college/student"), true);
  assert.equal(isHomePath("student", "/student/fees"), false);
  assert.equal(isHomePath("student", "/"), false);
  assert.equal(isHomePath("hrm", null), false);
  // the Dean of Student Affairs lands on the hostel dashboard, and is asked there, not on the general dashboard at "/"
  assert.equal(officeHome("dsa"), "/hostel");
  assert.equal(isHomePath("dsa", "/hostel"), true);
  assert.equal(isHomePath("dsa", "/hostel/import"), false);
  assert.equal(isHomePath("dsa", "/"), false);
  // every desk named is a path, never the dashboard itself
  for (const [o, p] of Object.entries(OFFICE_HOME)) assert.ok(p.startsWith("/") && p !== "/", o);
});

test("the student is asked on the dashboard only, from iam/me's bloodGroupPrompt", () => {
  const me = { activeOffice: "student", bloodGroupPrompt: { current: "B+" } };
  assert.deepEqual(dashboardPrompts(me, "/student"), { blood: { kind: "STUDENT", current: "B+" }, missing: [] });
  assert.deepEqual(dashboardPrompts(me, "/college/student"), { blood: { kind: "STUDENT", current: "B+" }, missing: [] });
  assert.deepEqual(dashboardPrompts(me, "/student/fees"), { blood: null, missing: [] });
  assert.deepEqual(dashboardPrompts({ activeOffice: "student", bloodGroupPrompt: null }, "/student"), { blood: null, missing: [] });
  assert.deepEqual(dashboardPrompts({ activeOffice: "student", bloodGroupPrompt: {} }, "/student").blood, { kind: "STUDENT", current: null });
  assert.deepEqual(dashboardPrompts(null, "/student"), { blood: null, missing: [] });
});

test("a member of staff: the blood-group modal while not confirmed, the panel while anything is missing", () => {
  const p = {
    staff: true, complete: false,
    photo: { present: true, enhanced: false, pendingSubmission: null },
    email: { value: "a.b@moaum.edu.ng", verified: false, pending: null },
    bloodGroup: { value: null, confirmed: false },
  };
  const got = dashboardPrompts({ activeOffice: "hrm", identityPrompt: p }, "/");
  assert.deepEqual(got.blood, { kind: "STAFF", current: null });
  assert.deepEqual(got.missing.map((m) => m.key), ["PHOTO", "EMAIL", "BLOOD"]);
  assert.match(got.missing[0].detail, /not checked and enhanced/);
  assert.match(got.missing[1].detail, /a\.b@moaum\.edu\.ng has not been verified/);
  // a confirmed blood group: no modal, the panel for the rest
  const confirmed = dashboardPrompts({ activeOffice: "hrm", identityPrompt: { ...p, bloodGroup: { value: "O+", confirmed: true } } }, "/");
  assert.equal(confirmed.blood, null);
  assert.deepEqual(confirmed.missing.map((m) => m.key), ["PHOTO", "EMAIL"]);
  // not on another screen, not for a desk office away from its desk, not once complete, not for a person not in service
  assert.deepEqual(dashboardPrompts({ activeOffice: "hrm", identityPrompt: p }, "/me/identity"), { blood: null, missing: [] });
  assert.deepEqual(dashboardPrompts({ activeOffice: "library", identityPrompt: p }, "/"), { blood: null, missing: [] });
  assert.equal(dashboardPrompts({ activeOffice: "library", identityPrompt: p }, "/credentials/idcards").missing.length, 3);
  assert.deepEqual(dashboardPrompts({ activeOffice: "hrm", identityPrompt: { ...p, complete: true } }, "/"), { blood: null, missing: [] });
  assert.deepEqual(dashboardPrompts({ activeOffice: "hrm", identityPrompt: { ...p, staff: false } }, "/"), { blood: null, missing: [] });
  assert.deepEqual(dashboardPrompts({ activeOffice: "applicant", identityPrompt: p }, "/applicant"), { blood: null, missing: [] });
});

test("the notices say that mail to an address not yet verified is not listed (V749, platform.person_notices)", () => {
  // the state read (GET /staff/identity, or iam/me's identityPrompt): an address on record, or a code sent to a new one, not verified
  assert.equal(noticesAwaitEmail({ staff: true, email: { value: "a.b@moaum.edu.ng", verified: false, pending: null } }), true);
  assert.equal(noticesAwaitEmail({ email: { value: "a.b@moaum.edu.ng", verified: false, pending: "c.d@moaum.edu.ng" } }), true);
  // no address on record, or a state that names none: nothing sent to an address is listed either
  assert.equal(noticesAwaitEmail({ staff: false, email: { value: null, verified: false } }), true);
  assert.equal(noticesAwaitEmail({ staff: true, email: null }), true);
  // verified: the list holds the mail too, and says nothing
  assert.equal(noticesAwaitEmail({ email: { value: "a.b@moaum.edu.ng", verified: true } }), false);
  // no state read — iam/me sends no identityPrompt once everything is done, or GET /staff/identity was refused: nothing guessed
  assert.equal(noticesAwaitEmail(null), false);
  assert.equal(noticesAwaitEmail(undefined), false);
  // the words both screens say, and the way to verify beside them
  assert.equal(NOTICES_AWAIT_EMAIL, "Messages sent to your e-mail address appear here once you verify it at My identity");
  const here = import.meta.dirname ?? ".";
  const page = readFileSync(join(here, "../app/me/notices/page.tsx"), "utf8");
  const screen = readFileSync(join(here, "../app/me/notices/Notices.tsx"), "utf8");
  const lecturer = readFileSync(join(here, "../app/dashboards/Lecturer.tsx"), "utf8");
  assert.match(page, /\/api\/v1\/staff\/identity/);
  assert.match(page, /awaitEmail=\{identity\.ok && noticesAwaitEmail\(identity\.data\)\}/);
  assert.match(screen, /title=\{NOTICES_AWAIT_EMAIL\}/);
  assert.match(screen, /href="\/me\/identity#email"/);
  assert.match(lecturer, /noticesAwaitEmail\(me\?\.identityPrompt\)/);
  assert.match(lecturer, /\{NOTICES_AWAIT_EMAIL\}/);
  assert.match(lecturer, /href="\/me\/identity#email"/);
  // the screen no longer promises the whole outbox, and names the work notices it lists
  assert.equal(screen.includes("Nothing has been sent to you yet"), false);
  assert.equal(screen.includes("To the address on your record"), false);
  for (const kind of ["deferment", "report_snapshot", "ticket", "offering", "score_sheet", "transfer", "clearance_document", "putme_score_export", "clearance_chase"]) {
    assert.match(screen, new RegExp(`\\b${kind}: "`), kind);
  }
});

test("what is missing says where each stands", () => {
  assert.deepEqual(missingItems(null), []);
  const pending = missingItems({ photo: { enhanced: false, pendingSubmission: "x", pendingState: "PROCESSED" }, email: { verified: false, pending: "n@x.ng" }, bloodGroup: { value: "o+", confirmed: false } });
  assert.match(pending[0].detail, /waiting for you to look at it and accept it/);
  assert.match(pending[1].detail, /A code was sent to n@x\.ng/);
  assert.match(pending[2].detail, /O\+ is on record but you have not confirmed it/);
  assert.match(missingItems({ photo: { pendingSubmission: "x", pendingState: "FAILED" } })[0].detail, /could not be enhanced/);
  assert.match(missingItems({ photo: { present: false } })[0].detail, /No passport photograph/);
  assert.deepEqual(missingItems({ photo: { enhanced: true }, email: { verified: true }, bloodGroup: { confirmed: true } }), []);
});

test("a photograph is a JPEG or PNG of up to 6 MB, and the verdict and flags read in words", () => {
  assert.equal(photoFileProblem({ type: "image/jpeg", size: 1000 }), null);
  assert.equal(photoFileProblem({ type: "image/png", size: PHOTO_MAX_BYTES }), null);
  assert.match(photoFileProblem({ type: "image/heic", size: 1000 }) ?? "", /JPEG or PNG/);
  assert.match(photoFileProblem({ type: "image/jpeg", size: PHOTO_MAX_BYTES + 1 }) ?? "", /up to 6 MB/);
  assert.match(photoFileProblem({ type: "image/jpeg", size: 0 }) ?? "", /empty/);
  assert.equal(qualityWord("GOOD").kind, "ok");
  assert.equal(qualityWord("FAIR").kind, "warn");
  assert.equal(qualityWord("REPLACE").kind, "bad");
  assert.equal(qualityWord(null).label, "Not assessed");
  assert.deepEqual(flagWords(["TOO_DARK", "SOMETHING_NEW", 3, ""]), ["Too dark — take it in better light, facing a window", "Something new"]);
  // the pipeline's colour-cast advice (a backdrop tinted all over: white balance leaves a strong cast alone, so the holder is told) —
  // the wall's paint as much as the light, so the words never blame daylight that is already there (PhotoEnhancer.FLAGS, the same words)
  assert.deepEqual(flagWords(["COLOUR_CAST"]), ["The background or the light is tinted — a white or light grey wall in daylight is best"]);
  assert.deepEqual(flagWords(null), []);
  assert.deepEqual(photoStateWord("FAILED"), ["Could not be enhanced", "bad"]);
  assert.deepEqual(photoStateWord("ODD_STATE"), ["Odd state", "grey"]);
});

test("an upload as the server answers it, its measurements and its steps", () => {
  assert.equal(submissionOf(null), null);
  assert.equal(submissionOf({ state: "PROCESSED" }), null);
  const s = submissionOf({ id: "u1", state: "FAILED", quality: null, assessment: { width: 4000, flags: ["BLURRY"] }, enhancement: [{ step: "auto_levels" }], error: "  " });
  assert.ok(s);
  assert.equal(s.state, "FAILED");
  assert.equal(s.error, null);
  assert.deepEqual(s.enhancement, { steps: [{ step: "auto_levels" }] });
  assert.deepEqual(describeRecord({ width: 4000, meanLuma: 61.234, flags: ["TOO_DARK"], face: "x", background: { uniformity: 0.8 }, orientationCorrected: true, note: null }),
    [["Width (pixels)", "4,000"], ["Brightness (mean, 0–255)", "61.23"], ["Background · uniformity", "0.8"], ["Turned upright", "Yes"]]);
  assert.deepEqual(enhancementSteps({ steps: ["Cropped to 4:5", { step: "white_balance", gainR: 1.1, applied: true }, { description: "Mild denoise", applied: false }, 7] }), [
    { title: "Cropped to 4:5", detail: "", applied: true },
    { title: "White balance", detail: "gain r 1.1", applied: true },
    { title: "Mild denoise", detail: "", applied: false },
  ]);
  assert.deepEqual(enhancementSteps(null), []);
  // PhotoEnhancer's own steps: named in words, the figures kept (the orientation's operation words among them)
  assert.deepEqual(enhancementSteps({ method: "Global corrections only", steps: [
    { step: "orientation", applied: true, exif: 6, operation: "rotated 90° clockwise" },
    { step: "whiteBalance", applied: false, method: "grey world", reason: "too few pixels" },
  ] }), [
    { title: "Turned upright (from the camera's orientation mark)", detail: "exif 6; operation rotated 90° clockwise", applied: true },
    { title: "Colour balance (from the near-neutral pixels)", detail: "method grey world; reason too few pixels", applied: false },
  ]);
  // the readings the pipeline added: the highlights, the centre washed out, the background's tint
  assert.deepEqual(describeRecord({ highlights: 251, centreClippedPct: 0.4, background: { tint: 0.031 } }),
    [["Highlights (0–255)", "251"], ["Washed out at the centre (%)", "0.4"], ["Background · tint", "0.03"]]);
  assert.deepEqual(describeRecord({ method: "Global corrections only", steps: [], before: { meanLuma: 40.5 } }),
    [["Method", "Global corrections only"], ["Before · brightness (mean, 0–255)", "40.5"]]);
  assert.match(faceWords({}), /no face detector/);
  assert.equal(faceWords({ face: "not assessed (no face detector on the server)" }), "not assessed (no face detector on the server)");
});

test("the e-mail: the form checked before a code is asked, and every answer to a code in words", () => {
  assert.equal(emailProblem("a.b@moaum.edu.ng"), null);
  assert.match(emailProblem("") ?? "", /Enter/);
  assert.match(emailProblem("not an address") ?? "", /not an e-mail/);
  assert.match(emailProblem("A.B@moaum.edu.ng ", { value: "a.b@moaum.edu.ng", verified: true }) ?? "", /already your verified/);
  assert.equal(emailProblem("a.b@moaum.edu.ng", { value: "a.b@moaum.edu.ng", verified: false }), null);
  assert.equal(emailOutcome("VERIFIED").kind, "ok");
  for (const o of ["WRONG", "EXPIRED", "TAKEN"]) assert.equal(emailOutcome(o).kind, "bad");
  assert.match(emailOutcome(undefined).title, /could not be checked/);
  assert.equal(codeOf("12 34-56 78"), "123456");
});

test("the report's counts and pages read whichever way the server names them", () => {
  assert.equal(field({ blood_confirmed: 3 }, "blood_confirmed"), 3);
  assert.equal(field({ bloodConfirmed: 4 }, "blood_confirmed"), 4);
  const c = countsOf({ total: "10", blood_confirmed: 4, needsUpdate: 6 }, STUDENT_COUNTS);
  assert.equal(c.total, 10);
  assert.equal(c.blood_confirmed, 4);
  assert.equal(c.needs_update, 6);
  assert.equal(c.with_photo, 0);
  assert.equal(countsOf({ counts: { no_sign_in: 7 } }, STAFF_COUNTS).no_sign_in, 7);
  assert.equal(countsOf([{ total: 2 }], STAFF_COUNTS).total, 2);
  const pg = pageOf({ rows: [{ student_id: "s1", matric_no: "M/1", name: "A B", level: 200, blood_group: "O+", blood_confirmed: true, has_photo: false, complete: false, total: 41 }] },
    studentRowOf, { page: 2, size: 20 });
  assert.equal(pg.total, 41);
  assert.equal(pg.page, 2);
  // the API counts its pages from 0 and holds a page to 200 rows: the screen's page is the one it asked for, the size the server's
  const api = pageOf({ rows: [], total: 900, page: 1, size: 200 }, studentRowOf, { page: 2, size: 500 });
  assert.deepEqual([api.page, api.size, api.total], [2, 200, 900]);
  assert.deepEqual([pg.rows[0].studentId, pg.rows[0].level, pg.rows[0].bloodConfirmed, pg.rows[0].hasPhoto], ["s1", 200, true, false]);
  const bare = pageOf([{ personId: "p1", staffNumber: "SS/1", photoEnhanced: true, emailVerified: false, emailPending: "x@y.ng", total: 3 }], staffRowOf, { page: 1, size: 50 });
  assert.equal(bare.total, 3);
  assert.deepEqual([bare.rows[0].personId, bare.rows[0].photoEnhanced, bare.rows[0].emailPending], ["p1", true, "x@y.ng"]);
  assert.deepEqual(pageOf({ rows: [], total: 0 }, studentRowOf, { page: 1, size: 50 }).rows, []);
  assert.deepEqual(choicesOf({ units: [{ code: "ICT", name: "Directorate of ICT", faculty_code: null }, { code: "", name: "x" }, "junk"] }, "units"),
    [{ code: "ICT", name: "Directorate of ICT", facultyCode: null, deptCode: null }]);
  assert.deepEqual(choicesOf({ programmes: [{ code: "CSC", name: "Computer Science", dept_code: "CSC", faculty_code: "SCI" }] }, "programmes"),
    [{ code: "CSC", name: "Computer Science", facultyCode: "SCI", deptCode: "CSC" }]);
  assert.deepEqual(choicesOf(null, "units"), []);
  assert.deepEqual(bloodWord(null, false), ["None", "bad"]);
  assert.deepEqual(bloodWord("A+", false), ["A+ · not confirmed", "warn"]);
  assert.deepEqual(staffPhotoWord(true, false), ["On file, not enhanced", "warn"]);
  assert.deepEqual(staffEmailWord("x@y.ng", false, "z@y.ng"), ["Code sent to z@y.ng", "warn"]);
});

test("the contact banner: a member of staff gives the phone, and the e-mail is verified at My identity (V749)", () => {
  // a student keeps both boxes
  assert.deepEqual(contactPromptPlan({ kind: "student", email: null, email_ok: false, phone_ok: false }), { emailBox: true, phoneBox: true, emailAtIdentity: false });
  // a member of staff with neither: the phone box, and My identity for the e-mail
  assert.deepEqual(contactPromptPlan({ kind: "person", email: null, email_ok: false, phone_ok: false }), { emailBox: false, phoneBox: true, emailAtIdentity: true });
  // a usable address and no phone: the phone alone
  assert.deepEqual(contactPromptPlan({ kind: "person", email: "a.b@moaum.edu.ng", email_ok: true, phone_ok: false }), { emailBox: false, phoneBox: true, emailAtIdentity: false });
  // a phone and no usable address: nothing to type here, only the way to My identity
  assert.deepEqual(contactPromptPlan({ kind: "person", email: null, email_ok: false, phone_ok: true }), { emailBox: false, phoneBox: false, emailAtIdentity: true });
});

test("the contact banner's save: a student's own e-mail and phone; a member of staff's phone and never an e-mail (V749)", () => {
  assert.deepEqual(contactPromptBody("student", " s@x.ng ", " 08031234567 "), { email: "s@x.ng", phone: "08031234567" });
  assert.deepEqual(contactPromptBody("student", "  ", "08031234567"), { email: null, phone: "08031234567" });
  // the address the banner was drawn with never goes back: one verified at My identity in another tab, or corrected by an office,
  // since then would have the phone refused (STAFF_EMAIL_VERIFY); the API keeps the address on record as it stands when saved
  assert.deepEqual(contactPromptBody("person", "old.address@moaum.edu.ng", "08031234567"), { email: null, phone: "08031234567" });
  assert.deepEqual(contactPromptBody("person", "", " 0803 123 4567 "), { email: null, phone: "0803 123 4567" });
  // the banner sends what contactPromptBody gives, for both kinds
  const here = import.meta.dirname ?? ".";
  const banner = readFileSync(join(here, "../components/ContactPrompt.tsx"), "utf8");
  assert.match(banner, /const body = contactPromptBody\(p\.kind, email, phone\);/);
  assert.equal(banner.includes("keptEmail"), false);
});

test("the profile shows the record's e-mail from the profile itself and saves none: the API keeps the address on record (V749)", () => {
  const here = import.meta.dirname ?? ".";
  const page = readFileSync(join(here, "../app/me/profile/page.tsx"), "utf8");
  const screen = readFileSync(join(here, "../app/me/profile/Profile.tsx"), "utf8");
  // no second request to fail: GET /api/v1/staff/profile answers the address on record (iam.person.email)
  assert.equal(page.includes("/api/v1/staff/contact"), false);
  // shown read-only, changed at My identity only
  assert.match(screen, /readOnly aria-describedby/);
  assert.match(screen, /href="\/me\/identity#email"/);
  // the save's body names no e-mail: PUT /api/v1/staff/profile writes the record's address itself, so a page opened before the
  // address changed (verified in another tab, corrected by an office) neither holds back the save nor puts the old address back
  const body = screen.slice(screen.indexOf("const body: Raw = {"), screen.indexOf("for (const [k] of [...OUTPUT, ...ENGAGE]) body[k]"));
  assert.ok(body.length > 0);
  assert.doesNotMatch(body, /\bemail\b/);
  assert.equal(screen.includes("profileEmail"), false);
  // the address shown is the record's as last read (the props), not the form's state from when the page opened: the save's
  // router.refresh() reads it again, so a stale page shows the address on record once saved
  assert.match(screen, /value=\{str\(initial\?\.email\)\} autoComplete="off" readOnly/);
  assert.match(screen, /router\.refresh\(\)/);
});

test("an office's notice is named as one on /me/notices by the mark admissions.tell_office gives it (V749)", () => {
  const here = import.meta.dirname ?? ".";
  const screen = readFileSync(join(here, "../app/me/notices/Notices.tsx"), "utf8");
  assert.match(screen, /n\.about_kind === "application" && n\.template_key === "OFFICE_TELL" \? "Office notice"/);
  const db = join(here, "../../../db");
  const sql = readFileSync(join(db, readdirSync(db).find((f) => f.startsWith("V749__")) ?? ""), "utf8");
  const tell = sql.slice(sql.indexOf("CREATE OR REPLACE FUNCTION admissions.tell_office"), sql.indexOf("COMMENT ON FUNCTION admissions.tell_office"));
  assert.match(tell, /'application', p_about, NULL, 'OFFICE_TELL'/);
});

test("the completion report offers each office only the tabs it reads (V749)", () => {
  assert.deepEqual(completionTabs("ict"), ["students", "staff"]);
  assert.deepEqual(completionTabs("records"), ["students"]);
  assert.deepEqual(completionTabs("dsa"), ["students"]);
  assert.deepEqual(completionTabs("hrm"), ["staff"]);
  assert.deepEqual(completionTabs("bursary"), []);
  assert.deepEqual(completionTabs(null), []);
  // the tab asked for when it is readable, else the first readable one
  assert.equal(completionTab("staff", "registrar"), "staff");
  assert.equal(completionTab(null, "registrar"), "students");
  assert.equal(completionTab("staff", "records"), "students");
  assert.equal(completionTab("staff", "dsa"), "students");
  assert.equal(completionTab("students", "hrm"), "staff");
  assert.equal(completionTab("", "hrm"), "staff");
  assert.equal(completionTab("junk", "security"), "students");
  // an office that reads neither: the address's tab, and the API says why
  assert.equal(completionTab("staff", "bursary"), "staff");
  assert.equal(completionTab(null, null), "students");
});

test("the completion tabs follow the API's readers, and the menu reaches exactly those offices", () => {
  const here = import.meta.dirname ?? ".";
  const java = readFileSync(join(here, "../../../api/src/main/java/ng/edu/moaum/portal/credentials/IdentityCompletionController.java"), "utf8");
  const readers = (name: string) => {
    const m = java.match(new RegExp(`${name}\\s*=([^;]+);`));
    assert.ok(m, name);
    return [...m[1].matchAll(/'OFFICE_([a-z_]+)'/g)].map((x) => x[1]).sort();
  };
  assert.deepEqual(readers("STUDENT_READERS"), [...COMPLETION_READERS.students].sort());
  assert.deepEqual(readers("STAFF_READERS"), [...COMPLETION_READERS.staff].sort());
  const withMenu = Object.entries(MENUS).filter(([, m]) => JSON.stringify(m).includes("\"t/identitycompletion\"")).map(([o]) => o).sort();
  assert.deepEqual(withMenu, [...new Set([...COMPLETION_READERS.students, ...COMPLETION_READERS.staff])].sort());
});
