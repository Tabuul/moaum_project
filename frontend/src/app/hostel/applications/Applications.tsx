"use client";

/** The applications desk (V261): every application with the student, eligibility and its reason, the preferences and roommate
 *  asked for, the review, the seat; filtered and searched on the server, exported with S/N first and names A–Z; reviewed one
 *  at a time or in bulk; seated by hand into a named free bed; the waiting list in order. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { ALLOC_STATE, APP_STATE, CATEGORIES, REVIEW, callHostel, dayOf, whenAt, type ApplicationRow, type FreeBed } from "@/lib/hostel";
import type { AppFilters, AppList } from "./page";

const OFFICERS = ["services", "housing", "registrar", "admin", "super"];

export function Applications({ list, filters, session: s, office }: { list: AppList; filters: AppFilters; session: string; office: string | null }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const may = !!office && OFFICERS.includes(office);
  const [q, setQ] = useState(filters.q);
  const [picked, setPicked] = useState<string[]>([]);
  const [ask, setAsk] = useState<{ kind: "review"; ids: string[]; decision: string } | { kind: "seat"; row: ApplicationRow } | { kind: "withdraw"; row: ApplicationRow } | null>(null);
  const [note, setNote] = useState("");
  const [beds, setBeds] = useState<FreeBed[]>([]);
  const [bed, setBed] = useState("");
  const [busy, setBusy] = useState(false);
  const rows = list.rows;
  const [s1, s2] = s.split("/");
  const go = (next: Partial<AppFilters>) => { const f = { ...filters, ...next, page: next.page ?? "" }; if (next.fac !== undefined) { f.dept = ""; f.prog = ""; } if (next.dept !== undefined) f.prog = ""; const qs = new URLSearchParams(); qs.set("session", s); for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v); queryNav(`/hostel/applications?${qs}`); };
  const faculties = [...new Map(list.options.map((o) => [o.faculty_code, o.faculty])).entries()].filter(([k]) => k);
  const depts = [...new Map(list.options.filter((o) => !filters.fac || o.faculty_code === filters.fac).map((o) => [o.dept_code, o.department])).entries()].filter(([k]) => k);
  const progs = [...new Map(list.options.filter((o) => (!filters.fac || o.faculty_code === filters.fac) && (!filters.dept || o.dept_code === filters.dept)).map((o) => [o.programme_code, o.programme])).entries()];
  const pages = Math.max(1, Math.ceil(list.total / list.size));
  const scope = [filters.state ? filters.state.toLowerCase().replace("_", " ") : "every application", filters.fac, filters.dept, filters.prog, filters.level ? `${filters.level} Level` : "", filters.hall, filters.q ? `search “${filters.q}”` : ""].filter(Boolean).join(" · ");
  const standing = (r: ApplicationRow) => r.state === "APPLIED" && !r.review ? ["Under review", "warn"] as const : r.state === "APPLIED" && r.review === "CORRECTION" ? ["Correction asked", "warn"] as const : r.state === "APPLIED" ? ["Approved — awaiting allocation", "info"] as const : [APP_STATE[r.state]?.[0] ?? r.state, APP_STATE[r.state]?.[1] ?? "grey"] as const;

  const HEAD = ["S/N", "Application No", "Student ID", "Student Name", "Faculty", "Department", "Programme", "Level", "Gender", "Preferred Hostel", "Category", "Payment", "Eligibility", "Status", "Review", "Allocation", "Applied"];
  const body = () => rows.map((r, i) => [i + 1, r.reference, r.student_number, r.student_name, r.faculty ?? "", r.department ?? "", r.programme ?? "", r.level, r.sex ?? "", r.hall_pref_name ?? "Any", r.category, r.fee_paid ? "PAID" : r.allocation_state === "HELD" ? "PENDING" : "UNPAID", r.eligible ? "Eligible" : r.eligibility_why, standing(r)[0], r.review ?? "", r.allocation_ref ? `${r.allocation_ref} · ${r.hall_name} ${r.block}-${r.room_no} ${r.bed_label ?? ""}` : "", dayOf(r.applied_at)]);
  async function excel() { const blob = await brandedXlsx("Hostel Applications", HEAD, body(), { sheetName: "Applications", serial: docSerial("HST"), sub: `${s} · ${scope}` }); downloadBlob(blob, `hostel-applications-${s.replace("/", "-")}.xlsx`); }

  async function review() {
    if (!ask || ask.kind !== "review") return;
    if (["REJECTED", "CORRECTION"].includes(ask.decision) && !note.trim()) { notifyProblem({ status: 422, title: "Say why." }); return; }
    setBusy(true);
    try {
      const r = ask.ids.length === 1 ? await callHostel("POST", `/hostel/sessions/${s1}/${s2}/applications/${ask.ids[0]}/review`, { decision: ask.decision, note: note.trim() || null }, `${ask.decision} hostel application`)
        : await callHostel("POST", `/hostel/sessions/${s1}/${s2}/applications/review-bulk`, { ids: ask.ids, decision: ask.decision, note: note.trim() || null }, `${ask.decision} ${ask.ids.length} hostel applications`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`${ask.ids.length} application(s) ${ask.decision.toLowerCase()}`); setAsk(null); setNote(""); setPicked([]); router.refresh();
    } finally { setBusy(false); }
  }
  async function openSeat(row: ApplicationRow) {
    setAsk({ kind: "seat", row }); setBed(""); setNote("");
    const r = await callHostel<FreeBed[]>("GET", `/hostel/sessions/${s1}/${s2}/free-beds${row.sex ? `?sex=${row.sex}` : ""}`, undefined, "Free beds for a manual allocation");
    setBeds(r.ok ? r.data : []);
  }
  async function seat() {
    if (!ask || ask.kind !== "seat") return;
    if (!bed || !note.trim()) { notifyProblem({ status: 422, title: "Choose the bed and say why." }); return; }
    setBusy(true);
    try {
      const r = await callHostel<{ reference: string }>("POST", `/hostel/sessions/${s1}/${s2}/applications/${ask.row.application_id}/allocate`, { bedId: bed, reason: note.trim() }, `Allocate ${ask.row.student_number} by hand: ${note.trim()}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`Allocated · ${r.data.reference}`); setAsk(null); setNote(""); router.refresh();
    } finally { setBusy(false); }
  }
  async function withdraw() {
    if (!ask || ask.kind !== "withdraw") return;
    setBusy(true);
    try {
      const r = await callHostel("POST", `/hostel/sessions/${s1}/${s2}/applications/${ask.row.application_id}/withdraw`, { decision: "WITHDRAW", note: note.trim() || null }, `Withdraw hostel application ${ask.row.reference}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify("Application withdrawn"); setAsk(null); setNote(""); router.refresh();
    } finally { setBusy(false); }
  }
  const all = rows.length > 0 && rows.every((r) => picked.includes(r.application_id));
  const waitlist = filters.state === "WAITLISTED";

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href={`/hostel?session=${encodeURIComponent(s)}`}>Accommodation</Link><span>›</span><strong>Applications</strong></div>
      <PageHead title={waitlist ? "Waiting list" : "Hostel applications"} description={`${s} · ${scope}. ${list.total.toLocaleString()} application(s); names A–Z${waitlist ? "; the list order is the draw position" : ""}.`}
        actions={<>
          {may && picked.length ? <><Btn kind="primary" onClick={() => { setAsk({ kind: "review", ids: picked, decision: "APPROVED" }); setNote(""); }}>Approve {picked.length}</Btn><Btn kind="ghost" onClick={() => { setAsk({ kind: "review", ids: picked, decision: "WAITLISTED" }); setNote(""); }}>Waitlist {picked.length}</Btn><Btn kind="ghost" onClick={() => { setAsk({ kind: "review", ids: picked, decision: "REJECTED" }); setNote(""); }}>Reject {picked.length}</Btn></> : null}
          <Btn kind="secondary" onClick={() => void excel()} disabled={!rows.length}>Download Excel</Btn>
          <Btn kind="ghost" onClick={() => brandedPrint("Hostel Applications", `${s} · ${scope}`, HEAD, body(), docSerial("HST"))} disabled={!rows.length}>Download PDF</Btn>
          <LinkBtn kind="ghost" href={`/hostel?session=${encodeURIComponent(s)}`}>Back to the desk</LinkBtn>
        </>} />
      {list.setting?.requires_review ? <Note kind="info" title="This session reviews each application">Only approved applications are seated by the allocation run; approve, waitlist, reject or ask for a correction below.</Note> : null}

      <div className="scope">
        <div className="scope__f"><Field id="af-state" label="Standing"><select id="af-state" className="ctl" value={filters.state} onChange={(e) => go({ state: e.target.value })}>
          <option value="">Everyone</option><option value="PENDING_REVIEW">Pending review</option><option value="APPROVED">Approved, unallocated</option><option value="UNALLOCATED">Unallocated</option><option value="ALLOCATED">Allocated</option><option value="PAYMENT_PENDING">Payment pending</option><option value="CONFIRMED">Confirmed</option><option value="WAITLISTED">Waiting list</option><option value="LAPSED">Lapsed</option><option value="REJECTED">Rejected</option><option value="WITHDRAWN">Withdrawn</option></select></Field></div>
        <div className="scope__f"><Field id="af-fac" label="Faculty"><select id="af-fac" className="ctl" value={filters.fac} onChange={(e) => go({ fac: e.target.value })}><option value="">Every faculty</option>{faculties.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="af-dept" label="Department"><select id="af-dept" className="ctl" value={filters.dept} onChange={(e) => go({ dept: e.target.value })}><option value="">Every department</option>{depts.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="af-prog" label="Programme"><select id="af-prog" className="ctl" value={filters.prog} onChange={(e) => go({ prog: e.target.value })}><option value="">Every programme</option>{progs.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="af-level" label="Level"><select id="af-level" className="ctl" value={filters.level} onChange={(e) => go({ level: e.target.value })}><option value="">Any</option>{["100", "200", "300", "400", "500", "600", "700", "800", "900"].map((l) => <option key={l} value={l}>{l}</option>)}</select></Field></div>
        <form className="scope__search" onSubmit={(e) => { e.preventDefault(); go({ q: q.trim() }); }}>
          <Field id="af-q" label="Search"><input id="af-q" className="ctl" placeholder="Name, student ID, application number, programme" value={q} onChange={(e) => setQ(e.target.value)} /></Field>
          <Btn kind="secondary" type="submit">Search</Btn>
        </form>
      </div>

      <Panel title={`${list.total.toLocaleString()} application(s)`} right={pages > 1 ? <span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => go({ page: String(list.page - 1) })} disabled={list.page <= 0}>Previous</Btn><span className="sub2">Page {list.page + 1} of {pages}</span><Btn kind="ghost" onClick={() => go({ page: String(list.page + 1) })} disabled={list.page + 1 >= pages}>Next</Btn></span> : "Names A–Z"}>
        {rows.length ? (
          <DTable pageSize={0} cols={[...(may ? ["|mid"] : []), "S/N|num", waitlist ? "Position|num" : "Application|mid", "Student", "Programme", "Preference", "Eligibility", "Standing", "Allocation", "|num"]} rows={rows.map((r, i) => [
            ...(may ? [<input key="pk" type="checkbox" aria-label={`Choose ${r.student_name}`} checked={picked.includes(r.application_id)} onChange={(e) => setPicked(e.target.checked ? [...picked, r.application_id] : picked.filter((x) => x !== r.application_id))} />] : []),
            <span key="sn" className="tnum sub2">{list.page * list.size + i + 1}</span>,
            waitlist ? <strong key="p" className="tnum">{r.draw_position ?? "—"}</strong> : <span key="ref" className="tnum sub2">{r.reference}<div className="sub2">{dayOf(r.applied_at)}</div></span>,
            <span key="c"><strong>{r.student_name}</strong><div className="sub2 tnum">{r.student_number} · {r.level} Level · {r.sex === "F" ? "Female" : r.sex === "M" ? "Male" : "—"}</div></span>,
            <span key="pr">{r.programme ?? "—"}<div className="sub2">{r.department ?? "—"} · {r.faculty ?? "—"}</div></span>,
            <span key="pf">{r.hall_pref_name ?? "Any hall"}{r.room_type_pref ? ` · ${r.room_type_pref}` : ""}{r.block_pref ? ` · block ${r.block_pref}` : ""}
              {r.category !== "NONE" ? <div className="sub2"><Pil kind="info">{CATEGORIES.find((c) => c[0] === r.category)?.[1] ?? r.category}</Pil> {r.category_note}</div> : null}
              {r.special_need ? <div className="sub2">Special need: {r.special_need}</div> : null}{r.roommate_name ? <div className="sub2">Roommate: {r.roommate_name}</div> : null}</span>,
            <span key="e"><Pil kind={r.eligible ? "ok" : "bad"}>{r.eligible ? "Eligible" : "Not eligible"}</Pil>{!r.eligible ? <div className="sub2">{r.eligibility_why}</div> : null}</span>,
            <span key="st"><Pil kind={standing(r)[1]}>{standing(r)[0]}</Pil>{r.review && r.review !== "APPROVED" ? <div className="sub2"><Pil kind={REVIEW[r.review]?.[1] ?? "grey"}>{REVIEW[r.review]?.[0] ?? r.review}</Pil> {r.review_note}</div> : null}</span>,
            r.allocation_id ? <span key="al"><Link className="lnk b600" href={`/hostel/allocations/${r.allocation_id}?session=${encodeURIComponent(s)}`}>{r.allocation_ref}</Link><div className="sub2">{r.hall_name} {r.block}-{r.room_no} · {r.bed_label}</div><Pil kind={ALLOC_STATE[r.allocation_state ?? ""]?.[1] ?? "grey"}>{ALLOC_STATE[r.allocation_state ?? ""]?.[0] ?? r.allocation_state}</Pil>{r.allocation_state === "HELD" && r.held_until ? <div className="sub2 tnum">hold to {whenAt(r.held_until)}</div> : null}</span> : <span key="al" className="sub2">—</span>,
            <span key="o" className="row row--inline row--tight">
              {may && r.state === "APPLIED" && r.review !== "APPROVED" ? <Btn kind="secondary" onClick={() => { setAsk({ kind: "review", ids: [r.application_id], decision: "APPROVED" }); setNote(""); }}>Approve</Btn> : null}
              {may && ["APPLIED", "UNSUCCESSFUL", "LAPSED"].includes(r.state) && r.eligible ? <Btn kind="primary" onClick={() => void openSeat(r)}>Allocate</Btn> : null}
              {may && r.state === "APPLIED" ? <Btn kind="ghost" onClick={() => { setAsk({ kind: "review", ids: [r.application_id], decision: "REJECTED" }); setNote(""); }}>Reject</Btn> : null}
              {may && r.state === "APPLIED" ? <Btn kind="ghost" onClick={() => { setAsk({ kind: "review", ids: [r.application_id], decision: "CORRECTION" }); setNote(""); }}>Correction</Btn> : null}
              {may && ["APPLIED", "UNSUCCESSFUL"].includes(r.state) ? <Btn kind="ghost" onClick={() => { setAsk({ kind: "withdraw", row: r }); setNote(""); }}>Withdraw</Btn> : null}
              <LinkBtn href={`/hostel/students/${r.student_id}?session=${encodeURIComponent(s)}`} size="sm">History</LinkBtn>
            </span>,
          ])} texts={rows.map((r) => `${r.student_name} ${r.student_number} ${r.reference} ${r.programme ?? ""} ${r.state}`)} />
        ) : <PBody><div className="sub2">No application matches. Widen the filters.</div></PBody>}
        {may && rows.length ? <PBody><label className="row row--tight sub2" style={{ gap: 8 }}><input type="checkbox" checked={all} onChange={(e) => setPicked(e.target.checked ? [...new Set([...picked, ...rows.map((r) => r.application_id)])] : picked.filter((x) => !rows.some((r) => r.application_id === x)))} /> Choose everyone on this page</label></PBody> : null}
      </Panel>

      {ask?.kind === "review" ? (
        <Modal title={`${ask.decision === "APPROVED" ? "Approve" : ask.decision === "REJECTED" ? "Reject" : ask.decision === "WAITLISTED" ? "Waitlist" : "Ask for a correction on"} ${ask.ids.length} application(s)`} onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind={ask.decision === "REJECTED" ? "urgent" : "primary"} onClick={() => void review()} disabled={busy}>{busy ? "Working…" : "Confirm"}</Btn></>}>
          <p>{ask.decision === "APPROVED" ? "Approved applications are seated by the allocation run, or by hand." : ask.decision === "WAITLISTED" ? "The student goes to the end of the waiting list and is offered a bed in order when one is free." : ask.decision === "REJECTED" ? "The student is told, with the reason." : "The student is told what to correct; they withdraw and apply again."} Each student is notified.</p>
          <Field id="rv-note" label={["REJECTED", "CORRECTION"].includes(ask.decision) ? "Reason" : "Note"} required={["REJECTED", "CORRECTION"].includes(ask.decision)} full><textarea id="rv-note" className="ctl" rows={3} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        </Modal>
      ) : ask?.kind === "seat" ? (
        <Modal title={`Allocate ${ask.row.student_name}`} sub={`${ask.row.student_number} · ${ask.row.sex === "F" ? "Female" : ask.row.sex === "M" ? "Male" : "Gender not on record"} · prefers ${ask.row.hall_pref_name ?? "any hall"}`} onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void seat()} disabled={busy || !bed || !note.trim()}>{busy ? "Working…" : "Allocate the bed"}</Btn></>}>
          <p>Every check the allocation run makes is made here: gender, capacity, the bed and room in service, eligibility, no second bed in the session. The student is told and a hold starts for payment.</p>
          <Field id="st-bed" label="Free bed" required full><select id="st-bed" className="ctl" value={bed} onChange={(e) => setBed(e.target.value)}><option value="">{beds.length ? "Choose a bed" : "Reading free beds…"}</option>{beds.map((b) => <option key={b.bed_id} value={b.bed_id}>{b.hall_name} · {b.block}-{b.room_no} · bed {b.bed}{b.room_type_label ? ` · ${b.room_type_label}` : ""}{b.hall_code === ask.row.hall_pref ? " · preferred hall" : ""}</option>)}</select></Field>
          <Field id="st-note" label="Reason" required full><textarea id="st-note" className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        </Modal>
      ) : ask?.kind === "withdraw" ? (
        <Modal title={`Withdraw ${ask.row.reference}`} onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="urgent" onClick={() => void withdraw()} disabled={busy}>Withdraw</Btn></>}>
          <p>The application leaves the list; a held bed is released. The student may apply again while the window is open.</p>
          <Field id="wd-note" label="Reason" full><textarea id="wd-note" className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
