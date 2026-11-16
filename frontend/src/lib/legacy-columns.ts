/**
 * Records → Migrate from Old Portal: an old-portal export read onto the keys each importer takes, and the rows of a registration or
 * results file checked before anything is sent. A course registration or past result is recorded as the student took it: the file's
 * Course Title, Credit Units and Category on every row (the University's decision of 15 November 2026). Credit units are read only
 * from a column naming them (Credit Units, Credit Unit, CU) — the old portal's own Units column is a status code (1 GST, 2 core,
 * 3 elective, 0 carry-over), so an undergraduate file that carries it and no credit units is stopped; the postgraduate uploads keep
 * reading their Units column as they always have.
 */

export type LegacyTab = "biodata" | "pgstudents" | "students" | "registration" | "results" | "pgregistration" | "pgresults" | "pgresearch" | "jamb" | "passports" | "clearance";

/** a field's column in the file, found once from the header, with how its cell is normalised */
export type Col = { key: string; idx: number; norm?: (s: string) => string };

/** why a whole file is not read: said once, before any row is checked */
export type FileStop = { title: string; detail: string };

/* any institutional matriculation number: a 2–6 letter prefix (MOAU / MOAUM / BSU …) then 2–8 slash
   segments. Postgraduate numbers spell out faculty/department/programme (e.g. MOAU/AM/BSM/PGDM/MSC/25/0021),
   so the shape is kept permissive rather than tied to the undergraduate MOAUM/DEPT/YY/NNNN form. */
export const MATRIC_OK = /^[A-Z]{2,6}(\/[A-Z0-9]{1,12}){2,8}$/i;

/** a session as the record writes it */
export const SESSION_OK = /^[0-9]{4}\/[0-9]{4}$/;

/** the undergraduate uploads that record the course as taken: course title, credit units and category on every row */
export function asTakenKind(kind: LegacyTab): boolean {
  return kind === "registration" || kind === "results";
}

/** the uploads read a session and semester at a time */
export function scopedKind(kind: LegacyTab): boolean {
  return kind === "registration" || kind === "results" || kind === "pgregistration" || kind === "pgresults";
}

/** postgraduate study has two semesters */
export function twoSemesterKind(kind: LegacyTab): boolean {
  return kind === "pgregistration" || kind === "pgresults";
}

/** a semester cell to its number — First / 1st / 1 / "First semester" → 1, Second / 2nd / 2 → 2, Summer / Third / 3rd / 3 → 3
 *  (postgraduate study: 1 and 2 only); anything else is no semester (0), never a guess */
export function semNum(v: string | null | undefined, twoSemesters = false): number {
  const t = String(v ?? "").trim().toLowerCase().replace(/\s+/g, " ").replace(/^semester:?\s*/, "").replace(/\s*semester$/, "");
  const n = /^(first|1st|1)$/.test(t) ? 1 : /^(second|2nd|2)$/.test(t) ? 2 : /^(summer|third|3rd|3)$/.test(t) ? 3 : 0;
  return twoSemesters && n === 3 ? 0 : n;
}

/** an Excel date serial, a DD-MM-YYYY / ISO string, or the 0000-00-00 sentinel → ISO or "" */
export function normDob(s: string): string {
  const t = s.trim();
  if (!t || /^0{2,4}[-/]0{1,2}[-/]0{1,2}$/.test(t)) return "";
  if (/^\d{4}-\d{2}-\d{2}$/.test(t)) return t;
  const m = t.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$/); // DD-MM-YYYY (Nigerian order)
  if (m) return `${m[3]}-${m[2].padStart(2, "0")}-${m[1].padStart(2, "0")}`;
  if (/^\d{4,6}(\.0+)?$/.test(t)) { // Excel serial (days since 1899-12-30)
    const d = new Date(Date.UTC(1899, 11, 30) + Math.trunc(Number(t)) * 86400000);
    const y = d.getUTCFullYear();
    return y >= 1940 && y <= 2015 ? d.toISOString().slice(0, 10) : "";
  }
  return "";
}

/** a Nigerian mobile with a possibly-lost leading zero or +234 → 0XXXXXXXXXX or "" */
export function normPhone(s: string): string {
  const d = s.replace(/\D/g, "");
  if (d.length === 11 && d.startsWith("0")) return d;
  if (d.length === 10) return "0" + d;
  if (d.length === 13 && d.startsWith("234")) return "0" + d.slice(3);
  if (d.length === 14 && d.startsWith("2340")) return "0" + d.slice(4);
  return "";
}

