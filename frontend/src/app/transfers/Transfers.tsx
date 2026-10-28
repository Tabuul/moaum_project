"use client";

/** tTransfers — inter-departmental transfer pipeline. A student applies; the application moves through
 *  four desks, each a single Approve: the current department, the new department, the Registrar, and the
 *  Academic office. Every office sees the whole pipeline; the Approve button shows only on the row and to
 *  the office whose turn it is (the server decides). Once approved, the student pays the Bursary-set fee
 *  and the registry effects the change. V669: a transfer the OLD portal approved is never recorded here again — it is restored on
 *  the programme swap (Restore a transfer approved on the old portal): no application, fee or approval, the number unchanged. V686: the
 *  applications the old portal approved and the queue still holds are chosen from In the queue and freed together — each student moved to
 *  the programme applied for, without the approvals. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, RoleLine, Tabs, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify , notifyProblem } from "@/components/proto/Toast";

import { SearchSelect } from "@/components/proto/SearchSelect";
import { DEFAULT_REASON, freedSummary, inQueue, OUTCOME_WORDS, refusalWords, type Freed } from "@/lib/transfer-queue";
export interface TransferRow {
  id: string; student_id: string; name: string; matric_no: string | null;
  from_programme: string; from_dept: string | null; from_level: number;
  to_programme: string; to_dept: string | null; mode_of_entry: string;
  utme_score: number | null; cgpa: number | null; reason: string; state: string;
  stageLabel?: string; canApprove?: boolean;
  recommended_level: number | null; committee_note: string | null; decline_note: string | null; withdrawn_why: string | null;
  applied_at: string; from_dept_at: string | null; to_dept_at: string | null; reg_at: string | null; acad_at: string | null; effected_at: string | null;
  fee_reference: string | null; fee_confirmed_at: string | null; session: string;
  /** V669, V686: a withdrawn application whose transfer the old portal approved, restored — the reference it was restored under */
  restoredRef?: string | null;
}
export interface Programme { code: string; name: string; faculty: string }

const STATE: Record<string, "ok" | "info" | "bad" | "grey" | "warn"> = {
  APPLIED: "warn", FROM_OK: "info", TO_OK: "info", REG_OK: "info",
  APPROVED: "info", EFFECTED: "ok", DECLINED: "bad", WITHDRAWN: "grey",
};
const LABEL: Record<string, string> = {
  APPLIED: "With current department", FROM_OK: "With new department", TO_OK: "With Registrar",
  REG_OK: "With Academic office", APPROVED: "Approved — awaiting fee", EFFECTED: "Completed",
  DECLINED: "Declined", WITHDRAWN: "Withdrawn",
};

