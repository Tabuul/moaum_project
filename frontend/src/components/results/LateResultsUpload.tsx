"use client";

/**
 * V702: late results for a published sheet from one upload — the candidates on its roll with no mark, each raised as a late result
 * (V422) through the chain to Senate, as one raised by hand would be. The file is read here; the server matches each number to the
 * roll and answers every row: raised, not a late result (a mark already, or not on the roll), repeated, or refused with the reason.
 */
import { useState } from "react";
import { Field, Modal } from "@/components/proto/blocks";
import { Btn, Note, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";
import { buildXlsx, csvRows, xlsxRows } from "@/lib/xlsx";
import { downloadBlob } from "@/lib/exportbrand";
import { LATE_TONE, LATE_WORD, lateRows, type LateOutcome, type LateRow } from "@/lib/result-monitor";

interface Answer { courseCode: string; counts: Record<LateOutcome, number>; rows: { row: number; number: string; outcome: LateOutcome; detail: string | null; ref: string | null }[] }
export interface LateCandidateRow { student_id: string; number: string; surname: string; other_names: string }

export function LateResultsUpload({ sheetId, courseCode, caMax, candidates, onClose, onDone }: {
  sheetId: string; courseCode: string; caMax: number; candidates: LateCandidateRow[]; onClose: () => void; onDone: () => void;
}) {
  const [file, setFile] = useState<{ name: string; rows: LateRow[]; problem: string | null } | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [answer, setAnswer] = useState<Answer | null>(null);

  async function read(f: File | undefined) {
    if (!f) return;
    try {
      const table = /\.csv$/i.test(f.name) ? csvRows(await f.text()) : await xlsxRows(await f.arrayBuffer());
      setFile({ name: f.name, ...lateRows(table) });
    } catch {
      setFile({ name: f.name, rows: [], problem: "The file could not be read; upload the Excel template or a CSV." });
    }
    setAnswer(null);
  }

  function template() {
    const rows = candidates.map((c) => [c.number, `${c.surname.toUpperCase()}, ${c.other_names}`, "", "", ""]);
    downloadBlob(buildXlsx(["Matric No.", "Name", `CA (out of ${caMax})`, `Exam (out of ${100 - caMax})`, "Outcome"], rows, "Late results"),
      `${courseCode} late results.xlsx`);
  }

  async function send() {
    if (!file || file.problem || reason.trim().length < 10) return;
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/results/sheets/${sheetId}/late-results`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${courseCode}: late results uploaded — ${reason.trim()}`) },
        body: JSON.stringify({ reason: reason.trim(), rows: file.rows }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: "The late results were not raised" }); return; }
      setAnswer(j as Answer);
      const raised = (j as Answer).counts.RAISED ?? 0;
      notify(`${courseCode}: ${raised} late result${raised === 1 ? "" : "s"} raised for verification.`);
      onDone();
    } finally { setBusy(false); }
  }

  const blocked = !file || !!file.problem || reason.trim().length < 10;
  return (
    <Modal title={`Upload late results — ${courseCode}`} sub="Candidates on the roll with no mark on the published sheet; each goes through the chain to Senate" onClose={onClose}
      foot={answer ? <><span className="grow" /><Btn kind="primary" onClick={onClose}>Done</Btn></> : (
        <><Btn kind="ghost" onClick={onClose}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={blocked || busy} busy={busy} onClick={() => void send()}>
          {file && !file.problem ? `Raise ${file.rows.length} late result${file.rows.length === 1 ? "" : "s"}` : "Raise the late results"}</Btn></>
      )}>
      {answer ? (
        <>
          <div className="row row--inline" style={{ gap: 6, marginBottom: 8 }}>
            {(Object.keys(LATE_WORD) as LateOutcome[]).map((k) => <Pil key={k} kind={LATE_TONE[k]}>{`${LATE_WORD[k]}: ${answer.counts[k] ?? 0}`}</Pil>)}
          </div>
          <DTable noPrint pageSize={20} cols={["Row|num", "Matric No.", "Outcome", "Detail"]}
            rows={answer.rows.map((x) => [x.row, <span className="tnum" key="n">{x.number || "—"}</span>, <Pil key="o" kind={LATE_TONE[x.outcome]}>{LATE_WORD[x.outcome]}</Pil>,
              x.ref ? `Amendment ${x.ref}` : x.detail ?? ""])} />
        </>
      ) : (
        <>
          <p className="sub2">{`${candidates.length} candidate${candidates.length === 1 ? "" : "s"} on the roll have no mark. The template lists them with the columns the upload reads: Matric No., CA, Exam and, for a candidate not graded, the outcome (absent, withheld, incomplete, malpractice or exempted).`}</p>
          <div className="row row--inline" style={{ gap: 8, margin: "6px 0 10px" }}>
            <Btn kind="ghost" onClick={template}>Download the template</Btn>
            <label className="btn btn--ghost" style={{ cursor: "pointer" }}>
              Choose the file
              <input type="file" accept=".xlsx,.csv" hidden onChange={(e) => void read(e.target.files?.[0])} />
            </label>
            {file ? <span className="sub2">{file.name}</span> : null}
          </div>
          {file?.problem ? <Note kind="bad" title="The file cannot go as it is">{file.problem}</Note> : null}
          {file && !file.problem ? <Note kind="info" title={`${file.rows.length} row${file.rows.length === 1 ? "" : "s"} read`}>Each is matched to the roll when it goes; a student with a mark already is passed over, to be corrected by an amendment.</Note> : null}
          <Field id="late-why" label="Why the results are late" required hint="In words Senate can read: why the candidates were not on the sheet, and where the marks come from">
            <textarea id="late-why" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} />
          </Field>
        </>
      )}
    </Modal>
  );
}
