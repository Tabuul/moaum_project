"use client";

/** The deferments desk (V259, revised by V264): the figures for the office's stage, the applications waiting at this
 *  desk first, every application within the bound — searched and filtered on the server by student, application number,
 *  faculty, department, programme, session, semester, status, batch and date — the Academic Office's forwarding of the
 *  faculty-approved list to the DVC in a numbered batch, the DVC's queue by batch, the students due to resume, and the
 *  report as Excel or PDF with S/N first and names A–Z. A Head sees their department, a Dean their faculty, the
 *  Bursary, the Academic Office, the DVC and the Registry everyone. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { OFFICE_OF, SEM, STATE, StatePil, ReturnPil, dayOf, naira, periodOf, returnOf, type Batch, type Deferment } from "@/lib/deferments";
import type { DeskFilters, DeskList } from "./page";

export interface DefermentDashboard {
  scope: { kind: string; office: string; stage: string }; session: string | null;
  totals: { total: number; waiting_bursary: number; waiting_hod: number; waiting_faculty: number; waiting_academic: number; forwarded_dvc: number; pending: number; correction: number;
    approved: number; rejected: number; active: number; completed: number; faculty_approved: number; forwarded: number; returning: number; overdue: number; extensions: number; mine: number };
  byFaculty: Row[]; byDepartment: Row[]; byProgramme: Row[]; byKind: Row[]; bySession: Row[]; byReason: Row[];
  setting: { fee: number; max_sessions: number; allow_extension: boolean; reminder_days: number; overdue_after_days: number };
}
interface Row { faculty?: string; department?: string; programme?: string; kind?: string; session?: string; reason?: string; total: number; pending: number; approved: number; active: number; rejected: number }

const STAGE_WORD: Record<string, string> = { bursar: "the Bursary", hod: "the department", dean: "the faculty", facultyofficer: "the faculty", academic: "the Academic Office", dvc: "the Deputy Vice-Chancellor", registrar: "the Registry (reads the whole chain)", dregistrar: "the Registry (reads the whole chain)", super: "every desk" };

export function Desk({ list, dash, filters, batches }: { list: DeskList; dash: DefermentDashboard | null; filters: DeskFilters; batches: Batch[] }) {
  const queryNav = useQueryNav();
  const router = useRouter();
  const [q, setQ] = useState(filters.q);
  const [busy, setBusy] = useState(false);
  const [forwardOpen, setForwardOpen] = useState(false);
  const [forwardNote, setForwardNote] = useState("");
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const t = dash?.totals;
  const office = list.scope.office;
  const rows = list.rows;
  const mine = rows.filter((r) => r.state === list.scope.stage);
  const isAcademic = ["academic", "registrar", "dregistrar", "super"].includes(office);
  const isDvc = office === "dvc";
  const facultyApproved = rows.filter((r) => r.state === "FAC_RECOMMENDED");
  const faculties = [...new Map(list.options.programmes.map((p) => [p.faculty_code, p.faculty])).entries()];
  const depts = [...new Map(list.options.programmes.filter((p) => !filters.fac || p.faculty_code === filters.fac).map((p) => [p.dept_code, p.department])).entries()];
  const progs = list.options.programmes.filter((p) => (!filters.fac || p.faculty_code === filters.fac) && (!filters.dept || p.dept_code === filters.dept));
  const go = (next: Partial<DeskFilters>) => { const f = { ...filters, ...next }; if (next.fac !== undefined) { f.dept = ""; f.prog = ""; } if (next.dept !== undefined) f.prog = ""; const qs = new URLSearchParams(); for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v); queryNav(`/deferments?${qs}`); };
  const reset = () => { setQ(""); queryNav("/deferments"); };
  const scope = [filters.session, filters.semester ? SEM(Number(filters.semester)) : null, filters.state ? STATE[filters.state]?.[0] ?? filters.state : null, filters.kind, filters.batch ? `batch ${filters.batch}` : null, filters.from || filters.to ? `${filters.from || "…"} → ${filters.to || "…"}` : null, filters.q ? `search “${filters.q}”` : null].filter(Boolean).join(" · ") || "All applications";

  const HEAD = ["S/N", "Application No.", "Student ID", "Student Name", "Faculty", "Department", "Programme", "Type", "Session", "Semester", "Current Stage", "Status", "Fee", "Date Submitted", "Faculty Approval", "Forwarded", "Batch", "Expected Return"];
  const exportable = () => (office === "academic" ? rows.filter((r) => r.downloadable) : rows);
  const body = () => exportable().map((r, i) => [i + 1, r.reference, r.number, `${r.surname}, ${r.other_names}`, r.faculty, r.department, r.programme, r.kind === "SESSION" ? "Session" : "Semester", r.session, r.kind === "SESSION" ? "All" : SEM(r.semester), OFFICE_OF[r.state] ?? "", STATE[r.state]?.[0] ?? r.state, r.fee_state ?? "", r.submitted_at ? dayOf(r.submitted_at) : "", r.fac_at ? dayOf(r.fac_at) : "", r.forwarded_at ? dayOf(r.forwarded_at) : "", r.batch_reference ?? "", returnOf(r)]);
  async function excel() { const blob = await brandedXlsx("Deferment Applications", HEAD, body(), { sheetName: "Deferments", serial: docSerial("DEF"), sub: scope }); downloadBlob(blob, `deferments-${(filters.session || "all").replace("/", "-")}.xlsx`); }
  const pdf = () => brandedPrint("Deferment Applications", scope, HEAD, body(), docSerial("DEF"));

  async function forward(all: boolean) {
    setBusy(true);
    try {
      const ids = all ? [] : [...picked];
      const r = await fetch("/api/bff/api/v1/deferments/forward", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(all ? "Faculty-approved deferment applications forwarded to the DVC" : `${ids.length} deferment application(s) forwarded to the DVC`) },
        body: JSON.stringify({ ids: all ? null : ids, session: filters.session || null, semester: filters.semester ? Number(filters.semester) : null, note: forwardNote.trim() || null }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      notify(`Batch ${(j as Batch).reference} forwarded to the DVC · ${(j as Batch).count} application(s)`);
      setForwardOpen(false); setPicked(new Set()); setForwardNote("");
      router.refresh();
    } finally { setBusy(false); }
  }

  const table = (items: Deferment[], pick = false) => (
    <DTable pageSize={0} cols={[...(pick ? ["|mid"] : []), "S/N|num", "Application No.", "Student", "Faculty · Department · Programme", "Type|mid", "Period", "Current stage", "Status|mid", "Submitted|mid", ...(isDvc ? ["Faculty approval|mid", "Forwarded|mid"] : []), "|num"]}
      rows={items.map((r, i) => [
        ...(pick ? [<input key="pk" type="checkbox" className="pchk" checked={picked.has(r.id)} onChange={(e) => { const n = new Set(picked); if (e.target.checked) n.add(r.id); else n.delete(r.id); setPicked(n); }} />] : []),
        <span key="sn" className="tnum sub2">{i + 1}</span>,
        <Link key="r" className="lnk tnum b600" href={`/deferments/${r.id}`}>{r.reference}</Link>,
        <span key="s"><strong>{r.surname}, {r.other_names}</strong><div className="sub2 tnum">{r.number} · {r.level} Level</div></span>,
        <span key="p">{r.faculty}<div className="sub2">{r.department} · {r.programme}</div></span>,
        <span key="k">{r.kind === "SESSION" ? "Session" : "Semester"}</span>,
        <span key="pe" className="tnum">{periodOf(r)}</span>,
        <span key="cs" className="sub2">{OFFICE_OF[r.state] ?? "—"}{r.batch_reference ? <div className="tnum">{r.batch_reference}</div> : null}</span>,
        <span key="st"><StatePil state={r.state} /> {r.return_status && ["ACTIVE", "APPROVED"].includes(r.state) ? <ReturnPil status={r.return_status} /> : null}</span>,
        <span key="d" className="tnum sub2">{dayOf(r.submitted_at ?? r.created_at)}</span>,
        ...(isDvc ? [<span key="fa" className="tnum sub2">{dayOf(r.fac_at)}</span>, <span key="fw" className="tnum sub2">{dayOf(r.forwarded_at)}</span>] : []),
        <span key="o" className="row row--inline row--tight" style={{ justifyContent: "flex-end" }}>
          <LinkBtn href={`/deferments/${r.id}`} size="sm" kind={r.state === list.scope.stage ? "primary" : "ghost"}>{r.state === list.scope.stage ? "Review" : "View"}</LinkBtn>
          {r.downloadable ? <a className="btn btn--ghost btn--sm" href={`/deferments/${r.id}/application`} target="_blank" rel="noopener">Download</a> : null}
        </span>,
      ])} texts={items.map((r) => `${r.reference} ${r.surname} ${r.other_names} ${r.number} ${r.programme} ${r.department} ${r.faculty} ${STATE[r.state]?.[0] ?? ""} ${r.batch_reference ?? ""}`)} />
  );

  const tiles: [string, string, string | null, string][] = !t ? [] : office === "bursar" ? [
    ["Awaiting Bursary", String(t.waiting_bursary), t.waiting_bursary ? "var(--amber-ink)" : null, "Submitted, fee paid, financial verification due"],
    ["Approved", String(t.approved + t.waiting_hod + t.waiting_faculty + t.waiting_academic + t.forwarded_dvc), null, "Passed the Bursary"],
    ["Rejected", String(t.rejected), null, "With the reason on the record"], ["Returned", String(t.correction), t.correction ? "var(--amber-ink)" : null, "Returned for correction"],
  ] : office === "hod" ? [
    ["Awaiting HOD", String(t.waiting_hod), t.waiting_hod ? "var(--amber-ink)" : null, "Bursary-approved, your decision due"],
    ["Approved", String(t.approved + t.waiting_faculty + t.waiting_academic + t.forwarded_dvc), null, "Passed the department"],
    ["Rejected", String(t.rejected), null, "With the reason on the record"], ["Returned", String(t.correction), t.correction ? "var(--amber-ink)" : null, "Returned for correction"],
  ] : ["dean", "facultyofficer"].includes(office) ? [
    ["Awaiting Faculty", String(t.waiting_faculty), t.waiting_faculty ? "var(--amber-ink)" : null, "Department-approved, your decision due"],
    ["Approved", String(t.approved + t.waiting_academic + t.forwarded_dvc), null, "Passed the faculty"],
    ["Rejected", String(t.rejected), null, "With the reason on the record"], ["Returned", String(t.correction), t.correction ? "var(--amber-ink)" : null, "Returned for correction"],
  ] : office === "dvc" ? [
    ["Pending approval", String(t.forwarded_dvc), t.forwarded_dvc ? "var(--amber-ink)" : null, "Forwarded by the Academic Office"],
    ["Approved", String(t.approved), t.approved ? "var(--green-ink)" : null, "Final approval, with your comment on the record"],
    ["Rejected", String(t.rejected), null, "With the reason on the record"], ["Returned", String(t.correction), null, "Returned for correction"],
    ["Total received", String(t.forwarded), null, "Every application forwarded to this office"],
  ] : [
    ["Total applications", String(t.total), null, dash?.session ?? "Every session"],
    ["Bursary pending", String(t.waiting_bursary), t.waiting_bursary ? "var(--amber-ink)" : null, "WAITING BURSARY ACTION"],
    ["HOD pending", String(t.waiting_hod), t.waiting_hod ? "var(--amber-ink)" : null, "WAITING HOD ACTION"],
    ["Faculty pending", String(t.waiting_faculty), t.waiting_faculty ? "var(--amber-ink)" : null, "WAITING FACULTY ACTION"],
    ["Faculty approved", String(t.faculty_approved), t.faculty_approved ? "var(--green-ink)" : null, "Downloadable by the Academic Office"],
    ["Pending forwarding", String(t.waiting_academic), t.waiting_academic ? "var(--chrome)" : null, "Faculty-approved, not yet forwarded"],
    ["Forwarded to DVC", String(t.forwarded_dvc), null, "WAITING DVC ACTION"],
    ["Approved", String(t.approved), t.approved ? "var(--green-ink)" : null, "Approved by the DVC, in force or completed"],
    ["Completed", String(t.completed), null, "Returned from deferment"],
    ["Rejected", String(t.rejected), null, "With the reason on the record"],
    ["Overdue returns", String(t.overdue), t.overdue ? "var(--red-ink)" : null, "Past the return date, not confirmed"],
  ];
  const tileState: Record<string, string> = { "Awaiting Bursary": "SUBMITTED", "Bursary pending": "SUBMITTED", "Awaiting HOD": "BURSARY_APPROVED", "HOD pending": "BURSARY_APPROVED", "Awaiting Faculty": "DEPT_RECOMMENDED", "Faculty pending": "DEPT_RECOMMENDED",
    "Faculty approved": "FACULTY_APPROVED", "Pending forwarding": "FAC_RECOMMENDED", "Forwarded to DVC": "FORWARDED_TO_DVC", "Pending approval": "FORWARDED_TO_DVC", "Approved": "APPROVED", "Completed": "COMPLETED", "Rejected": "REJECTED", "Returned": "CORRECTION_REQUIRED", "Total applications": "", "Total received": "" };

  return (
    <>
      <PageHead title="Deferments" description={`${dash?.scope.kind === "DEPARTMENT" ? "Your department's" : dash?.scope.kind === "FACULTY" ? "Your faculty's" : dash?.scope.kind === "PG_SCHOOL" ? "The Postgraduate School's" : dash?.scope.kind === "COLLEGE" ? "The College's" : "The University's"} deferment applications: what waits at ${STAGE_WORD[office] ?? "this desk"}, every application and where it stands on the chain — Bursary → HOD → Faculty → Academic Office → DVC (final) — and the students due to resume.`}
        actions={<><LinkBtn kind="primary" href="/deferments/returns">Students Due to Resume</LinkBtn>{isAcademic ? <LinkBtn kind="secondary" href="/deferments/batches">Batches</LinkBtn> : null}<Btn kind="secondary" onClick={() => void excel()} disabled={!exportable().length}>Download Excel</Btn><Btn kind="ghost" onClick={pdf} disabled={!exportable().length}>Download PDF</Btn></>} />

      {t ? <Tiles items={tiles.map(([l, v, c, s]) => { const st = tileState[l]; const qs = new URLSearchParams(); for (const [k, val] of Object.entries({ ...filters, state: st ?? "" })) if (val) qs.set(k, val); return [<Link key={l} className="lnk" href={`/deferments?${qs}`}>{l}</Link>, v, c, s]; })} /> : null}

      {mine.length ? (
        <Panel title={`Waiting at this desk · ${STATE[list.scope.stage]?.[0] ?? ""}`} right={`${mine.length} to decide`}>{table(mine)}</Panel>
      ) : list.scope.stage !== "__none__" ? <Note kind="ok" title="Nothing waits at this desk">Applications arrive here when they reach this desk&rsquo;s stage; every application within your bound is listed below.</Note> : null}

      {isAcademic ? (
        <Panel title="Forwarding to the Deputy Vice-Chancellor" right={t ? <span className="row row--inline row--tight"><Pil kind="ok">Faculty approved {t.faculty_approved}</Pil><Pil kind="grey">Already forwarded {t.forwarded}</Pil><Pil kind={t.waiting_academic ? "warn" : "grey"}>Pending forwarding {t.waiting_academic}</Pil></span> : null}>
          <PBody>
            <div className="row row--between" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
              <span className="sub2">The Academic Office sees every stage and downloads an application once the faculty has approved it. Forward the whole faculty-approved list, or the ones ticked below, to the DVC in one numbered batch (DEF-DVC-YYYY-NNNNN); nothing is duplicated, every member is named on the batch.</span>
              <span className="row row--inline row--tight">
                <Btn kind="secondary" disabled={busy || !picked.size} onClick={() => setForwardOpen(true)}>Forward {picked.size || ""} Selected</Btn>
                <Btn kind="primary" disabled={busy || !facultyApproved.length} onClick={() => { setPicked(new Set()); setForwardOpen(true); }}>Forward Approved Applications to DVC</Btn>
              </span>
            </div>
            {facultyApproved.length ? <div className="mt-2">{table(facultyApproved, true)}</div> : <div className="sub2 mt-2">No faculty-approved application is waiting to be forwarded{filters.session ? ` for ${filters.session}` : ""}.</div>}
          </PBody>
        </Panel>
      ) : null}

      <div className="scope">
        <div className="scope__f"><Field id="dk-session" label="Session"><select id="dk-session" className="ctl" value={filters.session} onChange={(e) => go({ session: e.target.value })}><option value="">Every session</option>{list.options.sessions.map((s) => <option key={s} value={s}>{s}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="dk-sem" label="Semester"><select id="dk-sem" className="ctl" value={filters.semester} onChange={(e) => go({ semester: e.target.value })}><option value="">Any</option><option value="1">First</option><option value="2">Second</option></select></Field></div>
        <div className="scope__f"><Field id="dk-kind" label="Type"><select id="dk-kind" className="ctl" value={filters.kind} onChange={(e) => go({ kind: e.target.value })}><option value="">Both</option><option value="SEMESTER">Semester</option><option value="SESSION">Session</option></select></Field></div>
        <div className="scope__f"><Field id="dk-state" label="Status / current office"><select id="dk-state" className="ctl" value={filters.state} onChange={(e) => go({ state: e.target.value })}><option value="">Every status</option><option value="PENDING">In review (any desk)</option><option value="FACULTY_APPROVED">Faculty approved (downloadable)</option>{list.options.states.map((s) => <option key={s} value={s}>{STATE[s]?.[0] ?? s}</option>)}</select></Field></div>
        {list.scope.kind === "UNIVERSITY" || list.scope.kind === "PG_SCHOOL" || list.scope.kind === "COLLEGE" ? <div className="scope__f"><Field id="dk-fac" label="Faculty"><select id="dk-fac" className="ctl" value={filters.fac} onChange={(e) => go({ fac: e.target.value })}><option value="">All</option>{faculties.map(([c, n]) => <option key={c} value={c}>{n}</option>)}</select></Field></div> : null}
        {list.scope.kind !== "DEPARTMENT" ? <div className="scope__f"><Field id="dk-dept" label="Department"><select id="dk-dept" className="ctl" value={filters.dept} onChange={(e) => go({ dept: e.target.value })}><option value="">All</option>{depts.map(([c, n]) => <option key={c} value={c}>{n}</option>)}</select></Field></div> : null}
        <div className="scope__f"><Field id="dk-prog" label="Programme"><select id="dk-prog" className="ctl" value={filters.prog} onChange={(e) => go({ prog: e.target.value })}><option value="">All</option>{progs.map((p) => <option key={p.programme_code} value={p.programme_code}>{p.programme}</option>)}</select></Field></div>
        {isAcademic || isDvc ? <div className="scope__f"><Field id="dk-batch" label="Batch"><select id="dk-batch" className="ctl" value={filters.batch} onChange={(e) => go({ batch: e.target.value })}><option value="">Any</option>{list.options.batches.map((b) => <option key={b.id} value={b.reference}>{b.reference} · {b.count}</option>)}</select></Field></div> : null}
        <div className="scope__f"><Field id="dk-from" label="Submitted from"><input id="dk-from" type="date" className="ctl" value={filters.from} onChange={(e) => go({ from: e.target.value })} /></Field></div>
        <div className="scope__f"><Field id="dk-to" label="to"><input id="dk-to" type="date" className="ctl" value={filters.to} onChange={(e) => go({ to: e.target.value })} /></Field></div>
        <div className="scope__f grow"><Field id="dk-q" label="Search" hint="Student name or ID, matriculation number, application number, programme, department, faculty or batch">
          <form className="scope__search" onSubmit={(e) => { e.preventDefault(); go({ q: q.trim() }); }}><input id="dk-q" className="ctl" placeholder="Search deferment applications…" value={q} onChange={(e) => setQ(e.target.value)} /><Btn kind="primary" type="submit">Search</Btn><Btn kind="ghost" onClick={reset}>Reset</Btn></form>
        </Field></div>
      </div>

      <Panel title="Deferment applications" right={`${rows.length} · names A–Z${rows.length >= 500 ? " · first 500; narrow the search" : ""}`}>
        {rows.length ? table(rows) : <PBody><Note kind="info" title="No deferment application found">No application matches the selected session, status, batch and filters within your bound.</Note></PBody>}
      </Panel>

      {dash && (dash.byProgramme.length || dash.byReason.length) ? (
        <div className="grid grid--2">
          <Panel title="By programme"><DTable pageSize={0} cols={["Programme", "Total|num", "In review|num", "Approved|num", "Active|num", "Rejected|num"]} rows={dash.byProgramme.map((r) => [<span key="p">{r.programme}</span>, <span key="t" className="tnum">{r.total}</span>, <span key="pe" className="tnum">{r.pending}</span>, <span key="a" className="tnum">{r.approved}</span>, <span key="ac" className="tnum">{r.active}</span>, <span key="rj" className="tnum">{r.rejected}</span>])} /></Panel>
          <Panel title="By reason"><DTable pageSize={0} cols={["Reason", "Total|num", "In review|num", "Approved|num", "Active|num", "Rejected|num"]} rows={dash.byReason.map((r) => [<span key="p">{r.reason}</span>, <span key="t" className="tnum">{r.total}</span>, <span key="pe" className="tnum">{r.pending}</span>, <span key="a" className="tnum">{r.approved}</span>, <span key="ac" className="tnum">{r.active}</span>, <span key="rj" className="tnum">{r.rejected}</span>])} /></Panel>
        </div>
      ) : null}
      {dash && dash.byFaculty.length > 1 ? (
        <Panel title="By faculty"><DTable pageSize={0} cols={["Faculty", "Total|num", "In review|num", "Approved|num", "Active|num", "Rejected|num"]} rows={dash.byFaculty.map((r) => [<span key="p">{r.faculty}</span>, <span key="t" className="tnum">{r.total}</span>, <span key="pe" className="tnum">{r.pending}</span>, <span key="a" className="tnum">{r.approved}</span>, <span key="ac" className="tnum">{r.active}</span>, <span key="rj" className="tnum">{r.rejected}</span>])} /></Panel>
      ) : null}
      {dash?.setting ? <div className="sub2">Deferment application fee {naira(dash.setting.fee)} (stated by the Bursary on Fee Setup) · at most {dash.setting.max_sessions} session(s) deferred in all · returns reminded {dash.setting.reminder_days} days ahead, overdue after {dash.setting.overdue_after_days} days.</div> : null}
      {isAcademic && batches.length ? <div className="sub2">Latest batch: <Link className="lnk tnum" href="/deferments/batches">{batches[0].reference}</Link> · {batches[0].count} application(s) · {dayOf(batches[0].forwarded_at)} · {batches[0].dvc_status === "OPEN" ? `${batches[0].awaiting_dvc} awaiting the DVC` : "decided"}</div> : null}

      {forwardOpen ? (
        <Modal title={picked.size ? `Forward ${picked.size} application(s) to the DVC` : `Forward the faculty-approved list to the DVC`} sub={picked.size ? "The ticked applications only" : `${facultyApproved.length} application(s)${filters.session ? ` for ${filters.session}` : ""}${filters.semester ? ` · ${SEM(Number(filters.semester))}` : ""}`} onClose={() => setForwardOpen(false)}
          foot={<><Btn kind="ghost" onClick={() => setForwardOpen(false)}>Back</Btn><Btn kind="primary" disabled={busy} onClick={() => void forward(!picked.size)}>Forward to DVC</Btn></>}>
          <p>A numbered batch (DEF-DVC-YYYY-NNNNN) is created naming every application in it, the date, the session and you; each application becomes <b>FORWARDED TO DVC</b>, the students are told, and the DVC is told the batch awaits. Applications already forwarded are never included again.</p>
          <Field id="fw-note" label="Covering note" hint="Optional; goes on the batch and on every application's trail."><textarea id="fw-note" className="ctl" rows={3} value={forwardNote} onChange={(e) => setForwardNote(e.target.value)} /></Field>
          <ul className="plain sub2 mt-2" style={{ maxHeight: 220, overflowY: "auto" }}>{(picked.size ? facultyApproved.filter((r) => picked.has(r.id)) : facultyApproved).map((r) => <li key={r.id} className="tnum">{r.reference} · {r.surname}, {r.other_names} · {r.programme}</li>)}</ul>
        </Modal>
      ) : null}
    </>
  );
}
