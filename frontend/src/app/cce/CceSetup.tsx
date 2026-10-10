"use client";

/**
 * The CCE desk's set-up and records (V379): the programmes the Centre admits into (an existing programme offered on the route —
 * its duration, six years unless stated, and final level); the CCE session and how it follows undergraduate (one behind by
 * default, or a session the Academic Office names with its reason), with every change kept; the CCE applicant fees (the
 * Bursary's); the history of the desk; and the reports.
 */
import { useEffect, useState, type ReactNode } from "react";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { buildXlsx } from "@/lib/xlsx";
import { downloadBlob } from "@/lib/exportbrand";
import {
  ACTION_LABEL, REVIEW_LABEL, STATUS_LABEL, ccall, day, labelOf, naira, when,
  type AppRow, type CandidateRow, type FeeRule, type Mapping, type Overview, type Paged, type StudentRow,
} from "@/lib/cce";
import { cceSend, type Powers } from "./CceDesk";
import type { TabProps } from "./CceList";

/* ── the programmes ─────────────────────────────────────────────────────────────────────────────────────────────── */

interface Prog {
  code: string; name: string; department: string | null; faculty: string | null; full_time_years: number | null; full_time_final_level: number | null;
  configured: boolean; active: boolean; duration_years: number; final_level: number; duration_stated: number | null; final_level_stated: number | null;
  note: string | null; updated_at: string | null; listed: number; students: number;
}

