/** V385: the Post-UTME CBT scores from the engine to the admission, as the screens read them — the Directorate's score desk, the
 *  official score files, the Academic Office's import, and the public door's own words. */

export interface PutmeScoreRow {
  application_id: string; jamb_reg_no: string; application_no: string | null; surname: string; other_names: string; faculty: string | null; department: string | null;
  programme: string | null; programme_code: string | null; exam_id: string; exam_title: string; exam_reference: string; results_state: string; official: boolean;
  attempt_id: string; attempt_status: string; outcome: string; questions: number; attempted: number; max_marks: number; score: number | null; percentage: number;
  violations: number; submitted_at: string | null; existing_score: number | null; score_released_at: string | null; exported_in: string | null;
}
export interface PutmeExportRow {
  sn: number; application_id: string; jamb_reg_no: string; application_no: string | null; candidate_name: string; faculty: string | null; department: string | null;
  programme: string | null; exam_title: string | null; questions: number | null; attempted: number | null; max_marks: number | null; score: number | null; percentage: number;
  exam_date: string | null; attempt_status: string | null; outcome: string | null;
}
export type ExportState = "GENERATED" | "SENT_TO_ACADEMIC" | "RECEIVED" | "DOWNLOADED" | "IMPORTED" | "REJECTED" | "CANCELLED";
export interface PutmeExport {
  id: string; reference: string; session: string; exam_id: string | null; exam_title: string | null; state: ExportState; rows_count: number; sha256: string; message: string | null;
  generated_at: string; sent_at: string | null; received_at: string | null; downloaded_at: string | null; imported_at: string | null; rejected_at: string | null; cancelled_at: string | null;
  closing_note: string | null; generated_by_name: string | null; sent_by_name: string | null; received_by_name?: string | null; imported_by_name?: string | null;
  /** the imports as JSON text (the API aggregates them) */
  imports?: string | null; rows?: PutmeExportRow[];
}
export interface PutmeImportSummary { id: string; mode: string; reason: string | null; received: number; applied: number; unchanged: number; replaced: number; kept: number; released: number; notFound: number; importedAt: string; importedBy: string | null }
export interface PutmeExamRow { id: string; reference: string; title: string; state: string; results_state: string; live_state: string; starts_at: string | null; ends_at: string | null; sat: number }
export interface PutmeScoresPage {
  session: string; total: number; page: number; size: number; rows: PutmeScoreRow[];
  counts: { scored: number; official: number; exported: number; imported: number; released: number; average: number | null; highest: number | null; lowest: number | null; applicants: number };
  exams: PutmeExamRow[]; exports: PutmeExport[]; faculties: string[]; programmes: { code: string; name: string }[]; now: string;
}
export type PreviewOutcome = "NEW" | "SAME" | "DIFFERENT" | "RELEASED" | "NOT_FOUND" | "OUT_OF_RANGE";
export interface PreviewRow { sn: number; application_id: string; jamb_reg_no: string; application_no: string | null; candidate_name: string; programme: string | null; percentage: number; existing_score: number | null; score_released_at: string | null; outcome: PreviewOutcome }

export const EXPORT_WORD: Record<ExportState, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = {
  GENERATED: ["Generated", "info"], SENT_TO_ACADEMIC: ["Sent to the Academic Office", "warn"], RECEIVED: ["Received", "warn"], DOWNLOADED: ["Downloaded", "warn"],
  IMPORTED: ["Imported", "ok"], REJECTED: ["Rejected", "bad"], CANCELLED: ["Cancelled", "grey"],
};
export const PREVIEW_WORD: Record<PreviewOutcome, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = {
  NEW: ["Entered", "ok"], SAME: ["Same score already held", "grey"], DIFFERENT: ["A different score is held", "warn"], RELEASED: ["Released — never touched", "bad"],
  NOT_FOUND: ["Applicant not found", "bad"], OUT_OF_RANGE: ["Out of range", "bad"],
};

/** the public door's state, as GET /api/v1/putme/cbt/public gives it */
export interface PutmePublic {
  session: string;
  cbt: { type: string; state: string; open: boolean; opensAt: string | null; closesAt: string | null; message: string | null };
  results: { type: string; state: string; open: boolean; opensAt: string | null; closesAt: string | null; message: string | null };
  factor: string; factorLabel: string;
  /** V388: the result-checking page always asks for a second factor */
  resultFactor: string; resultFactorLabel: string;
  exams: { id: string; title: string; starts_at: string | null; ends_at: string | null; duration_minutes: number; live_state: string; questions: number }[];
  now: string;
}
