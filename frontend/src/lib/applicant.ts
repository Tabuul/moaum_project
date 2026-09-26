/**
 * The applicant's journey as the API states it (V021, proto/part13.html):
 * ten stages from the account to the matriculation number, every screen
 * rendering its waiting, live or completed state from the one number the
 * database computes.
 */

export interface OlGrade { subject: string; grade: string }
export interface OlSitting { body: string; type: string | null; year: string | null; examNumber: string | null; subjects: OlGrade[] }
export interface FeeReference { id: string; kind: "APPLICATION" | "ACCEPTANCE"; reference: string; amount: number; generatedAt: string; expiresAt: string; confirmedAt: string | null; channel: string | null }
export interface ApplicationDocument { id: string; kind: string; filename: string; contentType: string; bytes: number; uploadedAt: string; status: "PENDING" | "ACCEPTED" | "REJECTED"; reviewedAt: string | null; reviewNote: string | null }
export interface ScreeningSlip {
  batch: string; heldOn: string; startsAt: string; endsAt: string; venue: string; seat: string;
  /** the CBT placing (V260): published only once the desk publishes the schedule */
  published: boolean; batchState: string | null; centre: string | null; centreLocation: string | null; centreAddress: string | null; room: string | null; workstation: string | null;
  examName: string | null; checkinMinutes: number | null; instructions: string | null; venueInstructions: string | null; contact: string | null; token: string | null;
  attendance: string | null; examStatus: string | null; checkedInAt: string | null;
}
/** the time the candidate reports at the door: the batch's start less the examination's check-in minutes, HH:MM */
export function reportingTime(slip: ScreeningSlip): string {
  const [h, m] = String(slip.startsAt).slice(0, 5).split(":").map(Number);
  const t = Math.max(0, h * 60 + m - (slip.checkinMinutes ?? 30));
  return `${String(Math.floor(t / 60)).padStart(2, "0")}:${String(t % 60).padStart(2, "0")}`;
}
/** the public page the slip's QR opens */
export function putmeVerifyPath(token: string): string {
  return `/verify/putme/${encodeURIComponent(token)}`;
}
export interface ScreeningResult {
  utme: number | null;
  utmeScaled: number | null;
  screening: number | null;
  /** EXAM: the programme is screened by the post-UTME examination alone (V022); the score appears when it is entered and released */
  screeningSource: "CBT" | "OLEVEL" | "EXAM" | "NONE";
  weightUtme: number;
  weightPutme: number;
  aggregate: number | null;
  cutoff: number | null;
  meritPosition: number | null;
  applied: number | null;
  places: number | null;
}
export interface ClearanceItem { item: string; state: "NOT_PRESENTED" | "VERIFIED" | "QUERY"; note: string | null; decidedAt: string | null }
/** a notice queued about the application (V025): what was said, on which channel, and whether it went */
export interface Notice { id: string; channel: "EMAIL" | "SMS"; recipient: string; subject: string; body: string; created_at: string; state: "QUEUED" | "SENT" | "FAILED"; sent_at: string | null }

/** the basis of an offer, as JAMB's admission template names it in GENERAL REMARKS */
export const BASES: [string, string][] = [
  ["NM", "National Merit"],
  ["SM", "State Merit"],
  ["ELG", "Equality of Local Government"],
  ["LOCALITY", "Locality"],
  ["PLWD", "Persons Living With Disability"],
  ["OTHER", "Other"],
];

export interface Application {
  id: string;
  session: string;
  applicationNo: string;
  stage: number;
  name: string;
  surname: string;
  otherNames: string;
  jambKey: string;
  programme: string | null;
  programmeCode: string | null;
  faculty: string | null;
  entryMode: string;
  entryLevel: number;
  listKind: string | null;
  offerState: string;
  email: string;
  phone: string;
  biodata: { sex: string | null; stateOfOrigin: string | null; lga: string | null; dateOfBirth: string | null; utme: number | null; nextOfKin: string | null };
  olevel: OlSitting[];
  fees: { applicationFee: number; portalCharge: number; acceptanceFee: number; stated: boolean };
  feeReferences: FeeReference[];
  feeConfirmedAt: string | null;
  documents: ApplicationDocument[];
  jambPassport?: string | null;
  submittedAt: string | null;
  screeningSlip: ScreeningSlip | null;
  scoreReleasedAt: string | null;
  result: ScreeningResult | null;
  screeningScore?: number | null;
  decisionReleasedAt: string | null;
  decision: "OFFERED" | "WAITING" | "NOT_OFFERED" | null;
  decisionNote: string | null;
  decisionBasis: string | null;
  notices: Notice[];
  undertakingAt: string | null;
  acceptanceConfirmedAt: string | null;
  acceptedAt: string | null;
  declinedAt: string | null;
  clearance: ClearanceItem[];
  clearedAt: string | null;
  admissionNo: string | null;
  matricNo: string | null;
  studentProgramme: string | null;
}

