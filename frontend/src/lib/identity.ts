/**
 * V749: identity information — a student's and a member of staff's blood group, the staff photograph (checked and enhanced on the
 * server, saved as the card photograph only once accepted) and the staff e-mail (verified by a code sent to the new address). The
 * server decides everything (credentials.confirm_my_blood_group, iam.email_code_issue/check, hrm.accept_my_staff_photo); this only
 * says it in words, works out what is still missing, and decides on which screen the prompts are shown.
 */
import { isHomePath } from "./home-routes.ts";

export type Kind = "ok" | "warn" | "bad" | "info" | "grey";

/** the eight blood groups the card prints, in the order the University's form lists them */
export const BLOOD_GROUPS = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"] as const;
export type BloodGroup = (typeof BLOOD_GROUPS)[number];

/** a value already on the record, offered in the form only when it is exactly one of the eight (never a guess from free text:
 *  the person chooses, and confirms) */
export function bloodGroupOf(v: string | null | undefined): BloodGroup | "" {
  const g = (v ?? "").trim().toUpperCase();
  return (BLOOD_GROUPS as readonly string[]).includes(g) ? (g as BloodGroup) : "";
}

/** SAVE BLOOD GROUP waits on both: a group chosen, and the accuracy confirmed */
export function canSaveBloodGroup(group: string, confirmed: boolean): boolean {
  return bloodGroupOf(group) !== "" && confirmed;
}

// ── the staff identity state (iam.staff_identity_state, GET /api/v1/staff/identity; iam/me's identityPrompt) ─────────────────────

export interface StaffIdentityState {
  /** in service by V698's reading (a staff number, not ended, an office today or an HR record) */
  staff?: boolean;
  photo?: {
    present?: boolean;
    /** the photograph on file came through the enhancement and was accepted */
    enhanced?: boolean;
    contentType?: string | null;
    updatedAt?: string | null;
    /** an upload waiting on the holder: enhanced (PROCESSED) or not (FAILED) */
    pendingSubmission?: string | null;
    pendingState?: string | null;
    pendingQuality?: string | null;
  } | null;
  email?: {
    value?: string | null;
    verified?: boolean;
    verifiedAt?: string | null;
    /** the new address an open code was sent to — the old one stays until it is verified */
    pending?: string | null;
    pendingExpiresAt?: string | null;
  } | null;
  bloodGroup?: { value?: string | null; confirmed?: boolean; confirmedAt?: string | null; source?: string | null } | null;
  complete?: boolean;
}

export type MissingKey = "PHOTO" | "EMAIL" | "BLOOD";
export interface Missing { key: MissingKey; title: string; detail: string }

/** what a member of staff has still to do, in the order the update page lists it */
export function missingItems(s: StaffIdentityState | null | undefined): Missing[] {
  if (!s) return [];
  const out: Missing[] = [];
  const p = s.photo ?? {};
  if (!p.enhanced) {
    out.push({
      key: "PHOTO",
      title: "Passport photograph not yet enhanced and accepted",
      detail: p.pendingSubmission
        ? p.pendingState === "FAILED"
          ? "Your last upload could not be enhanced: try the enhancement again, or upload another photograph."
          : "Your enhanced photograph is waiting for you to look at it and accept it."
        : p.present
          ? "The photograph on file was not checked and enhanced for the card: upload it again to have it done."
          : "No passport photograph is on file.",
    });
  }
  const e = s.email ?? {};
  if (!e.verified) {
    out.push({
      key: "EMAIL",
      title: "E-mail address not verified",
      detail: e.pending
        ? `A code was sent to ${e.pending}: enter it to verify the address.`
        : e.value
          ? `${e.value} has not been verified by a code.`
          : "No e-mail address is on record.",
    });
  }
  const b = s.bloodGroup ?? {};
  if (!b.confirmed) {
    out.push({
      key: "BLOOD",
      title: "Blood group not confirmed",
      detail: bloodGroupOf(b.value) ? `${bloodGroupOf(b.value)} is on record but you have not confirmed it.` : "No blood group is on record.",
    });
  }
  return out;
}

// ── the dashboard prompts (Shell) ─────────────────────────────────────────────────────────────────────────────────────────────────