export function CceProgrammes({ session, powers, pick }: TabProps) {
  const [data, setData] = useState<{ defaultDurationYears: number; rows: Prog[] } | null>(null);
  const [onlyOffered, setOnlyOffered] = useState(true);
  const [tick, setTick] = useState(0);
  const [edit, setEdit] = useState<Prog | null>(null);
  const [form, setForm] = useState({ active: true, duration: "", final: "", note: "" });
  useEffect(() => {
    let live = true;
    void ccall<{ defaultDurationYears: number; rows: Prog[] }>(`/api/v1/cce/programmes?session=${encodeURIComponent(session)}`).then((r) => { if (!live) return; if (r.ok) setData(r.data); else notifyProblem(r.problem); });
    return () => { live = false; };
  }, [session, tick]);
  if (!data) return <Note kind="info" title="Reading the programmes…">One moment.</Note>;
  const rows = onlyOffered ? data.rows.filter((p) => p.configured) : data.rows;

  function open(p: Prog) {
    setEdit(p);
    setForm({ active: p.configured ? p.active : true, duration: p.duration_stated ? String(p.duration_stated) : "", final: p.final_level_stated ? String(p.final_level_stated) : "", note: p.note ?? "" });
  }
  async function save() {
    if (!edit) return;
    const out = await cceSend(`/programmes/${edit.code}`, "PUT", { active: form.active, durationYears: form.duration ? Number(form.duration) : null, finalLevel: form.final ? Number(form.final) : null, note: form.note.trim() || null },
      `${edit.name} ${form.active ? "offered" : "not admitting"} on CCE`);
    if (out) { setEdit(null); setTick((t) => t + 1); }
  }

  return (
    <>
      <PageHead title="CCE programmes" description={`Part-time, ${data.defaultDurationYears} years unless a programme states otherwise.`} actions={pick} />
      <Panel title={onlyOffered ? `Offered on CCE · ${rows.length}` : `Every undergraduate programme · ${rows.length}`} right={<label className="row row--inline row--tight"><input type="checkbox" checked={!onlyOffered} onChange={(e) => setOnlyOffered(!e.target.checked)} /> show every programme</label>}>
        {rows.length ? (
          <DTable cols={["Programme", "Faculty", "On CCE", "Duration", "Final level|num", "Listed|num", "Students|num", ""]} texts={rows.map((p) => `${p.name} ${p.code} ${p.faculty ?? ""} ${p.department ?? ""}`)} rows={rows.map((p) => [
            <span key="n">{p.name}<div className="sub2 tnum">{p.code} · {p.department ?? ""}</div></span>, p.faculty ?? "—",
            p.configured ? <Pil key="a" kind={p.active ? "ok" : "grey"}>{p.active ? "Admitting" : "Not admitting"}</Pil> : <span key="a" className="sub2">not offered</span>,
            <span key="d">{p.duration_years} years{p.duration_stated ? "" : <span className="sub2"> (the route&rsquo;s)</span>}<div className="sub2">full-time: {p.full_time_years ? `${p.full_time_years} years` : "not stated"}</div></span>,
            p.final_level, p.listed, p.students,
            powers.academic ? <Btn key="e" kind="ghost" onClick={() => open(p)}>{p.configured ? "Edit" : "Offer on CCE"}</Btn> : <span key="e" />,
          ])} />
        ) : <PBody><div className="sub2">No programme is offered on CCE yet. {powers.academic ? "Tick “show every programme” and offer one." : "The Academic Office offers them."}</div></PBody>}
      </Panel>
      {edit ? (
        <Modal title={edit.configured ? `${edit.name} on CCE` : `Offer ${edit.name} on CCE`} sub={edit.code} onClose={() => setEdit(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setEdit(null)}>Back</Btn><Btn kind="primary" onClick={() => void save()}>Save</Btn></span>}>
          <label className="row row--inline row--tight mb-2"><input type="checkbox" checked={form.active} onChange={(e) => setForm({ ...form, active: e.target.checked })} /> The Centre admits into this programme</label>
          <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
            <Field id="cp-dur" label="Duration on CCE (years)" hint={`Blank: the route's ${data.defaultDurationYears} years`}><input id="cp-dur" className="ctl tnum" inputMode="numeric" style={{ maxWidth: 120 }} value={form.duration} onChange={(e) => setForm({ ...form, duration: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
            <Field id="cp-final" label="Final level" hint="Blank: entry level plus a level a year"><input id="cp-final" className="ctl tnum" inputMode="numeric" style={{ maxWidth: 120 }} value={form.final} onChange={(e) => setForm({ ...form, final: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
          </div>
          <Field id="cp-note" label="Note"><input id="cp-note" className="ctl" value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></Field>
          <div className="sub2">A programme that stops admitting keeps its students.</div>
        </Modal>
      ) : null}
    </>
  );
}

/* ── the CCE session ────────────────────────────────────────────────────────────────────────────────────────────── */

interface MappingView { mapping: Mapping; sessions: { session: string; state: string }[]; history: { at: string; what: string; before: string | null; after: string | null; reason: string | null; office: string | null; actor_name: string | null }[] }

function sessionWord(json: string | null): string {
  if (!json) return "—";
  try {
    const o = JSON.parse(json) as Record<string, unknown>;
    if ("session" in o) return `${o.session ?? "—"} (${o.override ? `named: ${o.override}` : `offset ${o.offset}`})`;
    return Object.entries(o).map(([k, v]) => `${k.replace(/_/g, " ")} ${v ?? "—"}`).join(", ");
  } catch { return json; }
}

export function CceSession({ powers, refresh }: { powers: Powers; refresh: () => void }) {
  const [v, setV] = useState<MappingView | null>(null);
  const [tick, setTick] = useState(0);
  const [form, setForm] = useState<{ offset: string; override: string; reason: string; effective: string } | null>(null);
  useEffect(() => {
    let live = true;
    void ccall<MappingView>("/api/v1/cce/session-mapping").then((r) => { if (!live) return; if (r.ok) setV(r.data); else notifyProblem(r.problem); });
    return () => { live = false; };
  }, [tick]);
  if (!v) return <Note kind="info" title="Reading the CCE session…">One moment.</Note>;
  const m = v.mapping;
  async function save() {
    if (!form) return;
    const out = await cceSend("/session-mapping", "PUT", { offset: Number(form.offset), override: form.override || null, reason: form.reason.trim(), effectiveFrom: form.effective || null },
      `The CCE session mapping changed: ${form.reason.trim()}`);
    if (out) { setForm(null); setTick((t) => t + 1); refresh(); }
  }
  return (
    <>
      <PageHead title="CCE session mapping" description="CCE runs one session behind undergraduate by default, unless the Academic Office names a session." />
      <Panel title="The relationship" right={powers.academic ? <Btn kind="primary" onClick={() => setForm({ offset: String(m.session_offset), override: m.overridden ? m.route_session ?? "" : "", reason: "", effective: "" })}>Change it</Btn> : null}>
        <PBody>
          <KvGrid cls="grid--4" pairs={[
            ["Undergraduate session", <b key="u" className="tnum">{m.undergraduate_session ?? "—"}</b>],
            ["CCE session", <b key="c" className="tnum">{m.route_session ?? "—"}</b>],
            ["Relationship", m.relationship ?? "—"],
            ["Status", m.overridden ? <Pil key="s" kind="warn">Named by the Academic Office</Pil> : <Pil key="s" kind="ok">Following undergraduate (offset {m.session_offset})</Pil>],
            ["The CCE session on the calendar", (m.route_session_state ?? "not on the calendar").toLowerCase()],
            ["Effective from", day(m.effective_from)],
            ["Configured by", `${m.configured_by_name ?? "the V379 migration"}${m.configured_office ? ` (${m.configured_office})` : ""}`],
            ["Last updated", when(m.configured_at)],
          ]} />
          {m.overridden ? <Note kind="info" title="Why a session is named">{m.override_reason}</Note> : null}
          <div className="sub2 mt-1">{m.name}: {m.study_mode === "PART_TIME" ? "part-time" : m.study_mode}, entry at {m.entry_level} level, {m.default_duration_years} years unless a programme states otherwise.</div>
        </PBody>
      </Panel>
      <Panel title="Every change">
        {v.history.length ? <DTable cols={["When", "What", "Before", "After", "Why", "Who"]} rows={v.history.map((h) => [
          <span key="w" className="tnum">{when(h.at)}</span>, h.what === "SESSION_MAPPING" ? "Session mapping" : h.what.replace("PROGRAMME", "Programme"),
          <span key="b" className="sub2">{sessionWord(h.before)}</span>, <span key="a" className="sub2">{sessionWord(h.after)}</span>, h.reason ?? "—",
          <span key="o" className="sub2">{h.actor_name ?? "—"}{h.office ? ` · ${h.office}` : ""}</span>,
        ])} /> : <PBody><div className="sub2">No change since the route was set up (one session behind).</div></PBody>}
      </Panel>
      {form ? (
        <Modal title="The CCE session" onClose={() => setForm(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setForm(null)}>Back</Btn><Btn kind="primary" disabled={!form.reason.trim()} onClick={() => void save()}>Save</Btn></span>}>
          <Field id="cs-offset" label="Follow undergraduate by" hint="One session behind (−1) is the University's rule for CCE">
            <select id="cs-offset" className="ctl" value={form.offset} onChange={(e) => setForm({ ...form, offset: e.target.value })}>
              {[-3, -2, -1, 0, 1].map((n) => <option key={n} value={n}>{n === 0 ? "The same session" : n < 0 ? `${-n} session${n === -1 ? "" : "s"} behind` : `${n} session ahead`} ({n})</option>)}
            </select>
          </Field>
          <Field id="cs-override" label="Or name the CCE session" hint="Leave on “follow undergraduate” unless CCE must stand in a particular session">
            <select id="cs-override" className="ctl" value={form.override} onChange={(e) => setForm({ ...form, override: e.target.value })}>
              <option value="">Follow undergraduate by the offset</option>
              {v.sessions.map((s) => <option key={s.session} value={s.session}>{s.session} ({s.state.toLowerCase()})</option>)}
            </select>
          </Field>
          <Field id="cs-eff" label="Effective from"><input id="cs-eff" type="date" className="ctl" value={form.effective} onChange={(e) => setForm({ ...form, effective: e.target.value })} /></Field>
          <Field id="cs-reason" label="The reason" required hint="Kept with the change"><textarea id="cs-reason" className="ctl" rows={3} value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} /></Field>
          <div className="sub2">Records already filed keep their sessions.</div>
        </Modal>
      ) : null}
    </>
  );
}

/* ── the fees: the Bursary's ────────────────────────────────────────────────────────────────────────────────────── */

interface FeesView { session: string; rule: FeeRule | null; stated: { session: string; application_fee: number; portal_charge: number; acceptance_fee: number; stated_at: string; stated_office: string; stated_by_name: string | null }[]; collected: { kind: string; paid: number; amount: number }[]; sessions: { session: string; state: string }[] }

export function CceFees({ powers, session: given }: { powers: Powers; session?: string }) {
  const [session, setSession] = useState(given ?? "");
  const [v, setV] = useState<FeesView | null>(null);
  const [tick, setTick] = useState(0);
  const [form, setForm] = useState<{ app: string; portal: string; acc: string } | null>(null);
  useEffect(() => {
    let live = true;
    void ccall<FeesView>(`/api/v1/cce/fees${session ? `?session=${encodeURIComponent(session)}` : ""}`).then((r) => { if (!live) return; if (r.ok) setV(r.data); else notifyProblem(r.problem); });
    return () => { live = false; };
  }, [session, tick]);
  if (!v) return <Note kind="info" title="Reading the CCE fees…">One moment.</Note>;
  async function save() {
    if (!form || !v) return;
    const out = await cceSend("/fees", "PUT", { session: v.session, applicationFee: Number(form.app), portalCharge: Number(form.portal || 0), acceptanceFee: Number(form.acc) }, `The CCE applicant fees for ${v.session} stated`);
    if (out) { setForm(null); setTick((t) => t + 1); }
  }
  const r = v.rule;
  return (
    <>
      <PageHead title="CCE applicant fees" description="Stated by the Bursary. CCE applicants pay no admission checking fee; CCE students pay only the CCE school-fee lines."
        actions={<select className="ctl" style={{ width: 160 }} aria-label="Session" value={v.session} onChange={(e) => setSession(e.target.value)}>{v.sessions.map((s) => <option key={s.session} value={s.session}>{s.session}</option>)}</select>} />
      <Panel title={`${v.session}`} right={powers.bursar ? <Btn kind="primary" onClick={() => setForm({ app: r ? String(r.application_fee) : "", portal: r ? String(r.portal_charge) : "0", acc: r ? String(r.acceptance_fee) : "" })}>{r?.stated ? "Change them" : "State them"}</Btn> : null}>
        <PBody>
          {r ? (
            <Tiles cls="grid--3" items={[["APPLICATION FEE", naira(r.application_fee), null, Number(r.portal_charge) ? `+ ${naira(r.portal_charge)} portal charge` : "no portal charge"], ["ACCEPTANCE FEE", naira(r.acceptance_fee), null, ""], ["STATED", r.stated ? "For this session" : `Carried from ${r.carried_from}`, r.stated ? null : "var(--amber-ink)", ""]]} />
          ) : <Note kind="bad" title="Not stated">The Bursary has not stated the CCE applicant fees; a CCE applicant cannot pay until it does.</Note>}
        </PBody>
      </Panel>
      <div className="grid grid--2">
        <Panel title="Collected for this session">
          {v.collected.length ? <DTable noPrint pageSize={0} cols={["Fee", "Paid|num", "Amount|num"]} rows={v.collected.map((c) => [c.kind === "APPLICATION" ? "CCE application" : c.kind === "ACCEPTANCE" ? "CCE acceptance" : c.kind, c.paid, naira(c.amount)])} />
            : <PBody><div className="sub2">Nothing collected yet.</div></PBody>}
        </Panel>
        <Panel title="Stated">
          {v.stated.length ? <DTable noPrint pageSize={0} cols={["Session", "Application|num", "Portal|num", "Acceptance|num", "By"]} rows={v.stated.map((s) => [s.session, naira(s.application_fee), naira(s.portal_charge), naira(s.acceptance_fee), <span key="b" className="sub2">{s.stated_by_name ?? "—"} · {day(s.stated_at)}</span>])} />
            : <PBody><div className="sub2">Never stated.</div></PBody>}
        </Panel>
      </div>
      {form ? (
        <Modal title="The CCE applicant fees" sub={v.session} onClose={() => setForm(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setForm(null)}>Back</Btn><Btn kind="primary" disabled={form.app === "" || form.acc === ""} onClick={() => void save()}>Save</Btn></span>}>
          {([["app", "Application fee (₦)"], ["portal", "Portal charge (₦)"], ["acc", "Acceptance fee (₦)"]] as const).map(([k, label]) => (
            <Field key={k} id={`cf-${k}`} label={label}><input id={`cf-${k}`} className="ctl tnum" inputMode="decimal" style={{ maxWidth: 180 }} value={form[k]} onChange={(e) => setForm({ ...form, [k]: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
          ))}
          <div className="sub2">An application fee and portal charge of nothing opens the form without a payment.</div>
        </Modal>
      ) : null}
    </>
  );
}

/* ── the history ────────────────────────────────────────────────────────────────────────────────────────────────── */

interface HistoryRow { at: string; kind: string; action: string; subject: string; from_state: string | null; to_state: string | null; note: string | null; office: string | null; actor_name: string | null }

export function CceHistory({ session, pick }: TabProps) {
  const [rows, setRows] = useState<HistoryRow[] | null>(null);
  useEffect(() => {
    let live = true;
    void ccall<{ rows: HistoryRow[] }>(`/api/v1/cce/history?session=${encodeURIComponent(session)}&limit=1000`).then((r) => { if (!live) return; if (r.ok) setRows(r.data.rows); else notifyProblem(r.problem); });
    return () => { live = false; };
  }, [session]);
  return (
    <>
      <PageHead title="CCE audit history" description={`CCE ${session}`} actions={pick} />
      <Panel title="What happened">
        {rows === null ? <PBody><div className="sub2">Reading…</div></PBody> : rows.length ? (
          <DTable cols={["When", "Of", "What", "Note", "Who"]} texts={rows.map((h) => `${h.subject} ${h.action} ${h.note ?? ""} ${h.actor_name ?? ""}`)} rows={rows.map((h) => [
            <span key="w" className="tnum">{when(h.at)}</span>,
            <span key="s">{h.kind === "APPLICATION" ? "Application" : h.kind === "LIST" ? "CCE list" : "Session"} <span className="tnum">{h.subject}</span></span>,
            <span key="a">{ACTION_LABEL[h.action] ?? h.action.replace(/_/g, " ").toLowerCase()}{h.to_state && h.kind === "APPLICATION" ? <div className="sub2">{labelOf(REVIEW_LABEL, h.to_state)[0]}</div> : null}</span>,
            <span key="n" className="sub2">{h.note ?? ""}</span>,
            <span key="o" className="sub2">{h.actor_name ?? "—"}{h.office ? ` · ${h.office}` : ""}</span>,
          ])} />
        ) : <PBody><div className="sub2">Nothing yet for {session}.</div></PBody>}
      </Panel>
    </>
  );
}

/* ── the reports ────────────────────────────────────────────────────────────────────────────────────────────────── */

export function CceReports({ session, pick, overview }: TabProps & { overview: Overview }) {
  const c = overview.stats;
  const [busy, setBusy] = useState<string | null>(null);
  async function exportOf(kind: "candidates" | "applications" | "students") {
    setBusy(kind);
    try {
      const r = await ccall<Paged<CandidateRow | AppRow | StudentRow>>(`/api/v1/cce/${kind}?session=${encodeURIComponent(session)}&page=0&size=5000`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      let head: string[]; let body: (string | number | null)[][];
      if (kind === "candidates") {
        const rows = r.data.rows as CandidateRow[];
        head = ["S/N", "JAMB number", "Name", "Date of birth", "Sex", "Phone", "Email", "State", "LGA", "Programme", "Department", "Faculty", "Status", "Application"];
        body = rows.map((x, i) => [i + 1, x.jamb_reg_no, x.name, x.date_of_birth, x.sex, x.phone, x.email, x.state_of_origin, x.lga, x.programme, x.department, x.faculty, labelOf(STATUS_LABEL, x.status)[0], x.application_no]);
      } else if (kind === "applications") {
        const rows = r.data.rows as AppRow[];
        head = ["S/N", "Application", "JAMB number", "Name", "Sex", "Programme", "Department", "Faculty", "State", "Submitted", "Application fee", "Accepted", "Admission number"];
        body = rows.map((x, i) => [i + 1, x.application_no, x.jamb_reg_no, x.name, x.sex, x.programme, x.department, x.faculty, labelOf(REVIEW_LABEL, x.state)[0], day(x.submitted_at), x.fee_confirmed_at ? "Paid" : "Unpaid", day(x.accepted_at), x.admission_no]);
      } else {
        const rows = r.data.rows as StudentRow[];
        head = ["S/N", "Matric / admission number", "JAMB number", "Name", "Programme", "Department", "Faculty", "Level", "Entry session", "Expected completion", "Study mode", "Status"];
        body = rows.map((x, i) => [i + 1, x.matric_no ?? x.admission_no, x.jamb_reg_no, x.name, x.programme, x.department, x.faculty, x.current_level, x.entry_session, x.expected_completion, "PART-TIME", x.status]);
      }
      downloadBlob(buildXlsx(head, body, `CCE ${kind}`), `cce-${kind}-${session.replace("/", "-")}.xlsx`);
      if (r.data.total > r.data.rows.length) notify(`The first ${r.data.rows.length.toLocaleString()} of ${r.data.total.toLocaleString()} rows were exported`, "info");
    } finally { setBusy(null); }
  }
  const tile = (label: string, n: number | undefined, sub?: ReactNode): [string, number, null, ReactNode] => [label, n ?? 0, null, sub ?? ""];
  return (
    <>
      <PageHead title="CCE reports" description={`CCE ${session} · undergraduate ${overview.mapping.undergraduate_session ?? "—"}`} actions={pick} />
      <Tiles cls="grid--5" items={[
        tile("IMPORTED", c.imported, `${c.eligible ?? 0} eligible`), tile("APPLICATIONS STARTED", c.started), tile("SUBMITTED", c.submitted, `${c.pending ?? 0} pending`),
        tile("UNDER REVIEW", c.under_review, `${c.with_applicant ?? 0} with the applicant`), tile("ADMITTED", c.admitted, `${c.not_admitted ?? 0} not admitted`),
        tile("ACCEPTANCE PAID", c.acceptance_paid), tile("STUDENTS ACTIVATED", c.activated), tile("MATRICULATED", c.matriculated), tile("CURRENT CCE STUDENTS", c.current_students),
        tile("WITHDRAWN FROM THE LIST", c.withdrawn),
      ]} />
      <Panel title="Lists to download" right={<Pil kind="info">{session}</Pil>}>
        <PBody>
          <div className="row row--inline" style={{ flexWrap: "wrap" }}>
            <Btn kind="secondary" disabled={!!busy} onClick={() => void exportOf("candidates")}>{busy === "candidates" ? "Preparing…" : "The CCE list (Excel)"}</Btn>
            <Btn kind="secondary" disabled={!!busy} onClick={() => void exportOf("applications")}>{busy === "applications" ? "Preparing…" : "Applications (Excel)"}</Btn>
            <Btn kind="secondary" disabled={!!busy} onClick={() => void exportOf("students")}>{busy === "students" ? "Preparing…" : "CCE students (Excel)"}</Btn>
          </div>

        </PBody>
      </Panel>
      <Panel title="By programme">
        <DTable cols={["Programme", "Faculty", "Listed|num", "Applied|num", "Admitted|num", "Students|num"]} rows={overview.byProgramme.map((r) => [r.programme, r.faculty ?? "—", r.listed, r.applied, r.admitted, r.students])} />
      </Panel>
    </>
  );
}