export function Transfers({ rows, programmes, actingOffice }: { rows: TransferRow[]; programmes: Programme[]; actingOffice: string | null }) {
  const router = useRouter();
  const o = actingOffice ?? "";
  const mayRecord = ["academic", "registrar", "dregistrar", "super"].includes(o);
  // V669: the offices that restore a transfer approved on the old portal (the programme swap's)
  const mayRestore = ["academic", "registrar", "dregistrar", "ict", "super"].includes(o);
  const [findNo, setFindNo] = useState("");
  const [finding, setFinding] = useState(false);

  // V686: the offices that free old-portal transfers open on the queue
  const [tab, setTab] = useState(mayRestore && rows.some((r) => inQueue(r.state)) ? "QUEUE" : "APPLIED");
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [freeing, setFreeing] = useState({ reason: DEFAULT_REASON, reference: "", approvedOn: "" });
  const [freed, setFreed] = useState<Freed[] | null>(null);
  const [rec, setRec] = useState({ number: "", programme: "", reason: "", utme: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const count = (s: string) => rows.filter((r) => r.state === s).length;
  const queued = rows.filter((r) => inQueue(r.state));
  const restored = rows.filter((r) => r.state === "WITHDRAWN" && r.restoredRef);
  const shown = tab === "ALL" ? rows : tab === "QUEUE" ? queued : tab === "RESTORED" ? restored : rows.filter((r) => r.state === tab);
  const pickedRows = queued.filter((r) => picked.has(r.id));
  const toggle = (id: string) => setPicked((s) => { const n = new Set(s); if (n.has(id)) n.delete(id); else n.add(id); return n; });

  async function freeFromQueue() {
    const n = pickedRows.length;
    if (!n || !window.confirm(`Free ${n} application${n === 1 ? "" : "s"} from the queue? Each student is moved to the programme they applied for, at the level they are at, `
      + "without the approvals; the matriculation number does not change and the old portal's transfer is recorded in their history.")) return;
    const j = await send("/old-portal", { applications: pickedRows.map((r) => r.id), reason: freeing.reason.trim(), reference: freeing.reference.trim() || null,
      approvedOn: freeing.approvedOn || null }, `${n} transfer application${n === 1 ? "" : "s"} approved on the old portal freed from the queue`);
    if (!j) return;
    const res = (j.rows ?? []) as Freed[];
    setFreed(res);
    setPicked(new Set());
    setSaid(freedSummary(res));
  }

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/transfers${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  async function openRestore() {
    setFinding(true);
    try {
      const r = await fetch(`/api/bff/api/v1/programme-swaps/find?number=${encodeURIComponent(findNo.trim())}`);
      const j = await r.json().catch(() => null);
      if (!r.ok || !j?.id) { notifyProblem(j ?? { status: r.status, title: "No student with that number" }); return; }
      router.push(`/programme-swap/${j.id}?restore=1`);
    } finally {
      setFinding(false);
    }
  }

  return (
    <>
      <RoleLine allowed={["hod", "registrar", "dregistrar", "academic"]} actingOffice={actingOffice}
        canAct={mayRecord || o === "hod"}
        action="Approving inter-departmental transfers" />
      <Note kind="info" title="One application, four approvals — each a single Approve">
        <b>Current department</b> → <b>new department</b> → <b>Registrar</b> → <b>Academic office</b>. Then the student pays
        the non-refundable processing fee and the change is effected; the matriculation number does not change.
      </Note>
      {said ? <Note kind="ok" title={said}>On the record, in your name.</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}

      <Tiles items={[
        ["With current department", String(count("APPLIED")), count("APPLIED") ? "var(--chrome)" : null, "First approval"],
        ["With new department", String(count("FROM_OK")), count("FROM_OK") ? "var(--chrome)" : null, "Accepting the student"],
        ["With Registrar", String(count("TO_OK")), count("TO_OK") ? "var(--chrome)" : null, "Third approval"],
        ["With Academic office", String(count("REG_OK")), count("REG_OK") ? "var(--chrome)" : null, "Final approval"],
      ]} />

      <div className="card"><PBody>
        <Tabs look="segmented" value={tab} onChange={setTab}
          items={[["QUEUE", "In the queue"], ["APPLIED", "Current dept"], ["FROM_OK", "New dept"], ["TO_OK", "Registrar"], ["REG_OK", "Academic"], ["EFFECTED", "Completed"],
            ["RESTORED", "Approved on the old portal"], ["DECLINED", "Declined"], ["ALL", "All"]].map(([k, l]) => ({ id: k, label: l,
            count: k === "QUEUE" ? (queued.length || undefined) : k === "RESTORED" ? (restored.length || undefined) : k !== "ALL" && count(k) ? count(k) : undefined }))} />
      </PBody></div>

      {/* V686: the applications the old portal approved, freed from the queue together */}
      {mayRestore && queued.length ? (
        <Panel title="Free transfers approved on the old portal" right={`${pickedRows.length} of ${queued.length} in the queue chosen`}>
          <PBody>
            <div className="sub2">Students whose transfer the old portal approved and who were put back in this queue. Tick them below (in the queue), or choose every
              application in the queue; each student is moved to the programme they applied for, at the level they are at, with no approval, fee or new application.
              The application leaves the queue with the reason, the old portal&rsquo;s transfer is recorded in the student&rsquo;s history, and the matriculation number never changes.
              One the checks refuse is left in the queue with the reason.</div>
            <div className="row mt-2" style={{ flexWrap: "wrap", gap: 8 }}>
              <Btn kind="secondary" disabled={busy} onClick={() => { setPicked(new Set(queued.map((r) => r.id))); setTab("QUEUE"); }}>Choose every application in the queue ({queued.length})</Btn>
              {pickedRows.length ? <Btn kind="ghost" disabled={busy} onClick={() => setPicked(new Set())}>Clear the choice</Btn> : null}
            </div>
            <div className="grid grid--3 mt-2">
              <Field id="tq-reason" label="Reason" hint="Ten characters at least; kept with each application and in each student's history">
                <input id="tq-reason" className="ctl" maxLength={600} value={freeing.reason} onChange={(e) => setFreeing({ ...freeing, reason: e.target.value })} />
              </Field>
              <Field id="tq-ref" label="Old portal reference or memo" hint="Optional">
                <input id="tq-ref" className="ctl tnum" maxLength={80} value={freeing.reference} onChange={(e) => setFreeing({ ...freeing, reference: e.target.value })} />
              </Field>
              <Field id="tq-on" label="Approved on" hint="Optional">
                <input id="tq-on" type="date" className="ctl" value={freeing.approvedOn} onChange={(e) => setFreeing({ ...freeing, approvedOn: e.target.value })} />
              </Field>
            </div>
            <div className="mt-2">
              <Btn kind="primary" busy={busy} busyLabel="Moving the students…" disabled={busy || !pickedRows.length || freeing.reason.trim().length < 10} onClick={() => void freeFromQueue()}>
                {pickedRows.length ? `Free ${pickedRows.length} from the queue and move ${pickedRows.length === 1 ? "the student" : "them"}` : "Tick the applications to free"}
              </Btn>
            </div>
            {freed ? (
              <div className="mt-2">
                <Note kind={freed.some((x) => x.outcome === "REFUSED") ? "bad" : "ok"} title={freedSummary(freed)}>Each is on the record in your name.</Note>
                <DTable cols={["Student", "From → To", "Level|num", "Result", "Reference"]} rows={freed.map((x) => [
                  <Two key="s" a={x.name ?? "—"} b={x.matric_no ?? ""} />,
                  <span key="ft" className="sub2">{x.from_programme ?? "—"} → <b>{x.to_programme ?? "—"}</b></span>,
                  <span key="l" className="tnum">{x.to_level ?? "—"}</span>,
                  <span key="o"><Pil kind={OUTCOME_WORDS[x.outcome]?.[1] ?? "grey"}>{OUTCOME_WORDS[x.outcome]?.[0] ?? x.outcome}</Pil>{x.detail ? <div className="sub2">{refusalWords(x.detail)}</div> : null}</span>,
                  <span key="r" className="tnum sub2">{x.swap_ref ?? "—"}</span>,
                ])} />
              </div>
            ) : null}
          </PBody>
        </Panel>
      ) : null}

      <Panel title={tab === "QUEUE" ? "Transfer applications in the queue" : "Transfer applications"} right={`${shown.length} shown`}>
        {shown.length ? (
          <DTable cols={[...(mayRestore ? ["Free|mid"] : []), "Student", "From → To", "Entry · UTME · CGPA|mid", "Reason", "Stage", "Action|num"]} rows={shown.map((r) => [
            ...(mayRestore ? [inQueue(r.state)
              ? <input key="pk" type="checkbox" checked={picked.has(r.id)} onChange={() => toggle(r.id)} aria-label={`Free ${r.name}'s application from the queue`} style={{ width: 18, height: 18 }} />
              : <span key="pk" />] : []),
            <Two key="s" a={r.name} b={r.matric_no ?? ""} />,
            <span key="ft"><span className="sub2">{r.from_programme} · {r.from_level}L</span><div><b>→ {r.to_programme}</b></div></span>,
            <span className="sub2 tnum" key="e">{r.mode_of_entry}{r.utme_score != null ? ` · ${r.utme_score}` : ""}{r.cgpa != null ? ` · ${Number(r.cgpa).toFixed(2)}` : ""}</span>,
            <span className="sub2" key="r">{r.reason}{r.decline_note ? <div className="sub2">Declined: {r.decline_note}</div> : null}{r.withdrawn_why ? <div className="sub2">Withdrawn: {r.withdrawn_why}</div> : null}</span>,
            <span key="st">{r.state === "WITHDRAWN" && r.restoredRef
              ? <><Pil kind="ok">Moved — approved on the old portal</Pil><div className="sub2 tnum">{r.restoredRef}</div></>
              : <Pil kind={STATE[r.state] ?? "grey"}>{r.stageLabel ?? LABEL[r.state] ?? r.state}</Pil>}{r.fee_reference ? <div className="sub2 tnum">{r.fee_reference}{r.fee_confirmed_at ? " · paid" : " · unpaid"}</div> : null}</span>,
            <span key="ac" className="row row--inline row--tight row--right">
              {r.canApprove ? <Btn kind="go" disabled={busy} onClick={() => { if (window.confirm(`Approve ${r.name}'s transfer at this stage? It moves to the next office.`)) void send(`/${r.id}/approve`, {}, `Approve transfer for ${r.name}`).then((j) => { if (j) setSaid(`${r.name} approved — ${LABEL[String(j.state)] ?? "advanced"}`); }); }}>Approve</Btn> : null}
              {r.canApprove ? <Btn kind="ghost" disabled={busy} onClick={() => { const w = window.prompt("Decline this application — why? The reason is recorded and shown to the student."); if (w && w.trim()) void send(`/${r.id}/decline`, { why: w.trim() }, `Decline transfer for ${r.name}`).then((j) => { if (j) setSaid(`${r.name} declined`); }); }}>Decline</Btn> : null}
            </span>,
          ])} texts={shown.map((r) => `${r.name} ${r.matric_no ?? ""} ${r.from_programme} ${r.to_programme} ${r.state}`)} />
        ) : <PBody><div className="sub2">No application in this stage.</div></PBody>}
      </Panel>

      {/* V669: a transfer the old portal approved is restored, never recorded again as an application */}
      {mayRestore ? (
        <Panel title="Restore a transfer approved on the old portal" right="No new application, fee or approval">
          <PBody>
            <div className="sub2">For a student whose transfer the old portal approved and whom the migration placed back in the department they left. The student is
              put on the approved programme and level directly, the old portal&rsquo;s transfer is recorded in the history, and an application left in this queue for the
              same programme is withdrawn. The matriculation number never changes.</div>
            <div className="row mt-2" style={{ alignItems: "flex-end", flexWrap: "wrap" }}>
              <Field id="tr-find" label="Matriculation, JAMB or admission number">
                <input id="tr-find" className="ctl tnum" value={findNo} onChange={(e) => setFindNo(e.target.value)} placeholder="MOAU/SC/MCB/24/75807"
                  onKeyDown={(e) => { if (e.key === "Enter" && findNo.trim()) void openRestore(); }} />
              </Field>
              <Btn kind="primary" busy={finding} busyLabel="Finding the student…" disabled={!findNo.trim()} onClick={() => void openRestore()}>Open the student</Btn>
              <LinkBtn kind="ghost" href="/transfers/bulk?restore=1">Many students: restore in bulk</LinkBtn>
            </div>
          </PBody>
        </Panel>
      ) : null}

      {mayRecord ? (
        <Panel title="Record a new transfer application" right="A new request on paper: it starts the transfer at the first desk">
          <PBody>
            <div className="grid grid--2">
              <Field id="tr-num" label="Student number"><input id="tr-num" className="ctl tnum" value={rec.number} onChange={(e) => setRec({ ...rec, number: e.target.value })} placeholder="MOAUM/CSC/23/0001" /></Field>
              <Field id="tr-prog" label="Course applied for"><SearchSelect id="tr-prog" value={rec.programme} onChange={(v) => setRec({ ...rec, programme: v })} placeholder="Search a programme…" options={programmes.map((p) => ({ value: p.code, label: `${p.name} — ${p.faculty}` }))} /></Field>
            </div>
            <div className="grid grid--2">
              <Field id="tr-reason" label="Reason for seeking transfer"><input id="tr-reason" className="ctl" value={rec.reason} onChange={(e) => setRec({ ...rec, reason: e.target.value })} /></Field>
              <Field id="tr-utme" label="UTME score" hint="Optional"><input id="tr-utme" className="ctl tnum" inputMode="numeric" value={rec.utme} onChange={(e) => setRec({ ...rec, utme: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
            </div>
            <div><Btn kind="primary" disabled={busy || !rec.number.trim() || !rec.programme || !rec.reason.trim()} onClick={async () => { const j = await send("", { number: rec.number.trim(), toProgramme: rec.programme, reason: rec.reason.trim(), utme: rec.utme ? Number(rec.utme) : null }, `Record transfer application for ${rec.number.trim()}`); if (j) { setSaid("Application recorded — it goes to the current department"); setRec({ number: "", programme: "", reason: "", utme: "" }); } }}>Record the application</Btn></div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