const headerOf = (header: (string | null | undefined)[]) => header.map((x) => String(x ?? "").trim().toLowerCase());
/** a column that names credit units: Credit Units, Credit Unit, CU */
const isCredit = (h: string) => /credit/.test(h) || /^cu$/.test(h);
/** a column that names units without saying credit — the old portal's status code */
const isUnitsLike = (h: string) => /^units?$/.test(h) || h.includes("unit");

/* map an old-portal export's own column names onto the keys the importer reads, so a real file
   uploads without renaming — CA in [0,40], Exam in [0,60], Total in [0,100]; an out-of-range
   mark is skipped and reported, not fatal. */
/* resolve each field's column index from the header ONCE — the header is the same for every
   row, so matching column names with regex per row (over tens of thousands of rows) is what
   froze the tab. Here it is done once and every row is then a cheap read by index. */
export function resolveColumns(kind: LegacyTab, header: (string | null | undefined)[]): Col[] {
  const h = headerOf(header);
  const at = (...names: RegExp[]) => h.findIndex((x) => names.some((n) => n.test(x)));
  const cols: Col[] = [];
  const add = (key: string, idx: number, norm?: (s: string) => string) => { if (idx >= 0) cols.push({ key, idx, norm }); };
  add("matric", at(/matric/, /reg\.?\s*(no|number)/, /registration/, /mat\.?\s*no/, /matno/));
  if (kind === "biodata" || kind === "pgstudents") {
    add("jamb", at(/jamb/, /utme\s*reg/));
    add("surname", at(/surname/, /last\s*name/));
    add("otherNames", at(/other\s*name/, /first\s*name/, /given/));
    add("name", at(/full\s*name/, /^name$/, /student\s*name/, /^names$/));
    add("programme", at(/programme/, /program/, /course of study/));
    add("sex", at(/^sex$/, /gender/));
    add("dob", at(/birth/, /^dob$/, /d\.o\.b/), normDob);
    add("entryMode", at(/entry\s*mode/, /mode of entry/, /mode_entry/, /^mode$/, /admission type/));
    add("entrySession", at(/entry\s*session/, /^yoe$/, /year of entry/, /admission\s*session/, /session admitted/));
    add("level", at(/current\s*level/, /^level$/, /^lvl$/));
    add("phone", at(/phone/, /mobile/, /gsm/, /^tel$/), normPhone);
    add("email", at(/^e-?mail$/, /e-?mail/));
    add("address", at(/^address$/, /home\s*address/, /residential/, /contact\s*address/));
    add("nationality", at(/nationality/));
    add("state", at(/state\s*of\s*origin/, /^state$/));
    add("lga", at(/^lga$/, /local\s*govt/, /local\s*government/));
    add("guardianName", at(/guardian\s*name/, /guardianname/));
    add("guardianAddress", at(/guardian\s*address/, /guardianaddress/));
    add("sponsorName", at(/sponsor\s*name/, /sponsorname/));
    add("sponsorAddress", at(/sponsor\s*address/, /sponsoraddress/));
    add("nokName", at(/nok\s*name/, /nokname/, /next\s*of\s*kin.*name/, /kin\s*name/));
    add("nokAddress", at(/nok\s*address/, /nokaddress/, /next\s*of\s*kin.*address/, /kin\s*address/));
    add("extracurricular", at(/extra.?curricular/, /hobb/));
    add("appno", at(/^appno$/, /application\s*no/, /app\s*no/));
    add("schoolId", at(/school\s*id/, /schoolid/, /^school$/));
  } else if (kind === "students") {
    add("surname", at(/surname/, /last\s*name/));
    add("otherNames", at(/other\s*name/, /first\s*name/, /given/));
    add("name", at(/full\s*name/, /^name$/, /student\s*name/, /^names$/));
    add("programme", at(/programme/, /program/, /course of study/, /department|dept/));
    add("sex", at(/^sex$/, /gender/));
    add("dob", at(/birth/, /^dob$/, /d\.o\.b/), normDob);   // V717: day first, as the other tabs
    add("entryMode", at(/entry\s*mode/, /mode of entry/, /^mode$/, /admission type/));
    add("entrySession", at(/entry\s*session/, /admission\s*session/, /year of entry/, /session admitted/));
    add("level", at(/current\s*level/, /^level$/, /^lvl$/));
    add("schoolId", at(/school\s*id/, /schoolid/, /^school$/));
    // V381: a CCE (part-time) student is told by the route or the study mode as well as the entry mode
    add("studyMode", at(/study\s*mode/, /mode of study/, /^study$/));
    add("route", at(/^route$/, /admission\s*route/, /study\s*route/, /^programme\s*type$/));
  } else if (kind === "jamb") {
    add("jamb", at(/jamb/, /jamb\s*reg/, /jamb\s*no/, /jamb\s*number/, /utme\s*reg/));
  } else if (kind === "pgresearch") {
    add("topic", at(/topic/, /research\s*title/, /thesis\s*title/, /project\s*title/, /dissertation\s*title/, /^title$/));
    add("stage", at(/^stage$/, /status/));
    add("supervisor", at(/^supervisor$/, /main\s*supervisor/, /first\s*supervisor/, /supervisor\s*1/));
    add("supervisor2", at(/second\s*supervisor/, /supervisor\s*2/));
    add("coSupervisor", at(/co-?\s*supervisor/));
    add("vivaScore", at(/viva\s*score/, /defence\s*score/));
    add("vivaGrade", at(/viva\s*grade/, /research\s*grade/));
    add("vivaOutcome", at(/viva\s*outcome/, /defence\s*outcome/, /^outcome$/, /recommendation/));
    add("plagiarism", at(/plagiar/, /similarity/));
    add("pgsr", at(/pgsr/));
    add("proposalApproved", at(/proposal\s*approv/, /proposal\s*date/));
    add("seminarHeld", at(/seminar/));
    add("titleRegistered", at(/title\s*regist/));
    add("panelConstituted", at(/panel/));
    add("draftSubmitted", at(/draft/));
    add("vivaHeld", at(/viva\s*(held|date)/, /defence\s*date/));
    add("finalSubmitted", at(/final\s*sub/, /bound/));
    add("cleared", at(/clear/));
    add("awardDate", at(/award/, /graduat/));
  } else {
    add("course", at(/course\s*code/, /^course$/, /^code$/, /subject\s*code/));
    if (asTakenKind(kind)) {
      // the course as the student took it: credit units only from a column naming them (never the old portal's Units status
      // code, which is never sent), the title, and the category
      add("creditUnits", at(/credit/, /^cu$/));
      add("title", at(/course\s*title/, /^title$/));
      add("category", at(/categ/));
    } else {
      add("units", at(/unit/, /^cu$/, /credit/));
    }
    add("level", at(/^level$/, /^lvl$/));
    add("session", at(/session/));
    add("semester", at(/semester/, /^sem$/));
    if (kind === "pgregistration" || kind === "pgresults") {
      add("title", at(/course\s*title/, /^title$/, /descrip/));
      add("kind", at(/^kind$/, /^type$/, /category/));
      add("mode", at(/study\s*mode/, /^mode$/));
    }
    if (kind === "results" || kind === "pgresults") {
      add("ca", at(/\bca\b/, /continuous/, /c\.a/));
      add("exam", at(/exam/, /examination/));
      add("total", at(/total/, /^score$/, /^mark$/, /aggregate/));
    }
    if (kind === "results") {
      add("outcome", at(/outcome/, /remark/, /status/, /grade/));
    }
  }
  return cols;
}