export interface PromptsInput {
  activeOffice: string | null;
  /** a student whose blood group is not confirmed (iam/me): the value on record that is not confirmed, or none */
  bloodGroupPrompt?: { current?: string | null } | null;
  /** a member of staff whose identity information is not complete (iam/me) */
  identityPrompt?: StaffIdentityState | null;
}
export interface Prompts {
  /** the blood-group modal: whose, and the value to start from */
  blood: { kind: "STUDENT" | "STAFF"; current: string | null } | null;
  /** the staff identity panel's lines; none, no panel */
  missing: Missing[];
}

/** what the person's dashboard asks — on the dashboard of the acting office only (lib/home-routes), never on another screen */
export function dashboardPrompts(me: PromptsInput | null | undefined, pathname: string | null | undefined): Prompts {
  const none: Prompts = { blood: null, missing: [] };
  if (!me || !isHomePath(me.activeOffice, pathname)) return none;
  if (me.activeOffice === "student") {
    return me.bloodGroupPrompt ? { blood: { kind: "STUDENT", current: me.bloodGroupPrompt.current ?? null }, missing: [] } : none;
  }
  if (me.activeOffice === "applicant") return none;
  const p = me.identityPrompt;
  // a person not in service (no staff number, ended) can save none of it: the server refuses, so nothing is asked
  if (!p || p.complete || p.staff === false) return none;
  const missing = missingItems(p);
  return {
    blood: p.bloodGroup?.confirmed ? null : { kind: "STAFF", current: p.bloodGroup?.value ?? null },
    missing,
  };
}

// ── a member of staff's own notices (GET /api/v1/me/notices: /me/notices, the Lecturer dashboard) ─────────────────────────────────

/** what the notices screen and the Lecturer dashboard say while the address is not verified, with the way to My identity beside it */
export const NOTICES_AWAIT_EMAIL = "Messages sent to your e-mail address appear here once you verify it at My identity";

/** V749: a member of staff's own notices (platform.person_notices) are those about them, the e-mail sent to the address they verified,
 *  and some notices of their work — mail to an address not yet verified is left out, so an address typed on someone's record never
 *  shows them another person's mail. Until the address is verified the list is shorter, and says so: true when the state read
 *  (GET /api/v1/staff/identity, or iam/me's identityPrompt) shows the address not verified, or none on record; false when it is
 *  verified, or when no state was read (iam/me sends no identityPrompt once everything is done) */
export function noticesAwaitEmail(s: StaffIdentityState | null | undefined): boolean {
  return !!s && s.email?.verified !== true;
}

// ── the photograph ───────────────────────────────────────────────────────────────────────────────────────────────────────────────

/** the largest original the server takes (moaum.photo.max-bytes' default); the proxy buffers 10 MB, and 6 MB is 8 MB as base64 */
export const PHOTO_MAX_BYTES = 6 * 1024 * 1024;
export const PHOTO_TYPES = ["image/jpeg", "image/png"] as const;

/** why a chosen file cannot be sent, or null — the server checks it again, by its bytes */
export function photoFileProblem(f: { type: string; size: number }): string | null {
  if (!(PHOTO_TYPES as readonly string[]).includes(f.type)) return "A photograph is a JPEG or PNG image. A phone's HEIC picture: save it as JPEG first.";
  if (f.size <= 0) return "That file is empty.";
  if (f.size > PHOTO_MAX_BYTES) return "A photograph is up to 6 MB.";
  return null;
}

/** the verdict on an upload */
export const QUALITY: Record<string, { label: string; kind: Kind; words: string }> = {
  GOOD: { label: "Good", kind: "ok", words: "The photograph is fit for the identity card." },
  FAIR: { label: "Fair — usable", kind: "warn", words: "It can go on the card, though a better photograph would print better: see what was found." },
  REPLACE: { label: "Needs replacing", kind: "bad", words: "This photograph cannot be used on the card. Take another and upload it." },
};
export function qualityWord(q: string | null | undefined): { label: string; kind: Kind; words: string } {
  if (!q) return { label: "Not assessed", kind: "grey", words: "" };
  return QUALITY[q] ?? { label: humanise(q), kind: "grey", words: "" };
}

