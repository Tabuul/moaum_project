"use client";

/** Matriculation Management (V267): the exercise faculty by faculty — the eligible students of a faculty grouped by programme,
 *  the numbers proposed from the configured rule and reserved, every one reviewed, validated and correctable with a reason,
 *  the batch marked ready, the final review across faculties, and the one confirmed act that issues: number, status,
 *  sign-in identity, history, notice. Generating is preparation; issuing is the official act. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tabs, Tiles, KvGrid } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { BATCH_WORD, ISSUERS, PREPARERS, dayOf, standing, whenAt, yy, type Batch, type BatchDetail, type BatchRow, type Candidate, type IssuedRow, type ManagePage, type Overview, type PendingRow } from "@/lib/matric-manage";

export interface ManageFilters { session: string; fac: string; prog: string; status: string; q: string; tab: string; batch: string }
type Tab = "faculty" | "all" | "batches" | "issued" | "pending" | "conflicts";

export function Manage({ page, overview, issued, pending, filters, actingOffice }: { page: ManagePage; overview: Overview | null; issued: IssuedRow[]; pending: PendingRow[]; filters: ManageFilters; actingOffice: string | null }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const mayPrepare = PREPARERS.includes(actingOffice ?? "");
  const mayIssue = ISSUERS.includes(actingOffice ?? "");
  const tab = (["faculty", "all", "batches", "issued", "pending", "conflicts"].includes(filters.tab) ? filters.tab : "faculty") as Tab;
  const [session, setSession] = useState(filters.session);
  const [q, setQ] = useState(filters.q);
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set());
  const [editing, setEditing] = useState<BatchRow | Candidate | null>(null);
  const [newNo, setNewNo] = useState("");
  const [reason, setReason] = useState("");
  const [dropping, setDropping] = useState<{ rowId: string; name: string } | null>(null);
  const [cancelling, setCancelling] = useState<Batch | null>(null);
  const [reviewing, setReviewing] = useState<Batch | null>(null);
  const [confirming, setConfirming] = useState<Batch | "ALL" | null>(null);
  const [done, setDone] = useState<{ ref: string; detail: BatchDetail }[] | null>(null);
  const [viewing, setViewing] = useState<BatchDetail | null>(null);
  const fv = page.faculty ?? null;
  const batch = fv?.batch?.batch ?? null;
  const base = `/api/bff/api/v1/matriculation/sessions/${filters.session}/management`;

  const go = (next: Partial<ManageFilters>) => {
    const f = { ...filters, ...next };
    if (next.fac !== undefined && next.fac !== filters.fac) { f.prog = ""; f.status = ""; }
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(f)) if (v && !(k === "tab" && v === "faculty")) qs.set(k, v);
    queryNav(`/matriculation/manage?${qs}`);
  };
  async function call<T>(path: string, method: "POST" | "PUT", body: unknown, label: string, key: string): Promise<T | null> {
    setBusy(key); setProblem(null);
    try {
      const r = await fetch(`${base}${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(label) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return null; }
      notify(label); return j as T;
    } finally { setBusy(null); }
  }
  const generate = async (programme?: string) => {
    if (!fv) return;
    const d = await call<BatchDetail>(`/faculties/${fv.code}/generate`, "POST", { programme: programme ?? null }, programme ? `Numbers proposed for ${programme} (${fv.name})` : `Numbers proposed for ${fv.name}`, "gen");
    if (d) { notify(`${d.batch.students} proposed · ${d.batch.valid} valid · ${d.batch.conflicts} conflict(s) — nothing is issued yet`); router.refresh(); }
  };
  const validate = async (b: Batch) => { const d = await call<BatchDetail>(`/batches/${b.id}/validate`, "POST", {}, `Batch ${b.ref} validated`, b.id); if (d) router.refresh(); };
  const ready = async (b: Batch) => { const d = await call<BatchDetail>(`/batches/${b.id}/ready`, "POST", {}, `Batch ${b.ref} marked ready for issuance`, b.id); if (d) router.refresh(); };
  const saveEdit = async () => {
    if (!editing || !batch) return;
    const rowId = "row_id" in editing ? editing.row_id : editing.id;
    const d = await call<BatchDetail>(`/batches/${batch.id}/rows/${rowId}`, "PUT", { matricNo: newNo.trim().toUpperCase(), reason: reason.trim() }, `Proposed number corrected to ${newNo.trim().toUpperCase()}`, "edit");
    if (d) { setEditing(null); setReason(""); router.refresh(); }
  };
  const drop = async () => {
    if (!dropping || !batch) return;
    const d = await call<BatchDetail>(`/batches/${batch.id}/rows/${dropping.rowId}/drop`, "POST", { reason: reason.trim() }, `${dropping.name} taken off batch ${batch.ref}`, "drop");
    if (d) { setDropping(null); setReason(""); router.refresh(); }
  };
  const cancel = async () => {
    if (!cancelling) return;
    const d = await call<BatchDetail>(`/batches/${cancelling.id}/cancel`, "POST", { reason: reason.trim() }, `Batch ${cancelling.ref} cancelled`, "cancel");
    if (d) { setCancelling(null); setReason(""); router.refresh(); }
  };
  const issue = async () => {
    if (!confirming) return;
    const targets: Batch[] = confirming === "ALL" ? (overview?.faculties ?? []).filter((f) => f.batch_state === "READY_FOR_ISSUANCE").map((f) => ({ id: f.batch_id as string, ref: f.batch_ref as string, faculty: f.faculty } as Batch)) : [confirming];
    const results: { ref: string; detail: BatchDetail }[] = [];
    for (const t of targets) {
      const d = await call<BatchDetail>(`/batches/${t.id}/issue`, "POST", { confirm: true }, `Matriculation numbers issued: batch ${t.ref}`, "issue");
      if (!d) break;
      results.push({ ref: t.ref, detail: d });
    }
    setConfirming(null); setReviewing(null);
    if (results.length) { setDone(results); router.refresh(); }
  };
  async function openBatch(id: string) {
    setBusy(id);
    try {
      const r = await fetch(`${base}/batches/${id}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      setViewing(j as BatchDetail);
    } finally { setBusy(null); }
  }

  const sub = [fv?.name, filters.prog, filters.status, filters.q ? `search “${filters.q}”` : ""].filter(Boolean).join(" · ");
  const excel = async (title: string, head: string[], body: (string | number)[][], file: string) => { const blob = await brandedXlsx(title, head, body, { sheetName: "Matriculation", serial: docSerial("MAT"), sub: `${filters.session}${sub ? ` · ${sub}` : ""}` }); downloadBlob(blob, file); };
  const pdf = (title: string, head: string[], body: (string | number)[][]) => brandedPrint(title, `${filters.session}${sub ? ` · ${sub}` : ""}`, head, body, docSerial("MAT"));
  const students = fv?.students ?? [];
  const byName = <T extends { surname: string; other_names: string }>(xs: T[]) => [...xs].sort((a, b) => `${a.surname} ${a.other_names}`.localeCompare(`${b.surname} ${b.other_names}`));
  const FAC_HEAD = ["S/N", "Student", "Student ID", "Faculty", "Programme", "Matric No.", "Status"];
  const facBody = () => byName(students).map((c, i) => [i + 1, `${c.surname}, ${c.other_names}`, c.admission_no ?? "", c.faculty, c.programme, c.matric_no ?? c.proposed_no ?? "", standing(c).word]);
  const PROG_HEAD = ["S/N", "Student", "Programme", "Matric No.", "Session", "Status"];
  const progBody = (code: string) => byName(students.filter((c) => c.programme_code === code)).map((c, i) => [i + 1, `${c.surname}, ${c.other_names}`, c.programme, c.matric_no ?? c.proposed_no ?? "", filters.session, standing(c).word]);
  const ISS_HEAD = ["S/N", "Matric No.", "Student Name", "Faculty", "Department", "Programme", "Session", "Username", "Previous Username", "Issued Date", "Batch"];
  const issBody = () => byName(issued).map((r, i) => [i + 1, r.matric_no, `${r.surname}, ${r.other_names}`, r.faculty ?? "", r.department ?? "", r.programme ?? "", r.entry_session ?? "", r.matric_no, r.previous_username ?? r.admission_no ?? "", dayOf(r.issued_at), r.batch_ref ?? r.run_ref ?? ""]);
  const ALL_HEAD = ["S/N", "Student", "Faculty", "Department", "Programme", "Matric No.", "Session"];
  const allBody = () => byName(issued).map((r, i) => [i + 1, `${r.surname}, ${r.other_names}`, r.faculty ?? "", r.department ?? "", r.programme ?? "", r.matric_no, r.entry_session ?? ""]);
  const PEND_HEAD = ["S/N", "Student", "Faculty", "Programme", "Reason"];
  const pendBody = () => byName(pending).map((r, i) => [i + 1, `${r.surname}, ${r.other_names}`, r.faculty, r.programme, r.reason]);

  const validation = (c: Candidate) => {
    if (c.matric_no) return <span className="sub2">Issued {dayOf(c.matriculated_at)}</span>;
    if (c.row_id) return (c.problems ?? []).length ? <span className="ink-red">{(c.problems ?? []).map((x, i) => <div key={i}>⚠ {x}</div>)}</span> : <span className="ink-green">✓ Valid{c.edited ? " · corrected" : ""}</span>;
    return c.eligible ? <span className="sub2">Eligible · no number proposed yet</span> : <span className="ink-amber">{c.reason}</span>;
  };
  const openEdit = (c: Candidate | BatchRow) => { setEditing(c); setNewNo(("proposed_no" in c ? c.proposed_no : null) ?? ""); setReason(""); setProblem(null); };
  const rowsWithProblems = students.filter((c) => c.row_id && (c.problems ?? []).length);
  const batchOpen = batch && (batch.state === "GENERATED" || batch.state === "READY_FOR_ISSUANCE");
  const kp = fv?.kpis;
  const link = (extra: Partial<ManageFilters>) => { const f = { ...filters, ...extra }; const qs = new URLSearchParams(); for (const [k, v] of Object.entries(f)) if (v && !(k === "tab" && v === "faculty")) qs.set(k, v); return `/matriculation/manage?${qs}`; };

  const studentTable = (list: Candidate[]) => (
    <DTable pageSize={0} cols={["S/N|num", "Student ID", "Student Name", "Programme", "Year|mid", "Series|mid", "Proposed Matric No.", "Status|mid", "Validation", "|num"]} rows={list.map((c, i) => [
      <span key="sn" className="tnum sub2">{i + 1}</span>,
      <span key="id" className="tnum sub2">{c.admission_no ?? "—"}</span>,
      <Link key="n" className="lnk" href={`/students/${c.student_id}`}><strong>{c.surname}, {c.other_names}</strong></Link>,
      <span key="p" className="sub2">{c.programme}</span>,
      <span key="y" className="tnum">{yy(c.entry_session)}</span>,
      <span key="s" className="tnum sub2">{c.series_code ?? "—"}</span>,
      <b key="m" className="tnum">{c.matric_no ?? c.proposed_no ?? "—"}</b>,
      <Pil key="st" kind={standing(c).kind}>{standing(c).word}</Pil>,
      <span key="v">{validation(c)}</span>,
      <span key="x" className="row row--inline row--tight row--end">{c.row_id && batchOpen && mayPrepare && !c.matric_no ? <><Btn kind={(c.problems ?? []).length ? "urgent" : "ghost"} size="sm" onClick={() => openEdit(c)}>{(c.problems ?? []).length ? "Fix" : "Edit"}</Btn><Btn kind="ghost" size="sm" onClick={() => { setDropping({ rowId: c.row_id as string, name: `${c.surname}, ${c.other_names}` }); setReason(""); }}>Drop</Btn></> : null}</span>,
    ])} texts={list.map((c) => `${c.surname} ${c.other_names} ${c.admission_no ?? ""} ${c.proposed_no ?? ""} ${c.matric_no ?? ""} ${c.programme}`)} />
  );

  return (
    <>
      <PageHead title="Matriculation Management" description="Faculty by faculty: the eligible students grouped by programme, matriculation numbers proposed from the configured rule and reserved, every one reviewed and validated, corrections with a reason, the batch marked ready, the final review across faculties — and only then the confirmed act that issues the numbers, marks the students matriculated, makes the number their sign-in and tells them. Generating is preparation; issuing is the official act."
        actions={<><LinkBtn kind="ghost" href={`/matriculation?session=${encodeURIComponent(filters.session)}`}>Matriculation run</LinkBtn><LinkBtn kind="ghost" href="/matriculation/config">Number format</LinkBtn>
          {fv ? <><Btn kind="secondary" onClick={() => void excel(`Faculty Matriculation Report — ${fv.name}`, FAC_HEAD, facBody(), "faculty-matriculation.xlsx")} disabled={!students.length}>Excel</Btn><Btn kind="ghost" onClick={() => pdf(`Faculty Matriculation Report — ${fv.name}`, FAC_HEAD, facBody())} disabled={!students.length}>PDF</Btn></> : null}</>} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {page.separateDuties ? <Note kind="info" title="Duties are separated">The officer who generated or marked a batch ready does not issue it; another authorised officer does. The Registry switches this under Number format.</Note> : null}

      <div className="scope">
        <div className="scope__f"><Field id="mm-session" label="Academic session"><form className="scope__search" onSubmit={(e) => { e.preventDefault(); if (/^\d{4}\/\d{4}$/.test(session)) go({ session }); }}><input id="mm-session" className="ctl tnum" value={session} onChange={(e) => setSession(e.target.value)} pattern="\d{4}/\d{4}" placeholder="2026/2027" /></form></Field></div>
        <div className="scope__f"><Field id="mm-fac" label="Faculty"><select id="mm-fac" className="ctl" value={filters.fac} disabled={!!page.boundFaculty} onChange={(e) => go({ fac: e.target.value })}><option value="">Select faculty…</option>{page.faculties.map((f) => <option key={f.code} value={f.code}>{f.name}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="mm-prog" label="Programme"><select id="mm-prog" className="ctl" value={filters.prog} disabled={!fv} onChange={(e) => go({ prog: e.target.value })}><option value="">All programmes</option>{(fv?.programmes ?? []).map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="mm-status" label="Status"><select id="mm-status" className="ctl" value={filters.status} onChange={(e) => go({ status: e.target.value })}><option value="">All</option><option value="ELIGIBLE">Eligible</option><option value="UNPREPARED">Eligible · not yet prepared</option><option value="PREPARED">Prepared</option><option value="CONFLICTS">Conflicts</option><option value="PENDING">Pending</option><option value="ISSUED">Matriculated</option></select></Field></div>
        <div className="scope__f grow"><Field id="mm-q" label="Search" hint="Name, student ID, admission or application number, matriculation number, programme, series"><form className="scope__search" onSubmit={(e) => { e.preventDefault(); go({ q: q.trim(), session }); }}><input id="mm-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search students…" /><Btn kind="primary" type="submit">{fv ? "Load Students" : "Load"}</Btn><Btn kind="ghost" onClick={() => { setQ(""); go({ q: "", status: "", prog: "" }); }}>Reset</Btn></form></Field></div>
      </div>

      <Tabs<Tab> label="Matriculation views" value={tab} onChange={(t) => go({ tab: t })} items={[
        { id: "faculty", label: "Faculty view", count: kp ? kp.eligible + kp.prepared : undefined }, { id: "all", label: "All faculties", disabled: !page.canViewAll },
        { id: "batches", label: "Batches", count: page.batches.length }, { id: "issued", label: "Issued", count: issued.length }, { id: "pending", label: "Pending", count: pending.length }, { id: "conflicts", label: "Conflicts", count: rowsWithProblems.length || undefined },
      ]} />

      {tab === "faculty" && !fv ? <Note kind="info" title="Select a faculty">Choose the academic session and a faculty, then press Load Students. The eligible students appear grouped by programme; a faculty officer sees their own faculty only.</Note> : null}

      {tab === "faculty" && fv && kp ? (
        <>
          <Tiles items={[
            ["Eligible students", String(kp.eligible), null, "Admitted, registered, fees settled, no number", link({ status: "ELIGIBLE" })],
            ["Prepared", String(kp.prepared), kp.prepared ? "var(--chrome)" : null, kp.unprepared ? `${kp.unprepared} eligible not yet proposed` : "Numbers proposed on the open batch", link({ status: "PREPARED" })],
            ["Pending", String(kp.pending), kp.pending ? "var(--amber-ink)" : null, "Not yet eligible, with the reason", link({ status: "PENDING" })],
            ["Already matriculated", String(kp.already), null, "Numbers on the record", link({ status: "ISSUED" })],
            ["Matric numbers generated", String(kp.prepared), null, batch ? `Batch ${batch.ref}` : "No open batch"],
            ["Matric numbers issued", String(kp.issued), kp.issued ? "var(--green-ink)" : null, "By the faculty's batches this session", link({ tab: "issued" })],
            ["Conflicts", String(kp.conflicts), kp.conflicts ? "var(--red-ink)" : "var(--green-ink)", kp.conflicts ? "Must be resolved before issuance" : "None", link({ tab: "conflicts" })],
            ["Faculty list", fv.listState === "CONFIRMED" ? "Confirmed" : fv.listState === "DRAFT" ? "Draft" : "Not returned", null, "The Faculty Officer's confirmed list (Matriculation run)"],
          ]} />

          <Panel title={batch ? `Batch ${batch.ref}` : "No open batch for this faculty"} right={batch ? <Pil kind={BATCH_WORD[batch.state][1]}>{BATCH_WORD[batch.state][0]}</Pil> : `${kp.eligible} eligible`}>
            <PBody>
              {batch ? (
                <div className="stack">
                  <KvGrid cls="grid--4" pairs={[["Students on the batch", <b key="v" className="tnum">{batch.students}</b>], ["Valid", <b key="v" className="tnum ink-green">{batch.valid}</b>], ["Conflicts", <b key="v" className={`tnum${batch.conflicts ? " ink-red" : ""}`}>{batch.conflicts}</b>],
                    ["Prepared by", `${batch.prepared_officer ?? "—"} · ${whenAt(batch.generated_at ?? batch.prepared_at)}`], ["Reviewed by", batch.reviewed_at ? `${batch.reviewed_officer ?? "—"} · ${whenAt(batch.reviewed_at)}` : "Not yet marked ready"], ["Corrections", String(batch.edited ?? 0)], ["Dropped", String(batch.dropped ?? 0)]]} />
                  <div className="row row--inline row--tight">
                    {mayPrepare && kp.unprepared > 0 && batchOpen ? <Btn kind="secondary" disabled={busy !== null} onClick={() => void generate(filters.prog || undefined)}>Generate for the {kp.unprepared} not yet proposed</Btn> : null}
                    {mayPrepare && batchOpen ? <Btn kind="ghost" disabled={busy !== null} onClick={() => void validate(batch)}>Validate</Btn> : null}
                    {mayPrepare && batch.state === "GENERATED" ? <Btn kind="primary" disabled={busy !== null || batch.conflicts > 0 || batch.students === 0} onClick={() => void ready(batch)}>Mark ready for issuance</Btn> : null}
                    {mayIssue && batch.state === "READY_FOR_ISSUANCE" ? <Btn kind="go" disabled={busy !== null} onClick={() => setReviewing(batch)}>Final review &amp; issue</Btn> : null}
                    {mayIssue && batchOpen ? <Btn kind="urgent" disabled={busy !== null} onClick={() => { setCancelling(batch); setReason(""); }}>Cancel batch</Btn> : null}
                    <Btn kind="ghost" onClick={() => void openBatch(batch.id)}>Batch record</Btn>
                  </div>
                  {batch.conflicts > 0 ? <Note kind="bad" title={`Cannot issue matriculation numbers — ${batch.conflicts} record${batch.conflicts === 1 ? "" : "s"} require attention`}>Resolve every conflict (Fix or Drop on the row) before final issuance. Nothing is issued while a conflict stands.</Note>
                    : batch.state === "READY_FOR_ISSUANCE" ? <Note kind="info" title="Ready for issuance">Every proposed number is valid. The numbers are not on any student record yet; an authorised officer issues them from the final review.</Note>
                    : <Note kind="info" title="Proposed, not issued">The numbers below are proposals held in the series for this batch. They reach the student record only when the batch is marked ready and an authorised officer confirms the issue.</Note>}
                </div>
              ) : (
                <div className="row row--between">
                  <span className="sub2">Generating proposes a number for every eligible student of the faculty{filters.prog ? " (this programme only)" : ""} from the configured rule and reserves the sequences. Nothing is written to any student record until the batch is issued.</span>
                  {mayPrepare ? <Btn kind="primary" disabled={busy !== null || kp.eligible === 0} onClick={() => void generate(filters.prog || undefined)}>{busy === "gen" ? "Generating…" : `Generate Matriculation Numbers${filters.prog ? " for this programme" : ""}`}</Btn> : null}
                </div>
              )}
            </PBody>
          </Panel>

          {(fv.programmes.filter((p) => !filters.prog || p.code === filters.prog)).map((p) => {
            const list = students.filter((c) => c.programme_code === p.code);
            if (!list.length) return null;
            const open = !collapsed.has(p.code);
            return (
              <Panel key={p.code} title={<button type="button" className="lnk b600" onClick={() => setCollapsed((s) => { const n = new Set(s); if (n.has(p.code)) n.delete(p.code); else n.add(p.code); return n; })}>{open ? "▾" : "▸"} {p.name}</button>}
                right={<span className="row row--inline row--tight"><span className="sub2">{p.department ?? ""} · {list.length} student{list.length === 1 ? "" : "s"} · {p.eligible} eligible · {p.prepared} prepared · {p.matriculated} matriculated</span>
                  <Btn kind="ghost" size="sm" onClick={() => void excel(`Programme Matriculation Report — ${p.name}`, PROG_HEAD, progBody(p.code), "programme-matriculation.xlsx")}>Excel</Btn><Btn kind="ghost" size="sm" onClick={() => pdf(`Programme Matriculation Report — ${p.name}`, PROG_HEAD, progBody(p.code))}>PDF</Btn></span>}>
                {open ? studentTable(list) : null}
              </Panel>
            );
          })}
          {!students.length ? <Note kind="info" title="No student matches">No student of {fv.name} matches the filters for {filters.session}.</Note> : null}
        </>
      ) : null}

      {tab === "all" ? (
        !page.canViewAll || !overview ? <Note kind="info" title="The all-faculties view is the Registry's">Your office is bound to its faculty; open the Faculty view.</Note> : (
          <>
            <Panel title="Final matriculation review" right={`${filters.session} · every faculty`}>
              <PBody>
                <Tiles items={[
                  ["Faculties", String(overview.totals.faculties), null, "With students in the exercise"], ["Programmes", String(overview.totals.programmes), null, "On the open batches"],
                  ["Students prepared", String(overview.totals.prepared), null, "Numbers proposed, not issued"], ["Valid", String(overview.totals.valid), "var(--green-ink)", "Ready to issue"],
                  ["Conflicts", String(overview.totals.conflicts), overview.totals.conflicts ? "var(--red-ink)" : "var(--green-ink)", overview.totals.conflicts ? "Resolve before issuance" : "None"],
                  ["Already matriculated", String(overview.totals.already), null, "On the record this session"], ["Ready for issuance", String(overview.totals.ready), overview.totals.ready ? "var(--chrome)" : null, `${overview.totals.in_review} batch(es) still in review`],
                  ["Issued", String(overview.totals.issued), overview.totals.issued ? "var(--green-ink)" : null, "By batch this session"],
                ]} />
                {mayIssue ? <div className="row row--end mt-2"><Btn kind="go" disabled={busy !== null || !overview.totals.ready} onClick={() => setConfirming("ALL")}>Confirm &amp; Issue every READY batch ({overview.totals.ready})</Btn></div> : null}
              </PBody>
            </Panel>
            <Panel title="Faculties" right="Prepared · valid · conflicts · issued">
              <DTable pageSize={0} cols={["Faculty", "Eligible|mid", "Pending|mid", "Prepared|mid", "Valid|mid", "Conflicts|mid", "Issued|mid", "Batch", "|num"]} rows={overview.faculties.map((f) => [
                <strong key="f">{f.faculty}</strong>, <span key="e" className="tnum">{f.eligible}</span>, <span key="p" className="tnum sub2">{f.pending}</span>, <span key="pr" className="tnum">{f.prepared}</span>,
                <span key="v" className="tnum ink-green">{f.valid}</span>, <span key="c" className={`tnum${f.conflicts ? " ink-red b600" : ""}`}>{f.conflicts}</span>, <span key="i" className="tnum">{f.issued}</span>,
                <span key="b">{f.batch_ref ? <><span className="tnum">{f.batch_ref}</span> <Pil kind={BATCH_WORD[f.batch_state as keyof typeof BATCH_WORD][1]}>{BATCH_WORD[f.batch_state as keyof typeof BATCH_WORD][0]}</Pil></> : <span className="sub2">—</span>}</span>,
                <span key="x" className="row row--inline row--tight row--end"><LinkBtn kind="ghost" size="sm" href={link({ fac: f.faculty_code, tab: "faculty" })}>Open</LinkBtn>{mayIssue && f.batch_state === "READY_FOR_ISSUANCE" ? <Btn kind="go" size="sm" onClick={() => setReviewing({ id: f.batch_id as string, ref: f.batch_ref as string, faculty: f.faculty, students: f.prepared, valid: f.valid, conflicts: f.conflicts } as Batch)}>Issue</Btn> : null}</span>,
              ])} texts={overview.faculties.map((f) => f.faculty)} />
            </Panel>
          </>
        )
      ) : null}

      {tab === "batches" ? (
        <Panel title="Matriculation batches" right={`${page.batches.length} · ${filters.session}`}>
          {page.batches.length ? <DTable pageSize={30} cols={["Batch", "Faculty", "State|mid", "Students|mid", "Valid|mid", "Conflicts|mid", "Issued|mid", "Prepared", "Issued by", "|num"]} rows={page.batches.map((b) => [
            <b key="r" className="tnum">{b.ref}</b>, <span key="f">{b.faculty}</span>, <Pil key="s" kind={BATCH_WORD[b.state][1]}>{BATCH_WORD[b.state][0]}</Pil>,
            <span key="n" className="tnum">{b.students}</span>, <span key="v" className="tnum">{b.valid}</span>, <span key="c" className={`tnum${b.conflicts ? " ink-red" : ""}`}>{b.conflicts}</span>, <span key="i" className="tnum">{b.issued}</span>,
            <span key="p" className="sub2">{b.prepared_officer ?? "—"} · {whenAt(b.prepared_at)}</span>, <span key="ib" className="sub2">{b.issued_at ? `${b.issued_officer ?? "—"} · ${whenAt(b.issued_at)}` : b.cancelled_at ? `Cancelled · ${b.cancel_reason ?? ""}` : "—"}</span>,
            <span key="x" className="row row--inline row--tight row--end"><Btn kind="ghost" size="sm" disabled={busy === b.id} onClick={() => void openBatch(b.id)}>Record</Btn>{b.state === "ISSUED" ? <LinkBtn kind="ghost" size="sm" href={link({ tab: "issued", batch: b.ref, fac: b.faculty_code })}>Issued list</LinkBtn> : <LinkBtn kind="ghost" size="sm" href={link({ tab: "faculty", fac: b.faculty_code })}>Open</LinkBtn>}</span>,
          ])} /> : <PBody><div className="sub2">No batch has been opened for {filters.session}.</div></PBody>}
        </Panel>
      ) : null}

      {tab === "issued" ? (
        <Panel title="Issued matriculation numbers" right={<span className="row row--inline row--tight"><span className="sub2">{issued.length} · names A–Z{filters.batch ? ` · batch ${filters.batch}` : ""}</span>
          <Btn kind="secondary" size="sm" disabled={!issued.length} onClick={() => void excel("Issued Matriculation Numbers", ISS_HEAD, issBody(), "issued-matriculation.xlsx")}>Excel</Btn><Btn kind="ghost" size="sm" disabled={!issued.length} onClick={() => pdf("Issued Matriculation Numbers", ISS_HEAD, issBody())}>PDF</Btn>
          <Btn kind="ghost" size="sm" disabled={!issued.length} onClick={() => void excel("All-Faculty Matriculation Report", ALL_HEAD, allBody(), "all-faculty-matriculation.xlsx")}>All-faculty report</Btn>{filters.batch ? <LinkBtn kind="ghost" size="sm" href={link({ batch: "" })}>Every batch</LinkBtn> : null}</span>}>
          {issued.length ? <DTable pageSize={50} cols={["S/N|num", "Matric No.", "Student Name", "Faculty", "Department", "Programme", "Session|mid", "Username", "Issued|mid", "Batch"]} rows={byName(issued).map((r, i) => [
            <span key="sn" className="tnum sub2">{i + 1}</span>, <b key="m" className="tnum">{r.matric_no}</b>, <Link key="n" className="lnk" href={`/students/${r.student_id}`}><strong>{r.surname}, {r.other_names}</strong></Link>,
            <span key="f" className="sub2">{r.faculty ?? ""}</span>, <span key="d" className="sub2">{r.department ?? ""}</span>, <span key="p">{r.programme ?? ""}</span>, <span key="s" className="tnum">{r.entry_session ?? ""}</span>,
            <span key="u"><span className="tnum">{r.matric_no}</span>{r.previous_username ? <div className="sub2">was {r.previous_username}</div> : null}</span>, <span key="i" className="tnum sub2">{dayOf(r.issued_at)}</span>, <span key="b" className="tnum sub2">{r.batch_ref ?? r.run_ref ?? ""}</span>,
          ])} texts={issued.map((r) => `${r.surname} ${r.other_names} ${r.matric_no} ${r.programme ?? ""} ${r.faculty ?? ""}`)} /> : <PBody><div className="sub2">No number has been issued for {filters.session}{fv ? ` in ${fv.name}` : ""}.</div></PBody>}
        </Panel>
      ) : null}

      {tab === "pending" ? (
        <Panel title="Pending matriculation" right={<span className="row row--inline row--tight"><span className="sub2">{pending.length} · admitted, not yet eligible</span><Btn kind="secondary" size="sm" disabled={!pending.length} onClick={() => void excel("Pending Matriculation Report", PEND_HEAD, pendBody(), "pending-matriculation.xlsx")}>Excel</Btn><Btn kind="ghost" size="sm" disabled={!pending.length} onClick={() => pdf("Pending Matriculation Report", PEND_HEAD, pendBody())}>PDF</Btn></span>}>
          {pending.length ? <DTable pageSize={50} cols={["S/N|num", "Student", "Student ID", "Faculty", "Programme", "Reason"]} rows={byName(pending).map((r, i) => [
            <span key="sn" className="tnum sub2">{i + 1}</span>, <Link key="n" className="lnk" href={`/students/${r.student_id}`}><strong>{r.surname}, {r.other_names}</strong></Link>, <span key="id" className="tnum sub2">{r.admission_no ?? "—"}</span>,
            <span key="f" className="sub2">{r.faculty}</span>, <span key="p">{r.programme}</span>, <span key="r" className="ink-amber">{r.reason}</span>,
          ])} texts={pending.map((r) => `${r.surname} ${r.other_names} ${r.programme} ${r.faculty}`)} /> : <PBody><div className="sub2">Nobody is pending{fv ? ` in ${fv.name}` : ""}: every admitted student of the session is eligible or matriculated.</div></PBody>}
        </Panel>
      ) : null}

      {tab === "conflicts" ? (
        <Panel title="Conflicts" right={fv ? `${rowsWithProblems.length} on batch ${batch?.ref ?? "—"}` : "Select a faculty"}>
          {!fv ? <PBody><div className="sub2">Choose a faculty to see the conflicts on its open batch.</div></PBody> : rowsWithProblems.length ? studentTable(rowsWithProblems) : <PBody><Note kind="ok" title="No conflict">Every proposed number on the open batch is valid.</Note></PBody>}
        </Panel>
      ) : null}

      {editing ? (
        <Modal title="Correct the proposed matriculation number" sub={`${editing.surname}, ${editing.other_names} · currently ${("proposed_no" in editing ? editing.proposed_no : null) ?? "—"}`} onClose={() => setEditing(null)}
          foot={<><Btn kind="ghost" onClick={() => setEditing(null)}>Back</Btn><Btn kind="primary" disabled={busy !== null || !newNo.trim() || !reason.trim()} onClick={() => void saveEdit()}>Save the correction</Btn></>}>
          <p className="sub2">The number is validated like any other: the configured shape, the student&rsquo;s own segments, a sequence nobody holds. Who changed it, from what, to what and why goes on the batch&rsquo;s edit history. A correction never bypasses validation.</p>
          <Field id="ed-no" label="Proposed matriculation number" required><input id="ed-no" className="ctl tnum" value={newNo} onChange={(e) => setNewNo(e.target.value.toUpperCase())} autoComplete="off" /></Field>
          <Field id="ed-why" label="Reason" required hint="Required · goes on the record"><textarea id="ed-why" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
          {"problems" in editing && (editing.problems ?? []).length ? <Note kind="bad" title="Why this row is in conflict">{(editing.problems ?? []).map((x, i) => <div key={i}>⚠ {x}</div>)}</Note> : null}
        </Modal>
      ) : null}
      {dropping ? (
        <Modal title={`Take ${dropping.name} off the batch`} sub="The reserved number is released; the student stays eligible for a later batch" onClose={() => setDropping(null)}
          foot={<><Btn kind="ghost" onClick={() => setDropping(null)}>Back</Btn><Btn kind="urgent" disabled={busy !== null || !reason.trim()} onClick={() => void drop()}>Drop from the batch</Btn></>}>
          <Field id="dr-why" label="Reason" required><textarea id="dr-why" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : null}
      {cancelling ? (
        <Modal title={`Cancel batch ${cancelling.ref}`} sub="Every reserved number is released; nothing was issued, so nothing is reversed" onClose={() => setCancelling(null)}
          foot={<><Btn kind="ghost" onClick={() => setCancelling(null)}>Back</Btn><Btn kind="urgent" disabled={busy !== null || !reason.trim()} onClick={() => void cancel()}>Cancel the batch</Btn></>}>
          <Field id="cn-why" label="Reason" required><textarea id="cn-why" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : null}
      {reviewing ? (
        <Modal title="Final matriculation review" sub={`Batch ${reviewing.ref} · ${reviewing.faculty} · ${filters.session}`} onClose={() => setReviewing(null)}
          foot={<><Btn kind="ghost" onClick={() => setReviewing(null)}>Cancel</Btn><span className="grow" /><Btn kind="go" disabled={busy !== null || reviewing.conflicts > 0} onClick={() => setConfirming(reviewing)}>Confirm &amp; Issue Matriculation Numbers</Btn></>}>
          <KvGrid cls="grid--3" pairs={[["Academic session", filters.session], ["Faculty", reviewing.faculty], ["Students", <b key="v" className="tnum">{reviewing.students}</b>], ["Valid", <b key="v" className="tnum ink-green">{reviewing.valid}</b>], ["Conflicts", <b key="v" className={`tnum${reviewing.conflicts ? " ink-red" : ""}`}>{reviewing.conflicts}</b>], ["Ready for issuance", <b key="v" className="tnum">{reviewing.conflicts ? 0 : reviewing.students}</b>]]} />
          <p className="sub2 mt-2">Every record was validated again a moment ago; it is validated once more, row by row, inside the issuing transaction. A single failure issues nothing.</p>
        </Modal>
      ) : null}
      {confirming ? (
        <Modal title="Confirm matriculation issuance" sub="This action cannot be silently reversed" onClose={() => setConfirming(null)}
          foot={<><Btn kind="ghost" onClick={() => setConfirming(null)}>Cancel</Btn><Btn kind="go" disabled={busy !== null} onClick={() => void issue()}>{busy === "issue" ? "Issuing…" : "Confirm & Issue"}</Btn></>}>
          <p>You are about to permanently issue matriculation numbers to <b className="tnum">{confirming === "ALL" ? overview?.totals.valid ?? 0 : confirming.students}</b> student{(confirming === "ALL" ? overview?.totals.valid : confirming.students) === 1 ? "" : "s"}{confirming === "ALL" ? ` across ${overview?.totals.ready ?? 0} ready batch(es)` : ` (batch ${confirming.ref})`}.</p>
          <p>This action will:</p>
          <ul className="plain stack">
            <li>✓ Assign official matriculation numbers and move each series forward</li><li>✓ Mark the students matriculated (status ADMITTED → ACTIVE)</li><li>✓ Make each matriculation number the student&rsquo;s portal sign-in username, keeping the same account and password</li>
            <li>✓ Create the permanent matriculation history and the username-change history</li><li>✓ Write the audit trail and notify every student</li>
          </ul>
        </Modal>
      ) : null}
      {done ? (
        <Modal title="Matriculation issuance completed" sub={done.map((d) => d.ref).join(" · ")} onClose={() => setDone(null)} foot={<><span className="grow" /><LinkBtn kind="secondary" href={link({ tab: "issued", batch: done.length === 1 ? done[0].ref : "" })}>Issued list</LinkBtn><Btn kind="primary" onClick={() => setDone(null)}>Close</Btn></>}>
          {done.map((d) => {
            const v = d.detail.verification; const r = d.detail.result;
            return (
              <div key={d.ref} className="mb-2">
                <div className="eyebrow mb-1">Batch {d.ref}</div>
                <KvGrid cls="grid--4" pairs={[["Successfully matriculated", <b key="v" className="tnum ink-green">{r?.issued ?? 0}</b>], ["Failed", <b key="v" className={`tnum${v?.failed ? " ink-red" : ""}`}>{v?.failed ?? 0}</b>], ["Username updates", <b key="v" className="tnum">{r?.username_updates ?? 0}</b>],
                  ["Verified on the record", <span key="v" className="tnum sub2">{v ? `${v.with_number} with number · ${v.status_active} active · ${v.history_rows} history · ${v.username_rows} username · ${v.unique_numbers} unique` : "—"}</span>]]} />
                {v?.failed ? <Note kind="bad" title={`${v.failed} record(s) did not verify`}>Those students were not marked as successfully matriculated; the Registry reads the batch record.</Note> : null}
              </div>
            );
          })}
        </Modal>
      ) : null}
      {viewing ? (
        <Modal title={`Batch ${viewing.batch.ref}`} sub={`${viewing.batch.faculty} · ${viewing.batch.session}`} wide onClose={() => setViewing(null)} foot={<><span className="grow" /><Btn kind="primary" onClick={() => setViewing(null)}>Close</Btn></>}>
          <div className="stack">
            <div className="row row--inline row--tight"><Pil kind={BATCH_WORD[viewing.batch.state][1]}>{BATCH_WORD[viewing.batch.state][0]}</Pil><span className="sub2">Prepared {viewing.batch.prepared_officer ?? "—"} · {whenAt(viewing.batch.prepared_at)}{viewing.batch.reviewed_at ? ` · reviewed ${viewing.batch.reviewed_officer ?? "—"} ${whenAt(viewing.batch.reviewed_at)}` : ""}{viewing.batch.issued_at ? ` · issued ${viewing.batch.issued_officer ?? "—"} ${whenAt(viewing.batch.issued_at)}` : ""}{viewing.batch.cancelled_at ? ` · cancelled ${whenAt(viewing.batch.cancelled_at)}: ${viewing.batch.cancel_reason ?? ""}` : ""}</span></div>
            <DTable pageSize={0} cols={["S/N|num", "Student", "Programme", "Number", "State|mid", "Validation / note"]} rows={viewing.rows.map((r, i) => [
              <span key="sn" className="tnum sub2">{i + 1}</span>, <span key="n"><strong>{r.surname}, {r.other_names}</strong><div className="sub2 tnum">{r.admission_no ?? ""}</div></span>, <span key="p" className="sub2">{r.programme ?? ""}</span>,
              <span key="m"><b className="tnum">{r.issued_no ?? r.proposed_no ?? "—"}</b>{r.edited ? <div className="sub2">corrected from {r.previous_no ?? r.generated_no} · {r.edit_reason} · {r.edited_officer ?? ""}</div> : null}</span>,
              <Pil key="s" kind={r.state === "ISSUED" ? "ok" : r.state === "DROPPED" ? "grey" : r.problems.length ? "bad" : "info"}>{r.state}</Pil>,
              <span key="v" className="sub2">{r.state === "DROPPED" ? r.drop_reason : r.problems.length ? <span className="ink-red">{r.problems.join("; ")}</span> : r.state === "ISSUED" ? `Issued ${whenAt(r.issued_at)}` : "✓ Valid"}</span>,
            ])} />
            {viewing.edits.length ? <div><div className="eyebrow mb-1">Corrections</div>{viewing.edits.map((e) => <div key={e.id} className="sub2">{whenAt(e.edited_at)} · {e.surname}, {e.other_names}: {e.previous_no ?? "—"} → <b className="tnum">{e.new_no}</b> · {e.reason} · {e.officer ?? ""}{e.office ? ` (${e.office})` : ""}</div>)}</div> : null}
          </div>
        </Modal>
      ) : null}
    </>
  );
}
