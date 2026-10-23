/**
 * V640: examination readiness — the words, the columns each report carries, the drill-down from a figure to its students (and one
 * grouping down), the six reports of the package, and the quick presets. The server counts and lists; this only says it.
 */
export type Kind = "ok" | "warn" | "bad" | "info" | "grey";

export interface ReadinessFigures {
  total: number; paid_registered: number; paid_not_registered: number; not_paid: number; not_paid_registered: number; no_fee_stated: number;
  part_paid: number; exam_cards: number; exceptions: number;
}

export interface SummaryRow extends ReadinessFigures { key: string; label: string }

export interface Summary { filters: Record<string, unknown>; scope: string; by: string; rows: SummaryRow[]; total: SummaryRow; at: string }

export interface ReadinessRow {
  student_id: string; matric_no: string | null; jamb_no: string | null; surname: string; other_names: string; sex: string | null; status: string;
  academic_status: string; programme_type: string | null; admission_route: string | null; study_mode: string | null;
  faculty_code: string; faculty: string; dept_code: string; department: string; programme_code: string; programme: string; level: number;
  entry_session: string | null; fee_status: string; payable: number | null; paid_amount: number | null; outstanding: number | null;
  last_paid_at: string | null; fully_paid: boolean; school_fees_paid: boolean; registration_stream: string; registration_status: string;
  registration_level: number | null; courses: number | null; units: number | null; carryovers: number | null; course_registered: boolean | null;
  course_entry_type: string | null; course_expected: string | null; paid: boolean; registered: boolean; exam_card: boolean | null;
  readiness: string; exception: string | null;
}

export interface StudentPage { filters: Record<string, unknown>; scope: string; category: string; rows: ReadinessRow[]; total: number; page: number; size: number; amounts: boolean; at: string }

export interface CourseRow {
  course_code: string; title: string; units: number; dept_code: string; department: string; registered: number; registered_paid: number;
  registered_not_paid: number; registered_no_fee: number; expected: number; expected_not_registered: number; expected_not_registered_paid: number; not_paid: number;
}

export interface Options { period: { session: string; semester: number }; sessions: string[]; types: { code: string; label: string }[]; scope: { words: string }; amounts: boolean }

export interface Issued { reference: string; title: string; generatedAt: string; filters: Record<string, unknown>; scope: string; figures: ReadinessFigures; parts: string[] }

export const CATEGORY: Record<string, [string, Kind, string]> = {
  ALL: ["All students", "info", "every student of the scope for the semester"],
  PAID_REGISTERED: ["Paid + registered", "ok", "school fees paid and the courses registered"],
  PAID_NOT_REGISTERED: ["Paid + not registered", "warn", "school fees paid, no registration"],
  NOT_PAID: ["Not paid", "bad", "a fee is charged and nothing is paid"],
  NOT_PAID_REGISTERED: ["Registered, not paid", "bad", "registered without the school-fees payment"],
  NO_FEE_STATED: ["No fee stated", "grey", "nothing charged for the student — never counted as not paid"],
  EXAM_CARD: ["Examination card", "ok", "paid and a submitted registration with courses: the card's own rule"],
  EXCEPTIONS: ["Registration exceptions", "warn", "a draft, returned or empty registration, registered without paying, awaiting approval"],
  PART_PAID: ["Part payment", "warn", "paid by the card's rule, something still outstanding"],
};

export const EXCEPTION: Record<string, string> = {
  REGISTRATION_NOT_SUBMITTED: "Registration not submitted",
  REGISTRATION_RETURNED: "Registration returned for correction",
  REGISTRATION_WITHOUT_COURSES: "Registration without courses",
  REGISTERED_NOT_PAID: "Registered, school fees not paid",
  REGISTERED_NO_FEE_STATED: "Registered, no fee stated",
  FEES_SETTLED_NO_SCHOOL_FEES_PAYMENT: "Fees settled, no school-fees payment on record (card withheld)",
  REGISTRATION_AWAITING_APPROVAL: "Registration awaiting approval (not yet on class lists)",
  PART_PAYMENT: "Part payment",
};

export const BY: [string, string][] = [["faculty", "Faculty"], ["department", "Department"], ["programme", "Programme"], ["level", "Level"],
  ["type", "Programme type"], ["status", "Academic status"]];

/** one grouping down: a faculty opens its departments, a department its programmes, a programme its levels */
export const NEXT_BY: Record<string, string> = { faculty: "department", department: "programme", programme: "level", level: "level", type: "faculty", status: "faculty" };

