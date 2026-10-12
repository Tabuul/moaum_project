"use client";

/** Clearance management (V415): fresh and final clearance seen whole — who is eligible and not started, where every student
 *  stands, each office's load and pace (every figure opens the students behind it on the desk) — the starting of the
 *  eligible, and the workflows' offices, order, conditions, documents and reminders, stated by the Registry. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { CONDITION_WORD, OVERALL_WORD, type Overview, type Workflow, type WorkflowStage, type Workflows } from "@/lib/clearance";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

const list = (v: (string | number)[]) => v.join(", ");
const split = (v: string) => v.split(",").map((x) => x.trim()).filter(Boolean);

export function ClearanceManage({ workflows, workflow, session, overview }: { workflows: Workflows; workflow: string; session: string; overview: Overview | null }) {
  const router = useRouter();
  const nav = useQueryNav();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const [one, setOne] = useState({ student: "", basis: "MANUAL", reason: "" });
  const wf = workflows.workflows.find((w) => w.code === workflow) ?? workflows.workflows[0];
  const desk = (extra: Record<string, string>) => `/clearance?${new URLSearchParams({ wf: workflow, session, ...extra }).toString()}`;

  async function call<T>(path: string, method: string, body: unknown, reason: string): Promise<T | null> {
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/clearance${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j ?? { status: r.status, title: "The request was refused." }) as Problem; setProblem(p); notifyProblem(p); return null; }
      return j as T;
    } catch { const p = { status: 0, title: "The network dropped the request." }; setProblem(p); notifyProblem(p); return null; }
  }

  /** every eligible student started, a batch at a time, until none remain */
  async function startEligible() {
    setBusy(true);
    let started = 0;
    try {
      for (let round = 0; round < 50; round++) {
        const r = await call<{ started: number; remaining: number }>("/start-eligible", "POST", { workflow, session, limit: 500 }, `${wf.label} started for the eligible students of ${session}`);
        if (!r) break;
        started += r.started;
        setSaid(`${started.toLocaleString()} started${r.remaining ? ` · ${r.remaining.toLocaleString()} still to start` : ""}`);
        if (!r.remaining || !r.started) break;
      }
      notify(`${started.toLocaleString()} student${started === 1 ? "" : "s"} started — each told once`);
      router.refresh();
    } finally { setBusy(false); }
  }

  async function startOne() {
    setBusy(true);
    const r = await call<{ reference: string }>("/start", "POST", { workflow, session, student: one.student.trim(), basis: one.basis, reason: one.reason.trim() || null },
      `${wf.label} started for ${one.student.trim()}`);
    setBusy(false);
    if (r) { notify(`Started: ${r.reference}`); setOne({ student: "", basis: "MANUAL", reason: "" }); router.refresh(); }
  }

  function exportOffices(kind: "xlsx" | "pdf") {
    if (!overview) return;
    const headers = ["Office", "Applies", "Waiting", "Pending", "Under review", "Requires action", "Not cleared", "Rejected", "Cleared", "Not required", "Average days to clear"];
    const rows = overview.offices.map((o) => [o.label, o.applies, o.waiting, o.pending, o.under_review, o.requires_action, o.not_cleared, o.rejected, o.cleared, o.not_applicable, o.avg_days ?? "—"]);
    const title = `${wf.label} by office`;
    if (kind === "xlsx") void brandedXlsx(title, headers, rows, { sub: session, serial: docSerial("CLR") }).then((b) => downloadBlob(b, `clearance-offices-${workflow.toLowerCase()}-${session.replace("/", "-")}.xlsx`));
    else brandedPrint(title, `Session ${session}`, headers, rows, docSerial("CLR"));
  }

  const o = overview?.overall ?? {};
  const total = Object.values(o).reduce((a, n) => a + Number(n), 0);
  const e = overview?.eligible;

  return (
    <>
      <div className="row row--tight" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
        <Tabs label="Clearance" value={workflow} onChange={(v) => nav(`/clearance/manage?${new URLSearchParams({ wf: v, session }).toString()}`)}
          items={workflows.workflows.map((w) => ({ id: w.code, label: w.active ? w.label : `${w.label} (off)` }))} />
        <Field id="cm-session" label="Session">
          <select id="cm-session" className="ctl" value={session} onChange={(ev) => nav(`/clearance/manage?${new URLSearchParams({ wf: workflow, session: ev.target.value }).toString()}`)}>
            {workflows.sessions.map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
        </Field>
        <span className="grow" />
        <LinkBtn href={desk({})}>Open the desk</LinkBtn>
      </div>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="info" title={said} /> : null}
      {!wf.active ? <Note kind="info" title={`${wf.label} is off`}>Turn it on under the workflow below before starting anyone.</Note> : null}

      {overview ? (
        <>
          <Tiles items={[
            ["Eligible, not started", (e?.not_started ?? 0).toLocaleString(), e?.not_started ? "var(--amber-ink)" : null, `${(e?.started ?? 0).toLocaleString()} started · ${(e?.ineligible ?? 0).toLocaleString()} not eligible`],
            ["Clearances", total.toLocaleString(), null, session, desk({})],
            ...(["IN_PROGRESS", "PARTIALLY_CLEARED", "PENDING_ACTION", "NOT_CLEARED", "REJECTED", wf.complete_word] as string[]).map((k) =>
              [OVERALL_WORD[k] ?? k, Number(o[k] ?? 0).toLocaleString(), k === wf.complete_word ? "var(--green-ink)" : k === "NOT_CLEARED" || k === "REJECTED" ? "var(--red-ink)" : null,
               total ? `${Math.round((100 * Number(o[k] ?? 0)) / total)}%` : "—", desk({ status: k })] as [string, string, string | null, string, string]),
          ]} />
          {workflows.canStart && wf.active ? (
            <Panel title="Start clearance">
              <PBody>
                <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "flex-end" }}>
                  <Btn kind="go" disabled={busy || !e?.not_started} onClick={() => void startEligible()}>Start for the eligible students ({(e?.not_started ?? 0).toLocaleString()})</Btn>
                  <span className="sub2">Each is told once, with the reference and the first office.</span>
                </div>
                {e?.reasons?.length ? (
                  <div className="sub2 mt-2">Not eligible: {e.reasons.map((r) => `${r.reason} (${r.students.toLocaleString()})`).join(" · ")}</div>
                ) : null}
                <div className="row mt-2" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "flex-end" }}>
                  <Field id="cm-one" label="One student" hint="Matric, admission or JAMB number">
                    <input id="cm-one" className="ctl" value={one.student} onChange={(ev) => setOne({ ...one, student: ev.target.value })} autoComplete="off" />
                  </Field>
                  {workflows.canOverride ? (
                    <Field id="cm-basis" label="Basis">
                      <select id="cm-basis" className="ctl" value={one.basis} onChange={(ev) => setOne({ ...one, basis: ev.target.value })}>
                        <option value="MANUAL">Eligible</option><option value="OVERRIDE">Past the eligibility check (override)</option>
                      </select>
                    </Field>
                  ) : null}
                  <Field id="cm-reason" label="Reason" required={one.basis === "OVERRIDE"}>
                    <input id="cm-reason" className="ctl" value={one.reason} onChange={(ev) => setOne({ ...one, reason: ev.target.value })} />
                  </Field>
                  <Btn kind="primary" disabled={busy || !one.student.trim() || (one.basis === "OVERRIDE" && !one.reason.trim())} onClick={() => void startOne()}>Start</Btn>
                </div>
              </PBody>
            </Panel>
          ) : null}
          <Panel title="By office" right={<span className="row row--tight">
            <Btn kind="ghost" disabled={!overview.offices.length} onClick={() => exportOffices("xlsx")}>Export (Excel)</Btn>
            <Btn kind="ghost" disabled={!overview.offices.length} onClick={() => exportOffices("pdf")}>PDF</Btn></span>}>
            <DTable pageSize={0} cols={["Office", "Applies|num", "Waiting|num", "Pending|num", "Under review|num", "Requires action|num", "Not cleared|num", "Rejected|num", "Cleared|num", "Not required|num", "Avg days|num"]}
              rows={overview.offices.map((x) => [
                <b key="o">{x.label}</b>,
                ...([["", x.applies], ["WAITING", x.waiting], ["PENDING", x.pending], ["UNDER_REVIEW", x.under_review], ["REQUIRES_ACTION", x.requires_action],
                  ["NOT_CLEARED", x.not_cleared], ["REJECTED", x.rejected], ["CLEARED", x.cleared], ["NOT_APPLICABLE", x.not_applicable]] as [string, number][]).map(([st, n]) =>
                  <a key={st || "all"} className="tnum" href={desk({ unit: x.unit, ...(st ? { status: st } : {}) })}>{Number(n).toLocaleString()}</a>),
                <span key="d" className="tnum sub2">{x.avg_days ?? "—"}</span>,
              ])} />
          </Panel>
        </>
      ) : <Note kind="info" title="Choose a session" />}

      <WorkflowEditor key={wf.code} wf={wf} units={workflows.units} canConfigure={workflows.canConfigure} call={call} onSaved={() => router.refresh()} />
    </>
  );
}