/** one spreadsheet row → the importer's keys, using the pre-resolved columns (no per-row regex) */
export function applyRow(cols: Col[], r: (string | number | null | undefined)[]): Record<string, string> {
  const o: Record<string, string> = {};
  for (const c of cols) {
    let v = String(r[c.idx] ?? "").trim();
    if (c.norm) v = c.norm(v);
    if (v) o[c.key] = v;
  }
  return o;
}

/** why a registration or results file cannot be read at all, from its header alone: the old portal's Units column with no credit
 *  units beside it (its 1/2/3/0 is a status code), or no column for the course or how it was taken. Null for a file that reads. */
export function columnsStop(kind: LegacyTab, header: (string | null | undefined)[]): FileStop | null {
  if (!asTakenKind(kind)) return null;
  const h = headerOf(header);
  if (h.some(isUnitsLike) && !h.some(isCredit)) {
    return {
      title: "The file's Units column is not credit units.",
      detail: "The old portal's Units column is a status code (1 GST, 2 core, 3 elective, 0 carry-over), not credit units — add a Credit Units column with the credit units each course carried when the student took it, and upload the file again.",
    };
  }
  const cols = new Set(resolveColumns(kind, header).map((c) => c.key));
  const missing = [["course", "Course Code"], ["title", "Course Title"], ["creditUnits", "Credit Units"], ["category", "Category"]]
    .filter(([k]) => !cols.has(k)).map(([, label]) => label);
  if (!missing.length) return null;
  const list = missing.length === 1 ? missing[0] : `${missing.slice(0, -1).join(", ")} and ${missing[missing.length - 1]}`;
  return {
    title: `The file has no ${list} column${missing.length === 1 ? "" : "s"}.`,
    detail: "Every row records the course as the student took it — its code, title, credit units and category (Core, Elective, GST or Carry-over; the old portal's 2, 3, 1, 0 are read too) — and nothing is taken from today's catalogue in its place. Download the template, add the columns, and upload the file again.",
  };
}

