/** The Post-UTME score on the applicant's dashboard, held until their admission is decided (21 October 2026, V617, after V608 and
 *  V610). The API gives the result only once the Academic Office has released the scores and the decision is the applicant's to read
 *  (offered, waiting list or not offered), and only where the score is the Post-UTME examination's — the CBT or the written
 *  examination of an index programme: the aggregate computed from the O'Level result for a programme screened without the
 *  examination is never shown. Before the decision nothing is said of a score, on the Overview or the Screening result. The
 *  programme's cut-off is a UTME cut-off (of 400, admissions.cutoff_for), so it is read against the UTME score, never against the
 *  aggregate (of 100). Node-tested. */
import type { Application, ScreeningResult } from "./applicant.ts";

export type PutmeOnDashboard = { score: number | null; of: string; aggregate: number | null; weights: string } | null;

/** what the screening score is out of, in words */
export function scoreOf(source: string | null | undefined): string {
  switch (source) {
    case "CBT": return "of 100 · computer-based test";
    case "EXAM": return "of 100 · the Post-UTME examination";
    case "OLEVEL": return "of 100 · from your O’Level results";
    default: return "no screening component";
  }
}

/** the Post-UTME score and the Screening result screen (21 October 2026, V617): held from every applicant until their admission is
 *  decided — a decision they may read, offered, waiting list or not offered (the API gives it, and the result with it, only then) */
export function screeningResultOpen(a: Pick<Application, "decision">): boolean {
  return !!a.decision;
}

/** a score released by the Academic Office and given to this applicant: the release and the result the API gives with it — only
 *  for a score of the examination */
export function scoreReleased(a: Pick<Application, "result" | "scoreReleasedAt">): boolean {
  return !!a.scoreReleasedAt && !!a.result;
}

export function putmeOnDashboard(a: Pick<Application, "result" | "scoreReleasedAt" | "decision">): PutmeOnDashboard {
  const r = a.result;
  /* held until the admission is decided (V617): with no decision to read, or no result given with it — a programme screened without
     the examination, or no score released — nothing is said of a score */
  if (!screeningResultOpen(a) || !scoreReleased(a) || !r) return null;
  return { score: r.screening == null ? null : Number(r.screening), of: scoreOf(r.screeningSource),
    aggregate: r.aggregate == null ? null : Number(r.aggregate), weights: `UTME ${r.weightUtme}% · Post-UTME ${r.weightPutme}%` };
}

/** the UTME score against the programme's UTME cut-off: null when either is not known */
export function utmeMeetsCutoff(r: Pick<ScreeningResult, "utme" | "cutoff">): boolean | null {
  return r.utme == null || r.cutoff == null ? null : Number(r.utme) >= Number(r.cutoff);
}
