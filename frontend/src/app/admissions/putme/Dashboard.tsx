"use client";

/** The Post-UTME CBT desk (V260): the figures, where the candidates stand, the capacity against the need, the
 *  validation report, the batches, and the three acts — generate, publish, reopen. The Academic Office and the
 *  Registry act; every other reader of admissions reads. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { Donut, HBars, VZ, vzNum } from "@/components/proto/vz";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { BATCH_STATE, EXAM_STATE, STATUS, callPutme, clock, dayOf, type Overview } from "@/lib/putme";

const OFFICERS = ["academic", "registrar", "dregistrar", "super"];
const STATUS_COLS: Record<string, string> = { READY_FOR_SCHEDULING: VZ.s1, SCHEDULED: VZ.good, RESCHEDULED: VZ.s3, RESCHEDULE_REQUIRED: VZ.crit, PAYMENT_PENDING: VZ.warn, DOCUMENT_PENDING: VZ.s4, EXAM_COMPLETED: VZ.s2, ABSENT: VZ.crit, DISQUALIFIED: VZ.crit, NOT_ELIGIBLE: VZ.s5 };

export function Dashboard({ view, sessions, office }: { view: Overview; sessions: string[]; office: string | null }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const [busy, setBusy] = useState<string | null>(null);
  const [ask, setAsk] = useState<"generate" | "publish" | "reopen" | "complete" | null>(null);
  const [note, setNote] = useState("");
  const s = view.session;
  const x = view.exam;
  const may = !!office && OFFICERS.includes(office);
  const q = (path: string) => `${path}?session=${encodeURIComponent(s)}`;
  const pv = view.preview;
  const errors = (view.findings ?? []).filter((f) => f.severity === "ERROR");
  const warnings = (view.findings ?? []).filter((f) => f.severity === "WARNING");
  const batches = view.batches ?? [];
  const live = batches.filter((b) => b.state === "DRAFT" || b.state === "PUBLISHED");
  const count = (st: string) => Number(view.statuses.find((r) => r.status === st)?.n ?? 0);
  const eligible = view.statuses.filter((r) => r.status !== "NOT_ELIGIBLE").reduce((a, r) => a + Number(r.n), 0);

  async function act(kind: "generate" | "publish" | "reopen" | "complete") {
    setBusy(kind);
    try {
      const r = kind === "generate" ? await callPutme<{ batches: number; seated: number; unseated: number }>(s, "POST", "/generate", {}, `Generate the Post-UTME batches for ${s}`)
        : kind === "publish" ? await callPutme<{ told: number }>(s, "POST", "/publish", {}, `Publish the Post-UTME schedule for ${s}`)
        : await callPutme(s, "POST", "/exam/state", { state: kind === "reopen" ? "OPEN_FOR_SCHEDULING" : "COMPLETED", note: note.trim() || null }, `${kind === "reopen" ? "Reopen" : "Complete"} the Post-UTME examination for ${s}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      if (kind === "generate") { const d = r.data as { batches: number; seated: number; unseated: number }; notify(`${d.batches} batch(es) made · ${d.seated} seated · ${d.unseated} without a place`, d.unseated ? "warn" : "ok"); }
      else if (kind === "publish") notify(`Schedule published · ${(r.data as { told: number }).told} candidate(s) told`);
      else notify(kind === "reopen" ? "Examination reopened for scheduling" : "Examination completed");
      setAsk(null); setNote(""); router.refresh();
    } finally { setBusy(null); }
  }

  const HEAD = ["S/N", "Batch", "Date", "Start", "End", "Centre", "Room", "Slot", "Capacity", "Assigned", "Checked in", "Absent", "State"];
  const body = () => batches.map((b, i) => [i + 1, b.label, dayOf(b.held_on), clock(b.starts_at), clock(b.ends_at), b.centre ?? b.venue, b.room ?? "", b.slot ?? "", b.capacity, b.assigned, b.checked_in, b.absent, BATCH_STATE[b.state]?.[0] ?? b.state]);
  async function excel() { const blob = await brandedXlsx("Post-UTME CBT Batches", HEAD, body(), { sheetName: "Batches", serial: docSerial("CBT"), sub: `${x?.name ?? "Post-UTME"} · ${s}` }); downloadBlob(blob, `putme-batches-${s.replace("/", "-")}.xlsx`); }

  return (
    <>
      <PageHead title="Post-UTME CBT Schedule" description={x ? `${x.name} · ${s}. Where every candidate stands, the places the examination can seat, and the schedule generated, validated and published.` : `No examination is set up for ${s} yet. Name it on the setup screen, with its centres, days and slots.`}
        actions={<>
          <Field id="pt-session" label="Session"><select id="pt-session" className="ctl" value={s} onChange={(e) => queryNav(`/admissions/putme?session=${encodeURIComponent(e.target.value)}`)}>{(sessions.includes(s) ? sessions : [s, ...sessions]).map((n) => <option key={n} value={n}>{n}</option>)}</select></Field>
          <LinkBtn kind="secondary" href={q("/admissions/putme/setup")}>Setup</LinkBtn>
          <LinkBtn kind="secondary" href={q("/admissions/putme/candidates")}>Candidates</LinkBtn>
          <LinkBtn kind="primary" href={q("/admissions/putme/checkin")}>Check-in Desk</LinkBtn>
        </>} />

      {x ? (
        <Note kind={x.state === "SCHEDULED" || x.state === "ONGOING" ? "ok" : x.state === "CANCELLED" ? "bad" : "info"} title={<>{x.name} <Pil kind={EXAM_STATE[x.state]?.[1] ?? "grey"}>{EXAM_STATE[x.state]?.[0] ?? x.state}</Pil></>}
          action={may ? <span className="row row--inline row--tight">
            {["CONFIGURING", "OPEN_FOR_SCHEDULING", "SCHEDULING_IN_PROGRESS", "DRAFT"].includes(x.state) ? <Btn kind="primary" onClick={() => setAsk("generate")} disabled={!!busy || !(pv?.capacity)}>{live.length ? "Generate again" : "Generate Batches"}</Btn> : null}
            {live.some((b) => b.state === "DRAFT") ? <Btn kind={errors.length ? "ghost" : "primary"} onClick={() => setAsk("publish")} disabled={!!busy || !!errors.length} title={errors.length ? "Resolve the errors on the validation report first" : undefined}>Publish Schedule</Btn> : null}
            {["SCHEDULED", "ONGOING"].includes(x.state) ? <Btn kind="ghost" onClick={() => setAsk("reopen")} disabled={!!busy}>Reopen for scheduling</Btn> : null}
            {["SCHEDULED", "ONGOING"].includes(x.state) ? <Btn kind="ghost" onClick={() => setAsk("complete")} disabled={!!busy}>Mark completed</Btn> : null}
          </span> : null}>
          <span className="blk">{x.starts_on ? `${dayOf(x.starts_on)}${x.ends_on && x.ends_on !== x.starts_on ? ` – ${dayOf(x.ends_on)}` : ""}` : "Dates not yet named"} · {x.duration_minutes} min sitting · report {x.checkin_minutes} min before · {pv?.days ?? 0} day(s) × {pv?.slots ?? 0} slot(s) × {pv?.rooms ?? 0} room(s) at {pv?.centres ?? 0} centre(s){x.published_at ? ` · published ${dayOf(x.published_at)}` : ""}</span>
          {!view.examProgrammes.length ? <span className="blk">No programme is named as screened by examination this session, so nobody is eligible. Name them under <Link className="lnk" href="/admissions/settings">Admission Settings</Link>.</span> : null}
        </Note>
      ) : (
        <Note kind="info" title="No examination yet" action={may ? <LinkBtn kind="primary" href={q("/admissions/putme/setup")}>Set up the examination</LinkBtn> : null}>
          The examination is named once a session: its dates, check-in and sitting minutes, its centres with their rooms and workstations, its days and its slots. The candidates below stand as they are whether or not it exists.
        </Note>
      )}

      <Tiles items={[
        ["Eligible candidates", vzNum(eligible), null, `${view.examProgrammes.length} programme(s) screened by examination`, q("/admissions/putme/candidates") + "&status=ELIGIBLE"],
        ["Ready to schedule", vzNum(count("READY_FOR_SCHEDULING") + count("RESCHEDULE_REQUIRED")), count("RESCHEDULE_REQUIRED") ? "var(--amber-ink)" : null, count("RESCHEDULE_REQUIRED") ? `${count("RESCHEDULE_REQUIRED")} need rescheduling` : "Submitted and paid, no seat yet", q("/admissions/putme/candidates") + "&status=UNSCHEDULED"],
        ["Scheduled", vzNum(count("SCHEDULED") + count("RESCHEDULED")), "var(--green-ink)", `${live.length} live batch(es)`, q("/admissions/putme/candidates") + "&status=SCHEDULED"],
        ["Awaiting fee or form", vzNum(count("PAYMENT_PENDING") + count("DOCUMENT_PENDING")), count("PAYMENT_PENDING") + count("DOCUMENT_PENDING") ? "var(--amber-ink)" : null, `${count("PAYMENT_PENDING")} unpaid · ${count("DOCUMENT_PENDING")} unsubmitted`],
        ["Seats", vzNum(pv?.capacity ?? 0), pv && pv.capacity < pv.ready + pv.scheduled ? "var(--red-ink)" : null, pv ? `${vzNum(pv.used)} used · ${vzNum(pv.places)} place(s) · ${vzNum(pv.required_batches)} batch(es) needed for the ready` : "Set up the examination"],
        ["Sat the examination", vzNum(count("EXAM_COMPLETED")), null, `${count("ABSENT")} absent · ${count("DISQUALIFIED")} disqualified`],
      ]} cls="grid--3" />

      {x && view.findings?.length ? (
        <Panel title="Validation report" right={`${errors.length} error(s) · ${warnings.length} warning(s)`}>
          <PBody>
            {errors.map((f) => <Note key={f.code} kind="bad" title={`${f.message}`}>{f.n} affected · {f.code}. The schedule cannot be published until this is resolved.</Note>)}
            {warnings.map((f) => <Note key={f.code} kind="info" title={f.message}>{f.n} affected · {f.code}. Publishing proceeds; the desk should look.</Note>)}
          </PBody>
        </Panel>
      ) : x && live.length ? <Note kind="ok" title="The schedule validates">No capacity, duplicate, clash or eligibility finding stands against the batches.</Note> : null}

      <div className="grid grid--2">
        <Panel title="Where the candidates stand" right={`${s}`}>
          <PBody>
            {view.statuses.length ? <Donut capLabel="candidates" capValue={vzNum(view.statuses.reduce((a, r) => a + Number(r.n), 0))} items={view.statuses.map((r) => ({ l: STATUS[r.status]?.[0] ?? r.status, v: Number(r.n), c: STATUS_COLS[r.status] ?? VZ.s5 }))} /> : <div className="sub2">No applicant has registered for {s} yet.</div>}
          </PBody>
        </Panel>
        <Panel title="Eligible candidates by faculty" right="Scheduled of eligible">
          <PBody>
            {view.byFaculty?.length ? <HBars items={view.byFaculty.map((f) => ({ l: `${f.faculty ?? "No faculty"} · ${f.scheduled}/${f.candidates}`, v: Number(f.candidates) }))} /> : <div className="sub2">Nobody is eligible yet.</div>}
          </PBody>
        </Panel>
      </div>

      {x ? (
        <div className="grid grid--2">
          <Panel title="By examination day" right="Candidates seated against capacity">
            {view.byDate?.length ? <DTable cols={["Day", "Seated|num", "Capacity|num"]} rows={view.byDate.map((d) => [dayOf(d.held_on), <span className="tnum" key="c">{d.candidates}</span>, <span className="tnum" key="k">{d.capacity}</span>])} /> : <PBody><div className="sub2">No batch yet.</div></PBody>}
          </Panel>
          <Panel title="By centre" right="Rooms, batches, seats">
            {view.byCentre?.length ? <DTable cols={["Centre", "Rooms|num", "Batches|num", "Capacity|num", "Assigned|num"]} rows={view.byCentre.map((c) => [c.centre, <span className="tnum" key="r">{c.rooms}</span>, <span className="tnum" key="b">{c.batches}</span>, <span className="tnum" key="k">{c.capacity}</span>, <span className="tnum" key="a">{c.assigned}</span>])} /> : <PBody><div className="sub2">No centre is named for this examination. <Link className="lnk" href={q("/admissions/putme/setup")}>Name them on the setup screen.</Link></div></PBody>}
          </Panel>
        </div>
      ) : null}

      {view.byProgramme?.length ? (
        <Panel title="Eligible candidates by programme" right="Scheduled of eligible">
          <DTable cols={["Programme", "Faculty", "Eligible|num", "Scheduled|num", "|num"]} rows={view.byProgramme.map((p) => [p.programme, p.faculty ?? "—", <span className="tnum" key="c">{p.candidates}</span>, <span className="tnum" key="s">{p.scheduled}</span>, <LinkBtn key="o" href={`${q("/admissions/putme/candidates")}&prog=${encodeURIComponent(p.programme_code)}`} size="sm">Open</LinkBtn>])} texts={view.byProgramme.map((p) => `${p.programme} ${p.faculty ?? ""}`)} />
        </Panel>
      ) : null}

      <Panel title="Batches" right={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => void excel()} disabled={!batches.length}>Excel</Btn><Btn kind="ghost" onClick={() => brandedPrint("Post-UTME CBT Batches", `${x?.name ?? "Post-UTME"} · ${s}`, HEAD, body(), docSerial("CBT"))} disabled={!batches.length}>PDF</Btn></span>}>
        {batches.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Batch", "Day", "Time|mid", "Centre · room", "Capacity|num", "Assigned|num", "Checked in|num", "State|mid", "|num"]} rows={batches.map((b, i) => [
            <span key="sn" className="tnum sub2">{i + 1}</span>,
            <Link key="l" className="lnk b600" href={`/admissions/putme/batches/${b.id}?session=${encodeURIComponent(s)}`}>{b.label}</Link>,
            <span key="d" className="tnum">{dayOf(b.held_on)}</span>,
            <span key="t" className="tnum sub2">{clock(b.starts_at)} – {clock(b.ends_at)}</span>,
            <span key="c">{b.centre ?? b.venue}{b.room ? <span className="sub2"> · {b.room}</span> : null}</span>,
            <span key="k" className="tnum">{b.capacity}</span>,
            <span key="a" className="tnum">{b.assigned}</span>,
            <span key="ci" className="tnum">{b.checked_in}</span>,
            <Pil key="st" kind={BATCH_STATE[b.state]?.[1] ?? "grey"}>{BATCH_STATE[b.state]?.[0] ?? b.state}</Pil>,
            <LinkBtn key="o" href={`/admissions/putme/batches/${b.id}?session=${encodeURIComponent(s)}`} size="sm">Open</LinkBtn>,
          ])} texts={batches.map((b) => `${b.label} ${b.centre ?? b.venue} ${b.room ?? ""} ${b.state}`)} />
        ) : <PBody><div className="sub2">No batch exists for {s}. {may && x ? "Generate them once the examination has its days, slots and centres." : ""}</div></PBody>}
      </Panel>

      {ask ? (
        <Modal title={ask === "generate" ? "Generate the batches" : ask === "publish" ? "Publish the schedule" : ask === "reopen" ? "Reopen for scheduling" : "Mark the examination completed"} onClose={() => setAsk(null)}
          foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Not now</Btn><Btn kind="primary" onClick={() => void act(ask)} disabled={!!busy}>{busy ? "Working…" : ask === "generate" ? "Generate" : ask === "publish" ? "Publish and notify" : ask === "reopen" ? "Reopen" : "Complete"}</Btn></>}>
          {ask === "generate" ? <p>Every candidate who is ready is seated in order of the {String(x?.strategy ?? "PROGRAMME").toLowerCase().replace("_", " ")} strategy, into the places still free. Candidates already seated keep their seats. {pv ? `${vzNum(pv.ready)} ready · ${vzNum(pv.capacity - pv.used)} seat(s) free.` : ""}</p>
            : ask === "publish" ? <p>Every draft batch becomes published and every candidate in it is told their day, time, centre, room and seat by email and SMS, and their slip appears on the portal. {warnings.length ? `${warnings.length} warning(s) stand; publishing proceeds.` : ""}</p>
            : <Field id="pt-note" label="Note for the record" full><textarea id="pt-note" className="ctl" rows={3} value={note} onChange={(e) => setNote(e.target.value)} /></Field>}
        </Modal>
      ) : null}
    </>
  );
}
