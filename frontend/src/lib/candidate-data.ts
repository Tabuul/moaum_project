/**
 * The three other JAMB downloads (proto/part54.html): the passports named by
 * the number, the dates of birth and the O'Level results. Read in the
 * browser, matched on the registration number, counted both ways.
 */

/** twelve digits then two or three letters — the shape of every number JAMB sends */
export const JNUM = /(\d{12}[A-Za-z]{2,3})/;

export function jkey(v: unknown): string {
  return String(v ?? "").trim().toUpperCase();
}

export function norm(s: unknown): string {
  return String(s ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");
}

/** the number inside a filename, found rather than assumed; "" when there is none */
export function jambNumFromName(filename: string): { num: string; how: string } {
  const base = String(filename ?? "").split(/[\\/]/).pop() ?? "";
  const m = JNUM.exec(base);
  if (!m) return { num: "", how: "" };
  const num = m[1].toUpperCase();
  const rest = base.replace(/\.[^.]+$/, "");
  return { num, how: rest.toUpperCase() === num ? "" : `from ${base}` };
}

export interface DobRow {
  num: string;
  raw: string;
  surname: string;
  first: string;
  middle: string;
  dob: string;
  ambiguous: boolean;
  reading: string;
  kind: string;
}

const DOB_COLS: Record<string, string> = { regnumber: "num", regno: "num", rgnum: "num", surname: "surname", firstname: "first", middlename: "middle", dateofbirth: "dob", regtype: "kind" };
const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

export function dobParse(rows: string[][]): { rows: DobRow[]; trimmed: number } | { err: string } {
  if (!rows.length) return { err: "The file has no rows in it." };
  const head = rows[0];
  const ix: Record<string, number> = {};
  head.forEach((h, i) => {
    const f = DOB_COLS[norm(h)];
    if (f && ix[f] === undefined) ix[f] = i;
  });
  if (ix.num === undefined || ix.dob === undefined) {
    return { err: `This file names no registration number (Reg. Number) or no DateofBirth column. The row it read was: ${head.slice(0, 8).join(", ")}` };
  }
  const out: DobRow[] = [];
  let trimmed = 0;
  for (let i = 1; i < rows.length; i++) {
    const r = rows[i];
    const raw = r[ix.num];
    if (!raw) continue;
    const num = jkey(raw);
    if (String(raw) !== num) trimmed++;
    const d = String(r[ix.dob] ?? "").trim();
    const m = /^(\d{1,2})-(\d{1,2})-(\d{4})$/.exec(d);
    const amb = !!(m && Number(m[1]) <= 12 && Number(m[2]) <= 12);
    out.push({
      num, raw: String(raw),
      surname: r[ix.surname] ?? "", first: r[ix.first] ?? "", middle: r[ix.middle] ?? "",
      dob: d, ambiguous: amb,
      reading: m ? `${m[1]} ${MONTHS[Number(m[2]) - 1] ?? "?"} ${m[3]}` : "",
      kind: r[ix.kind] ?? "",
    });
  }
  return { rows: out, trimmed };
}

export const CRED: Record<string, true> = { A1: true, B2: true, B3: true, C4: true, C5: true, C6: true };

/** JAMB abbreviates and is not consistent about it */
export function olSubject(s: unknown): string {
  const n = norm(s);
  if (n === "litenglish" || n === "literatureinenglish") return "Literature in English";
  if (/^english/.test(n)) return "English Language";
  if (/^math/.test(n)) return "Mathematics";
  if (/^princofaccount|^financialaccount|^accounting/.test(n)) return "Financial Accounting";
  if (/^bibleknowled|^crk|^christianreligious/.test(n)) return "Christian Religious Studies";
  if (/^computerstudies/.test(n)) return "Computer Studies / ICT";
  return String(s ?? "").trim();
}

/** one sitting as JAMB sent it: the body and year, the exam number it is verified against, the subjects */
export interface OlSitting {
  type: string;
  series: string;
  year: string;
  exnum: string;
  subjects: { raw: string; subject: string; grade: string }[];
}

/** the grades in order of worth, best first */
export const GRADES = ["A1", "B2", "B3", "C4", "C5", "C6", "D7", "E8", "F9"];

export interface OlRow {
  num: string;
  /** the best grade per subject across the sittings — what the credit check reads */
  subjects: { raw: string; subject: string; grade: string }[];
  /** every sitting apart: WAEC, NECO, NABTEB, one or two of them */
  sittings: OlSitting[];
  type: string;
  series: string;
  year: string;
  exnum: string;
  credits: number;
  eng: string | null;
  maths: string | null;
  meets: boolean;
}

const OL_COLS: Record<string, string> = { regnum: "num", regnumber: "num", subjectname: "subject", grade: "grade", examseries: "series", examyear: "year", examtype: "type", examnumber: "exnum", datecreated: "created", instname: "inst" };

export function olParse(rows: string[][]): { rows: OlRow[]; lines: number } | { err: string } {
  if (!rows.length) return { err: "The file has no rows in it." };
  const head = rows[0];
  const ix: Record<string, number> = {};
  head.forEach((h, i) => {
    const f = OL_COLS[norm(h)];
    if (f && ix[f] === undefined) ix[f] = i;
  });
  if (ix.num === undefined || ix.subject === undefined || ix.grade === undefined) {
    return { err: `This file names no RegNum, SubjectName or Grade column. The row it read was: ${head.slice(0, 9).join(", ")}` };
  }
  const by = new Map<string, OlRow>();
  let n = 0;
  for (let i = 1; i < rows.length; i++) {
    const r = rows[i];
    if (!r[ix.num]) continue;
    n++;
    const k = jkey(r[ix.num]);
    let c = by.get(k);
    if (!c) {
      c = { num: k, subjects: [], sittings: [], type: r[ix.type] ?? "", series: r[ix.series] ?? "", year: r[ix.year] ?? "", exnum: r[ix.exnum] ?? "", credits: 0, eng: null, maths: null, meets: false };
      by.set(k, c);
    }
    /* a sitting is one body, one year, one exam number; the file is one row per subject */
    const type = String(r[ix.type] ?? "").trim();
    const year = String(r[ix.year] ?? "").trim();
    const exnum = String(r[ix.exnum] ?? "").trim();
    let sitting = c.sittings.find((s) => s.type === type && s.year === year && s.exnum === exnum);
    if (!sitting) {
      sitting = { type, series: String(r[ix.series] ?? "").trim(), year, exnum, subjects: [] };
      c.sittings.push(sitting);
    }
    const subject = { raw: r[ix.subject], subject: olSubject(r[ix.subject]), grade: String(r[ix.grade] ?? "").trim().toUpperCase() };
    sitting.subjects.push(subject);
  }
  const rank = (g: string) => { const i = GRADES.indexOf(g); return i < 0 ? GRADES.length : i; };
  for (const c of by.values()) {
    /* the best grade per subject across the sittings */
    const best = new Map<string, { raw: string; subject: string; grade: string }>();
    for (const s of c.sittings) for (const g of s.subjects) {
      const have = best.get(g.subject);
      if (!have || rank(g.grade) < rank(have.grade)) best.set(g.subject, g);
    }
    c.subjects = [...best.values()];
    let credits = 0;
    for (const s of c.subjects) {
      if (CRED[s.grade]) credits++;
      if (s.subject === "English Language") c.eng = s.grade;
      if (s.subject === "Mathematics") c.maths = s.grade;
    }
    c.credits = credits;
    c.meets = credits >= 5 && !!(c.eng && CRED[c.eng]) && !!(c.maths && CRED[c.maths]);
  }
  return { rows: [...by.values()], lines: n };
}

export interface Match<T extends { num: string }> {
  candidates: number;
  matched: T[];
  orphan: T[];
  missing: { num: string; name: string; list: string }[];
  byNum: Record<string, { num: string; name: string; list: string }>;
}

/** matched both ways: what arrived for nobody, and who is still waiting */
export function capsMatch<T extends { num: string }>(items: T[], cands: { num: string; name: string; list: string }[]): Match<T> {
  const byNum: Record<string, { num: string; name: string; list: string }> = {};
  for (const c of cands) byNum[c.num] = c;
  const matched: T[] = [];
  const orphan: T[] = [];
  const have = new Set<string>();
  for (const it of items) {
    have.add(it.num);
    if (byNum[it.num]) matched.push(it);
    else orphan.push(it);
  }
  return { candidates: cands.length, matched, orphan, missing: cands.filter((c) => !have.has(c.num)), byNum };
}

/* ── V298: the duplicate check, read the way the database reads it (admissions.exam_body, olevel_series_class, olevel_exam_key) ── */

/** JAMB's ExamType as the examining body */
export function examBody(type: unknown): "WAEC" | "NECO" | "NABTEB" | "OTHER" {
  const t = String(type ?? "").toUpperCase();
  if (t.includes("NECO")) return "NECO";
  if (t.includes("NABTEB")) return "NABTEB";
  if (t.includes("WAEC") || t.includes("WASSCE") || t.includes("WASC")) return "WAEC";
  return "OTHER";
}

/** the private November/December examinations (GCE, "private", "external") apart from the school's */
export function seriesClass(type: unknown, series: unknown): "INTERNAL" | "EXTERNAL" {
  const s = String(series ?? "").toUpperCase();
  if (/(NOV|DEC|PRIVATE|EXTERNAL|GCE)/.test(s)) return "EXTERNAL";
  if (s.trim()) return "INTERNAL";
  return /(GCE|PRIVATE|EXTERNAL|NOV|DEC)/.test(String(type ?? "").toUpperCase()) ? "EXTERNAL" : "INTERNAL";
}

/** the exam number as compared: upper case, without spaces, dashes, slashes or dots; "" when there is none */
export function examKey(n: unknown): string {
  return String(n ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
}

export function examYear(y: unknown): string {
  return /(?:19|20)\d{2}/.exec(String(y ?? ""))?.[0] ?? "";
}

const sigOf = (s: OlSitting) => [...new Set(s.subjects.map((g) => `${g.subject}=${g.grade}`))].sort().join(",");

export interface OlFileDuplicates {
  /** V315: a candidate with the same exam number twice under other grades — one sitting cannot have two sets of grades */
  sameSitting: { num: string; body: string; year: string; series: "INTERNAL" | "EXTERNAL"; numbers: string[] }[];
  /** the same result twice in the file (the same body and exam number with the same grades, or, without a number, the same examination and grades) */
  sameResult: { num: string; body: string; year: string; exnum: string }[];
  /** an exam number the file gives more than one candidate */
  sharedNumber: { body: string; exnum: string; nums: string[] }[];
  /** a subject listed more than once in one sitting */
  repeatedSubjects: { num: string; body: string; year: string; subject: string; times: number }[];
}

/** what the file itself repeats, before anything is recorded — the server checks the same against the record. The rule (V315): a
 *  duplicate is the SAME EXAM NUMBER; another number of the same body, whatever the year and series, is another sitting, recorded —
 *  results are combined across sittings. */
export function olDuplicates(rows: OlRow[]): OlFileDuplicates {
  const out: OlFileDuplicates = { sameSitting: [], sameResult: [], sharedNumber: [], repeatedSubjects: [] };
  const byNumber = new Map<string, { body: string; exnum: string; nums: Set<string> }>();
  for (const r of rows) {
    const kept: OlSitting[] = [];
    for (const s of r.sittings) {
      const body = examBody(s.type), year = examYear(s.year), cls = seriesClass(s.type, s.series), key = examKey(s.exnum);
      const counts = new Map<string, number>();
      for (const g of s.subjects) counts.set(g.subject, (counts.get(g.subject) ?? 0) + 1);
      for (const [subject, times] of counts) if (times > 1) out.repeatedSubjects.push({ num: r.num, body, year: s.year, subject, times });
      if (key) {
        const k = `${body}|${key}`;
        const e = byNumber.get(k) ?? { body, exnum: s.exnum, nums: new Set<string>() };
        e.nums.add(r.num);
        byNumber.set(k, e);
      }
      const same = kept.find((o) => examBody(o.type) === body && ((key && examKey(o.exnum) === key && sigOf(o) === sigOf(s))
        || ((!key || !examKey(o.exnum)) && year && body !== "OTHER" && examYear(o.year) === year && seriesClass(o.type, o.series) === cls && sigOf(o) === sigOf(s))));
      if (same) { out.sameResult.push({ num: r.num, body, year: s.year, exnum: s.exnum }); continue; }
      const clash = key ? kept.find((o) => examBody(o.type) === body && examKey(o.exnum) === key) : undefined;
      if (clash) {
        const hit = out.sameSitting.find((x) => x.num === r.num && x.body === body && examKey(x.numbers[0]) === key);
        if (hit) hit.numbers.push(s.exnum);
        else out.sameSitting.push({ num: r.num, body, year, series: cls, numbers: [clash.exnum, s.exnum] });
        continue;
      }
      kept.push(s);
    }
  }
  for (const e of byNumber.values()) if (e.nums.size > 1) out.sharedNumber.push({ body: e.body, exnum: e.exnum, nums: [...e.nums].sort() });
  return out;
}

/** V298: a finding of the O'Level upload check, as the register gives it (admissions.olevel_duplicates) */
export interface OlevelDuplicateRow {
  id: string; kind: "SAME_RESULT" | "SAME_SITTING" | "NUMBER_ELSEWHERE"; state: "SKIPPED" | "HELD" | "KEPT" | "USED" | "OPEN" | "VERIFIED";
  jamb_key: string; candidate?: string | null; programme?: string | null; source_name: string; sitting_no: number;
  exam_body: string; exam_type_raw?: string | null; exam_year?: string | null; exam_series?: string | null; exam_number?: string | null; subjects?: string | null;
  other_jamb_key?: string | null; other_candidate?: string | null; other_exam_year?: string | null; other_exam_number?: string | null; other_subjects?: string | null; other_on_record?: boolean;
  detected_at: string; decided_at?: string | null; decided_office?: string | null; decided_by?: string | null; note?: string | null;
}
export interface OlevelDuplicateRegister { session: string; rows: OlevelDuplicateRow[] }

export const FINDING_WORD: Record<OlevelDuplicateRow["kind"], [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  SAME_RESULT: ["Already on record", "grey"],
  SAME_SITTING: ["Same exam number, other grades", "bad"],
  NUMBER_ELSEWHERE: ["Exam number on another applicant", "warn"],
};
export const FINDING_STATE: Record<OlevelDuplicateRow["state"], [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  SKIPPED: ["Not recorded again", "grey"], HELD: ["Held — to decide", "bad"], KEPT: ["Result on record kept", "ok"],
  USED: ["Uploaded result used", "ok"], OPEN: ["Open — to verify", "warn"], VERIFIED: ["Verified", "ok"],
};
