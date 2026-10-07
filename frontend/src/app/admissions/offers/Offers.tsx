"use client";

/**
 * Offers that lapse and a waiting list that moves (V358), for the Admissions Office. The session's acceptance deadline — a
 * date, days after each offer's own release, or the later of the two; none set, no offer lapses. The offers past it,
 * neither accepted nor paid for, lapsed when the office says so (each applicant told). The places freed — an offer lapsed or
 * declined — each filled from the programme's waiting list in merit order by the office's choice; the place's quota basis is
 * shown beside each candidate's state and LGA, for the office to keep the quota as the policy holds it. The server decides
 * and refuses what does not stand; the screen only asks.
 */
import { useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";

interface Past { app_id: string; application_no: string; name: string; programme: string; programme_name: string; released: string; deadline_on: string; undertaking: boolean }
interface Vacancy { vacated_id: string; application_no: string; name: string; programme: string; programme_name: string; basis: string | null; why: "LAPSED" | "DECLINED"; freed_at: string }
interface Waiting { rank: number; app_id: string; application_no: string; jamb_reg_no: string; name: string; entry_mode: string; aggregate: number; state_of_origin: string | null; lga: string | null }
interface View {
  session: string; deadline: { accept_by: string | null; days_after_release: number | null; note: string | null; set_at: string; set_by: string | null } | null;
  pastDeadline: Past[]; vacancies: Vacancy[]; counts: { offered: number; accepted: number; declined: number; lapsed: number; promoted: number; waiting: number };
}
const BASIS: Record<string, string> = { NM: "National Merit", SM: "State Merit", ELG: "Equality of LGs", LOCALITY: "Locality", PLWD: "PLWD", OTHER: "Other" };
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

async function call<T>(path: string, method: string, body: unknown, reason: string): Promise<T | null> {
  const r = await fetch(`/api/bff/api/v1/admissions/offers${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: body == null ? undefined : JSON.stringify(body) });
  if (!r.ok) { notifyProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }); return null; }
  return (await r.json()) as T;
}

export function Offers({ session, sessions, canDecide }: { session: string; sessions: string[]; canDecide: boolean }) {
  const [s, setS] = useState(session);
  const [v, setV] = useState<View | null>(null);
  const [f, setF] = useState({ acceptBy: "", days: "", note: "" });
  const [busy, setBusy] = useState(false);
  const [lapse, setLapse] = useState(false);
  const [prog, setProg] = useState<string>("");
  const [w, setW] = useState<{ waiting: Waiting[]; vacancies: Vacancy[] } | null>(null);
  const [pick, setPick] = useState<Set<string>>(new Set());
  const [ask, setAsk] = useState(false);
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let live = true;
    void fetch(`/api/bff/api/v1/admissions/offers?session=${encodeURIComponent(s)}`, { cache: "no-store" }).then(async (r) => {
      if (!live) return;
      if (!r.ok) { notifyProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }); return; }
      const d = (await r.json()) as View;
      setV(d);
      setF({ acceptBy: d.deadline?.accept_by ?? "", days: d.deadline?.days_after_release == null ? "" : String(d.deadline.days_after_release), note: d.deadline?.note ?? "" });
    });
    return () => { live = false; };
  }, [s, tick]);
  useEffect(() => {
    let live = true;
    if (prog) void fetch(`/api/bff/api/v1/admissions/offers/waiting?session=${encodeURIComponent(s)}&programme=${encodeURIComponent(prog)}`, { cache: "no-store" })
      .then(async (r) => { if (live && r.ok) { const d = await r.json(); setW(d); setPick(new Set((d.waiting as Waiting[]).slice(0, (d.vacancies as Vacancy[]).length).map((x) => x.app_id))); } });
    return () => { live = false; };
  }, [s, prog, tick]);
  if (!v) return <Note kind="info" title="Loading the offers…">One moment.</Note>;
  const programmes = [...new Map(v.vacancies.map((x) => [x.programme, x.programme_name])).entries()];
  const days = f.days.trim() === "" ? null : Number(f.days);
  const badDays = days != null && (!Number.isInteger(days) || days < 1 || days > 120);

  async function saveDeadline() {
    setBusy(true);
    try {
      const d = await call<View>("/deadline", "PUT", { session: s, acceptBy: f.acceptBy || null, daysAfterRelease: days, note: f.note.trim() || null },
        f.acceptBy || days ? `Acceptance deadline for ${s}` : `Acceptance deadline for ${s} cleared`);
      if (d) { setV(d); notify(f.acceptBy || days ? "The acceptance deadline is set." : "No acceptance deadline: no offer lapses."); }
    } finally { setBusy(false); }
  }
  async function doLapse() {
    setBusy(true);
    try {
      const d = await call<View & { lapsed: number }>("/lapse", "POST", { session: s, applicationIds: v!.pastDeadline.map((x) => x.app_id) }, `Offers lapsed past the deadline (${s})`);
      if (d) { setV(d); setLapse(false); notify(`${d.lapsed} offer${d.lapsed === 1 ? "" : "s"} lapsed; each applicant is told.`); setTick((t) => t + 1); }
    } finally { setBusy(false); }
  }
  async function promote() {
    setBusy(true);
    try {
      const d = await call<{ promoted: number }>("/promote", "POST", { session: s, programme: prog, applicationIds: w!.waiting.filter((x) => pick.has(x.app_id)).map((x) => x.app_id) },
        `Promoted from the waiting list (${prog}, ${s})`);
      if (d) { setAsk(false); notify(`${d.promoted} promoted from the waiting list; each is told.`); setTick((t) => t + 1); }
    } finally { setBusy(false); }
  }
  const c = v.counts;
  return (
    <>
      <PageHead title="Offers and the waiting list" description="The session's acceptance deadline, the offers past it, and the places they free — filled from the waiting list in merit order, by the Admissions Office's choice."
        actions={<select className="ctl" aria-label="Session" value={s} onChange={(e) => { setS(e.target.value); setProg(""); setW(null); }}>{sessions.map((x) => <option key={x}>{x}</option>)}</select>} />
      <KvGrid cls="grid--3" pairs={[["Offers released", String(c.offered)], ["Accepted", String(c.accepted)], ["Declined", String(c.declined)],
        ["Lapsed", String(c.lapsed)], ["Promoted from the waiting list", String(c.promoted)], ["On the waiting list", String(c.waiting)]]} />
      <Panel title="The acceptance deadline" right={v.deadline ? <Pil kind="info">Set</Pil> : <Pil kind="grey">None — no offer lapses</Pil>}>
        <PBody>
          <p className="sub2">An offer neither accepted nor paid for by its deadline may be lapsed. Give a date, or the days allowed after each offer&rsquo;s own release, or both — then the later of the two holds, so an offer released late (a promotion) still has its days. An applicant who has paid the acceptance fee is never lapsed.</p>
          <div className="grid grid--3">
            <Field id="od-by" label="Accept by"><input id="od-by" className="ctl" type="date" value={f.acceptBy} disabled={!canDecide} onChange={(e) => setF({ ...f, acceptBy: e.target.value })} /></Field>
            <Field id="od-days" label="Days after release" hint="1 to 120" error={badDays ? "1 to 120 days" : undefined}><input id="od-days" className="ctl tnum" inputMode="numeric" value={f.days} disabled={!canDecide} onChange={(e) => setF({ ...f, days: e.target.value })} /></Field>
            <Field id="od-note" label="On the authority of"><input id="od-note" className="ctl" maxLength={500} value={f.note} disabled={!canDecide} placeholder="e.g. Admissions Committee, 4th meeting" onChange={(e) => setF({ ...f, note: e.target.value })} /></Field>
          </div>
          {v.deadline ? <p className="sub2">{`Set ${day(v.deadline.set_at)}${v.deadline.set_by ? ` by ${v.deadline.set_by}` : ""}.`}</p> : null}
          {canDecide ? <div className="row mt-2"><Btn kind="primary" disabled={busy || badDays} onClick={() => void saveDeadline()}>{f.acceptBy || days ? "Save the deadline" : "Clear the deadline"}</Btn></div> : null}
        </PBody>
      </Panel>
      <Panel title="Offers past their deadline" right={v.pastDeadline.length ? <Pil kind="warn">{`${v.pastDeadline.length} to lapse`}</Pil> : <Pil kind="ok">None</Pil>}>
        <PBody>
          {!v.pastDeadline.length ? <p className="sub2">{v.deadline ? "No released offer is past its deadline unaccepted and unpaid." : "No deadline is set for this session, so no offer is past it."}</p> : (
            <>
              <DTable pageSize={25} cols={["Application", "Name", "Programme", "Released", "Deadline", "Undertaking"]} rows={v.pastDeadline.map((x) => [x.application_no, x.name, x.programme_name, day(x.released), day(x.deadline_on),
                x.undertaking ? <Pil key="u" kind="info">Signed, not paid</Pil> : "—"])} texts={v.pastDeadline.map((x) => `${x.application_no} ${x.name} ${x.programme_name}`)} />
              {canDecide ? <div className="row mt-2"><Btn kind="urgent" disabled={busy} onClick={() => setLapse(true)}>{`Lapse ${v.pastDeadline.length} offer${v.pastDeadline.length === 1 ? "" : "s"}`}</Btn></div> : null}
            </>
          )}
        </PBody>
      </Panel>
      <Panel title="Places freed — filled from the waiting list" right={v.vacancies.length ? <Pil kind="info">{`${v.vacancies.length} place${v.vacancies.length === 1 ? "" : "s"}`}</Pil> : <Pil kind="grey">None</Pil>}>
        <PBody>
          {!v.vacancies.length ? <p className="sub2">No place is freed: an offer lapsed or declined frees one, until it is filled from the waiting list.</p> : (
            <>
              <DTable pageSize={25} cols={["Programme", "Place of", "Basis", "Freed", "|mid"]} rows={v.vacancies.map((x) => [x.programme_name, `${x.application_no} — ${x.name}`,
                x.basis ? BASIS[x.basis] ?? x.basis : "—", `${x.why === "LAPSED" ? "Lapsed" : "Declined"} ${day(x.freed_at)}`,
                <Btn key="w" kind={prog === x.programme ? "primary" : "ghost"} onClick={() => setProg(x.programme)}>Waiting list</Btn>])} />
              {programmes.length > 1 ? <p className="sub2 mt-1">{`Places freed in ${programmes.length} programmes.`}</p> : null}
            </>
          )}
        </PBody>
      </Panel>
      {prog && w ? (
        <Panel title={`Waiting list — ${programmes.find(([code]) => code === prog)?.[1] ?? prog}`} right={<Pil kind="info">{`${w.vacancies.length} place${w.vacancies.length === 1 ? "" : "s"} to fill`}</Pil>}>
          <PBody>
            <p className="sub2">{`In merit order. The places to fill, in the order they were freed: ${w.vacancies.map((x) => `${x.basis ? BASIS[x.basis] ?? x.basis : "unstated basis"} (${x.application_no})`).join(", ")}. Choose whom to promote — the top of the list is chosen for you; keep the quota as the policy holds it (a State Merit place for an indigene, a Locality place for the catchment).`}</p>
            {!w.waiting.length ? <p className="sub2">No eligible candidate is waiting in this programme.</p> : (
              <DTable pageSize={0} cols={["|mid", "Rank|num", "Application", "Name", "Aggregate|num", "State", "LGA"]} rows={w.waiting.map((x) => [
                <input key="c" type="checkbox" aria-label={`Promote ${x.name}`} disabled={!canDecide} checked={pick.has(x.app_id)}
                  onChange={() => setPick((p) => { const n = new Set(p); if (n.has(x.app_id)) n.delete(x.app_id); else n.add(x.app_id); return n; })} />,
                x.rank, x.application_no, x.name, Number(x.aggregate).toFixed(2), x.state_of_origin ?? "—", x.lga ?? "—"])} />
            )}
            {canDecide ? <div className="row mt-2"><Btn kind="primary" disabled={busy || !pick.size || pick.size > w.vacancies.length} onClick={() => setAsk(true)}>{`Promote ${pick.size}`}</Btn>
              {pick.size > w.vacancies.length ? <span className="sub2">{`Only ${w.vacancies.length} place${w.vacancies.length === 1 ? " is" : "s are"} freed.`}</span> : null}</div> : null}
          </PBody>
        </Panel>
      ) : null}
      {lapse ? (
        <Modal title={`Lapse ${v.pastDeadline.length} offer${v.pastDeadline.length === 1 ? "" : "s"}`} onClose={() => setLapse(false)}
          foot={<><Btn kind="ghost" onClick={() => setLapse(false)}>Cancel</Btn><span className="grow" /><Btn kind="urgent" disabled={busy} onClick={() => void doLapse()}>Lapse them</Btn></>}>
          <p>Each applicant listed is told that the offer was not accepted by its deadline and has lapsed. A lapsed offer is not reinstated; each frees a place to fill from the waiting list.</p>
        </Modal>
      ) : null}
      {ask && w ? (
        <Modal title={`Promote ${pick.size} from the waiting list`} onClose={() => setAsk(false)}
          foot={<><Btn kind="ghost" onClick={() => setAsk(false)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy} onClick={() => void promote()}>Promote</Btn></>}>
          <p>{`${w.waiting.filter((x) => pick.has(x.app_id)).map((x) => x.name).join("; ")} — each offered the next freed place, released at once and told; the decision is read under Admission Status, and each has the days allowed after release to accept.`}</p>
        </Modal>
      ) : null}
    </>
  );
}