interface Draft { unit: string; required: boolean; waits: boolean; condition: string; programmes: string; faculties: string; departments: string; levels: string; entryModes: string; documents: string; deadlineDays: string; instructions: string }
const draftOf = (s: WorkflowStage): Draft => ({ unit: s.unit, required: s.required, waits: s.waits, condition: s.condition, programmes: list(s.programmes), faculties: list(s.faculties),
  departments: list(s.departments), levels: list(s.levels), entryModes: list(s.entry_modes), documents: s.documents.join("; "), deadlineDays: s.deadline_days ? String(s.deadline_days) : "", instructions: s.instructions ?? "" });

/** the workflow's offices in their order, each required or not, sequential or not, its condition, scope, documents and deadline */
function WorkflowEditor({ wf, units, canConfigure, call, onSaved }: {
  wf: Workflow; units: { code: string; label: string }[]; canConfigure: boolean;
  call: <T>(path: string, method: string, body: unknown, reason: string) => Promise<T | null>; onSaved: () => void;
}) {
  const [head, setHead] = useState({ label: wf.label, active: wf.active, reminderDays: String(wf.reminder_days), certificate: wf.certificate, description: wf.description ?? "" });
  const [stages, setStages] = useState<Draft[]>(wf.stages.filter((s) => s.active).sort((a, b) => a.ord - b.ord).map(draftOf));
  const [busy, setBusy] = useState(false);
  const [why, setWhy] = useState("");
  const set = (i: number, patch: Partial<Draft>) => setStages(stages.map((s, j) => (j === i ? { ...s, ...patch } : s)));
  const move = (i: number, d: number) => { const n = [...stages]; const t = n[i + d]; if (!t) return; n[i + d] = n[i]; n[i] = t; setStages(n); };
  const free = units.filter((u) => !stages.some((s) => s.unit === u.code));
  const label = (code: string) => units.find((u) => u.code === code)?.label ?? code;

  async function save() {
    setBusy(true);
    const body = {
      label: head.label.trim(), active: head.active, reminderDays: Number(head.reminderDays) || 0, certificate: head.certificate, description: head.description.trim() || null,
      stages: stages.map((s, i) => ({
        unit: s.unit, ord: i + 1, required: s.required, waits: s.waits, condition: s.condition, programmes: split(s.programmes), faculties: split(s.faculties),
        departments: split(s.departments), levels: split(s.levels).map(Number).filter((n) => n > 0), entryModes: split(s.entryModes),
        documents: s.documents.split(";").map((x) => x.trim()).filter(Boolean), deadlineDays: s.deadlineDays.trim() || null, instructions: s.instructions.trim() || null,
      })),
    };
    const r = await call(`/workflows/${wf.code}`, "PUT", body, why.trim() || `${wf.label}: workflow stated`);
    setBusy(false);
    if (r) { notify(`${wf.label} saved`); setWhy(""); onSaved(); }
  }

  return (
    <Panel title={`Workflow — ${wf.label}`} right={<span className="sub2">{wf.prefix}/… references · {wf.per_session ? "a clearance each session" : "one clearance a student"}</span>}>
      <PBody>
        {!canConfigure ? <Note kind="info" title="Read only">The Registry and the Academic Office state the workflow.</Note> : null}
        <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "flex-end" }}>
          <Field id="wf-label" label="Name"><input id="wf-label" className="ctl" disabled={!canConfigure} value={head.label} onChange={(e) => setHead({ ...head, label: e.target.value })} /></Field>
          <Field id="wf-rem" label="Remind every (days)" hint="0 for no reminders"><input id="wf-rem" className="ctl" type="number" min={0} max={60} disabled={!canConfigure} value={head.reminderDays} onChange={(e) => setHead({ ...head, reminderDays: e.target.value })} /></Field>
          <label className="row row--tight"><input type="checkbox" className="chk" disabled={!canConfigure} checked={head.active} onChange={(e) => setHead({ ...head, active: e.target.checked })} /> In use</label>
          <label className="row row--tight"><input type="checkbox" className="chk" disabled={!canConfigure} checked={head.certificate} onChange={(e) => setHead({ ...head, certificate: e.target.checked })} /> Issues a certificate</label>
        </div>
        <DTable pageSize={0} cols={["Order|num", "Office", "Required|mid", "Waits for the earlier offices|mid", "Applies to", "Only for (programmes · faculties · departments · levels · entry)", "Documents asked for", "Deadline (days)", "|num"]}
          rows={stages.map((s, i) => [
            <span key="o" className="tnum">{i + 1}</span>,
            <b key="u">{label(s.unit)}</b>,
            <input key="r" type="checkbox" className="chk" disabled={!canConfigure} checked={s.required} onChange={(e) => set(i, { required: e.target.checked })} aria-label={`${label(s.unit)} required`} />,
            <input key="w" type="checkbox" className="chk" disabled={!canConfigure} checked={s.waits} onChange={(e) => set(i, { waits: e.target.checked })} aria-label={`${label(s.unit)} waits`} />,
            <select key="c" className="ctl" disabled={!canConfigure} value={s.condition} onChange={(e) => set(i, { condition: e.target.value })} aria-label={`${label(s.unit)} applies to`}>
              {Object.entries(CONDITION_WORD).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>,
            <span key="sc" className="row row--tight" style={{ flexWrap: "wrap" }}>
              {(["programmes", "faculties", "departments", "levels", "entryModes"] as const).map((k) => (
                <input key={k} className="ctl" style={{ width: 110 }} disabled={!canConfigure} placeholder={k === "entryModes" ? "entry modes" : k} value={s[k]} onChange={(e) => set(i, { [k]: e.target.value } as Partial<Draft>)} aria-label={`${label(s.unit)} ${k}`} />
              ))}
            </span>,
            <input key="d" className="ctl" disabled={!canConfigure} placeholder="Separate with ;" value={s.documents} onChange={(e) => set(i, { documents: e.target.value })} aria-label={`${label(s.unit)} documents`} />,
            <input key="dl" className="ctl" style={{ width: 70 }} type="number" min={1} max={365} disabled={!canConfigure} value={s.deadlineDays} onChange={(e) => set(i, { deadlineDays: e.target.value })} aria-label={`${label(s.unit)} deadline`} />,
            canConfigure ? <span key="a" className="row row--tight">
              <Btn kind="ghost" size="sm" disabled={i === 0} onClick={() => move(i, -1)} aria-label="Move up">↑</Btn>
              <Btn kind="ghost" size="sm" disabled={i === stages.length - 1} onClick={() => move(i, 1)} aria-label="Move down">↓</Btn>
              <Btn kind="ghost" size="sm" disabled={stages.length <= 1} onClick={() => setStages(stages.filter((_, j) => j !== i))}>Take out</Btn>
            </span> : <span key="a" />,
          ])} />
        {canConfigure ? (
          <div className="row mt-2" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "flex-end" }}>
            {free.length ? (
              <Field id="wf-add" label="Add an office">
                <select id="wf-add" className="ctl" value="" onChange={(e) => { if (e.target.value) setStages([...stages, { unit: e.target.value, required: true, waits: true, condition: "ALWAYS", programmes: "", faculties: "", departments: "", levels: "", entryModes: "", documents: "", deadlineDays: "", instructions: "" }]); }}>
                  <option value="">Choose…</option>{free.map((u) => <option key={u.code} value={u.code}>{u.label}</option>)}
                </select>
              </Field>
            ) : null}
            <Field id="wf-why" label="Reason for the change"><input id="wf-why" className="ctl" value={why} onChange={(e) => setWhy(e.target.value)} /></Field>
            <Btn kind="primary" disabled={busy || !stages.length || !head.label.trim()} onClick={() => void save()}>Save the workflow</Btn>
            <span className="sub2">An office taken out is kept on the record, not deleted; clearances under way follow the new order at once.</span>
          </div>
        ) : null}
      </PBody>
    </Panel>
  );
}
