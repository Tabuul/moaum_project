"use client";
/** The question bank from a spreadsheet (V322 follow-up): the template with worked examples, a file read and its columns mapped by
 *  name, every row judged on the server — the question, the options, the key as letters, numbers or text, the kind, the difficulty,
 *  the marks — duplicates found in the file and against the bank, the counts shown, and only the valid rows written on Import. */
import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { csvRows, xlsxRows } from "@/lib/xlsx";
import { xlsx } from "@/lib/xlsx-write";
import { QUESTION_FIELDS, detectQuestionMapping, questionHeaderRowIndex, questionRowsOf, type QuestionRow } from "@/lib/question-import";

interface Finding { row: number; stem: string; topic: string | null; kind: string; options: number; answers: number[]; answer: string | null; difficulty: string; marks: number; status: string; codes: string[]; messages: string[] }
interface Result { course: string; dryRun: boolean; summary: { total: number; valid: number; errors: number; duplicatesInFile: number; alreadyInBank: number; imported: number }; rows: Finding[] }

const STATUS: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = {
  VALID: ["Will be added", "ok"], IMPORTED: ["Added", "ok"], ERROR: ["Error", "bad"], DUPLICATE_IN_FILE: ["Duplicate in file", "warn"], ALREADY_IN_BANK: ["Already in the bank", "grey"],
};
const KIND_WORD: Record<string, string> = { MCQ: "Multiple choice", TRUE_FALSE: "True / false", MULTI: "Multiple select" };
const MAX_BYTES = 10 * 1024 * 1024;