export function words(v: string | null | undefined): string {
  if (!v) return "—";
  return v.toLowerCase().replace(/_/g, " ").replace(/^./, (c) => c.toUpperCase());
}

export function fullName(r: { surname: string; other_names: string }): string {
  return `${r.surname}${r.other_names ? ", " + r.other_names : ""}`;
}

export function semWord(n: number | string | null | undefined): string {
  const x = Number(n);
  return x === 1 ? "First" : x === 2 ? "Second" : x === 3 ? "Third" : "—";
}

/** the URL parameters a figure opens: the group's own filter, the category, and one grouping down */
export function drill(by: string, key: string, category: string): Record<string, string> {
  const p: Record<string, string> = { cat: category };
  if (key !== "ALL") {
    if (by === "faculty") p.fac = key;
    else if (by === "department") p.dept = key;
    else if (by === "programme") p.prog = key;
    else if (by === "level") p.level = key;
    else if (by === "type") p.type = key === "UNCLASSIFIED" ? "" : key;
    else if (by === "status") p.astatus = key;
    p.by = NEXT_BY[by] ?? by;
  }
  return p;
}

/** the columns of a student report, as the University's reports carry them (S/N comes first from the export itself) */
export function columnsFor(category: string, course: boolean, amounts: boolean): [string, (r: ReadinessRow, ctx: { session: string; semester: number; course?: string }) => string | number][] {
  const base: [string, (r: ReadinessRow, ctx: { session: string; semester: number; course?: string }) => string | number][] = [
    ["Matric No", (r) => r.matric_no ?? ""],
    ["Student Name", (r) => fullName(r)],
    ["Faculty", (r) => r.faculty],
    ["Department", (r) => r.department],
    ["Programme", (r) => r.programme],
    ["Level", (r) => r.level],
  ];
  if (course) {
    return [...base,
      ["Course", (_r, c) => c.course ?? ""],
      ["Fee Status", (r) => words(r.fee_status)],
      ["Registration Status", (r) => r.course_registered ? `Registered${r.course_entry_type && r.course_entry_type !== "CURRENT" ? ` (${words(r.course_entry_type)})` : ""}` : "Not registered"],
      ["Examination Status", (r) => CATEGORY[r.readiness]?.[0] ?? words(r.readiness)],
    ];
  }
  const period: [string, (r: ReadinessRow, ctx: { session: string; semester: number }) => string | number][] = [
    ["Session", (_r, c) => c.session], ["Semester", (_r, c) => semWord(c.semester)]];
  if (category === "PAID_REGISTERED" || category === "EXAM_CARD") {
    return [...base, ...period,
      ["Payment Status", (r) => words(r.fee_status)],
      ["Registration Status", (r) => words(r.registration_status)],
      ["Courses Registered", (r) => r.courses ?? ""],
      ["Total CU", (r) => r.units ?? ""],
    ];
  }
  if (category === "PAID_NOT_REGISTERED") {
    return [...base, ...period,
      ["Payment Date", (r) => (r.last_paid_at ? new Date(r.last_paid_at).toLocaleDateString("en-GB") : "")],
      ...(amounts ? [["Amount Paid", (r: ReadinessRow) => Number(r.paid_amount ?? 0)] as [string, (r: ReadinessRow) => number]] : []),
      ["Registration Status", (r) => words(r.registration_status)],
    ];
  }
  if (category === "NOT_PAID" || category === "NOT_PAID_REGISTERED" || category === "NO_FEE_STATED") {
    return [...base, ...period,
      ["Fee Status", (r) => words(r.fee_status)],
      ...(amounts ? [
        ["Amount Required", (r: ReadinessRow) => Number(r.payable ?? 0)],
        ["Amount Paid", (r: ReadinessRow) => Number(r.paid_amount ?? 0)],
        ["Outstanding", (r: ReadinessRow) => Number(r.outstanding ?? 0)],
      ] as [string, (r: ReadinessRow) => number][] : []),
      ["Registration Status", (r) => words(r.registration_status)],
    ];
  }
  return [...base, ...period,
    ["Status", (r) => words(r.academic_status)],
    ["Fee Status", (r) => words(r.fee_status)],
    ["Registration Status", (r) => words(r.registration_status)],
    ["Readiness", (r) => CATEGORY[r.readiness]?.[0] ?? words(r.readiness)],
    ["Exception", (r) => (r.exception ? EXCEPTION[r.exception] ?? words(r.exception) : "")],
  ];
}