/** what the assessment found, in words a person can act on — a flag not named here (one the server adds later) said in its own
 *  name, never dropped */
export const FLAG_WORDS: Record<string, string> = {
  TOO_DARK: "Too dark — take it in better light, facing a window",
  TOO_BRIGHT: "Too bright — parts are washed out; avoid direct sunlight or a flash",
  LOW_CONTRAST: "Flat and low in contrast",
  BLURRY: "Not sharp — hold the camera still and let it focus on the face",
  LOW_RESOLUTION: "Too small — use a larger photograph (at least 300 × 375 pixels once cropped)",
  LANDSCAPE: "Taken sideways (landscape) — the card's frame is upright, so the sides are cut off",
  BUSY_BACKGROUND: "The background is not plain — a plain, light background prints best",
  // the wall's own paint (cream, peach, a mid blue) reads as a tint as a lamp's light does: the words name both, never the light alone
  COLOUR_CAST: "The background or the light is tinted — a white or light grey wall in daylight is best",
};
export function flagWords(flags: unknown): string[] {
  if (!Array.isArray(flags)) return [];
  return flags.filter((f): f is string => typeof f === "string" && f.trim() !== "").map((f) => FLAG_WORDS[f] ?? humanise(f));
}

/** an upload's state */
export const PHOTO_STATE: Record<string, [string, Kind]> = {
  PROCESSED: ["Enhanced — waiting for you to accept it", "warn"],
  FAILED: ["Could not be enhanced", "bad"],
  ACCEPTED: ["Accepted — your card photograph", "ok"],
  DISCARDED: ["Discarded", "grey"],
  SUPERSEDED: ["Replaced by a later upload", "grey"],
};
export function photoStateWord(s: string | null | undefined): [string, Kind] {
  return (s && PHOTO_STATE[s]) || [s ? humanise(s) : "—", "grey"];
}

/** one upload as the server answered it (POST /photo, /photo/{id}/retry), or as the state names a pending one */
export interface PhotoSubmission {
  id: string;
  state: string;
  quality: string | null;
  assessment: Record<string, unknown> | null;
  enhancement: Record<string, unknown> | null;
  error: string | null;
}
export function submissionOf(raw: unknown): PhotoSubmission | null {
  if (!raw || typeof raw !== "object") return null;
  const o = raw as Record<string, unknown>;
  const id = typeof o.id === "string" ? o.id : typeof o.submissionId === "string" ? o.submissionId : null;
  if (!id) return null;
  const obj = (v: unknown) => (v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : null);
  return {
    id,
    state: typeof o.state === "string" ? o.state : "PROCESSED",
    quality: typeof o.quality === "string" ? o.quality : null,
    assessment: obj(o.assessment),
    enhancement: obj(o.enhancement) ?? (Array.isArray(o.enhancement) ? { steps: o.enhancement } : null),
    error: typeof o.error === "string" && o.error.trim() ? o.error : null,
  };
}

/** the measurements of an assessment (or an enhancement's figures), each a label and a value — the flags, the steps and the
 *  face are said apart */
export function describeRecord(rec: Record<string, unknown> | null | undefined, skip: readonly string[] = []): [string, string][] {
  if (!rec) return [];
  const out: [string, string][] = [];
  const omit = new Set(["flags", "steps", "operations", "face", "quality", ...skip]);
  for (const [k, v] of Object.entries(rec)) {
    if (omit.has(k) || v == null) continue;
    if (v && typeof v === "object" && !Array.isArray(v)) {
      for (const [k2, v2] of Object.entries(v as Record<string, unknown>)) {
        const s = scalar(v2);
        if (s != null) out.push([`${label(k)} · ${label(k2).toLowerCase()}`, s]);
      }
      continue;
    }
    const s = scalar(v);
    if (s != null) out.push([label(k), s]);
  }
  return out;
}

/** the enhancement's steps (PhotoEnhancer) in words: what each does to the whole photograph */
export const STEP_WORDS: Record<string, string> = {
  read: "Photograph read",
  orientation: "Turned upright (from the camera's orientation mark)",
  crop: "Cropped to the card's upright frame (4:5), centred and nearer the top — the face is not detected",
  resize: "Resized to the card's size",
  denoise: "Mild noise reduction",
  whiteBalance: "Colour balance (from the near-neutral pixels)",
  levels: "Light levels widened",
  exposure: "Exposure brought toward the middle (gamma)",
  sharpen: "Sharpened gently (unsharp mask)",
  encode: "Saved as a JPEG",
};

