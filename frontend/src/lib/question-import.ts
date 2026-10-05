/**
 * The columns of a question-bank spreadsheet and how a file's headings are matched to them: by name, never by position,
 * an exact heading first and then the first heading that contains an alias, each column taken once. The options come from
 * Option A … Option H columns, or from one Options column split on |, ; or a new line. The server resolves the answer
 * (letters, numbers or the option's text) and judges every row; this only reads the file.
 */
export interface QuestionRow { row: number; topic: string; stem: string; options: string[]; answer: string; kind: string; difficulty: string; marks: string; explanation: string }

export const OPTION_LETTERS = ["A", "B", "C", "D", "E", "F", "G", "H"] as const;

export const QUESTION_FIELDS: { key: string; label: string; required?: boolean; aliases: string[] }[] = [
  { key: "topic", label: "Topic", aliases: ["topic", "section", "unit", "module"] },
  { key: "stem", label: "Question", required: true, aliases: ["question", "stem", "question text", "item"] },
  ...OPTION_LETTERS.map((l) => ({ key: `option${l}`, label: `Option ${l}`, aliases: [`option ${l.toLowerCase()}`, `option${l.toLowerCase()}`, `${l.toLowerCase()}`, `choice ${l.toLowerCase()}`, `answer ${l.toLowerCase()}`, `opt ${l.toLowerCase()}`] })),
  { key: "options", label: "Options (one column)", aliases: ["options", "choices", "alternatives"] },
  { key: "answer", label: "Correct answer", required: true, aliases: ["correct answer", "answer", "correct", "key", "answer key", "correct option", "correct options"] },
  { key: "kind", label: "Kind", aliases: ["kind", "type", "question type", "format"] },
  { key: "difficulty", label: "Difficulty", aliases: ["difficulty", "level", "hardness"] },
  { key: "marks", label: "Marks", aliases: ["marks", "mark", "score", "points", "weight"] },
  { key: "explanation", label: "Explanation", aliases: ["explanation", "rationale", "feedback", "solution", "note", "notes"] },
];

/** which column (0-based) feeds each field; a field absent from the file is absent from the map */
export function detectQuestionMapping(header: string[]): Record<string, number> {
  const h = header.map((x) => String(x ?? "").trim().toLowerCase().replace(/[_]+/g, " ").replace(/\s*\*$/, "").replace(/\s+/g, " "));
  const map: Record<string, number> = {};
  const used = new Set<number>();
  for (const f of QUESTION_FIELDS) {
    const i = h.findIndex((x, idx) => !used.has(idx) && f.aliases.includes(x));
    if (i >= 0) { map[f.key] = i; used.add(i); }
  }
  for (const f of QUESTION_FIELDS) {
    if (map[f.key] !== undefined) continue;
    const i = h.findIndex((x, idx) => !used.has(idx) && x && f.aliases.some((a) => a.length > 2 && x.includes(a)));
    if (i >= 0) { map[f.key] = i; used.add(i); }
  }
  return map;
}

/** the header row: the first row that names the question and at least one option or an options column, else the first row */
export function questionHeaderRowIndex(cells: string[][]): number {
  const i = cells.findIndex((row) => { const m = detectQuestionMapping(row); return m.stem !== undefined && (m.optionA !== undefined || m.options !== undefined); });
  return i < 0 ? 0 : i;
}

/** the file's rows as the server judges them, a row number from the sheet on each, blank rows left out */
export function questionRowsOf(cells: string[][], headerIndex: number, mapping: Record<string, number>): QuestionRow[] {
  const g = (r: string[], key: string) => { const i = mapping[key]; return i === undefined || i < 0 ? "" : String(r[i] ?? "").trim(); };
  return cells.slice(headerIndex + 1).map((r, i) => {
    let options = OPTION_LETTERS.map((l) => g(r, `option${l}`)).filter(Boolean);
    if (!options.length && g(r, "options")) options = g(r, "options").split(/\s*[|;\n]\s*/).map((o) => o.trim()).filter(Boolean);
    return { row: headerIndex + i + 2, topic: g(r, "topic"), stem: g(r, "stem"), options, answer: g(r, "answer"), kind: g(r, "kind"), difficulty: g(r, "difficulty"), marks: g(r, "marks"), explanation: g(r, "explanation") };
  }).filter((r) => r.stem || r.options.length || r.answer);
}