/** the figures of a summary row, in the order the report shows them */
export const SUMMARY_COLUMNS: [keyof ReadinessFigures, string, string][] = [
  ["total", "Total eligible", "ALL"],
  ["paid_registered", "Paid + registered", "PAID_REGISTERED"],
  ["paid_not_registered", "Paid + not registered", "PAID_NOT_REGISTERED"],
  ["not_paid", "Not paid", "NOT_PAID"],
  ["not_paid_registered", "Of them registered", "NOT_PAID_REGISTERED"],
  ["no_fee_stated", "No fee stated", "NO_FEE_STATED"],
  ["exam_cards", "Examination cards", "EXAM_CARD"],
  ["exceptions", "Registration exceptions", "EXCEPTIONS"],
];

export const COURSE_COLUMNS: [keyof CourseRow, string][] = [
  ["registered", "Total registered"], ["registered_paid", "Paid"], ["registered_not_paid", "Not paid"],
  ["expected", "Expected (structure)"], ["expected_not_registered_paid", "Paid / not registered"],
];

/** the six reports of the package and what each reads */
export const PACKAGE_PARTS: { n: number; title: string; kind: "students" | "courses" | "summary"; category?: string; by?: string }[] = [
  { n: 1, title: "Paid and registered", kind: "students", category: "PAID_REGISTERED" },
  { n: 2, title: "Paid but not registered", kind: "students", category: "PAID_NOT_REGISTERED" },
  { n: 3, title: "Not paid", kind: "students", category: "NOT_PAID" },
  { n: 4, title: "Course-level registration", kind: "courses" },
  { n: 5, title: "Department summary", kind: "summary", by: "department" },
  { n: 6, title: "Faculty summary", kind: "summary", by: "faculty" },
];

/** the quick presets: what each opens */
export const PRESETS: { label: string; href: string }[] = [
  { label: "Paid and registered", href: "/reports/exam-readiness?cat=PAID_REGISTERED" },
  { label: "Paid but not registered", href: "/reports/exam-readiness?cat=PAID_NOT_REGISTERED" },
  { label: "Not paid", href: "/reports/exam-readiness?cat=NOT_PAID" },
  { label: "Course registration by department", href: "/reports/exam-readiness?view=courses" },
  { label: "Course registration by faculty", href: "/reports/exam-readiness?view=courses&cby=faculty" },
  { label: "Course examination readiness", href: "/reports/exam-readiness?view=course" },
  { label: "Student payment status", href: "/dbops/query?preset=payments" },
  { label: "Student registration status", href: "/dbops/query?preset=registrations" },
  { label: "Spillover students", href: "/student-query?spillover=ANY" },
  { label: "Graduated students", href: "/student-query?status=GRADUATED" },
  { label: "Undergraduate students", href: "/student-query?type=UNDERGRADUATE" },
  { label: "Postgraduate students", href: "/student-query?type=POSTGRADUATE" },
  { label: "CCE students", href: "/student-query?type=CCE" },
  { label: "JUPEB students", href: "/student-query?type=JUPEB" },
  { label: "Preliminary students", href: "/student-query?type=PRELIMINARY" },
];

export function money(n: number | null | undefined): string {
  return n == null ? "—" : `₦${Number(n).toLocaleString("en-GB", { maximumFractionDigits: 2 })}`;
}

/** the filters as a report's heading lines */
export function filterLines(f: Record<string, unknown>, types?: { code: string; label: string }[]): [string, string][] {
  const out: [string, string][] = [];
  if (f.session) out.push(["Session", String(f.session)]);
  if (f.semester) out.push(["Semester", semWord(Number(f.semester))]);
  if (f.faculty) out.push(["Faculty", String(f.faculty)]);
  if (f.department) out.push(["Department", String(f.department)]);
  if (f.programme) out.push(["Programme", String(f.programme)]);
  if (f.level) out.push(["Level", `${f.level} Level`]);
  if (f.programmeType) out.push(["Programme type", types?.find((t) => t.code === f.programmeType)?.label ?? String(f.programmeType)]);
  if (f.course) out.push(["Course", String(f.course)]);
  if (f.academicStatus) out.push(["Academic status", words(String(f.academicStatus))]);
  out.push(["Paid means", f.paidRule === "FULL" ? "school fees paid in full (the Bursary's rule)" : "a school-fees payment confirmed for the session (the examination card's rule)"]);
  return out;
}