/** what the enhancement did, one line a step: its own words where it gives them, else the step named with its figures */
export function enhancementSteps(enh: Record<string, unknown> | null | undefined): { title: string; detail: string; applied: boolean }[] {
  if (!enh) return [];
  const list = Array.isArray(enh.steps) ? enh.steps : Array.isArray(enh.operations) ? enh.operations : [];
  return list.flatMap((s) => {
    if (typeof s === "string") return s.trim() ? [{ title: s.trim(), detail: "", applied: true }] : [];
    if (!s || typeof s !== "object") return [];
    const o = s as Record<string, unknown>;
    const saidKey = ["description", "summary", "note", "words"].find((k) => typeof o[k] === "string" && (o[k] as string).trim());
    const nameKey = ["step", "name", "op", "operation", "kind"].find((k) => typeof o[k] === "string" && (o[k] as string).trim());
    const said = saidKey ? (o[saidKey] as string).trim() : undefined;
    const named = nameKey ? (o[nameKey] as string).trim() : undefined;
    // the figures: everything but the words used as the title and the applied mark
    const detail = describeRecord(o, [saidKey ?? "", nameKey ?? "", "applied"]).map(([k, v]) => `${k.toLowerCase()} ${v}`).join("; ");
    return [{ title: said ?? (named ? STEP_WORDS[named] ?? humanise(named) : "Step"), detail, applied: o.applied !== false }];
  });
}

/** the assessment's word on the face: the server has no face detector, and says so — never claimed here either */
export function faceWords(assessment: Record<string, unknown> | null | undefined): string {
  const f = assessment?.face;
  if (typeof f === "string" && f.trim()) return f.trim();
  return "Not assessed — the server has no face detector; look at the enhanced photograph yourself before accepting it.";
}

// ── the e-mail ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────

/** why an address cannot be sent a code, or null — the server checks the form again (platform.email_valid), and whether another
 *  person holds it */
export function emailProblem(v: string, current?: { value?: string | null; verified?: boolean } | null): string | null {
  const s = v.trim();
  if (!s) return "Enter the e-mail address.";
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(s)) return "That is not an e-mail address.";
  if (current?.verified && current.value && current.value.trim().toLowerCase() === s.toLowerCase()) return "That is already your verified address.";
  return null;
}

/** the answer to a code entered (iam.email_code_check) */
export const EMAIL_OUTCOME: Record<string, { kind: Kind; title: string; detail: string }> = {
  VERIFIED: { kind: "ok", title: "Your e-mail address is verified", detail: "The University writes to it from now on." },
  WRONG: { kind: "bad", title: "That code is not the one sent", detail: "Check the latest message and try again. After five wrong tries the code stops working." },
  EXPIRED: { kind: "bad", title: "That code has run out", detail: "Codes last 15 minutes and five tries. Send a new code." },
  TAKEN: { kind: "bad", title: "Another member of staff now holds that address", detail: "Use an address of your own. If it is yours, ask ICT to look into it." },
};
export function emailOutcome(o: unknown): { kind: Kind; title: string; detail: string } {
  return (typeof o === "string" && EMAIL_OUTCOME[o]) || { kind: "bad", title: "The code could not be checked", detail: "Try again in a moment." };
}

/** a six-digit code as typed: digits only, at most six */
export function codeOf(v: string): string {
  return v.replace(/\D/g, "").slice(0, 6);
}

/** the V430 "how do we reach you" banner. A student keeps both boxes. A member of staff gives the phone there and nothing else: a
 *  staff e-mail address changes only once a code sent to it comes back (My identity; the API refuses a new one elsewhere with
 *  STAFF_EMAIL_VERIFY), so the banner points to My identity for the e-mail and its save carries none (contactPromptBody). */
