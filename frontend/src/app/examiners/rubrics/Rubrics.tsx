"use client";
/** The assessment forms (V254): each form's lines in its sections with their maxima; a line edited, added or deactivated;
 *  a form added. A criterion is never deleted, so an assessment scored on it still reads. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Criterion, Rubric } from "@/lib/examiners";

type Draft = { rubricId: string; id: string | null; name: string; guidance: string; maxScore: string; section: string; ordinal: string; active: boolean };

export function Rubrics({ rubrics, mayEdit }: { rubrics: Rubric[]; mayEdit: boolean }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [newForm, setNewForm] = useState<{ name: string; kind: string; hasDefence: boolean; note: string } | null>(null);

  async function call(path: string, method: "POST" | "PUT", body: unknown, reason: string): Promise<boolean> {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/examiners${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
      if (!r.ok) { const p = (await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return false; }
      notify(reason); router.refresh(); return true;
    } finally { setBusy(false); }
  }
  const edit = (rubricId: string, c: Criterion | null, section = "WRITTEN") => { setProblem(null); setDraft({ rubricId, id: c?.id ?? null, name: c?.name ?? "", guidance: c?.guidance ?? "", maxScore: c ? String(Number(c.max_score)) : "", section: c?.section ?? section, ordinal: c ? String(c.ordinal) : "", active: c?.active ?? true }); };
  const total = (r: Rubric, s?: string) => r.criteria.filter((c) => c.active && (!s || c.section === s)).reduce((a, c) => a + Number(c.max_score), 0);

  return (
    <>
      <PageHead title="Assessment Criteria" description="The forms external examiners score on: the lines, their sections and their maximum marks. The total is computed from the lines; the grade comes from the University's grading scheme in force."
        actions={<>{mayEdit ? <Btn kind="primary" onClick={() => setNewForm({ name: "", kind: "UNDERGRADUATE", hasDefence: true, note: "" })}>New Form</Btn> : null}<LinkBtn href="/examiners/projects">Project Assignments</LinkBtn></>} />
      {problem && !draft && !newForm ? <ProblemNotice problem={problem} /> : null}
      {!mayEdit ? <Note kind="info" title="Read-only">The Academic Office, the Deputy Registrar (Academic) and the School of Postgraduate Studies keep these forms.</Note> : null}
      {rubrics.map((r) => (
        <Panel key={r.id} title={r.name} right={<span className="row row--inline row--tight"><Pil kind={r.kind === "POSTGRADUATE" ? "info" : "grey"}>{r.kind === "POSTGRADUATE" ? "Postgraduate" : "Undergraduate"}</Pil>{r.active ? <Pil kind="ok">Active</Pil> : <Pil kind="grey">Inactive</Pil>}<span className="sub2">{r.used} assignment{Number(r.used) === 1 ? "" : "s"} · total {total(r)}</span>{mayEdit ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void call(`/rubrics/${r.id}`, "PUT", { name: r.name, active: !r.active, hasDefence: r.has_defence, note: r.note }, r.active ? `${r.name} set inactive` : `${r.name} set active`)}>{r.active ? "Set Inactive" : "Set Active"}</Btn> : null}</span>}>
          {r.note ? <PBody><div className="sub2">{r.note}</div></PBody> : null}
          {(["WRITTEN", "DEFENCE"] as const).map((s) => {
            const lines = r.criteria.filter((c) => c.section === s);
            if (!lines.length && s === "DEFENCE" && !r.has_defence) return null;
            return (
              <div key={s} className="tablewrap">
                <table className="tbl--data">
                  <thead><tr><th>{s === "WRITTEN" ? "The written work" : "The defence"}</th><th>Guidance</th><th className="mid">Maximum</th><th className="mid">Order</th><th className="mid">State</th>{mayEdit ? <th /> : null}</tr></thead>
                  <tbody>
                    {lines.map((c) => (
                      <tr key={c.id} className={c.active ? undefined : "is-muted"}>
                        <td><strong>{c.name}</strong></td><td className="sub2">{c.guidance ?? "—"}</td><td className="mid tnum">{Number(c.max_score)}</td><td className="mid tnum sub2">{c.ordinal}</td>
                        <td className="mid">{c.active ? <Pil kind="ok">Active</Pil> : <Pil kind="grey">Inactive</Pil>}</td>
                        {mayEdit ? <td><Btn kind="ghost" size="sm" onClick={() => edit(r.id, c)}>Edit</Btn></td> : null}
                      </tr>
                    ))}
                    <tr><td className="b600">{s === "WRITTEN" ? "Written work" : "Defence"} out of</td><td /><td className="mid tnum b600">{total(r, s)}</td><td /><td />{mayEdit ? <td><Btn kind="ghost" size="sm" onClick={() => edit(r.id, null, s)}>Add a Line</Btn></td> : null}</tr>
                  </tbody>
                </table>
              </div>
            );
          })}
        </Panel>
      ))}
      {draft ? (
        <Modal title={draft.id ? `Edit: ${draft.name}` : "Add a line"} sub="A criterion on the form; its maximum counts toward the total" onClose={() => setDraft(null)}
          foot={<><Btn kind="ghost" onClick={() => setDraft(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !draft.name.trim() || !Number(draft.maxScore)} onClick={async () => { const body = { name: draft.name.trim(), guidance: draft.guidance || null, maxScore: Number(draft.maxScore), section: draft.section, ordinal: draft.ordinal ? Number(draft.ordinal) : null, active: draft.active }; if (await (draft.id ? call(`/criteria/${draft.id}`, "PUT", body, `Criterion ${draft.name.trim()} saved`) : call(`/rubrics/${draft.rubricId}/criteria`, "POST", body, `Criterion ${draft.name.trim()} added`))) setDraft(null); }}>Save</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <div className="stack">
            <Field id="cr-name" label="Criterion" required><input id="cr-name" className="ctl" value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} /></Field>
            <Field id="cr-guid" label="Guidance for the examiner"><input id="cr-guid" className="ctl" value={draft.guidance} onChange={(e) => setDraft({ ...draft, guidance: e.target.value })} /></Field>
            <div className="row">
              <Field id="cr-max" label="Maximum mark" required style={{ flex: "1 1 120px" }}><input id="cr-max" className="ctl tnum" inputMode="decimal" value={draft.maxScore} onChange={(e) => setDraft({ ...draft, maxScore: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
              <Field id="cr-sec" label="Section" style={{ flex: "1 1 140px" }}><select id="cr-sec" className="ctl" value={draft.section} onChange={(e) => setDraft({ ...draft, section: e.target.value })}><option value="WRITTEN">The written work</option><option value="DEFENCE">The defence</option></select></Field>
              <Field id="cr-ord" label="Order" style={{ flex: "1 1 90px" }}><input id="cr-ord" className="ctl tnum" inputMode="numeric" value={draft.ordinal} onChange={(e) => setDraft({ ...draft, ordinal: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
            </div>
            <label className="row row--tight"><input type="checkbox" className="chk" checked={draft.active} onChange={(e) => setDraft({ ...draft, active: e.target.checked })} /> <span>Active: scored on new assessments</span></label>
            <div className="sub2">Changing a maximum affects assessments in draft; a submitted assessment keeps the marks it was given.</div>
          </div>
        </Modal>
      ) : null}
      {newForm ? (
        <Modal title="New assessment form" sub="Lines are added once the form exists" onClose={() => setNewForm(null)}
          foot={<><Btn kind="ghost" onClick={() => setNewForm(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || newForm.name.trim().length < 3} onClick={async () => { if (await call("/rubrics", "POST", { name: newForm.name.trim(), kind: newForm.kind, hasDefence: newForm.hasDefence, note: newForm.note || null }, `Form ${newForm.name.trim()} created`)) setNewForm(null); }}>Create</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <div className="stack">
            <Field id="nf-name" label="Name" required><input id="nf-name" className="ctl" value={newForm.name} onChange={(e) => setNewForm({ ...newForm, name: e.target.value })} /></Field>
            <Field id="nf-kind" label="For"><select id="nf-kind" className="ctl" value={newForm.kind} onChange={(e) => setNewForm({ ...newForm, kind: e.target.value })}><option value="UNDERGRADUATE">Undergraduate projects</option><option value="POSTGRADUATE">Postgraduate research</option></select></Field>
            <label className="row row--tight"><input type="checkbox" className="chk" checked={newForm.hasDefence} onChange={(e) => setNewForm({ ...newForm, hasDefence: e.target.checked })} /> <span>Has a defence section</span></label>
            <Field id="nf-note" label="Note shown above the form"><input id="nf-note" className="ctl" value={newForm.note} onChange={(e) => setNewForm({ ...newForm, note: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
