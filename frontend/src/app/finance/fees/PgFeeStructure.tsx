"use client";

/**
 * V651: a postgraduate stage's fee structure in one step — the qualification, a programme or all of them, the stage (800 B — Year 2,
 * 900 D — Extension 1 …), the semester or the whole session, and the components with the total seen before saving. Each component is
 * a fee line for the stage (POST /finance/sessions/{session}/pg-fee-structure): the stage sets its level and whether its students are
 * fresh or returning, and the lines reach only the students the PG School reads at that stage. All are stated or none; a component
 * the schedule already states for the stage is refused.
 */
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { pgLevelOfName } from "@/lib/pg-academic";
import { Btn, IcoBtn, Note, Panel, PBody } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { FeeItem, PgStageOption, ProgrammeOption } from "./FeeSchedule";

const naira = (n: number) => "₦" + n.toLocaleString("en-NG", { minimumFractionDigits: 0, maximumFractionDigits: 2 });
interface Component { item: string; amount: string }
const blank = (): Component => ({ item: "", amount: "" });

export function PgFeeStructure({ session, stages, programmes, feeItems, may }: {
  session: string; stages: PgStageOption[]; programmes: ProgrammeOption[]; feeItems: FeeItem[]; may: boolean;
}) {
  const router = useRouter();
  const qualifications = useMemo(() => {
    const seen = new Map<string, { code: string; label: string; level: number }>();
    for (const s of stages) if (!seen.has(s.qualification)) seen.set(s.qualification, { code: s.qualification, label: s.qualification_label, level: s.level });
    return [...seen.values()].sort((a, b) => a.level - b.level);
  }, [stages]);
  const [qual, setQual] = useState("");
  const [prog, setProg] = useState("");
  const [stage, setStage] = useState("");
  const [semester, setSemester] = useState("");
  const [rows, setRows] = useState<Component[]>([blank()]);
  const [reason, setReason] = useState("");
  const [confirming, setConfirming] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [open, setOpen] = useState(false);

  if (!stages.length) return null;
  const q = qualifications.find((x) => x.code === qual) ?? null;
  const qStages = stages.filter((s) => s.qualification === qual);
  const st = stages.find((s) => s.code === stage) ?? null;
  // the School's programmes of the qualification, as the database reads a programme's level from its name
  const qProgs = q ? programmes.filter((p) => p.category === "POST GRADUATE" && pgLevelOfName(p.name) === q.level) : [];
  const progName = prog ? qProgs.find((p) => p.code === prog)?.name ?? prog : `Every ${q?.label ?? "postgraduate"} programme`;
  const filled = rows.filter((r) => r.item.trim() || r.amount.trim());
  const total = filled.reduce((n, r) => n + (Number(r.amount) || 0), 0);
  const names = filled.map((r) => r.item.trim().toLowerCase());
  const twice = names.find((n, i) => n && names.indexOf(n) !== i);
  const incomplete = filled.some((r) => !r.item.trim() || r.amount.trim() === "" || !(Number(r.amount) >= 0));
  const ready = !!st && filled.length > 0 && !incomplete && !twice;
  const semesterWords = semester === "1" ? "First semester" : semester === "2" ? "Second semester" : "The whole session";
  const set = (i: number, patch: Partial<Component>) => setRows(rows.map((r, k) => (k === i ? { ...r, ...patch } : r)));

  async function save(): Promise<void> {
    if (!st) return;
    setProblem(null);
    const r = await fetch(`/api/bff/api/v1/finance/sessions/${session}/pg-fee-structure`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason.trim() || `Postgraduate fee structure for ${st.label}, ${session}`) },
      body: JSON.stringify({ pgStage: st.code, programmeCode: prog || null, semester: semester ? Number(semester) : null, reason: reason.trim() || null,
        components: filled.map((c) => ({ item: c.item.trim(), amount: Number(c.amount) })) }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) {
      const p = j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText };
      setProblem(p); notifyProblem(p); setConfirming(false);
      return;
    }
    notify(`${filled.length} fee line${filled.length === 1 ? "" : "s"} stated for ${st.label}: ${naira(total)}`);
    setConfirming(false); setRows([blank()]); setReason("");
    router.refresh();
  }

  return (
    <Panel title="Postgraduate fee structure" right={<Btn kind="ghost" onClick={() => setOpen(!open)}>{open ? "Hide" : "State a stage's fees"}</Btn>}>
      <PBody>
        <div className="sub2">
          Each postgraduate stage has its own fees for {session}: the first stage of a cycle (700 Level, 800 A, 900 A) charges fresh students, every later stage
          returning ones, and an extension stage (700 Extension, 800 C, 900 D, 900 E) its own. A stage&rsquo;s lines reach only the students the PG School reads at
          that stage; lines for the whole level still reach every stage.
        </div>
        {open ? (
          <div className="mt-3">
            {!may ? <Note kind="info" title="Your office reads the fee structure">Stating fees is for the Bursar&rsquo;s office and the Students Account Officer.</Note> : null}
            <div className="grid grid--2">
              <Field id="pgfs-q" label="Qualification" required>
                <select id="pgfs-q" className="ctl" value={qual} onChange={(e) => { setQual(e.target.value); setProg(""); setStage(""); }}>
                  <option value="">Choose…</option>
                  {qualifications.map((x) => <option key={x.code} value={x.code}>{x.label} ({x.level} Level)</option>)}
                </select>
              </Field>
              <Field id="pgfs-p" label="Programme" hint={q ? `${qProgs.length} programme${qProgs.length === 1 ? "" : "s"}; blank for every one` : "Choose the qualification first"}>
                <SearchSelect id="pgfs-p" value={prog} onChange={setProg} disabled={!q} allLabel={`Every ${q?.label ?? ""} programme`}
                  options={qProgs.map((p) => ({ value: p.code, label: p.name, sub: p.code }))} />
              </Field>
              <Field id="pgfs-s" label="Stage" required hint={st ? `${st.category === "FRESH" ? "Fresh students (the first stage of a cycle)" : "Returning students"}${st.is_extension ? " · an extension" : ""}` : undefined}>
                <select id="pgfs-s" className="ctl" value={stage} disabled={!q} onChange={(e) => setStage(e.target.value)}>
                  <option value="">Choose…</option>
                  {qStages.map((s) => <option key={s.code} value={s.code}>{s.label}</option>)}
                </select>
              </Field>
              <Field id="pgfs-sem" label="Semester">
                <select id="pgfs-sem" className="ctl" value={semester} onChange={(e) => setSemester(e.target.value)}>
                  <option value="">The whole session</option><option value="1">First semester</option><option value="2">Second semester</option>
                </select>
              </Field>
            </div>
            <div className="mt-2"><strong>Fee components</strong></div>
            <datalist id="pgfs-items">{feeItems.map((it) => <option key={it.code} value={it.name} />)}</datalist>
            {rows.map((r, i) => (
              <div key={i} className="row row--tight mt-1" style={{ flexWrap: "wrap", alignItems: "flex-end" }}>
                <Field id={`pgfs-i${i}`} label={i === 0 ? "Item" : <span className="sr-only">Item {i + 1}</span>} style={{ flex: "2 1 220px" }}>
                  <input id={`pgfs-i${i}`} className="ctl" list="pgfs-items" value={r.item} placeholder="Tuition, Bench fee, Research supervision…" onChange={(e) => set(i, { item: e.target.value })} />
                </Field>
                <Field id={`pgfs-a${i}`} label={i === 0 ? "Amount (₦)" : <span className="sr-only">Amount {i + 1}</span>} style={{ flex: "1 1 120px" }}>
                  <input id={`pgfs-a${i}`} className="ctl tnum" type="number" min={0} step="0.01" inputMode="decimal" value={r.amount} onChange={(e) => set(i, { amount: e.target.value })} />
                </Field>
                <IcoBtn icon="trash" label={`Remove component ${i + 1}`} disabled={rows.length === 1} onClick={() => setRows(rows.filter((_, k) => k !== i))} />
              </div>
            ))}
            <div className="row row--tight mt-2" style={{ flexWrap: "wrap" }}>
              <Btn kind="ghost" disabled={rows.length >= 30} onClick={() => setRows([...rows, blank()])}>Add component</Btn>
              <span className="grow" />
              <span aria-live="polite"><span className="sub2">Total</span> <strong className="tnum">{naira(total)}</strong></span>
            </div>
            {twice ? <div className="ferr mt-1" role="alert">A component is listed twice: state each once.</div> : null}
            <Field id="pgfs-r" label="Note (optional)" hint="Kept with the lines on the audit trail" className="mt-2">
              <input id="pgfs-r" className="ctl" value={reason} maxLength={400} onChange={(e) => setReason(e.target.value)} placeholder="Approved by the PG School Board, 12 October" />
            </Field>
            {problem ? <ProblemNotice problem={problem} /> : null}
            <div className="row mt-2">
              <Btn kind="primary" size="md" disabled={!may || !ready} onClick={() => setConfirming(true)}>Preview fee structure</Btn>
            </div>
          </div>
        ) : null}
      </PBody>
      {confirming && st ? (
        <Modal title="Save fee structure" sub={`${session} · ${st.label}`} onClose={() => setConfirming(false)}
          foot={<><Btn kind="ghost" onClick={() => setConfirming(false)}>Back</Btn><Btn kind="primary" busyLabel="Saving…" onClick={save}>Save fee structure</Btn></>}>
          <div className="grid grid--2">
            {([["Qualification", q?.label ?? "—"], ["Programme", progName],
               ["Stage", `${st.label} · ${st.category === "FRESH" ? "fresh" : "returning"} students${st.is_extension ? " · an extension" : ""}`], ["Semester", semesterWords]] as const)
              .map(([k, v]) => <div key={k} className="kv"><span className="k">{k}</span><span className="v">{v}</span></div>)}
          </div>
          <table className="tbl tbl--data mt-3">
            <thead><tr><th>Component</th><th className="num">Amount</th></tr></thead>
            <tbody>
              {filled.map((c, i) => <tr key={i}><td>{c.item.trim()}</td><td className="num tnum">{naira(Number(c.amount))}</td></tr>)}
              <tr><th>Total</th><th className="num tnum">{naira(total)}</th></tr>
            </tbody>
          </table>
        </Modal>
      ) : null}
    </Panel>
  );
}
