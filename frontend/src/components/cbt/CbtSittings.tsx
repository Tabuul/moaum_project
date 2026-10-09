"use client";
/** V373: an examination sat in sittings — each with its venue, time and seats. The office adds the sittings, seats every candidate at
 *  once (by programme, name or matric number) or moves one, and prints each sitting's attendance list for the invigilator: seat by seat,
 *  the candidate's name, matric number, level and programme, extra time, and a column to sign. With sittings, a candidate starts only in
 *  their own sitting — the server judges that; this page only arranges it. V374: the office names each sitting's invigilators (one may be
 *  the chief), who are told and see the sitting's seats on their own screen; and it may set how late a candidate may still start on their
 *  own — after that, the invigilator admits them. */
import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { ATTEMPT_WORD, num, whenAt, type CbtExam } from "@/lib/cbt";
import { localInput } from "./CbtExams";
import { cbtSend } from "./CbtExam";

interface Invigilator { person_id: string; name: string; staff_number: string | null; chief: boolean }
interface Sitting { id: string; label: string; venue: string; starts_at: string; ends_at: string; capacity: number; seated: number; begun: number; marked?: number; invigilators?: Invigilator[] }
interface Sittings { sittings: Sitting[]; candidates: number; unseated: number; late_entry_minutes?: number | null; result?: { seated: number; unseated: number } }
interface Staff { id: string; staff_number: string | null; surname: string; given_names: string; offices: string }
interface Seat { seat_no: number; candidate_id: string; number: string; surname: string; other_names: string; level: number; programme: string; extra_minutes: number | null; attempt_status: string | null }
interface Form { id?: string; label: string; venue: string; startsAt: string; endsAt: string; capacity: string }

const hhmm = (iso: string) => new Date(iso).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });

