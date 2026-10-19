/**
 * V501: the examination card — the University's full examination permit for a semester — as the server answers it
 * (registration.exam_card_state): available, or the first rule that fails with its words; every course on the approved
 * registration (departmental, GST and EPS, carry-overs). The GST & EPS permit is a document of its own beside it
 * (lib/gst-eps-permit). The server decides; this only says it.
 */

export interface ExamCardCourse {
  course_code: string;
  title: string;
  units: number;
  entry_type: string | null;
  gst_eps: boolean;
  general_office: string | null;
}

export interface ExamCardState {
  available: boolean;
  code?: string | null;
  reason?: string | null;
  session: string;
  semester: number;
  openSemester?: number;
  registration?: { status: string; level: number; approvedAt?: string | null; approvalMode?: string | null } | null;
  courses: ExamCardCourse[];
  count: number;
  units: number;
  gstEpsCount: number;
  cleared?: boolean | null;
  issued?: { times: number; firstAt: string; lastAt: string } | null;
}

/** "6 papers · 18 credit units · including 2 GST/EPS" */
export function examCardSummary(s: Pick<ExamCardState, "count" | "units" | "gstEpsCount">): string {
  const parts = [`${s.count} paper${s.count === 1 ? "" : "s"}`, `${s.units} credit unit${s.units === 1 ? "" : "s"}`];
  if (s.gstEpsCount) parts.push(`including ${s.gstEpsCount} GST/EPS`);
  return parts.join(" · ");
}

/** the card's state in a word, for the panel's corner */
export function examCardStatusLabel(s: Pick<ExamCardState, "available" | "code">): string {
  if (s.available) return "Available";
  // V567: the card asks only for the school fees paid and the courses registered
  if (s.code === "EXAM_CARD_NOT_PAID") return "Fees not paid";
  if (s.code === "EXAM_CARD_NOT_SUBMITTED" || s.code === "EXAM_CARD_NO_REGISTRATION") return "Register your courses";
  return "Not available";
}