export function contactPromptPlan(p: { kind: string; email: string | null; email_ok: boolean; phone_ok: boolean }): {
  /** the e-mail box shown */
  emailBox: boolean;
  /** the phone box (and Save) shown */
  phoneBox: boolean;
  /** "Add your e-mail at My identity" shown */
  emailAtIdentity: boolean;
} {
  if (p.kind === "student") return { emailBox: true, phoneBox: true, emailAtIdentity: false };
  return { emailBox: false, phoneBox: !p.phone_ok, emailAtIdentity: !p.email_ok };
}

/** what the banner's Save sends. A student's own e-mail and phone, as typed. A member of staff's phone and no e-mail: PUT
 *  /api/v1/staff/contact keeps the address on record as it stands when it is saved, so the address the banner was drawn with never
 *  goes back — one verified at My identity in another tab, or corrected by an office, since the page opened would refuse the save
 *  (STAFF_EMAIL_VERIFY). The staff Save waits on a phone, so the API always has one of the two. */
export function contactPromptBody(kind: string, email: string, phone: string): { email: string | null; phone: string | null } {
  return { email: kind === "student" ? email.trim() || null : null, phone: phone.trim() || null };
}

// ── the completion report (GET /api/v1/identity/completion/...) ──────────────────────────────────────────────────────────────────

export const STUDENT_COUNTS = ["total", "blood_confirmed", "blood_missing", "blood_unconfirmed", "with_photo", "without_photo", "without_matric", "complete", "needs_update"] as const;
export const STAFF_COUNTS = ["total", "with_photo", "without_photo", "photo_enhanced", "email_verified", "email_unverified", "email_missing", "blood_confirmed", "blood_missing", "blood_unconfirmed", "complete", "no_sign_in"] as const;
export type StudentCounts = Record<(typeof STUDENT_COUNTS)[number], number>;
export type StaffCounts = Record<(typeof STAFF_COUNTS)[number], number>;

/** the offices that read each tab — IdentityCompletionController's STUDENT_READERS and STAFF_READERS, kept the same */
export const COMPLETION_READERS: Record<"students" | "staff", readonly string[]> = {
  students: ["ict", "admin", "super", "registrar", "dregistrar", "records", "dsa", "security"],
  staff: ["ict", "admin", "super", "hrm", "registrar", "dregistrar", "security"],
};
export type CompletionTab = "students" | "staff";

/** the tabs the acting office may read, students first — so Records and Student Affairs never meet the staff tab, nor HR the
 *  students'; an office that reads neither (or none known) is shown none */
export function completionTabs(office: string | null | undefined): CompletionTab[] {
  return (["students", "staff"] as const).filter((t) => !!office && COMPLETION_READERS[t].includes(office));
}

/** the tab opened: the one the address asks for when the office reads it, else the first it reads (the students where it reads none,
 *  and the API says why) */
export function completionTab(asked: string | null | undefined, office: string | null | undefined): CompletionTab {
  const tabs = completionTabs(office);
  if ((asked === "students" || asked === "staff") && (tabs.includes(asked) || !tabs.length)) return asked;
  return tabs[0] ?? "students";
}

/** the list filtered by what is missing */
export const STUDENT_MISSING: [string, string][] = [["", "Every student"], ["ANY", "Not complete"], ["BLOOD", "Blood group not confirmed"], ["PHOTO", "No photograph"], ["MATRIC", "No matriculation number"]];
export const STAFF_MISSING: [string, string][] = [["", "Every member of staff"], ["ANY", "Not complete"], ["PHOTO", "Photograph not enhanced and accepted"], ["EMAIL", "E-mail not verified"], ["BLOOD", "Blood group not confirmed"]];
export const STAFF_CATEGORIES: [string, string][] = [["", "Any category"], ["ACADEMIC", "Academic"], ["NON_ACADEMIC", "Non-academic"]];

/** a field read whether the server named it snake_case (a database row) or camelCase */
export function field(o: Record<string, unknown> | null | undefined, snake: string): unknown {
  if (!o) return undefined;
  if (snake in o) return o[snake];
  const camel = snake.replace(/_([a-z])/g, (_, c: string) => c.toUpperCase());
  return o[camel];
}
function num(v: unknown): number {
  const n = typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" ? Number(v) : NaN;
  return Number.isFinite(n) ? n : 0;
}
function str(v: unknown): string | null {
  return typeof v === "string" && v.trim() ? v : typeof v === "number" ? String(v) : null;
}
function bool(v: unknown): boolean {
  return v === true || v === "t" || v === "true";
}

