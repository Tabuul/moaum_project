/**
 * Reading a CAPS list: the rows of a spreadsheet become the rows the API
 * loads, every course resolved against the University's programmes, and
 * every doubt named by line and registration number.
 *
 * Two layouts arrive at the Academic Office: the raw CAPS download (RG_NUM,
 * CO_NAME, …) and the file the office builds from it (regno, programme, …).
 * They share not one column name, so headings are matched on a normalised
 * form. The list KIND — UTME or Direct Entry — is declared before the file
 * is read and nothing in the file may change it; a row that contradicts it
 * is a finding, and the API refuses the whole list on the same rule.
 */

export type ListKind = "UTME" | "DIRECT_ENTRY";

export interface Programme {
  code: string;
  name: string;
  deptCode: string;
  facultyCode: string;
  facultyName?: string;
  jambName: string | null;
  /** every further name JAMB has used for it (V018) */
  jambNames?: string[];
  category: string;
  archived: boolean;
}

/** The cut-offs a session's admission settings state: a faculty's, and a programme's own where set. */
export interface Cutoffs {
  faculty: Record<string, number>;
  programme: Record<string, number>;
  /** the one cut-off the list loads under (V024); when stated, the faculty's and programme's are the screening's, not the loading's */
  general?: number;
}

export interface ParsedRow {
  line: number;
  /** The cut-off this candidate fell under, when the settings say so: read, shown, not loaded. */
  belowCutoff: number | null;
  jambRegNo: string;
  name: string;
  surname: string;
  otherNames: string;
  sex: string;
  stateOfOrigin: string;
  lga: string;
  aggregate: number | null;
  courseName: string | null;
  jambCode: string | null;
  programme: Programme | null;
  subjects: [string, number | null][];
  eng: number | null;
  raw: Record<string, string>;
}

export interface Finding {
  line: number;
  regNo: string;
  message: string;
  /** A blocking finding keeps the list from being loaded at all. */
  blocking: boolean;
  /** A row held back by the cut-off: the rest of the list still loads. */
  excluded?: boolean;
}

export interface CapsParse {
  rows: ParsedRow[];
  findings: Finding[];
  layout: "CAPS download" | "built by this office";
  columns: number;
  /** Course names JAMB used that are on no alias — each needs a person before the list can load. */
  unresolved: string[];
  /** Rows under the cut-off the settings state: read, shown, not loaded. */
  belowCutoff: number;
}

export type CapsResult = CapsParse | { error: string };

const COLUMNS: Record<string, string> = {
  // the raw CAPS download
  rgnum: "regno", rgcandname: "name", rgsex: "sex", statename: "state",
  rgaggregate: "agg", coname: "coursename", lganame: "lga",
  subject1: "s1", rgsub1score: "s1s", subject2: "s2", rgsub2score: "s2s",
  subject3: "s3", rgsub3score: "s3s", engscore: "eng",
  // the office's derivative
  regno: "regno", name: "name", sex: "sex", state: "state",
  agregate: "agg", aggregate: "agg", programme: "coursecode", lga: "lga",
  sub1: "s1", sub1score: "s1s", sub2: "s2", sub2score: "s2s",
  sub3: "s3", sub3score: "s3s", sub4score: "eng", session: "session",
};

export const REG_NO = /^\d{12}[A-Z]{2,3}$/;

