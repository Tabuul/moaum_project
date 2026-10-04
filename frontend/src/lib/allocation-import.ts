/**
 * The columns of the bulk course allocation file (V321) and how a file's headings are matched to them:
 * by name, never by position, exact headings first and then the first heading that contains an alias,
 * each column taken once. The mapping is shown and can be changed before validation.
 */
export interface RowIn {
  row: number; staffId: string; lecturerName: string; lecturerDept: string; courseCode: string; courseTitle: string; courseDept: string;
  programme: string; level: string; session: string; semester: string; role: string; crossDepartment: string;
}

export const FIELDS: { key: keyof Omit<RowIn, "row">; label: string; required?: boolean; aliases: string[] }[] = [
  { key: "staffId", label: "Staff ID", required: true, aliases: ["staff id", "staff number", "staff no", "pno", "staffid", "staff_number"] },
  { key: "lecturerName", label: "Lecturer name", aliases: ["lecturer name", "lecturer", "name of lecturer", "full names", "name"] },
  { key: "lecturerDept", label: "Lecturer department", aliases: ["lecturer department", "lecturer dept", "lecturer_department", "department"] },
  { key: "courseCode", label: "Course code", required: true, aliases: ["course code", "course_code", "code", "course"] },
  { key: "courseTitle", label: "Course title", aliases: ["course title", "title", "course_title"] },
  { key: "courseDept", label: "Course department", aliases: ["course department", "course dept", "course_department", "owning department"] },
  { key: "programme", label: "Programme", aliases: ["programme code", "programme", "program", "programme name", "programme_code"] },
  { key: "level", label: "Level", aliases: ["level"] },
  { key: "session", label: "Session", required: true, aliases: ["session", "academic session", "academic_session", "session code"] },
  { key: "semester", label: "Semester", required: true, aliases: ["semester", "semester code", "term"] },
  { key: "role", label: "Role", aliases: ["role", "teaching role", "capacity"] },
  { key: "crossDepartment", label: "Cross-department", aliases: ["cross-department", "cross department", "cross_department", "other department", "service"] },
];

/** which column (0-based) feeds each field; a field absent from the file is absent from the map */
export function detectMapping(header: string[]): Record<string, number> {
  const h = header.map((x) => String(x ?? "").trim().toLowerCase().replace(/\s*\*$/, ""));
  const map: Record<string, number> = {};
  const used = new Set<number>();
  for (const f of FIELDS) {
    const i = h.findIndex((x, idx) => !used.has(idx) && f.aliases.includes(x));
    if (i >= 0) { map[f.key] = i; used.add(i); }
  }
  for (const f of FIELDS) {
    if (map[f.key] !== undefined) continue;
    const i = h.findIndex((x, idx) => !used.has(idx) && x && f.aliases.some((a) => x.includes(a)));
    if (i >= 0) { map[f.key] = i; used.add(i); }
  }
  return map;
}

/** the header row: the first row that names at least three of the fields, else the first row */
export function headerRowIndex(cells: string[][]): number {
  const i = cells.findIndex((row) => Object.keys(detectMapping(row)).length >= 3);
  return i < 0 ? 0 : i;
}

/** the file's rows as the server reads them, a row number from the sheet on each, blank rows left out */
export function rowsOf(cells: string[][], headerIndex: number, mapping: Record<string, number>, fallback: { session: string; semester: string }): RowIn[] {
  const g = (r: string[], key: string) => { const i = mapping[key]; return i === undefined || i < 0 ? "" : String(r[i] ?? "").trim(); };
  return cells.slice(headerIndex + 1).map((r, i) => ({
    row: headerIndex + i + 2, staffId: g(r, "staffId"), lecturerName: g(r, "lecturerName"), lecturerDept: g(r, "lecturerDept"), courseCode: g(r, "courseCode"),
    courseTitle: g(r, "courseTitle"), courseDept: g(r, "courseDept"), programme: g(r, "programme"), level: g(r, "level"),
    session: g(r, "session") || fallback.session, semester: g(r, "semester") || fallback.semester, role: g(r, "role"), crossDepartment: g(r, "crossDepartment"),
  })).filter((r) => r.staffId || r.courseCode);
}