export function CbtSittings({ exam, canManage }: { exam: CbtExam; canManage: boolean }) {
  const router = useRouter();
  const [data, setData] = useState<Sittings | null>(null);
  const [busy, setBusy] = useState(false);
  const [form, setForm] = useState<Form | null>(null);
  const [order, setOrder] = useState("PROGRAMME");
  const [list, setList] = useState<{ sitting: Sitting; rows: Seat[] } | null>(null);
  const [late, setLate] = useState<string | null>(null);
  const [naming, setNaming] = useState<Sitting | null>(null);
  const [q, setQ] = useState("");
  const [found, setFound] = useState<Staff[] | null>(null);
  const editable = canManage && exam.state !== "COMPLETED" && exam.state !== "CANCELLED";

  const load = useCallback(async () => {
    const r = await fetch(`/api/bff/api/v1/cbt/exams/${exam.id}/sittings`);
    if (r.ok) setData((await r.json()) as Sittings);
  }, [exam.id]);
  useEffect(() => { const t = window.setTimeout(() => void load(), 0); return () => window.clearTimeout(t); }, [load]);

  async function save() {
    if (!form) return;
    setBusy(true);
    try {
      const body = { label: form.label.trim(), venue: form.venue.trim(), startsAt: new Date(form.startsAt).toISOString(), endsAt: new Date(form.endsAt).toISOString(), capacity: Number(form.capacity) };
      const j = form.id ? await cbtSend(`/exams/${exam.id}/sittings/${form.id}`, "PUT", body, `Sitting ${body.label} changed`)
        : await cbtSend(`/exams/${exam.id}/sittings`, "POST", body, `Sitting ${body.label} added`);
      if (j) { setData(j as unknown as Sittings); setForm(null); }
    } finally { setBusy(false); }
  }
  async function remove(s: Sitting) {
    if (!window.confirm(`Remove ${s.label}? Its ${s.seated} seated candidate${s.seated === 1 ? "" : "s"} lose their seats and must be seated again.`)) return;
    setBusy(true);
    try { const j = await cbtSend(`/exams/${exam.id}/sittings/${s.id}/remove`, "POST", {}, `Sitting ${s.label} removed`); if (j) setData(j as unknown as Sittings); } finally { setBusy(false); }
  }
  async function seatAll() {
    setBusy(true);
    try {
      const j = await cbtSend(`/exams/${exam.id}/sittings/seat-all`, "POST", { order }, "Candidates seated in the sittings") as unknown as Sittings | null;
      if (j) setData(j);
    } finally { setBusy(false); }
  }
  async function saveLate() {
    if (late == null) return;
    const minutes = late.trim() === "" ? null : Number(late);
    setBusy(true);
    try {
      const j = await cbtSend(`/exams/${exam.id}/late-entry`, "PUT", { minutes }, minutes == null ? "No late-entry limit" : `Late entry closes ${minutes} minutes after a sitting begins`);
      if (j) { setLate(null); await load(); }
    } finally { setBusy(false); }
  }
  async function search() {
    const t = q.trim();
    if (t.length < 2) { setFound([]); return; }
    const r = await fetch(`/api/bff/api/v1/cbt/staff?q=${encodeURIComponent(t)}`);
    setFound(r.ok ? ((await r.json()) as Staff[]) : []);
  }
  async function name(person: Staff, chief: boolean) {
    if (!naming) return;
    setBusy(true);
    try {
      const j = await cbtSend(`/exams/${exam.id}/sittings/${naming.id}/invigilators`, "POST", { personId: person.id, chief },
        `${person.given_names} ${person.surname} named ${chief ? "chief invigilator" : "an invigilator"} for ${naming.label}`);
      if (j) await refreshNaming(naming.id);
    } finally { setBusy(false); }
  }
  async function unname(person: Invigilator) {
    if (!naming) return;
    setBusy(true);
    try {
      const j = await cbtSend(`/exams/${exam.id}/sittings/${naming.id}/invigilators/${person.person_id}/remove`, "POST", {}, `${person.name} no longer invigilates ${naming.label}`);
      if (j) await refreshNaming(naming.id);
    } finally { setBusy(false); }
  }
  async function refreshNaming(id: string) {
    const r = await fetch(`/api/bff/api/v1/cbt/exams/${exam.id}/sittings`);
    if (!r.ok) return;
    const j = (await r.json()) as Sittings;
    setData(j);
    setNaming(j.sittings.find((x) => x.id === id) ?? null);
  }
  async function openList(s: Sitting) {
    const r = await fetch(`/api/bff/api/v1/cbt/exams/${exam.id}/sittings/${s.id}/attendance`);
    if (r.ok) { const j = await r.json(); setList({ sitting: s, rows: j.rows as Seat[] }); }
  }
  async function move(row: Seat, sittingId: string) {
    const target = data?.sittings.find((x) => x.id === sittingId);
    if (!target || !list) return;
    setBusy(true);
    try {
      const j = await cbtSend(`/exams/${exam.id}/seats/${row.candidate_id}`, "PUT", { sittingId }, `${row.surname}, ${row.other_names} moved to ${target.label}`);
      if (j) { await openList(list.sitting); await load(); router.refresh(); }
    } finally { setBusy(false); }
  }

  const HEAD = ["Seat", "Matric No.", "Name", "Level", "Programme", "Extra time", "Signature"];
  const body = (rows: Seat[]) => rows.map((x) => [x.seat_no, x.number, `${x.surname.toUpperCase()}, ${x.other_names}`, x.level, x.programme, x.extra_minutes ? `+${x.extra_minutes} min` : "", ""]);
  const subOf = (s: Sitting) => `${exam.course_code} · ${exam.title} · ${s.label} · ${s.venue} · ${whenAt(s.starts_at)} to ${hhmm(s.ends_at)}`;

  if (!data) return <div className="sub2">Reading the sittings…</div>;
  return (
    <>
      <Panel title="Sittings" right={<span className="sub2">{num(data.candidates)} candidates · {num(data.candidates - data.unseated)} seated · {num(data.unseated)} without a seat</span>}>
        <PBody>
          <div className="sub2 mb-2">
            A large paper is sat in turns: each sitting has its venue, its time and its seats. When an examination has sittings, a candidate starts only in their own sitting,
            and their attempt ends with the sitting at the latest (extra time given by the office comes on top). Without sittings, the examination opens to every candidate in its window.
          </div>
          {data.unseated > 0 && data.sittings.length ? <Note kind="info" title={`${num(data.unseated)} candidate${data.unseated === 1 ? " has" : "s have"} no seat yet`}>Seat them below; if the sittings are full, add seats or another sitting. A candidate without a seat cannot start once the examination has sittings.</Note> : null}
          {editable ? (
            <div className="row row--inline row--tight" style={{ flexWrap: "wrap", alignItems: "flex-end" }}>
              <Btn kind="secondary" disabled={busy} onClick={() => setForm({ label: `Sitting ${data.sittings.length + 1}`, venue: data.sittings.at(-1)?.venue ?? "", startsAt: localInput(exam.starts_at), endsAt: "", capacity: String(data.sittings.at(-1)?.capacity ?? 100) })}>Add a sitting</Btn>
              {data.sittings.length ? <>
                <Field id="seat-order" label="Seat candidates by"><select id="seat-order" className="ctl" value={order} onChange={(e) => setOrder(e.target.value)}><option value="PROGRAMME">Programme, then matric number</option><option value="NAME">Name</option><option value="NUMBER">Matric number</option></select></Field>
                <Btn kind="primary" disabled={busy || !data.unseated} onClick={() => void seatAll()}>{data.unseated ? `Seat the ${num(data.unseated)} without a seat` : "Everyone has a seat"}</Btn>
              </> : null}
            </div>
          ) : null}
          {data.result ? <div className="sub2 mt-1">{num(data.result.seated)} seated just now{data.result.unseated ? ` · ${num(data.result.unseated)} found no free seat` : ""}.</div> : null}
          {data.sittings.length ? (
            <div className="mt-2">
              {late == null ? (
                <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
                  <span><b>Late entry:</b> {data.late_entry_minutes == null ? "no limit — a candidate may start at any time in their sitting" : `a candidate starting more than ${data.late_entry_minutes} minute${data.late_entry_minutes === 1 ? "" : "s"} after their sitting begins needs the invigilator to admit them`}.</span>
                  {editable ? <Btn kind="ghost" size="sm" onClick={() => setLate(data.late_entry_minutes == null ? "" : String(data.late_entry_minutes))}>Change</Btn> : null}
                </div>
              ) : (
                <div className="row row--inline row--tight" style={{ flexWrap: "wrap", alignItems: "flex-end" }}>
                  <Field id="late-entry" label="Late entry, minutes after a sitting begins" hint="Empty for no limit"><input id="late-entry" className="ctl tnum" inputMode="numeric" style={{ maxWidth: 120 }} value={late} onChange={(e) => setLate(e.target.value.replace(/[^0-9]/g, ""))} /></Field>
                  <Btn kind="primary" disabled={busy} onClick={() => void saveLate()}>Save</Btn>
                  <Btn kind="ghost" onClick={() => setLate(null)}>Back</Btn>
                </div>
              )}
            </div>
          ) : null}
        </PBody>
        {data.sittings.length ? (
          <DTable cols={["Sitting", "Venue", "Time", "Seats|num", "Begun|num", "Invigilators", "|mid"]} rows={data.sittings.map((s) => [
            <b key="l">{s.label}</b>, <span key="v">{s.venue}</span>,
            <span key="t" className="sub2">{whenAt(s.starts_at)} to {hhmm(s.ends_at)}</span>,
            <span key="c" className="tnum">{s.seated} / {s.capacity}{s.seated >= s.capacity ? <Pil kind="warn" className="ml-1">full</Pil> : null}</span>,
            <span key="b" className="tnum">{s.begun}</span>,
            <span key="i" className="sub2">{s.invigilators?.length ? s.invigilators.map((p) => `${p.name}${p.chief ? " (chief)" : ""}`).join("; ") : "None named"}</span>,
            <span key="a" className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
              <a className="btn btn--secondary btn--sm" href={`/cbt/invigilate/${s.id}`} target="_blank" rel="noopener">Invigilator&rsquo;s screen</a>
              {editable ? <Btn kind="ghost" size="sm" onClick={() => { setNaming(s); setQ(""); setFound(null); }}>Invigilators</Btn> : null}
              <Btn kind="ghost" size="sm" onClick={() => void openList(s)}>Attendance list</Btn>
              {editable ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => setForm({ id: s.id, label: s.label, venue: s.venue, startsAt: localInput(s.starts_at), endsAt: localInput(s.ends_at), capacity: String(s.capacity) })}>Edit</Btn> : null}
              {editable && !s.begun && !s.marked ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void remove(s)}>Remove</Btn> : null}
            </span>,
          ])} />
        ) : <PBody><div className="sub2">No sittings: the examination opens to every candidate in its window.</div></PBody>}
      </Panel>

      {form ? (
        <Modal title={form.id ? `Edit ${form.label}` : "Add a sitting"} sub={exam.reference} onClose={() => setForm(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setForm(null)}>Back</Btn><Btn kind="primary" disabled={busy || !form.label.trim() || !form.venue.trim() || !form.startsAt || !form.endsAt || !Number(form.capacity)} onClick={() => void save()}>{busy ? "Saving…" : form.id ? "Save the sitting" : "Add the sitting"}</Btn></span>}>
          <p className="sub2">Inside the examination&rsquo;s window, and at least the paper&rsquo;s {exam.duration_minutes} minutes long.</p>
          <Field id="st-label" label="Name" required><input id="st-label" className="ctl" value={form.label} onChange={(e) => setForm({ ...form, label: e.target.value })} /></Field>
          <Field id="st-venue" label="Venue" required hint="e.g. CBT Centre, Hall B"><input id="st-venue" className="ctl" value={form.venue} onChange={(e) => setForm({ ...form, venue: e.target.value })} /></Field>
          <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
            <Field id="st-start" label="Starts" required><input id="st-start" type="datetime-local" className="ctl" value={form.startsAt} onChange={(e) => setForm({ ...form, startsAt: e.target.value })} /></Field>
            <Field id="st-end" label="Ends" required><input id="st-end" type="datetime-local" className="ctl" value={form.endsAt} onChange={(e) => setForm({ ...form, endsAt: e.target.value })} /></Field>
            <Field id="st-cap" label="Seats" required><input id="st-cap" className="ctl tnum" inputMode="numeric" style={{ maxWidth: 110 }} value={form.capacity} onChange={(e) => setForm({ ...form, capacity: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
          </div>
        </Modal>
      ) : null}

      {naming ? (
        <Modal title={`Invigilators · ${naming.label}`} sub={subOf(naming)} wide onClose={() => setNaming(null)} foot={<Btn kind="ghost" onClick={() => setNaming(null)}>Close</Btn>}>
          <p className="sub2">Each invigilator is told by email (or a text when their record has no email) and finds the sitting under Invigilation: seat by seat, who has not come, who is writing, who has submitted; they mark a candidate absent or admit one who came late. Nobody invigilates two sittings at the same time.</p>
          {naming.invigilators?.length ? (
            <DTable cols={["Name", "Staff number", "|mid"]} rows={naming.invigilators.map((p) => [
              <span key="n">{p.name}{p.chief ? <Pil kind="info" className="ml-1">chief</Pil> : null}</span>,
              <span key="s" className="tnum sub2">{p.staff_number ?? "—"}</span>,
              <Btn key="r" kind="ghost" size="sm" disabled={busy} onClick={() => void unname(p)}>Remove</Btn>,
            ])} />
          ) : <div className="sub2 mb-2">No invigilator is named for this sitting yet.</div>}
          <form className="row row--inline row--tight mt-2" style={{ flexWrap: "wrap", alignItems: "flex-end" }} onSubmit={(e) => { e.preventDefault(); void search(); }}>
            <Field id="inv-q" label="Find a member of staff" hint="Name or staff number"><input id="inv-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} /></Field>
            <Btn kind="secondary" type="submit" disabled={q.trim().length < 2}>Search</Btn>
          </form>
          {found ? (found.length ? (
            <DTable cols={["Name", "Staff number", "Offices", "|mid"]} rows={found.map((p) => {
              const named = naming.invigilators?.find((x) => x.person_id === p.id);
              return [
                <span key="n">{p.surname.toUpperCase()}, {p.given_names}</span>,
                <span key="s" className="tnum sub2">{p.staff_number ?? "—"}</span>,
                <span key="o" className="sub2">{p.offices}</span>,
                <span key="a" className="row row--inline row--tight">
                  {!named ? <Btn kind="secondary" size="sm" disabled={busy} onClick={() => void name(p, false)}>Name</Btn> : null}
                  {!named?.chief ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void name(p, true)}>Name as chief</Btn> : <span className="sub2">Chief</span>}
                </span>,
              ];
            })} />
          ) : <div className="sub2 mt-1">Nobody holding an office today matches.</div>) : null}
        </Modal>
      ) : null}

      {list ? (
        <Modal title={`Attendance list · ${list.sitting.label}`} sub={subOf(list.sitting)} wide onClose={() => setList(null)}
          foot={<span className="row row--inline row--tight">
            <Btn kind="secondary" disabled={!list.rows.length} onClick={() => brandedPrint(`${exam.course_code} CBT attendance list`, subOf(list.sitting), HEAD, body(list.rows), docSerial("CBT"))}>Print</Btn>
            <Btn kind="ghost" disabled={!list.rows.length} onClick={() => void brandedXlsx(`${exam.course_code} CBT attendance list`, HEAD, body(list.rows), { sheetName: list.sitting.label, serial: docSerial("CBT"), sub: subOf(list.sitting) }).then((b) => downloadBlob(b, `${exam.reference.replace(/\//g, "-")}-${list.sitting.label.replace(/\s+/g, "-")}.xlsx`))}>Excel</Btn>
            <Btn kind="ghost" onClick={() => setList(null)}>Close</Btn></span>}>
          {list.rows.length ? (
            <DTable pageSize={50} cols={["Seat|num", "Matric No.", "Name", "Level|mid", "Programme", "Extra time|mid", "Status|mid", ...(editable ? ["Move to"] : [])]} rows={list.rows.map((x) => [
              <b key="s" className="tnum">{x.seat_no}</b>, <span key="n" className="tnum">{x.number}</span>, <span key="m">{x.surname.toUpperCase()}, {x.other_names}</span>,
              <span key="l" className="tnum">{x.level}</span>, <span key="p" className="sub2">{x.programme}</span>,
              <span key="x" className="tnum">{x.extra_minutes ? `+${x.extra_minutes} min` : "—"}</span>,
              x.attempt_status && x.attempt_status !== "NOT_STARTED" ? <Pil key="a" kind={(ATTEMPT_WORD[x.attempt_status] ?? ["", "grey"])[1]}>{(ATTEMPT_WORD[x.attempt_status] ?? [x.attempt_status])[0]}</Pil> : <span key="a" className="sub2">Not begun</span>,
              ...(editable ? [x.attempt_status && x.attempt_status !== "NOT_STARTED" ? <span key="mv" className="sub2">Begun</span> : (
                <select key="mv" className="ctl" aria-label={`Move ${x.surname} to another sitting`} value="" disabled={busy} onChange={(e) => { if (e.target.value) void move(x, e.target.value); }}>
                  <option value="">Move to…</option>
                  {data.sittings.filter((s) => s.id !== list.sitting.id).map((s) => <option key={s.id} value={s.id} disabled={s.seated >= s.capacity}>{s.label}{s.seated >= s.capacity ? " (full)" : ""}</option>)}
                </select>)] : []),
            ])} />
          ) : <div className="sub2">Nobody is seated in this sitting yet.</div>}
        </Modal>
      ) : null}
    </>
  );
}