export function QuestionImport({ course, courseTitle }: { course: string; courseTitle?: string }) {
  const router = useRouter();
  const file = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [fileName, setFileName] = useState<string | null>(null);
  const [grid, setGrid] = useState<{ header: string[]; rows: string[][] } | null>(null);
  const [mapping, setMapping] = useState<Record<string, number>>({});
  const [result, setResult] = useState<Result | null>(null);
  const [show, setShow] = useState("ALL");
  const required = QUESTION_FIELDS.filter((f) => f.required && mapping[f.key] === undefined);
  const noOptions = grid && mapping.optionA === undefined && mapping.options === undefined;

  function template() {
    const head = ["Topic", "Question", "Option A", "Option B", "Option C", "Option D", "Option E", "Correct Answer", "Kind", "Difficulty", "Marks", "Explanation"];
    const rows = [
      ["Government", "Which arm of government makes laws?", "The executive", "The legislature", "The judiciary", "The press", "", "B", "MCQ", "EASY", "1", "The National Assembly makes laws."],
      ["Government", "The judiciary interprets the law.", "True", "False", "", "", "", "A", "TRUE_FALSE", "EASY", "1", ""],
      ["Numbers", "Which of these are even numbers?", "3", "4", "7", "10", "", "B, D", "MULTI", "MEDIUM", "2", "Both 4 and 10 are even; a candidate earns the marks only with exactly those."],
    ];
    const instructions = [
      ["How to fill the Questions sheet"], [""],
      ["Question", "Required. The text the candidate reads."],
      ["Option A … Option H", "At least two; leave the rest blank. (Or one Options column with the options separated by | or ;)"],
      ["Correct Answer", "Required. The letter (B), the number (2), several letters for a multiple-select question (B, D), or the option's own text."],
      ["Kind", "Optional: MCQ, TRUE_FALSE or MULTI. Left blank it is worked out: several answers is MULTI, True/False alone is TRUE_FALSE, else MCQ."],
      ["Difficulty", "Optional: EASY, MEDIUM or HARD. Blank is MEDIUM."],
      ["Marks", "Optional whole number; blank is 1."],
      ["Topic, Explanation", "Optional. The topic groups the blueprint; the explanation is for the marker and the review, never shown during an examination."],
      [""], ["Every row is judged before anything is written; a question whose text is already in the bank is not added twice. The correct options never leave the server."],
    ];
    const bytes = xlsx([["Questions", [head, ...rows], { headerRows: [0] }], ["Instructions", instructions]]);
    downloadBlob(new Blob([bytes as BlobPart], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }), `${course.replace(/\s+/g, "-")}-question-template.xlsx`);
  }

  async function readFile(f: File) {
    setProblem(null); setResult(null);
    if (f.size > MAX_BYTES) { setProblem({ status: 400, title: "That file is larger than 10 MB." }); return; }
    setBusy(true);
    try {
      const cells = /\.csv$/i.test(f.name) ? csvRows(await f.text()) : await xlsxRows(await f.arrayBuffer());
      const hi = questionHeaderRowIndex(cells);
      const header = (cells[hi] ?? []).map((c) => String(c ?? ""));
      const kept = cells.slice(hi + 1).filter((r) => r.some((c) => String(c ?? "").trim()));
      setGrid({ header, rows: kept.map((r) => r.map((c) => String(c ?? ""))) });
      setMapping(detectQuestionMapping(header));
      setFileName(f.name);
      if (!kept.length) setProblem({ status: 400, title: "No question rows were found under the header." });
    } catch (e) { setProblem({ status: 400, title: "The file could not be read.", detail: e instanceof Error ? e.message : String(e) }); }
    finally { setBusy(false); }
  }

  const rowsIn = (): QuestionRow[] => (grid ? questionRowsOf([grid.header, ...grid.rows], 0, mapping) : []);

  async function send(dryRun: boolean) {
    const rows = rowsIn();
    if (!rows.length) { setProblem({ status: 400, title: "No question rows to check." }); return; }
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/cbt/questions/import", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${dryRun ? "Check" : "Import"} ${rows.length} questions into ${course} from ${fileName ?? "a file"}`) }, body: JSON.stringify({ course, dryRun, fileName, rows }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return; }
      setResult(j as Result);
      setShow((j as Result).summary.errors ? "ERROR" : "ALL");
      if (!dryRun) { notify(`${(j as Result).summary.imported} question${(j as Result).summary.imported === 1 ? "" : "s"} added to the ${course} bank`); router.refresh(); }
    } finally { setBusy(false); }
  }

  async function errorReport() {
    if (!result) return;
    const bad = result.rows.filter((r) => r.status !== "VALID" && r.status !== "IMPORTED");
    const head = ["Original row", "Question", "Options", "Answer given", "Kind", "Status", "Error"];
    const body = bad.map((r) => [r.row, r.stem, r.options, r.answer ?? "", KIND_WORD[r.kind] ?? r.kind, (STATUS[r.status] ?? [r.status])[0], r.messages.join("; ")]);
    downloadBlob(await brandedXlsx(`${course} question import — error report`, head, body, { sheetName: "Errors", serial: docSerial("QBK"), sub: fileName ?? "", noSerialColumn: true }), `${course.replace(/\s+/g, "-")}-question-import-errors.xlsx`);
  }

  const shown = result ? result.rows.filter((r) => show === "ALL" || r.status === show) : [];
  const s = result?.summary;
  return (
    <Panel title="Import questions from a spreadsheet" right={<span className="row row--inline row--tight"><Btn kind="ghost" disabled={busy} onClick={template}>Download template</Btn><Btn kind="primary" disabled={busy} onClick={() => file.current?.click()}>Upload Excel / CSV</Btn><input ref={file} type="file" accept=".xlsx,.xls,.csv" style={{ display: "none" }} onChange={(e) => { const f = e.target.files?.[0]; if (f) void readFile(f); e.target.value = ""; }} /></span>}>
      <PBody>
        <div className="sub2">One row per question into <b>{course}</b>{courseTitle ? ` — ${courseTitle}` : ""}: the question, the options (Option A … H, or one Options column), the correct answer as a letter, a number, several letters, or the option&rsquo;s text; the kind, difficulty, marks, topic and explanation are optional. Every row is judged before anything is written; a question already in the bank is not added twice.</div>
        {problem ? <div className="mt-2"><ProblemNotice problem={problem} /></div> : null}
        {grid ? (
          <div className="mt-2">
            <div className="row row--inline row--tight mb-2"><b>{fileName}</b><span className="sub2">· {grid.rows.length} row{grid.rows.length === 1 ? "" : "s"} · columns mapped</span><span className="grow" />
              <Btn kind="secondary" size="sm" disabled={busy || required.length > 0 || !!noOptions} onClick={() => void send(true)}>Check the file</Btn>
              <Btn kind="go" size="sm" disabled={busy || required.length > 0 || !!noOptions} onClick={() => void send(false)}>Import the valid rows</Btn></div>
            {required.length || noOptions ? <Note kind="bad" title="A required column is not mapped">{[...required.map((f) => f.label), ...(noOptions ? ["Options (Option A… or one Options column)"] : [])].join(", ")}: choose the column below.</Note> : null}
            <div className="grid grid--4">
              {QUESTION_FIELDS.map((f) => (
                <Field key={f.key} id={`qi-${f.key}`} label={f.label} required={f.required}>
                  <select id={`qi-${f.key}`} className="ctl" value={mapping[f.key] ?? ""} onChange={(e) => { const m = { ...mapping }; if (e.target.value === "") delete m[f.key]; else m[f.key] = Number(e.target.value); setMapping(m); }}>
                    <option value="">— not in the file —</option>
                    {grid.header.map((h, i) => <option key={i} value={i}>{h || `Column ${i + 1}`}</option>)}
                  </select>
                </Field>
              ))}
            </div>
          </div>
        ) : null}
        {result && s ? (
          <div className="mt-2">
            <Tiles cls="grid--5" items={[
              ["ROWS", String(s.total), null, fileName ?? ""],
              [result.dryRun ? "WILL BE ADDED" : "ADDED", String(result.dryRun ? s.valid : s.imported), "var(--green-ink)", result.dryRun ? "Valid, not yet written" : "On the bank now"],
              ["ERRORS", String(s.errors), s.errors ? "var(--red-ink)" : null, "Fix in the file and upload again"],
              ["DUPLICATES IN FILE", String(s.duplicatesInFile), null, "The same question twice"],
              ["ALREADY IN THE BANK", String(s.alreadyInBank), null, "Not added twice"],
            ]} />
            <div className="row row--inline row--tight mt-2">
              <select className="ctl" value={show} onChange={(e) => setShow(e.target.value)}>
                <option value="ALL">Every row ({s.total})</option><option value={result.dryRun ? "VALID" : "IMPORTED"}>{result.dryRun ? "Will be added" : "Added"} ({result.dryRun ? s.valid : s.imported})</option>
                <option value="ERROR">Errors ({s.errors})</option><option value="DUPLICATE_IN_FILE">Duplicates in file ({s.duplicatesInFile})</option><option value="ALREADY_IN_BANK">Already in the bank ({s.alreadyInBank})</option>
              </select>
              <span className="grow" />
              {s.errors + s.duplicatesInFile ? <Btn kind="ghost" size="sm" onClick={() => void errorReport()}>Download error report</Btn> : null}
              {result.dryRun && s.valid ? <Btn kind="go" size="sm" disabled={busy} onClick={() => void send(false)}>Import {s.valid} valid question{s.valid === 1 ? "" : "s"}</Btn> : null}
            </div>
            <DTable pageSize={25} noPrint cols={["Row|mid", "Question", "Kind|mid", "Options|num", "Key|mid", "Marks|num", "Status|mid", "Findings"]} rows={shown.map((r) => [
              <span key="n" className="tnum sub2">{r.row}</span>, <span key="s">{r.stem || <i className="sub2">no text</i>}{r.topic ? <div className="sub2">{r.topic}</div> : null}</span>,
              <span key="k" className="sub2">{KIND_WORD[r.kind] ?? r.kind}</span>, <span key="o" className="tnum">{r.options}</span>,
              <span key="a" className="tnum">{r.answers.length ? r.answers.map((i) => String.fromCharCode(65 + i)).join(", ") : r.answer ?? "—"}</span>, <span key="m" className="tnum">{r.marks}</span>,
              <Pil key="st" kind={(STATUS[r.status] ?? ["", "grey"])[1]}>{(STATUS[r.status] ?? [r.status])[0]}</Pil>,
              <span key="f" className="sub2">{r.messages.join("; ")}</span>,
            ])} texts={shown.map((r) => `${r.row} ${r.stem} ${r.status} ${r.codes.join(" ")}`)} />
          </div>
        ) : null}
      </PBody>
    </Panel>
  );
}