/** the counts, from the reply as it comes: the row itself, or under "counts" / "summary" */
export function countsOf<K extends string>(raw: unknown, keys: readonly K[]): Record<K, number> {
  const o = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const inner = [o.counts, o.summary].find((x) => x && typeof x === "object" && !Array.isArray(x)) as Record<string, unknown> | undefined;
  const row = inner ?? (Array.isArray(raw) ? ((raw[0] ?? {}) as Record<string, unknown>) : o);
  return Object.fromEntries(keys.map((k) => [k, num(field(row, k))])) as Record<K, number>;
}

export interface StudentRow {
  studentId: string; matricNo: string | null; name: string; programme: string | null; level: number | null; faculty: string | null;
  department: string | null; bloodGroup: string | null; bloodConfirmed: boolean; bloodConfirmedAt: string | null; hasPhoto: boolean; complete: boolean;
}
export interface StaffRow {
  personId: string; staffNumber: string | null; name: string; category: string | null; unit: string | null; faculty: string | null; inOffice: boolean;
  canSignIn: boolean; hasPhoto: boolean; photoEnhanced: boolean; email: string | null; emailVerified: boolean; emailPending: string | null;
  bloodGroup: string | null; bloodConfirmed: boolean; complete: boolean;
}
export interface ListPage<R> { rows: R[]; total: number; page: number; size: number }

function rowsOf(raw: unknown): Record<string, unknown>[] {
  if (Array.isArray(raw)) return raw as Record<string, unknown>[];
  const o = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  return Array.isArray(o.rows) ? (o.rows as Record<string, unknown>[]) : Array.isArray(o.items) ? (o.items as Record<string, unknown>[]) : [];
}
/** a page of the list, its total from the reply or the rows' own window count. The page is the one asked for, counted from 1 as
 *  the screen counts (the API counts from 0); the size is the one the server used (it holds a page to 200 rows). */
export function pageOf<R>(raw: unknown, read: (r: Record<string, unknown>) => R, asked: { page: number; size: number }): ListPage<R> {
  const rows = rowsOf(raw);
  const o = (raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {}) as Record<string, unknown>;
  const total = o.total != null ? num(o.total) : rows.length ? num(field(rows[0], "total")) || rows.length : 0;
  return { rows: rows.map(read), total, page: asked.page, size: o.size != null ? num(o.size) || asked.size : asked.size };
}

/** the lists a count's reply names to narrow by (the API's faculties, departments, programmes, units), each a code and a name with
 *  the faculty and department it sits in */
export interface Choice { code: string; name: string; facultyCode: string | null; deptCode: string | null }
export function choicesOf(raw: unknown, key: string): Choice[] {
  const o = (raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {}) as Record<string, unknown>;
  const list = o[key];
  if (!Array.isArray(list)) return [];
  return list.flatMap((x) => {
    const r = (x && typeof x === "object" ? x : {}) as Record<string, unknown>;
    const code = str(field(r, "code"));
    const name = str(field(r, "name")) ?? code;
    return code && name ? [{ code, name, facultyCode: str(field(r, "faculty_code")), deptCode: str(field(r, "dept_code")) }] : [];
  });
}
export function studentRowOf(r: Record<string, unknown>): StudentRow {
  const lv = field(r, "level");
  return {
    studentId: str(field(r, "student_id")) ?? "", matricNo: str(field(r, "matric_no")), name: str(field(r, "name")) ?? "", programme: str(field(r, "programme")),
    level: lv == null || lv === "" ? null : num(lv), faculty: str(field(r, "faculty")), department: str(field(r, "department")),
    bloodGroup: str(field(r, "blood_group")), bloodConfirmed: bool(field(r, "blood_confirmed")), bloodConfirmedAt: str(field(r, "blood_confirmed_at")),
    hasPhoto: bool(field(r, "has_photo")), complete: bool(field(r, "complete")),
  };
}
export function staffRowOf(r: Record<string, unknown>): StaffRow {
  return {
    personId: str(field(r, "person_id")) ?? "", staffNumber: str(field(r, "staff_number")), name: str(field(r, "name")) ?? "", category: str(field(r, "category")),
    unit: str(field(r, "unit")), faculty: str(field(r, "faculty")), inOffice: bool(field(r, "in_office")), canSignIn: bool(field(r, "can_sign_in")),
    hasPhoto: bool(field(r, "has_photo")), photoEnhanced: bool(field(r, "photo_enhanced")), email: str(field(r, "email")), emailVerified: bool(field(r, "email_verified")),
    emailPending: str(field(r, "email_pending")), bloodGroup: str(field(r, "blood_group")), bloodConfirmed: bool(field(r, "blood_confirmed")), complete: bool(field(r, "complete")),
  };
}

