/**
 * V764: the Direct Entry admission template — the list that goes back to JAMB for Direct Entry, as the Academic Office's desk
 * builds it from GET …/de-template (the University's decisions of 14 November 2026): the same five sheets as the UTME template
 * (Admission_Summary, Merit_List, Other_Qualified_Cases, Non_Qualified_Cases, Ranked_sheet; Programme_Summary for the whole
 * session), every registered Direct Entry applicant a row, ranked by the points of their qualification — the A-Level group
 * (A-Level, IJMB, JUPEB) before the diplomas (ND, HND, NCE), the three best subjects summed — qualified or not with the reasons.
 */
import type { Cell } from "./xlsx-write";

export interface DeSubject { subject: string; grade: string | null; points: number | null }
export interface DeRow {
  rank: number; applicationNo: string | null; regNo: string; name: string; gender: string | null; state: string | null; lga: string | null;
  programme: string; entryLevel: number | null; qualification: string | null; institution: string | null; awardedYear: number | null;
  subjects: DeSubject[]; otherQualifications: string | null; points: number | null; unreadGrades?: string | null; deStatus: string;
  olevelUploaded: boolean; olevelMissing: string | null; engGrade: string | null; mathsGrade: string | null; sittings: number | null;
  recordedDecision: string | null; decision: "OFFERED" | "WAITING" | "NOT_OFFERED"; decisionBasis: string | null; decisionNote: string | null;
  released: boolean; qualified: boolean; reason: string | null;
}
export interface DeQuotaRow { criterion: string; percent: number; quota: number; admitted: number; shortfall: number }
export interface DeLgaRow { lga: string; elg: number; sm: number; nm: number; total: number }
export interface DeTemplate {
  kind?: "DE"; session: string; programme: string; asAt: string; summary: Record<string, number | null>;
  quotaDistribution: DeQuotaRow[]; lgaAnalysis: DeLgaRow[]; lgaTotal: DeLgaRow; rows: DeRow[];
  /** every programme's own summary, when the workbook is the whole session's */
  perProgramme?: { programme: string; summary: Record<string, number | null> }[];
}

/** the qualification as JAMB's list names it */
export const DE_BASIS: Record<string, string> = { A_LEVEL: "A-Level", IJMB: "IJMB", JUPEB: "JUPEB", NCE: "NCE", ND: "ND", HND: "HND" };
/** the Direct Entry requirement's verdict, in words */
export const DE_STATUS: Record<string, string> = {
  MET: "Meets the requirement", SHORT: "Short of the requirement", NO_RULE: "No requirement set", UNVERIFIED: "Not captured",
};
const BASIS_LABEL: Record<string, string> = { NM: "National Merit", SM: "State Merit", ELG: "Equality of LG", LOCALITY: "Locality", PLWD: "PLWD", OTHER: "Other" };

/** the columns of a Direct Entry sheet; the non-qualified and ranked sheets add DE REMARKS (the reasons) */
export const DE_COLS = ["SN", "RANK", "REG_NO", "NAME", "GENDER", "STATE", "LGA", "ENTRY LEVEL", "QUALIFICATION", "INSTITUTION", "YEAR",
  "SUBJ1", "SUBJ1 GRADE", "SUBJ2", "SUBJ2 GRADE", "SUBJ3", "SUBJ3 GRADE", "DE POINTS", "OTHER QUALIFICATIONS", "DE REQUIREMENT",
  "ENG GRADE", "MATHS GRADE", "SITTINGS", "GRADES NOT READ", "GENERAL REMARKS"];

/** the remark a row carries: the basis it was offered on, the Board's note, or what the row's place says */
export function deRemark(x: DeRow): string {
  if (x.decisionBasis) return BASIS_LABEL[x.decisionBasis] ?? x.decisionBasis;
  if (x.decisionNote) return x.decisionNote;
  return x.decision === "OFFERED" ? "Recommended" : x.decision === "WAITING" ? "Waiting list" : "Not recommended";
}