export function norm(s: string | null | undefined): string {
  return String(s ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");
}

function integer(v: string): number | null {
  return /^-?\d+$/.test(v) ? Number(v) : null;
}

/** "Surname Given Other" as CAPS writes it → ["Surname", "Given Other"]. */
export function splitName(name: string): [string, string] {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return ["", ""];
  return [parts[0], parts.slice(1).join(" ")];
}

export function parseCaps(rows: string[][], kind: ListKind, programmes: Programme[], cutoffs?: Cutoffs): CapsResult {
  if (!rows.length) return { error: "The file has no rows in it." };
  const head = rows[0];
  const ix: Record<string, number> = {};
  head.forEach((h, i) => {
    const f = COLUMNS[norm(h)];
    if (f && ix[f] === undefined) ix[f] = i;
  });
  if (ix.regno === undefined) {
    return {
      error:
        "The first row of this file names no registration-number column. The importer reads headings rather " +
        "than positions, and looks for RG_NUM (the CAPS download) or regno (the file this office builds). " +
        `The row it read was: ${head.slice(0, 8).filter(Boolean).join(", ") || "(empty)"}`,
    };
  }
  if (ix.coursename === undefined && ix.coursecode === undefined) {
    return {
      error:
        "This file names neither a course (CO_NAME) nor a course code (programme), so there is no way to " +
        "tell what anybody was admitted to.",
    };
  }

  const byCode = new Map<string, Programme>();
  const byJambName = new Map<string, Programme>();
  for (const p of programmes) {
    byCode.set(p.code, p);
    if (p.jambName) byJambName.set(norm(p.jambName), p);
    for (const n of p.jambNames ?? []) byJambName.set(norm(n), p);
  }

  const layout = ix.coursename !== undefined ? "CAPS download" : "built by this office";
  const out: ParsedRow[] = [];
  const findings: Finding[] = [];
  const unresolved = new Set<string>();
  const seen = new Set<string>();

  for (let i = 1; i < rows.length; i++) {
    const r = rows[i] ?? [];
    const g = (f: string) => (ix[f] === undefined ? "" : (r[ix[f]] ?? ""));
    const line = i + 1;
    const regRaw = g("regno");
    if (!regRaw) continue;
    const regNo = regRaw.trim().toUpperCase();
    const flag = (message: string, blocking = true, excluded = false) =>
      findings.push({ line, regNo, message, blocking, ...(excluded ? { excluded } : {}) });

    if (!REG_NO.test(regNo)) {
      flag(`"${regRaw}" is not the shape of a JAMB registration number (twelve digits then two or three letters)`);
    }

    let programme: Programme | null = null;
    let code: string | null = null;
    let courseName: string | null = null;
    if (ix.coursename !== undefined) {
      courseName = g("coursename");
      programme = byJambName.get(norm(courseName)) ?? null;
      code = programme?.code ?? null;
      if (!programme) {
        unresolved.add(courseName);
        flag(`JAMB course "${courseName}" is on no alias — the University cannot tell which programme it means`);
      }
    } else {
      code = g("coursecode").toUpperCase();
      programme = byCode.get(code) ?? null;
      courseName = programme?.jambName ?? null;
      if (!programme) flag(`code ${code} is not one of the University's programmes`);
    }
    if (programme && programme.category !== "UNDER GRADUATE") {
      flag(`${programme.name} is a ${programme.category.toLowerCase()} programme; it is not admitted through this list`);
    }
    if (programme && programme.archived) {
      flag(`${programme.name} is archived; the University no longer admits into it`);
    }

    const agg = integer(g("agg"));
    const parts = [integer(g("s1s")), integer(g("s2s")), integer(g("s3s")), integer(g("eng"))];
    if (kind === "UTME") {
      if (!agg) {
        flag("a UTME row with no aggregate — is this the Direct Entry list?");
      } else if (!parts.includes(null) && agg !== (parts as number[]).reduce((a, b) => a + b, 0)) {
        flag(`the aggregate ${agg} is not the sum of the four scores (${(parts as number[]).reduce((a, b) => a + b, 0)})`, false);
      }
    } else if (agg) {
      flag(`a Direct Entry row carrying an aggregate of ${agg} — the two lists have been mixed`);
    }

    let belowCutoff: number | null = null;
    if (kind === "UTME" && cutoffs && programme && agg) {
      const cutoff = cutoffs.general ?? cutoffs.programme[programme.code] ?? cutoffs.faculty[programme.facultyCode];
      if (cutoff === undefined) {
        flag(`no UTME cut-off is set for ${programme.name} or its faculty in the admission settings`);
      } else if (agg < cutoff) {
        belowCutoff = cutoff;
        flag(`aggregate ${agg} is under the cut-off of ${cutoff} for ${programme.name} — read, not loaded`, false, true);
      }
    }

    if (seen.has(regNo)) flag("the same candidate appears twice in this file");
    seen.add(regNo);

    const name = g("name");
    const [surname, otherNames] = splitName(name);
    const sexRaw = g("sex").toUpperCase();
    const sex = ({ F: "F", M: "M", FEMALE: "F", MALE: "M" } as Record<string, string>)[sexRaw] ?? g("sex");

    const raw: Record<string, string> = {};
    head.forEach((h, c) => {
      if (h) raw[h] = r[c] ?? "";
    });

    out.push({
      line,
      belowCutoff,
      jambRegNo: regNo,
      name,
      surname,
      otherNames,
      sex,
      stateOfOrigin: g("state"),
      lga: g("lga"),
      aggregate: kind === "UTME" && agg ? agg : null, // 0 is not a score
      courseName,
      jambCode: code,
      programme,
      subjects: [[g("s1"), integer(g("s1s"))], [g("s2"), integer(g("s2s"))], [g("s3"), integer(g("s3s"))]],
      eng: integer(g("eng")),
      raw,
    });
  }
  if (!out.length) return { error: "The file has a heading row and no rows under it." };
  return {
    rows: out,
    findings,
    layout,
    columns: head.filter(Boolean).length,
    unresolved: [...unresolved],
    belowCutoff: out.filter((r) => r.belowCutoff !== null).length,
  };
}

export function isError(r: CapsResult): r is { error: string } {
  return "error" in r;
}

/**
 * The list as this browser read it, as CSV: every row with the programme it
 * resolved to and every finding against it, so the office can keep what the
 * screen showed and work the file in Excel. Nothing here is loaded.
 */
export function toCsv(p: CapsParse, kind: ListKind): string {
  const cell = (v: unknown): string => {
    const s = v === null || v === undefined ? "" : String(v);
    return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const byLine = new Map<number, string[]>();
  for (const f of p.findings) byLine.set(f.line, [...(byLine.get(f.line) ?? []), f.message]);
  const head = ["Line", "Registration number", "Surname", "Other names", "Sex", "State", "LGA", kind === "UTME" ? "Aggregate" : "Entry", "JAMB course", "Code", "Programme", "Below cut-off", "Findings"];
  const lines = [head.map(cell).join(",")];
  for (const r of p.rows) {
    lines.push([
      r.line, r.jambRegNo, r.surname, r.otherNames, r.sex, r.stateOfOrigin, r.lga,
      kind === "UTME" ? r.aggregate ?? "" : "Direct Entry",
      r.courseName ?? "", r.programme?.code ?? r.jambCode ?? "", r.programme?.name ?? "",
      r.belowCutoff !== null ? r.belowCutoff : "",
      (byLine.get(r.line) ?? []).join("; "),
    ].map(cell).join(","));
  }
  return lines.join("\r\n") + "\r\n";
}

export function blockingFindings(p: CapsParse): Finding[] {
  return p.findings.filter((f) => f.blocking);
}

/** The request body the API loads: NewCapsBatch. */
export interface NewCapsBatch {
  session: string;
  source: "CAPS_DOWNLOAD" | "CAPS_API";
  filename: string | null;
  fileSha256: string;
  listKind: ListKind;
  downloadedOn: string;
  rows: {
    jambRegNo: string;
    surname: string;
    otherNames: string;
    jambCode: string;
    aggregate: number | null;
    sex: string | null;
    stateOfOrigin: string | null;
    lga: string | null;
    entryMode: "UTME" | "DIRECT_ENTRY";
    raw: Record<string, string>;
  }[];
}

export function toRequest(
  p: CapsParse,
  meta: { session: string; filename: string | null; fileSha256: string; listKind: ListKind; downloadedOn: string },
): NewCapsBatch {
  return {
    session: meta.session,
    source: "CAPS_DOWNLOAD",
    filename: meta.filename,
    fileSha256: meta.fileSha256,
    listKind: meta.listKind,
    downloadedOn: meta.downloadedOn,
    rows: p.rows.filter((r) => r.belowCutoff === null).map((r) => ({
      jambRegNo: r.jambRegNo,
      surname: r.surname || "(no name)",
      otherNames: r.otherNames,
      jambCode: r.jambCode ?? "",
      aggregate: r.aggregate,
      sex: r.sex || null,
      stateOfOrigin: r.stateOfOrigin || null,
      lga: r.lga || null,
      entryMode: meta.listKind,
      raw: r.raw,
    })),
  };
}

export async function sha256Hex(buf: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", buf);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
