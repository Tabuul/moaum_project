/**
 * V510: a new appointment in HR — the employment record made from the form or an Excel upload, checked first by the database
 * (hrm.appointment_check), and the salary grades it names. This only reads and says what the server decides.
 */

export interface Grade {
  grade: string; step: number; category: "ACADEMIC" | "NON_ACADEMIC"; basic: number; housing: number; transport: number;
  other_allowances: number; monthly: number; staff: number;
}

export interface Appointed {
  id: string; staff_no: string; name: string; category: string; grade: string; step: number; appointment_date: string; status: string;
  home_department: string | null; department: string | null; home_unit: string | null; unit: string | null; present_rank: string | null;
}

export interface AppointmentsOverview {
  grades: Grade[]; counts: { active: number; suspended: number; ended: number; without_employment: number };
  recent: Appointed[]; departments: { code: string; name: string }[]; units: { code: string; name: string }[];
}

/** a row's check: what it would do (LINK an existing person by staff number, or CREATE one) and why not */
export interface RowCheck {
  row: string; ok: boolean; problems: string[]; warnings: string[]; action: "LINK" | "CREATE"; person_id: string | null; name: string;
  staff_no: string; category: string; grade: string; step: number | null; appointment_date: string | null; department: string | null; unit: string | null;
}

/** V749: an e-mail another person holds verified is theirs, so the appointment is made without it — the check warns first, and the
 *  answer names the address left off: POST /hr/appointments answers { employmentId, emailLeftOff }, an upload's appointed row carries
 *  email_left_off (hrm.appoint_many). Between the check and the appointment its holder may verify it, so the answer is what is told */
export interface AppointedOne { employmentId: string; emailLeftOff?: string | null }

/** an upload's answer (hrm.appoint_many): each row appointed, or not with its reasons */
export interface UploadRow { row: string; staff_no: string; name: string; appointed: boolean; problems?: string[]; email_left_off?: string | null }
export interface UploadResult { appointed: number; skipped: number; rows: UploadRow[] }

/** the words for an address left off: another person's, verified on their record */
export function leftOffWords(email: string): string {
  return `appointed without the e-mail ${email}, another person's verified address`;
}

/** the single appointment's message: the name, and the address left off where there was one */
export function appointedMessage(name: string, a: AppointedOne | null | undefined): { text: string; kind: "ok" | "warn" } {
  const off = a?.emailLeftOff?.trim();
  return off
    ? { text: `Appointed: ${name}, without the e-mail ${off}: it is another person's, verified on their record. The employment record is active; the member of staff verifies their own address at My identity.`, kind: "warn" }
    : { text: `Appointed: ${name}. The employment record is active.`, kind: "ok" };
}

/** the upload's result note, in the file's order: each row not appointed with its reasons, and each appointed one whose e-mail was
 *  left off */
export function uploadResultLines(res: UploadResult): { row: string; text: string }[] {
  const out: { row: string; text: string }[] = [];
  for (const r of res.rows ?? []) {
    if (!r.appointed) out.push({ row: r.row, text: `Row ${r.row} (${r.staff_no}): ${(r.problems ?? []).join(" ")}` });
    else if (r.email_left_off?.trim()) out.push({ row: r.row, text: `Row ${r.row} (${r.staff_no}): ${leftOffWords(r.email_left_off.trim())}` });
  }
  return out;
}

/** how many of an upload's appointed rows had their e-mail left off */
export function leftOffCount(res: UploadResult): number {
  return (res.rows ?? []).filter((r) => r.appointed && r.email_left_off?.trim()).length;
}

/** the fields of an appointment, as the form and the upload send them */
export const FIELDS = ["staff_no", "surname", "given_names", "sex", "email", "phone", "category", "grade", "step", "appointment_date", "department", "unit",
  "rank", "bank_name", "account_name", "account_number", "pension_pin"] as const;
export type Field = (typeof FIELDS)[number];

/** the upload's headings, as the template writes them */
export const TEMPLATE_HEAD = ["Staff No", "Surname", "Given Names", "Sex", "Email", "Phone", "Category", "Grade", "Step", "Date of Appointment",
  "Department", "Unit", "Rank", "Bank", "Account Name", "Account Number", "Pension PIN"];

/** the headings an upload may use for each field (normalised: lower case, words) */
export const ALIASES: Record<string, Field> = {
  "staff no": "staff_no", "staff number": "staff_no", "pno": "staff_no", "file no": "staff_no",
  "surname": "surname", "last name": "surname", "given names": "given_names", "other names": "given_names", "first name": "given_names", "first names": "given_names",
  "sex": "sex", "gender": "sex", "email": "email", "e mail": "email", "phone": "phone", "phone no": "phone", "phone number": "phone",
  "category": "category", "staff category": "category", "grade": "grade", "grade level": "grade", "salary grade": "grade", "step": "step",
  "date of appointment": "appointment_date", "appointment date": "appointment_date", "date of 1st appt": "appointment_date", "date of first appointment": "appointment_date",
  "department": "department", "dept": "department", "unit": "unit", "rank": "rank", "present rank": "rank", "designation": "rank",
  "bank": "bank_name", "bank name": "bank_name", "account name": "account_name", "account number": "account_number", "account no": "account_number",
  "pension pin": "pension_pin", "pen pin": "pension_pin", "rsa pin": "pension_pin",
};

export const CATEGORY_LABEL: Record<string, string> = { ACADEMIC: "Academic", NON_ACADEMIC: "Non-academic" };
