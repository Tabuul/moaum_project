"use client";

/** The candidates of the examination (V260): every applicant of the session with where they stand — eligible or
 *  not and why, seated or not and where — filtered by status, faculty, department, programme, batch and centre,
 *  searched on the server, exported with S/N first and names A–Z; chosen ones moved to a batch or unscheduled
 *  with a reason; a seating flagged by a programme change confirmed; each candidate's trail opened. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { ATTENDANCE, BATCH_STATE, STATUS, callPutme, clock, dayOf, whenAt, type Batch, type Candidate, type CandidateList } from "@/lib/putme";
import type { CandFilters } from "./page";

const OFFICERS = ["academic", "registrar", "dregistrar", "super"];
interface Ev { action: string; from_value: string | null; to_value: string | null; note: string | null; actor_office: string | null; at: string; batch: string | null; actor: string | null }
interface Seating { state: string; seat: string; reason: string | null; assigned_at: string; ended_at: string | null; attendance: string; exam_status: string; checked_in_at: string | null; label: string; held_on: string; starts_at: string; ends_at: string; venue: string }

export function Candidates({ view, batches, filters, office }: { view: CandidateList; batches: Batch[]; filters: CandFilters; office: string | null }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const s = view.session;
  const may = !!office && OFFICERS.includes(office);
  const [q, setQ] = useState(filters.q);
  const [picked, setPicked] = useState<string[]>([]);
  const [ask, setAsk] = useState<"move" | "unschedule" | null>(null);
  const [target, setTarget] = useState("");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [trail, setTrail] = useState<{ c: Candidate; events: Ev[]; seatings: Seating[] } | null>(null);
  const rows = view.rows;
  const go = (next: Partial<CandFilters>) => { const f = { ...filters, ...next, page: next.page ?? "" }; if (next.fac !== undefined) { f.dept = ""; f.prog = ""; } if (next.dept !== undefined) f.prog = ""; const qs = new URLSearchParams(); qs.set("session", s); for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v); queryNav(`/admissions/putme/candidates?${qs}`); };
  const faculties = [...new Map(view.options.map((o) => [o.faculty_code, o.faculty])).entries()].filter(([k]) => k);
  const depts = [...new Map(view.options.filter((o) => !filters.fac || o.faculty_code === filters.fac).map((o) => [o.dept_code, o.department])).entries()].filter(([k]) => k);
  const progs = [...new Map(view.options.filter((o) => (!filters.fac || o.faculty_code === filters.fac) && (!filters.dept || o.dept_code === filters.dept)).map((o) => [o.programme_code, o.programme])).entries()];
  const centres = [...new Set(batches.map((b) => b.centre ?? b.venue))];
  const live = batches.filter((b) => b.state === "DRAFT" || b.state === "PUBLISHED");
  const scope = [filters.status ? STATUS[filters.status]?.[0] ?? filters.status.toLowerCase() : "every candidate", filters.fac, filters.dept, filters.prog, filters.batch ? `batch ${batches.find((b) => b.id === filters.batch)?.label ?? ""}` : "", filters.centre, filters.q ? `search “${filters.q}”` : ""].filter(Boolean).join(" · ");
  const pages = Math.max(1, Math.ceil(view.total / view.size));

  const HEAD = ["S/N", "Application No", "JAMB No", "Surname", "Other Names", "Programme", "Department", "Faculty", "Status", "Batch", "Date", "Time", "Centre", "Room", "Seat", "Workstation", "Attendance", "Score"];
  const body = () => rows.map((r, i) => [i + 1, r.application_no, r.jamb_reg_no, r.surname, r.other_names, r.programme, r.department ?? "", r.faculty ?? "", STATUS[r.status]?.[0] ?? r.status, r.batch ?? "", r.held_on ? dayOf(r.held_on) : "", r.starts_at ? `${clock(r.starts_at)}–${clock(r.ends_at)}` : "", r.centre ?? "", r.room ?? "", r.seat ?? "", r.workstation ?? "", ATTENDANCE[r.attendance]?.[0] ?? r.attendance, r.screening_score ?? ""]);
  async function excel() { const blob = await brandedXlsx("Post-UTME CBT Candidates", HEAD, body(), { sheetName: "Candidates", serial: docSerial("CBT"), sub: `${s} · ${scope}` }); downloadBlob(blob, `putme-candidates-${s.replace("/", "-")}.xlsx`); }

  async function act() {
    if (!reason.trim()) { notifyProblem({ status: 422, title: ask === "move" ? "A move carries its reason." : "Unscheduling carries its reason." }); return; }
    if (ask === "move" && !target) { notifyProblem({ status: 422, title: "Choose the batch." }); return; }
    setBusy(true);
    try {
      const r = ask === "move"
        ? await callPutme<{ moved: { applicationId: string; result: string }[] }>(s, "POST", "/move", { applicationIds: picked, batchId: target, reason: reason.trim() }, `Move ${picked.length} candidate(s) to a batch: ${reason.trim()}`)
        : await callPutme<{ unscheduled: number }>(s, "POST", "/unschedule", { applicationIds: picked, reason: reason.trim() }, `Unschedule ${picked.length} candidate(s): ${reason.trim()}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(ask === "move" ? `${(r.data as { moved: unknown[] }).moved.length} candidate(s) seated` : `${(r.data as { unscheduled: number }).unscheduled} candidate(s) unscheduled`);
      setAsk(null); setReason(""); setTarget(""); setPicked([]); router.refresh();
    } finally { setBusy(false); }
  }
  async function confirm(c: Candidate) {
    const r = await callPutme(s, "POST", `/candidates/${c.application_id}/confirm-schedule`, {}, `Confirm the seating of ${c.application_no} after the programme change`);
    if (!r.ok) { notifyProblem(r.problem); return; } notify("Seating confirmed"); router.refresh();
  }
  async function openTrail(c: Candidate) {
    const [e, z] = await Promise.all([callPutme<Ev[]>(s, "GET", `/candidates/${c.application_id}/events`, undefined, "Read the candidate's trail"), callPutme<Seating[]>(s, "GET", `/candidates/${c.application_id}/seatings`, undefined, "Read the candidate's seatings")]);
    if (!e.ok) { notifyProblem(e.problem); return; }
    setTrail({ c, events: e.data, seatings: z.ok ? z.data : [] });
  }
  const all = rows.length > 0 && rows.every((r) => picked.includes(r.application_id));

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href={`/admissions/putme?session=${encodeURIComponent(s)}`}>Post-UTME CBT</Link><span>›</span><strong>Candidates</strong></div>
      <PageHead title="Candidates" description={`${s} · ${scope}. ${view.total.toLocaleString()} candidate(s); names A–Z.`}
        actions={<>
          {may && picked.length ? <><Btn kind="primary" onClick={() => setAsk("move")}>Move {picked.length} to a batch</Btn><Btn kind="ghost" onClick={() => setAsk("unschedule")}>Unschedule {picked.length}</Btn></> : null}
          <Btn kind="secondary" onClick={() => void excel()} disabled={!rows.length}>Download Excel</Btn>
          <Btn kind="ghost" onClick={() => brandedPrint("Post-UTME CBT Candidates", `${s} · ${scope}`, HEAD, body(), docSerial("CBT"))} disabled={!rows.length}>Download PDF</Btn>
          <LinkBtn kind="ghost" href={`/admissions/putme?session=${encodeURIComponent(s)}`}>Back to the desk</LinkBtn>
        </>} />

      <div className="scope">
        <div className="scope__f"><Field id="cf-status" label="Standing"><select id="cf-status" className="ctl" value={filters.status} onChange={(e) => go({ status: e.target.value })}>
          <option value="">Everyone</option><option value="ELIGIBLE">Eligible</option><option value="UNSCHEDULED">Ready, not seated</option><option value="SCHEDULED">Scheduled</option>
          {Object.entries(STATUS).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="cf-fac" label="Faculty"><select id="cf-fac" className="ctl" value={filters.fac} onChange={(e) => go({ fac: e.target.value })}><option value="">Every faculty</option>{faculties.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="cf-dept" label="Department"><select id="cf-dept" className="ctl" value={filters.dept} onChange={(e) => go({ dept: e.target.value })}><option value="">Every department</option>{depts.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="cf-prog" label="Programme"><select id="cf-prog" className="ctl" value={filters.prog} onChange={(e) => go({ prog: e.target.value })}><option value="">Every programme</option>{progs.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="cf-batch" label="Batch"><select id="cf-batch" className="ctl" value={filters.batch} onChange={(e) => go({ batch: e.target.value })}><option value="">Any batch</option>{batches.map((b) => <option key={b.id} value={b.id}>{b.label} · {dayOf(b.held_on)}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="cf-centre" label="Centre"><select id="cf-centre" className="ctl" value={filters.centre} onChange={(e) => go({ centre: e.target.value })}><option value="">Any centre</option>{centres.map((c) => <option key={c} value={c}>{c}</option>)}</select></Field></div>
        <form className="scope__search" onSubmit={(e) => { e.preventDefault(); go({ q: q.trim() }); }}>
          <Field id="cf-q" label="Search"><input id="cf-q" className="ctl" placeholder="Name, application or JAMB number, programme" value={q} onChange={(e) => setQ(e.target.value)} /></Field>
          <Btn kind="secondary" type="submit">Search</Btn>
        </form>
      </div>

      {rows.some((r) => r.schedule_review) ? <Note kind="info" title="Some seatings need a look">A candidate&rsquo;s programme changed after they were seated. Confirm the seating, or move them to the right batch.</Note> : null}

      <Panel title={`${view.total.toLocaleString()} candidate(s)`} right={pages > 1 ? <span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => go({ page: String(view.page - 1) })} disabled={view.page <= 0}>Previous</Btn><span className="sub2">Page {view.page + 1} of {pages}</span><Btn kind="ghost" onClick={() => go({ page: String(view.page + 1) })} disabled={view.page + 1 >= pages}>Next</Btn></span> : "Names A–Z"}>
        {rows.length ? (
          <DTable pageSize={0} cols={[may ? "|mid" : "S/N|num", ...(may ? ["S/N|num"] : []), "Candidate", "Programme", "Standing", "Seating", "Attendance|mid", "|num"]} rows={rows.map((r, i) => [
            ...(may ? [<input key="pk" type="checkbox" aria-label={`Choose ${r.surname}`} checked={picked.includes(r.application_id)} onChange={(e) => setPicked(e.target.checked ? [...picked, r.application_id] : picked.filter((x) => x !== r.application_id))} />] : []),
            <span key="sn" className="tnum sub2">{view.page * view.size + i + 1}</span>,
            <span key="c"><strong>{r.surname}</strong>, {r.other_names}<div className="sub2 tnum">{r.application_no} · JAMB {r.jamb_reg_no}{r.entry_mode === "DIRECT_ENTRY" ? " · DE" : ""}</div></span>,
            <span key="p">{r.programme}<div className="sub2">{r.department ?? "—"} · {r.faculty ?? "—"}</div></span>,
            <span key="st"><Pil kind={STATUS[r.status]?.[1] ?? "grey"}>{STATUS[r.status]?.[0] ?? r.status}</Pil>{r.schedule_review ? <> <Pil kind="warn">Review</Pil></> : null}<div className="sub2">{r.why}</div></span>,
            r.batch ? <span key="b"><Link className="lnk b600" href={`/admissions/putme/batches/${r.batch_id}?session=${encodeURIComponent(s)}`}>{r.batch}</Link> · seat <span className="tnum">{r.seat}</span>{r.workstation ? <span className="tnum"> · {r.workstation}</span> : null}<div className="sub2 tnum">{dayOf(r.held_on)} {clock(r.starts_at)} · {r.centre}{r.room ? ` · ${r.room}` : ""}</div></span> : <span key="b" className="sub2">—</span>,
            <span key="a"><Pil kind={ATTENDANCE[r.attendance]?.[1] ?? "grey"}>{ATTENDANCE[r.attendance]?.[0] ?? r.attendance}</Pil>{r.screening_score !== null ? <div className="sub2 tnum">score {r.screening_score}</div> : null}</span>,
            <span key="o" className="row row--inline row--tight">{may && r.schedule_review ? <Btn kind="secondary" onClick={() => void confirm(r)}>Confirm</Btn> : null}<Btn kind="ghost" onClick={() => void openTrail(r)}>Trail</Btn></span>,
          ])} texts={rows.map((r) => `${r.surname} ${r.other_names} ${r.application_no} ${r.jamb_reg_no} ${r.programme} ${r.batch ?? ""} ${r.status}`)} />
        ) : <PBody><div className="sub2">No candidate matches. Widen the filters.</div></PBody>}
        {may && rows.length ? <PBody><label className="row row--tight sub2" style={{ gap: 8 }}><input type="checkbox" checked={all} onChange={(e) => setPicked(e.target.checked ? [...new Set([...picked, ...rows.map((r) => r.application_id)])] : picked.filter((x) => !rows.some((r) => r.application_id === x)))} /> Choose everyone on this page</label></PBody> : null}
      </Panel>

      {ask ? (
        <Modal title={ask === "move" ? `Move ${picked.length} candidate(s) to a batch` : `Unschedule ${picked.length} candidate(s)`} onClose={() => setAsk(null)}
          foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void act()} disabled={busy}>{busy ? "Working…" : ask === "move" ? "Move" : "Unschedule"}</Btn></>}>
          {ask === "move" ? <Field id="mv-batch" label="Batch" required full><select id="mv-batch" className="ctl" value={target} onChange={(e) => setTarget(e.target.value)}><option value="">Choose a batch</option>{live.map((b) => <option key={b.id} value={b.id}>{b.label} · {dayOf(b.held_on)} {clock(b.starts_at)} · {b.centre ?? b.venue}{b.room ? ` · ${b.room}` : ""} · {b.assigned}/{b.capacity}</option>)}</select></Field> : <p>Each candidate&rsquo;s seat is released and they return to “ready for scheduling”. Each is told by email and SMS.</p>}
          <Field id="mv-reason" label="Reason" required full><textarea id="mv-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : null}
      {trail ? (
        <Modal title={`${trail.c.surname}, ${trail.c.other_names}`} sub={`${trail.c.application_no} · ${trail.c.programme}`} wide onClose={() => setTrail(null)} foot={<Btn kind="ghost" onClick={() => setTrail(null)}>Close</Btn>}>
          <Panel title="Seatings" right={`${trail.seatings.length}`}>
            {trail.seatings.length ? <DTable cols={["Batch", "Day", "Seat|mid", "State|mid", "Attendance|mid", "Reason", "From|mid", "To|mid"]} rows={trail.seatings.map((z, i) => [<b key="l">{z.label}</b>, <span key="d" className="tnum">{dayOf(z.held_on)} {clock(z.starts_at)}</span>, <span key="s" className="tnum">{z.seat}</span>, <Pil key="st" kind={z.state === "ACTIVE" ? "ok" : "grey"}>{z.state.toLowerCase()}</Pil>, <Pil key="a" kind={ATTENDANCE[z.attendance]?.[1] ?? "grey"}>{ATTENDANCE[z.attendance]?.[0] ?? z.attendance}</Pil>, <span key="r" className="sub2">{z.reason ?? ""}</span>, <span key="f" className="tnum sub2">{whenAt(z.assigned_at)}</span>, <span key="t" className="tnum sub2">{z.ended_at ? whenAt(z.ended_at) : "—"}</span>].map((c, j) => <span key={`${i}-${j}`}>{c}</span>))} /> : <PBody><div className="sub2">Never seated.</div></PBody>}
          </Panel>
          <Panel title="Trail" right={`${trail.events.length} event(s)`}>
            {trail.events.length ? <DTable cols={["When|mid", "What", "Batch|mid", "By"]} rows={trail.events.map((e) => [<span key="w" className="tnum sub2">{whenAt(e.at)}</span>, <span key="a">{e.action.replace(/_/g, " ").toLowerCase()}{e.from_value || e.to_value ? <span className="sub2"> · {e.from_value ?? "—"} → {e.to_value ?? "—"}</span> : null}{e.note ? <div className="sub2">{e.note}</div> : null}</span>, <span key="b" className="tnum">{e.batch ?? "—"}</span>, <span key="by" className="sub2">{e.actor ?? e.actor_office ?? "portal"}</span>])} /> : <PBody><div className="sub2">Nothing on the trail yet.</div></PBody>}
          </Panel>
          <div className="sub2">Batches: {batches.filter((b) => b.state !== "CANCELLED").map((b) => BATCH_STATE[b.state]?.[0] ? `${b.label}` : b.label).join(", ") || "none"}</div>
        </Modal>
      ) : null}
    </>
  );
}