/** the ten milestones, as the prototype names them */
export const STAGES: [string, string][] = [
  ["Account created", "Application account opened on the portal"],
  ["Application fee paid", "Confirmed by the bank to the University"],
  ["Application submitted", "Biodata, O’Level results and documents"],
  ["Screening slip issued", "Batch, venue and seat published"],
  ["Screening score released", "Post-UTME result on the portal"],
  ["Admission decision released", "From the JAMB admission list or the Board: offer, waiting list or not offered"],
  ["Offer accepted", "Acceptance fee paid within the deadline; acceptance letter issued"],
  ["Screening successful", "Online screening approved, or a change of programme approved"],
  ["Fees paid and courses registered", "Under your admission number"],
  ["Matriculated", "Matriculation number issued over the confirmed register"],
];

/** indexed by stage: what this applicant must do next, having got this far — [title, words, route, button] */
export const NEXT: [string, string, string, string][] = [
  ["Pay the application fee", "Nothing is submitted until the fee is confirmed.", "/applicant/fee", "Go to payment"],
  ["Complete and submit your application", "Biodata from JAMB, your O’Level results as JAMB sent them, your documents.", "/applicant/apply", "Open the form"],
  ["Wait for your screening batch", "Batches are published once applications close, so that every candidate is placed.", "/applicant/screening", "Screening slip"],
  ["Sit the post-UTME screening", "Bring your slip and photo identification.", "/applicant/screening", "Screening slip"],
  ["Check your admission status", "The offer appears here the moment the University uploads JAMB’s admission list or the Board releases its decision.", "/applicant/status", "Admission status"],
  ["Accept your offer and pay the acceptance fee", "An offer that lapses cannot be reinstated.", "/applicant/accept", "Accept the offer"],
  ["Complete the online screening", "Take your acceptance letter, then complete and submit the screening form; the screening officers decide.", "/applicant/clearance", "Online screening"],
  ["Pay your fees and register your courses", "You do this under your admission number, before you are matriculated.", "/applicant/matric", "What happens next"],
  ["Wait for your matriculation number", "Your Faculty Officer confirms you registered; the Academic Office then issues numbers in one run.", "/applicant/matric", "Matriculation"],
  ["Sign in as a student", "Your matriculation number has been issued.", "/applicant/matric", "Matriculation"],
];

export const DOCUMENT_KINDS: [string, string, string][] = [
  ["OLEVEL_STATEMENT", "O’Level statement of result", "WAEC, NECO or NABTEB"],
  ["BIRTH_CERT", "Birth certificate or declaration of age", "NPC or sworn declaration"],
  ["LGA_ID", "Local government identification", "Signed by the LGA"],
  ["JAMB_SLIP", "JAMB result slip", "Printed from the JAMB portal"],
  ["PASSPORT", "Passport photograph", "White background, taken this year"],
];

export const CLEARANCE_ITEMS: [string, string, string][] = [
  ["OLEVEL_ORIGINAL", "O’Level certificate or statement of result", "Original"],
  ["BIRTH_CERT", "Birth certificate or declaration of age", "NPC certificate or sworn declaration"],
  ["LGA_ID", "Local government identification", "Signed and stamped by the LGA"],
  ["JAMB_LETTER", "JAMB admission letter", "Printed from the JAMB portal"],
  ["MEDICAL", "Medical fitness certificate", "From the University Health Services"],
  ["PHOTOGRAPHS", "Passport photographs", "Six copies, white background"],
];

export const BODY: Record<string, string> = { WAEC: "WAEC", NECO: "NECO", NABTEB: "NABTEB", OTHER: "Other body" };

export function at(a: Application, n: number): boolean {
  return a.stage >= n;
}

/** the reference still open for a fee, if any */
export function openReference(a: Application, kind: "APPLICATION" | "ACCEPTANCE"): FeeReference | null {
  const now = Date.now();
  return a.feeReferences.find((r) => r.kind === kind && !r.confirmedAt && new Date(r.expiresAt).getTime() > now) ?? null;
}

export function confirmedReference(a: Application, kind: "APPLICATION" | "ACCEPTANCE"): FeeReference | null {
  return a.feeReferences.find((r) => r.kind === kind && r.confirmedAt) ?? null;
}

/** DD-MM-YYYY, or whatever JAMB sent, shown as a date where it can be read as one */
export function dob(v: string | null): string {
  if (!v) return "—";
  const m = /^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$/.exec(v.trim());
  if (m) {
    const d = new Date(Date.UTC(+m[3], +m[2] - 1, +m[1]));
    return d.toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" });
  }
  return v;
}