/** a row's blood group in words: the group and whether it is confirmed */
export function bloodWord(group: string | null, confirmed: boolean): [string, Kind] {
  if (!group) return ["None", "bad"];
  return confirmed ? [`${group} · confirmed`, "ok"] : [`${group} · not confirmed`, "warn"];
}
/** a member of staff's photograph in words */
export function staffPhotoWord(hasPhoto: boolean, enhanced: boolean): [string, Kind] {
  if (enhanced) return ["Enhanced and accepted", "ok"];
  return hasPhoto ? ["On file, not enhanced", "warn"] : ["None", "bad"];
}
/** a member of staff's e-mail in words */
export function staffEmailWord(email: string | null, verified: boolean, pending: string | null): [string, Kind] {
  if (verified) return ["Verified", "ok"];
  if (pending) return [`Code sent to ${pending}`, "warn"];
  return email ? ["Not verified", "warn"] : ["None", "bad"];
}
export function categoryWord(c: string | null): string {
  return c === "ACADEMIC" ? "Academic" : c === "NON_ACADEMIC" ? "Non-academic" : c ? humanise(c) : "—";
}

// ── words ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

/** "TOO_DARK" → "Too dark"; "meanLuma" → "Mean luma" */
export function humanise(code: string): string {
  const s = code.replace(/([a-z0-9])([A-Z])/g, "$1 $2").replace(/[_-]+/g, " ").trim().toLowerCase();
  return s ? s[0].toUpperCase() + s.slice(1) : "";
}
const LABELS: Record<string, string> = {
  width: "Width (pixels)", height: "Height (pixels)", megapixels: "Megapixels", format: "Format", aspect: "Aspect (width ÷ height)",
  meanLuma: "Brightness (mean, 0–255)", mean_luma: "Brightness (mean, 0–255)", centreLuma: "Brightness at the centre (0–255)",
  clippedDarkPct: "Lost in shadow (%)", clippedBrightPct: "Washed out (%)", sharpnessThreshold: "Sharpness wanted (at least)",
  decodeWarnings: "Read with warnings", spread: "Spread", busy: "Busy", method: "Method", before: "Before", after: "After", crop: "Crop", lumaSpread: "Contrast (spread)", luma_spread: "Contrast (spread)",
  lumaStd: "Contrast (spread)", luma_std: "Contrast (spread)", clippedDark: "Lost in shadow (%)", clipped_dark: "Lost in shadow (%)",
  clippedBright: "Washed out (%)", clipped_bright: "Washed out (%)", sharpness: "Sharpness", noise: "Noise", noiseEstimate: "Noise",
  noise_estimate: "Noise", orientation: "Orientation", orientationCorrected: "Turned upright", orientation_corrected: "Turned upright",
  background: "Background", uniformity: "Uniformity", brightness: "Brightness",
  highlights: "Highlights (0–255)", centreClippedPct: "Washed out at the centre (%)", tint: "Tint",
};
function label(k: string): string {
  return LABELS[k] ?? humanise(k);
}
function scalar(v: unknown): string | null {
  if (v == null) return null;
  if (typeof v === "boolean") return v ? "Yes" : "No";
  if (typeof v === "number") return Number.isInteger(v) ? v.toLocaleString("en-GB") : v.toLocaleString("en-GB", { maximumFractionDigits: 2 });
  if (typeof v === "string") return v.trim() ? v.trim() : null;
  if (Array.isArray(v)) {
    const parts = v.map(scalar).filter((x): x is string => x != null);
    return parts.length && parts.length === v.length ? parts.join(", ") : null;
  }
  return null;
}