/** one applicant's line, numbered i + 1 on its sheet */
export function deLine(x: DeRow, i: number, withReasons = false): Cell[] {
  const s = x.subjects ?? [];
  const line: Cell[] = [i + 1, x.rank, x.regNo, x.name, x.gender ?? "", x.state ?? "", x.lga ?? "", x.entryLevel ?? null,
    x.qualification ? DE_BASIS[x.qualification] ?? x.qualification : null, x.institution ?? null, x.awardedYear ?? null,
    s[0]?.subject ?? null, s[0]?.grade ?? null, s[1]?.subject ?? null, s[1]?.grade ?? null, s[2]?.subject ?? null, s[2]?.grade ?? null,
    x.points ?? null, x.otherQualifications ?? null, DE_STATUS[x.deStatus] ?? x.deStatus, x.engGrade ?? null, x.mathsGrade ?? null,
    x.sittings ?? null, x.unreadGrades ?? null, deRemark(x)];
  if (withReasons) line.push(x.reason ?? "Qualified");
  return line;
}

/** the workbook's sheets: the summary (and the summary by programme for the whole session), then — unless summaryOnly — the merit
 *  list, the other qualified, the non-qualified and the ranked sheet, each under the letterhead the UTME template uses */
export function deSheets(t: DeTemplate, summaryOnly = false): [string, Cell[][]][] {
  const head = (title: string): Cell[][] => [
    [null, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI"],
    [null, `${t.session} DIRECT ENTRY MERIT ADMISSION SUMMARY${t.programme ? ` FOR ${t.programme}` : ""}`],
    [null, `${title} AS AT ${t.asAt}`],
    [], [], [], [],
  ];
  const s = t.summary;
  const ratio = s.deRatio === null || s.deRatio === undefined ? "" : ` (${s.deRatio}%)`;
  const summary: Cell[][] = [...head("SUMMARY OF DIRECT ENTRY ADMISSION"), ["SN", "ITEM", "COUNT"],
    [1, "Total Applicants", s.totalApplicants], [2, "Registered Applicants", s.registeredApplicants], [3, "Qualified Cases", s.qualifiedCases],
    [4, "Non-Qualified Cases", s.nonQualifiedCases], [5, "Total Quota (100%)", s.totalQuota], [6, `DE Quota${ratio}`, s.deQuota],
    [7, "Number On Merit List", s.numberOnMeritList]];
  if (t.quotaDistribution.length) {
    summary.push([], [null, "QUOTA DISTRIBUTION"], ["SN", "ADMISSION CRITERIA", "(%)", "QUOTA", "ADMITTED", "S/FALLS", "REMARK"]);
    t.quotaDistribution.forEach((q, i) => summary.push([i + 1, q.criterion, q.percent, q.quota, q.admitted || "", q.shortfall, q.shortfall ? `${q.admitted} of ${q.quota}` : ""]));
  }
  if (t.lgaAnalysis.length) {
    summary.push([], [null, "NATIONAL/STATE/LOCAL GOVERNMENT ANALYSIS"], ["SN", "LGA NAME", "ELG", "SM", "NM", "TOTAL"]);
    t.lgaAnalysis.forEach((l, i) => summary.push([i + 1, l.lga, l.elg, l.sm, l.nm, l.total]));
    summary.push([null, t.lgaTotal.lga, t.lgaTotal.elg, t.lgaTotal.sm, t.lgaTotal.nm, t.lgaTotal.total]);
  }
  summary.push([], [null, "RANKING"], [null, "By the points of the qualification that counts: A-Level, IJMB and JUPEB (A 5, B 4, C 3, D 2, E 1; A* counts as A) before ND, HND and NCE (Distinction 4, Upper Credit 3, Credit or Lower Credit 2, Merit or Pass 1; a diploma graded A–E counts as A-Level grades); the three best subjects summed; ties by name. A fail counts nothing; a grade that cannot be read counts nothing and is named under GRADES NOT READ, with its qualification."]);
  const sheets: [string, Cell[][]][] = [["Admission_Summary", summary]];
  if (t.perProgramme?.length) {
    sheets.push(["Programme_Summary", [...head("SUMMARY BY PROGRAMME"),
      ["SN", "PROGRAMME", "TOTAL APPLICANTS", "REGISTERED", "QUALIFIED", "NON-QUALIFIED", "TOTAL QUOTA", "DE QUOTA", "ON MERIT LIST"],
      ...t.perProgramme.map((p, i) => [i + 1, p.programme, p.summary.totalApplicants, p.summary.registeredApplicants, p.summary.qualifiedCases,
        p.summary.nonQualifiedCases, p.summary.totalQuota, p.summary.deQuota, p.summary.numberOnMeritList] as Cell[])]]);
  }
  if (!summaryOnly) {
    const ranked = [...t.rows].sort((a, b) => a.programme.localeCompare(b.programme) || a.rank - b.rank);
    const merit = ranked.filter((x) => x.decision === "OFFERED");
    const other = ranked.filter((x) => x.decision === "WAITING");
    const non = ranked.filter((x) => x.decision === "NOT_OFFERED");
    const withReasons = [...DE_COLS, "DE REMARKS"];
    sheets.push(
      ["Merit_List", [...head("MERIT LIST"), DE_COLS, ...merit.map((x, i) => deLine(x, i))]],
      ["Other_Qualified_Cases", [...head("OTHER QUALIFIED CASES"), DE_COLS, ...other.map((x, i) => deLine(x, i))]],
      ["Non_Qualified_Cases", [...head("NON-QUALIFIED CASES"), withReasons, ...non.map((x, i) => deLine(x, i, true))]],
      ["Ranked_sheet", [...head("RANKED SHEET"), withReasons, ...ranked.map((x, i) => deLine(x, i, true))]],
    );
  }
  return sheets;
}

/** the whole session's summary: every programme's own template added up, so each count, quota and criterion is the programme's */
export function mergeDeTemplates(parts: DeTemplate[], session: string, asAt: string): DeTemplate {
  const sum = (k: string) => parts.reduce<number | null>((a, p) => (p.summary[k] === null || p.summary[k] === undefined ? a : (a ?? 0) + Number(p.summary[k])), null);
  const summary: Record<string, number | null> = {};
  for (const k of ["totalApplicants", "registeredApplicants", "qualifiedCases", "nonQualifiedCases", "totalQuota", "deQuota", "numberOnMeritList"]) summary[k] = sum(k);
  // one ratio for the session only when every programme read the same
  const ratios = [...new Set(parts.map((p) => p.summary.deRatio).filter((r) => r !== null && r !== undefined))];
  summary.deRatio = ratios.length === 1 ? Number(ratios[0]) : null;
  const quota = new Map<string, DeQuotaRow>();
  for (const p of parts) for (const q of p.quotaDistribution) {
    const c = quota.get(q.criterion) ?? { criterion: q.criterion, percent: q.percent, quota: 0, admitted: 0, shortfall: 0 };
    c.quota += q.quota; c.admitted += q.admitted; c.shortfall += q.shortfall; quota.set(q.criterion, c);
  }
  const lga = new Map<string, DeLgaRow>();
  for (const p of parts) for (const l of p.lgaAnalysis) {
    const c = lga.get(l.lga) ?? { lga: l.lga, elg: 0, sm: 0, nm: 0, total: 0 };
    c.elg += l.elg; c.sm += l.sm; c.nm += l.nm; c.total += l.total; lga.set(l.lga, c);
  }
  const lgaRows = [...lga.values()].sort((a, b) => a.lga.localeCompare(b.lga));
  const lgaTotal = lgaRows.reduce((t, l) => ({ lga: "TOTAL", elg: t.elg + l.elg, sm: t.sm + l.sm, nm: t.nm + l.nm, total: t.total + l.total }), { lga: "TOTAL", elg: 0, sm: 0, nm: 0, total: 0 });
  return {
    kind: "DE", session: parts[0]?.session ?? session, programme: "", asAt: parts[0]?.asAt ?? asAt, summary,
    quotaDistribution: [...quota.values()], lgaAnalysis: lgaRows, lgaTotal, rows: parts.flatMap((p) => p.rows),
    perProgramme: parts.map((p) => ({ programme: p.programme, summary: p.summary })),
  };
}

/** a programme's file name, as the workbook and the ZIP name it */
export function deFileName(t: Pick<DeTemplate, "programme" | "session">): string {
  return `DE ADMISSION TEMPLATE ${t.programme ? t.programme.replace(/[^A-Za-z0-9]+/g, " ").trim() : "ALL PROGRAMMES"} ${t.session.replace("/", "-")}.xlsx`;
}
