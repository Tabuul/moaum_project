"use client";

/**
 * A subject's continuous-assessment sheet (V355): each student, a score in each part of the session's assessment (within its
 * maximum), the total and whether complete. The office and the subject's lecturers enter scores while the subject is not locked;
 * the server refuses a score above a part's maximum, a student not registered for the subject, a lecturer's student of another
 * class, and anything once the subject is locked. A score cleared is kept empty, never deleted.
 */
import { useEffect, useMemo, useState } from "react";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { day, jcall, when } from "@/lib/jupeb";

export interface CaComponent { id: string; code: string; title: string; max_score: number; ord: number }
export interface CaRow { application_id: string; application_no: string; name: string; class_name: string | null; exam_no: string | null; scores: Record<string, number | null>; total: number | null; out_of: number | null; complete: boolean }
export interface CaSheetData {
  session: string; subject: { id: string; code: string; title: string }; components: CaComponent[]; lock: { locked_at: string; locked_by: string | null } | null;
  unlocks?: { unlocked_at: string; unlock_reason: string; unlocked_by: string | null }[]; rows: CaRow[]; due?: string | null;
}

const fmt = (n: number | null | undefined) => (n == null ? "" : Number(n).toLocaleString("en-NG", { maximumFractionDigits: 2 }));

/** the sheet, editable while the subject is not locked; saving sends only the cells changed */
export function CaSheetEditor({ url, saveUrl, canEdit, extra }: { url: string; saveUrl: string; canEdit: boolean; extra?: (d: CaSheetData, reload: () => void) => React.ReactNode }) {
  const [d, setD] = useState<CaSheetData | null>(null);
  const [draft, setDraft] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let live = true;
    void jcall<CaSheetData>(url).then((r) => { if (!live) return; if (r.ok) { setD(r.data); setDraft({}); } else notifyProblem(r.problem); });
    return () => { live = false; };
  }, [url, tick]);
  const key = (a: string, c: string) => `${a}|${c}`;
  const changed = useMemo(() => Object.entries(draft).filter(([k, v]) => {
    if (!d) return false;
    const [a, c] = k.split("|");
    const was = d.rows.find((r) => r.application_id === a)?.scores[c];
    return (v.trim() === "" ? null : Number(v)) !== (was == null ? null : Number(was));
  }), [draft, d]);
  if (!d) return <p className="sub2">Loading the sheet…</p>;
  const locked = !!d.lock;
  const editable = canEdit && !locked;
  const bad = changed.filter(([k, v]) => { const c = d.components.find((x) => x.id === k.split("|")[1]); return v.trim() !== "" && (!Number.isFinite(Number(v)) || Number(v) < 0 || (c && Number(v) > Number(c.max_score))); });
  async function save() {
    setBusy(true);
    try {
      const scores = changed.map(([k, v]) => { const [applicationId, componentId] = k.split("|"); return { applicationId, componentId, score: v.trim() === "" ? null : Number(v) }; });
      const r = await jcall<CaSheetData>(saveUrl, "PUT", { subjectId: d!.subject.id, scores }, `JUPEB assessment: ${d!.subject.title} (${scores.length} scores)`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      setD({ ...d!, ...r.data, rows: r.data.rows.length || !d!.rows.length ? r.data.rows : d!.rows }); setDraft({}); setTick((t) => t + 1);
      notify(`${scores.length} score${scores.length === 1 ? "" : "s"} saved.`);
    } finally { setBusy(false); }
  }
  async function excel() {
    downloadBlob(await brandedXlsx(`JUPEB continuous assessment — ${d!.subject.title} (${d!.subject.code}), ${d!.session}`,
      ["Application No", "Exam No", "Name", "Class", ...d!.components.map((c) => `${c.title} (/${fmt(c.max_score)})`), `Total (/${fmt(d!.rows[0]?.out_of)})`, "Complete"],
      d!.rows.map((r) => [r.application_no, r.exam_no ?? "", r.name, r.class_name ?? "", ...d!.components.map((c) => fmt(r.scores[c.id])), fmt(r.total), r.complete ? "Yes" : "No"]),
      { sheetName: "Assessment", serial: docSerial("JUPEBCA"), meta: [["Subject", `${d!.subject.title} (${d!.subject.code})`], ["Session", d!.session], ["State", locked ? "Locked (final)" : "Open"]] }),
      `jupeb-ca-${d!.subject.code.replace(/[^A-Za-z0-9]+/g, "")}-${d!.session.replace("/", "-")}.xlsx`);
  }
  const complete = d.rows.filter((r) => r.complete).length;
  return (
    <>
      <div className="row" style={{ gap: "var(--s-2)", flexWrap: "wrap", marginBottom: "var(--s-2)" }}>
        {locked ? <Pil kind="ok">{`Locked ${when(d.lock!.locked_at)}${d.lock!.locked_by ? ` by ${d.lock!.locked_by}` : ""}`}</Pil> : <Pil kind="warn">Open</Pil>}
        <Pil kind={complete === d.rows.length && d.rows.length ? "ok" : "info"}>{`${complete} of ${d.rows.length} complete`}</Pil>
        {d.due ? <Pil kind="info">{`Due to the Board ${day(d.due)}`}</Pil> : null}
        <Btn kind="ghost" disabled={!d.rows.length} onClick={() => void excel()}>Excel</Btn>
        {extra ? extra(d, () => setTick((t) => t + 1)) : null}
        {editable ? <Btn kind="primary" disabled={busy || !changed.length || bad.length > 0} onClick={() => void save()}>{busy ? "Saving…" : changed.length ? `Save ${changed.length} score${changed.length === 1 ? "" : "s"}` : "Save"}</Btn> : null}
      </div>
      {!d.components.length ? <Note kind="info" title="No parts of the assessment set">The JUPEB Office sets the session&rsquo;s parts of the continuous assessment (each with its maximum) before scores are entered.</Note> : (
        <DTable pageSize={50} cols={["Application No", "Name", "Class", ...d.components.map((c) => `${c.title} /${fmt(c.max_score)}|num`), `Total /${fmt(d.rows[0]?.out_of)}|num`, "|mid"]}
          texts={d.rows.map((r) => `${r.application_no} ${r.name}`)}
          rows={d.rows.map((r) => [r.application_no, r.name, r.class_name ?? "—",
            ...d.components.map((c) => {
              const k = key(r.application_id, c.id);
              const v = draft[k] ?? (r.scores[c.id] == null ? "" : String(r.scores[c.id]));
              const wrong = v.trim() !== "" && (!Number.isFinite(Number(v)) || Number(v) < 0 || Number(v) > Number(c.max_score));
              return editable ? <input key={c.id} className="ctl" style={{ width: 72, textAlign: "right", borderColor: wrong ? "var(--bad)" : undefined }} inputMode="decimal"
                aria-label={`${r.name}: ${c.title}`} value={v} onChange={(e) => setDraft({ ...draft, [k]: e.target.value })} /> : fmt(r.scores[c.id]) || "—";
            }),
            fmt(r.total) || "—", r.complete ? <Pil key="c" kind="ok">Complete</Pil> : <Pil key="c" kind="grey">Not yet</Pil>])} />
      )}
      {bad.length ? <p className="sub2" style={{ color: "var(--bad)" }}>A score is above its part&rsquo;s maximum, or not a number.</p> : null}
      {d.unlocks?.length ? <p className="sub2 mt-2">{`Unlocked before: ${d.unlocks.map((u) => `${when(u.unlocked_at)} (${u.unlock_reason}${u.unlocked_by ? `, ${u.unlocked_by}` : ""})`).join("; ")}`}</p> : null}
    </>
  );
}