/** what keeps a row back before it is sent: null to send it; "" to pass over it without a word (the header row repeated in the
 *  file); otherwise the reason, and the row is listed in the rows set aside */
export function rowHeld(kind: LegacyTab, o: Record<string, string>): string | null {
  if (!o.matric) return asTakenKind(kind) ? "No matriculation number" : "";
  if (/^matric/i.test(o.matric)) return "";
  /* on the matric-keyed imports, hold back a row with no valid matriculation number so the
     officer can download and fix it, rather than send it only for the server to reject it */
  const matricKind = kind === "biodata" || kind === "pgstudents" || kind === "students" || kind === "jamb" || kind === "pgresearch";
  if (matricKind && !MATRIC_OK.test(o.matric)) return "No valid matriculation number";
  return null;
}

/** a course code as a file may write it, compared one way: upper case, single spaces, ABC123 as ABC 123 */
export function codeKey(code: string | null | undefined): string {
  const t = String(code ?? "").toUpperCase().trim().replace(/\s+/g, " ");
  return t.replace(/^([A-Z]{2,4})\s*([0-9]{3})$/, "$1 $2");
}

/** what one copy of a student's course says — two copies that agree are one row stated twice; two that differ cannot both stand */
export function rowFingerprint(o: Record<string, string>): string {
  const bare = (s: string | undefined) => String(s ?? "").replace(/\s/g, "");
  return [String(o.title ?? "").trim().replace(/\s+/g, " "), bare(o.creditUnits), bare(o.category).toUpperCase(),
    bare(o.ca), bare(o.exam), bare(o.total), String(o.outcome ?? "").trim().toUpperCase()].join("|");
}

/** where each batch of a group ends: about `size` rows a batch, cut only between students, so a student's courses of a semester
 *  always go up (and are checked) together; the rows are in student order */
export function chunkEnds(rows: Record<string, string>[], size: number, keyOf: (r: Record<string, string>) => string = (r) => (r.matric ?? "").toUpperCase()): number[] {
  const ends: number[] = [];
  let start = 0;
  let i = 0;
  while (i < rows.length) {
    let j = i + 1;
    const k = keyOf(rows[i]);
    while (j < rows.length && keyOf(rows[j]) === k) j++;
    if (j - start > size && i > start) { ends.push(i); start = i; }
    i = j;
  }
  if (rows.length > start) ends.push(rows.length);
  return ends;
}

/** where each batch ends when the rows are simply taken `size` at a time */
export function fixedEnds(count: number, size: number): number[] {
  const ends: number[] = [];
  for (let e = size; e < count; e += size) ends.push(e);
  if (count > 0) ends.push(count);
  return ends;
}

/** the end of the batch that starts at `from` — the rest of the rows when no end lies past it, so a loop over the batches always ends */
export function batchEnd(ends: number[], from: number): number {
  return ends.find((e) => e > from) ?? Number.POSITIVE_INFINITY;
}

export type RowGroup = { session: string; semester: number; rows: Record<string, string>[]; ends: number[] };
export type Grouped = { groups: RowGroup[]; invalid: Record<string, string>[]; repeated: number; stop: FileStop | null };

