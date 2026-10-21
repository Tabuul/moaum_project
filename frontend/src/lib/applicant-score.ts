/** The Post-UTME score on the applicant's dashboard: the admitted sitter's alone (21 October 2026). The API gives the result only
 *  with a released offer of admission the applicant may read — Admission Status Checking paid and checked, or the admission under
 *  way — and only where the score is the Post-UTME examination's (the CBT, or the written examination of an index programme): the
 *  aggregate computed from the O'Level result for a programme screened without the examination is never shown, and an applicant not
 *  offered a place never sees a score, nor that scores were released. Before the decision the score is awaited after a published
 *  screening slip, and not spoken of for a candidate admitted from the JAMB list, who is not screened here. The programme's cut-off
 *  is a UTME cut-off (of 400, admissions.cutoff_for), so it is read against the UTME score, never against the aggregate (of 100).
 *  Node-tested. */
import type { Application, ScreeningResult } from "./applicant.ts";

export type PutmeOnDashboard =
  | { kind: "RELEASED"; score: number | null; of: string; aggregate: number | null; weights: string }
  | { kind: "AWAITED"; words: string }
  | null;

/** what the screening score is out of, in words */
export function scoreOf(source: string | null | undefined): string {
  switch (source) {
    case "CBT": return "of 100 · computer-based test";
    case "EXAM": return "of 100 · the Post-UTME examination";
    case "OLEVEL": return "of 100 · from your O’Level results";
    default: return "no screening component";
  }
}

/** a score released by the Academic Office and given to this applicant: the release and the result the API gives with it — only
 *  with an offer of admission read, only for a score of the examination */
export function scoreReleased(a: Pick<Application, "result" | "scoreReleasedAt">): boolean {
  return !!a.scoreReleasedAt && !!a.result;
}

export function putmeOnDashboard(a: Pick<Application, "result" | "scoreReleasedAt" | "screeningSlip" | "decisionReleasedAt" | "decision">): PutmeOnDashboard {
  const r = a.result;
  if (scoreReleased(a) && r) {
    return { kind: "RELEASED", score: r.screening == null ? null : Number(r.screening), of: scoreOf(r.screeningSource),
      aggregate: r.aggregate == null ? null : Number(r.aggregate), weights: `UTME ${r.weightUtme}% · Post-UTME ${r.weightPutme}%` };
  }
  /* the decision read (the API gives it only then) and no result with it: not offered a place, a programme screened without the
     examination, or no score released — nothing is said of a score */
  if (a.decision) return null;
  /* admitted from the JAMB list (V270): no slip and no score here */
  if (a.decisionReleasedAt && !a.screeningSlip) return null;
  if (a.screeningSlip?.published) return { kind: "AWAITED", words: "Shown here with an offer of admission, once the scores are released" };
  return { kind: "AWAITED", words: "After your screening" };
}

/** the UTME score against the programme's UTME cut-off: null when either is not known */
export function utmeMeetsCutoff(r: Pick<ScreeningResult, "utme" | "cutoff">): boolean | null {
  return r.utme == null || r.cutoff == null ? null : Number(r.utme) >= Number(r.cutoff);
}
