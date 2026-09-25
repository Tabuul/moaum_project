"use client";

/** One batch (V260): where and when it sits, who is in it seat by seat with the photograph on file, attendance
 *  and examination status marked at the desk, the attendance sheet for the hall (print, Excel), candidates moved
 *  to another batch, and the batch postponed or cancelled with its reason — every candidate told. */
import { useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, Passport } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { printNode } from "@/lib/print";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { ATTENDANCE, BATCH_STATE, EXAM_STATUS, callPutme, clock, longDay, whenAt, type Batch, type Candidate } from "@/lib/putme";
import type { BatchFull } from "./page";

const OFFICERS = ["academic", "registrar", "dregistrar", "super"];
const DOOR = ["academic", "registrar", "dregistrar", "records", "ict", "super"];

export function BatchPage({ b, session: s, batches, office }: { b: BatchFull; session: string; batches: Batch[]; office: string | null }) {
  const router = useRouter();
  const may = !!office && OFFICERS.includes(office);
  const door = !!office && DOOR.includes(office);
  const sheet = useRef<HTMLDivElement>(null);
  const [ask, setAsk] = useState<"POSTPONED" | "CANCELLED" | "move" | null>(null);
  const [reason, setReason] = useState("");
  const [target, setTarget] = useState("");
  const [picked, setPicked] = useState<string[]>([]);
  const [mark, setMark] = useState<{ c: Candidate; attendance: string; examStatus: string; remarks: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const rows = b.candidates;
  const live = b.state === "DRAFT" || b.state === "PUBLISHED";
  const reporting = (() => { const [h, m] = clock(b.starts_at).split(":").map(Number); const t = Math.max(0, h * 60 + m - (b.exam?.checkin_minutes ?? 30)); return `${String(Math.floor(t / 60)).padStart(2, "0")}:${String(t % 60).padStart(2, "0")}`; })();
  const q = `?session=${encodeURIComponent(s)}`;

  async function state() {
    if (!reason.trim() || (ask !== "POSTPONED" && ask !== "CANCELLED")) { notifyProblem({ status: 422, title: "Say why." }); return; }
    setBusy(true);
    try {
      const r = await callPutme<{ unseated: number }>(s, "POST", `/batches/${b.id}/state`, { state: ask, reason: reason.trim() }, `${ask === "POSTPONED" ? "Postpone" : "Cancel"} batch ${b.label}: ${reason.trim()}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`Batch ${b.label} ${ask.toLowerCase()} · ${r.data.unseated} candidate(s) returned to scheduling and told`); setAsk(null); setReason(""); router.refresh();
    } finally { setBusy(false); }
  }
  async function move() {
    if (!reason.trim() || !target) { notifyProblem({ status: 422, title: "Choose the batch and say why." }); return; }
    setBusy(true);
    try {
      const r = await callPutme(s, "POST", "/move", { applicationIds: picked, batchId: target, reason: reason.trim() }, `Move ${picked.length} candidate(s) from ${b.label}: ${reason.trim()}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`${picked.length} candidate(s) moved`); setAsk(null); setReason(""); setTarget(""); setPicked([]); router.refresh();
    } finally { setBusy(false); }
  }
  async function saveMark() {
    if (!mark) return;
    setBusy(true);
    try {
      const r = await callPutme(s, "POST", "/attendance", { applicationId: mark.c.application_id, attendance: mark.attendance, examStatus: mark.examStatus, remarks: mark.remarks.trim() || null }, `Mark ${mark.c.application_no} ${mark.attendance.toLowerCase()} / ${mark.examStatus.toLowerCase()}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify("Marked"); setMark(null); router.refresh();
    } finally { setBusy(false); }
  }

  const HEAD = ["S/N", "Seat", "Workstation", "Surname", "Other Names", "Application No", "JAMB No", "Programme", "Attendance", "Checked in", "Examination", "Remarks", "Signature"];
  const body = () => [...rows].sort((x, y) => x.surname.localeCompare(y.surname) || x.other_names.localeCompare(y.other_names)).map((r, i) => [i + 1, r.seat ?? "", r.workstation ?? "", r.surname, r.other_names, r.application_no, r.jamb_reg_no, r.programme, ATTENDANCE[r.attendance]?.[0] ?? r.attendance, r.checked_in_at ? whenAt(r.checked_in_at) : "", EXAM_STATUS[r.exam_status]?.[0] ?? r.exam_status, "", ""]);
  async function excel() { const blob = await brandedXlsx(`Attendance Sheet · Batch ${b.label}`, HEAD, body(), { sheetName: b.label, serial: docSerial("CBT"), sub: `${longDay(b.held_on)} · ${clock(b.starts_at)}–${clock(b.ends_at)} · ${b.centre ?? b.venue}${b.room ? ` · ${b.room}` : ""}` }); downloadBlob(blob, `putme-${b.label}-attendance.xlsx`); }
  const seated = [...rows].sort((x, y) => (x.seat ?? "").localeCompare(y.seat ?? ""));

  return (
    <>
      <style>{`.hall-mast { display: none; } @media print { .nav, .topbar, .no-print { display: none !important; } .main { padding: 0 !important; } .card { break-inside: avoid; } .hall-mast { display: block !important; text-align: center; margin-bottom: 14px; } .hall-mast img { height: 54px; } }`}</style>
      <div className="row row--tight sub2 no-print" style={{ gap: 6 }}><Link className="lnk" href={`/admissions/putme${q}`}>Post-UTME CBT</Link><span>›</span><strong>Batch {b.label}</strong></div>
      <PageHead title={<>Batch {b.label} <Pil kind={BATCH_STATE[b.state]?.[1] ?? "grey"}>{BATCH_STATE[b.state]?.[0] ?? b.state}</Pil></>} description={`${longDay(b.held_on)} · ${clock(b.starts_at)} – ${clock(b.ends_at)} · ${b.centre ?? b.venue}${b.room ? ` · ${b.room}` : ""}. ${rows.length} of ${b.capacity} seats; report by ${reporting}.`}
        actions={<>
          {may && picked.length && live ? <Btn kind="primary" onClick={() => setAsk("move")}>Move {picked.length} to another batch</Btn> : null}
          {may && live ? <><Btn kind="ghost" onClick={() => setAsk("POSTPONED")}>Postpone</Btn><Btn kind="ghost" onClick={() => setAsk("CANCELLED")}>Cancel batch</Btn></> : null}
          <Btn kind="secondary" onClick={() => void excel()} disabled={!rows.length}>Attendance sheet (Excel)</Btn>
          <Btn kind="secondary" onClick={() => printNode(sheet.current, `Attendance sheet · batch ${b.label}`)} disabled={!rows.length}>Print attendance sheet</Btn>
          <LinkBtn kind="ghost" href={`/admissions/putme/checkin${q}`}>Check-in desk</LinkBtn>
        </>} />
      {b.state === "DRAFT" ? <Note kind="info" title="This batch is a draft">Candidates are not told and see no slip until the schedule is published from the desk.</Note> : null}
      {!live ? <Note kind="bad" title={`This batch was ${b.state.toLowerCase()}`}>{b.note ?? ""} Its candidates were returned to scheduling and told; generate again or move them one by one.</Note> : null}

      <div ref={sheet}>
        <div className="hall-mast">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="" />
          <div className="b700 t-md">Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
          <div style={{ textTransform: "uppercase", letterSpacing: ".06em", fontSize: "var(--t-xs)" }}>{b.exam?.name ?? "Post-UTME Examination"} — Attendance Sheet</div>
          <div className="sub2">Batch {b.label} · {longDay(b.held_on)} · Serial {docSerial("CBT")}</div>
        </div>
        <Panel title={`${b.exam?.name ?? "Post-UTME examination"} · batch ${b.label}`} right={`${rows.length} of ${b.capacity} seats · ${s}`}>
          <PBody>
            <KvGrid cls="grid--4" pairs={[["Day", longDay(b.held_on)], ["Time", `${clock(b.starts_at)} – ${clock(b.ends_at)}`], ["Report by", reporting], ["Slot", b.slot ?? "—"], ["Centre", b.centre ?? b.venue], ["Room", b.room ?? "—"], ["Checked in", `${b.checked_in} · ${b.absent} absent`], ["Programmes", b.byProgramme.map((p) => `${p.programme} (${p.n})`).join(", ") || "—"]]} />
          </PBody>
        </Panel>
        <Panel title="Seats, in order" right="Photograph checked at the door and again at the seat">
          {seated.length ? (
            <DTable pageSize={0} cols={[...(may && live ? ["|mid"] : []), "S/N|num", "Seat|mid", "Photograph|mid", "Candidate", "Programme", "Attendance|mid", "Examination|mid", "Signature|mid", ...(door ? ["|num"] : [])]} rows={seated.map((r, i) => [
              ...(may && live ? [<input key="pk" className="no-print" type="checkbox" aria-label={`Choose ${r.surname}`} checked={picked.includes(r.application_id)} onChange={(e) => setPicked(e.target.checked ? [...picked, r.application_id] : picked.filter((x) => x !== r.application_id))} />] : []),
              <span key="sn" className="tnum sub2">{i + 1}</span>,
              <b key="s" className="tnum">{r.seat}{r.workstation ? <div className="sub2">{r.workstation}</div> : null}</b>,
              <Passport key="p" w={42} h={52} src={r.passport_id ? `/api/bff/api/v1/admissions/sessions/${s}/applications/${r.application_id}/documents/${r.passport_id}/content` : null} alt={`${r.surname} ${r.other_names}`} />,
              <span key="n"><strong>{r.surname}</strong>, {r.other_names}<div className="sub2 tnum">{r.application_no} · JAMB {r.jamb_reg_no}</div></span>,
              <span key="g" className="sub2">{r.programme}{r.schedule_review ? <> <Pil kind="warn">Review</Pil></> : null}</span>,
              <span key="a"><Pil kind={ATTENDANCE[r.attendance]?.[1] ?? "grey"}>{ATTENDANCE[r.attendance]?.[0] ?? r.attendance}</Pil>{r.checked_in_at ? <div className="sub2 tnum">{whenAt(r.checked_in_at)}</div> : null}</span>,
              <Pil key="x" kind={EXAM_STATUS[r.exam_status]?.[1] ?? "grey"}>{EXAM_STATUS[r.exam_status]?.[0] ?? r.exam_status}</Pil>,
              <span key="sg" style={{ display: "inline-block", width: 70, height: 18, borderBottom: "1px solid var(--line)" }} aria-label="Signature" />,
              ...(door ? [<Btn key="m" kind="ghost" className="no-print" onClick={() => setMark({ c: r, attendance: r.attendance, examStatus: r.exam_status, remarks: "" })} disabled={!live}>Mark</Btn>] : []),
            ])} texts={seated.map((r) => `${r.seat} ${r.surname} ${r.other_names} ${r.application_no} ${r.jamb_reg_no} ${r.programme}`)} />
          ) : <PBody><div className="sub2">Nobody is seated in this batch.</div></PBody>}
        </Panel>
      </div>

      {ask === "POSTPONED" || ask === "CANCELLED" ? (
        <Modal title={ask === "POSTPONED" ? `Postpone batch ${b.label}` : `Cancel batch ${b.label}`} onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Not now</Btn><Btn kind="urgent" onClick={() => void state()} disabled={busy}>{busy ? "Working…" : ask === "POSTPONED" ? "Postpone and tell them" : "Cancel and tell them"}</Btn></>}>
          <p>Every candidate in the batch loses this seat, returns to “reschedule required”, and is told by email and SMS. Their seating stays on the record as superseded. {ask === "POSTPONED" ? "Generate again once a new day or slot is named, or move them one by one." : ""}</p>
          <Field id="bs-reason" label="Reason" required full><textarea id="bs-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : ask === "move" ? (
        <Modal title={`Move ${picked.length} candidate(s) from ${b.label}`} onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void move()} disabled={busy}>{busy ? "Working…" : "Move"}</Btn></>}>
          <Field id="mv-batch" label="To batch" required full><select id="mv-batch" className="ctl" value={target} onChange={(e) => setTarget(e.target.value)}><option value="">Choose a batch</option>{batches.filter((z) => z.id !== b.id && (z.state === "DRAFT" || z.state === "PUBLISHED")).map((z) => <option key={z.id} value={z.id}>{z.label} · {longDay(z.held_on)} {clock(z.starts_at)} · {z.centre ?? z.venue}{z.room ? ` · ${z.room}` : ""} · {z.assigned}/{z.capacity}</option>)}</select></Field>
          <Field id="mv-reason" label="Reason" required full><textarea id="mv-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : null}
      {mark ? (
        <Modal title={`${mark.c.surname}, ${mark.c.other_names}`} sub={`Seat ${mark.c.seat} · ${mark.c.application_no}`} onClose={() => setMark(null)} foot={<><Btn kind="ghost" onClick={() => setMark(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void saveMark()} disabled={busy}>Save</Btn></>}>
          <div className="grid grid--2">
            <Field id="mk-att" label="Attendance"><select id="mk-att" className="ctl" value={mark.attendance} onChange={(e) => setMark({ ...mark, attendance: e.target.value })}>{Object.entries(ATTENDANCE).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}</select></Field>
            <Field id="mk-ex" label="Examination"><select id="mk-ex" className="ctl" value={mark.examStatus} onChange={(e) => setMark({ ...mark, examStatus: e.target.value })}>{Object.entries(EXAM_STATUS).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}</select></Field>
          </div>
          <Field id="mk-rm" label="Remarks" hint="Required for a disqualification" full><textarea id="mk-rm" className="ctl" rows={2} value={mark.remarks} onChange={(e) => setMark({ ...mark, remarks: e.target.value })} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