/** the rows of a registration or results file by session and semester, each group's batches cut between students. A file with a
 *  Session (or Semester) column is read by its cells — a blank or malformed cell sets the row aside, with its reason, and never
 *  falls back to the screen; the screen's session and semester stand only for a file without the column. On the undergraduate
 *  uploads a student's course stated twice in the file (whatever the code's spacing) is set aside before anything is sent: the
 *  first copy goes up when the copies agree, none when they differ. */
export function groupScopedRows(kind: LegacyTab, rows: Record<string, string>[], cols: Col[], fallback: { session: string; semester: string }, size = 400): Grouped {
  const two = twoSemesterKind(kind);
  const asTaken = asTakenKind(kind);
  const hasSession = cols.some((c) => c.key === "session");
  const hasSemester = cols.some((c) => c.key === "semester");
  const fbSession = fallback.session.trim();
  const fbSemester = semNum(fallback.semester, two);
  if (!hasSession && !SESSION_OK.test(fbSession)) {
    return { groups: [], invalid: [], repeated: 0, stop: { title: "No session to load against.",
      detail: "The file has no Session column: add one (YYYY/YYYY on every row), or enter the session in the field above." } };
  }
  if (!hasSemester && !fbSemester) {
    return { groups: [], invalid: [], repeated: 0, stop: { title: "No semester to load against.",
      detail: `The file has no Semester column: add one (${two ? "First or Second" : "First, Second or Summer"} on every row), or choose the semester in the field above.` } };
  }
  const invalid: Record<string, string>[] = [];
  const placed: { o: Record<string, string>; session: string; semester: number; key: string | null }[] = [];
  for (const o of rows) {
    const ses = hasSession ? (o.session ?? "").trim() : fbSession;
    const sem = hasSemester ? semNum(o.semester, two) : fbSemester;
    const why: string[] = [];
    if (!SESSION_OK.test(ses)) why.push(ses ? `The session "${ses}" is not written YYYY/YYYY` : "The Session cell is blank");
    if (!sem) why.push(o.semester ? `The semester "${o.semester}" is not ${two ? "First or Second" : "First, Second or Summer"}` : "The Semester cell is blank");
    if (why.length) { invalid.push({ ...o, reason: why.join("; ") }); continue; }
    placed.push({ o, session: ses, semester: sem, key: asTaken && o.course ? `${o.matric.toUpperCase()}|${codeKey(o.course)}|${ses}|${sem}` : null });
  }
  // one student's course stated more than once across the whole file
  const copies = new Map<string, { fp: string; line: string; conflict: boolean; sent: boolean }>();
  for (const p of placed) {
    if (!p.key) continue;
    const fp = rowFingerprint(p.o);
    const c = copies.get(p.key);
    if (!c) copies.set(p.key, { fp, line: p.o.line ?? "", conflict: false, sent: false });
    else if (c.fp !== fp) c.conflict = true;
  }
  let repeated = 0;
  const map = new Map<string, RowGroup>();
  for (const p of placed) {
    const c = p.key ? copies.get(p.key) : undefined;
    if (c && c.conflict) {
      invalid.push({ ...p.o, reason: "The same student and course appear more than once in the file with a different title, credit units, category or mark — none is loaded; keep one row" });
      repeated++;
      continue;
    }
    if (c && c.sent) {
      invalid.push({ ...p.o, reason: `The same student and course appear earlier in the file${c.line ? ` (row ${c.line})` : ""}` });
      repeated++;
      continue;
    }
    if (c) c.sent = true;
    const gk = `${p.session}|${p.semester}`;
    let g = map.get(gk);
    if (!g) { g = { session: p.session, semester: p.semester, rows: [], ends: [] }; map.set(gk, g); }
    g.rows.push(p.o);
  }
  const groups = [...map.values()];
  for (const g of groups) {
    if (asTaken) {
      // a student's rows together (in the file's order), so no batch splits them
      g.rows = g.rows.map((o, i) => ({ o, i })).sort((a, b) => {
        const x = (a.o.matric ?? "").toUpperCase(); const y = (b.o.matric ?? "").toUpperCase();
        return x < y ? -1 : x > y ? 1 : a.i - b.i;
      }).map((e) => e.o);
      g.ends = chunkEnds(g.rows, size);
    } else {
      g.ends = fixedEnds(g.rows.length, size);
    }
  }
  return { groups, invalid, repeated, stop: null };
}
