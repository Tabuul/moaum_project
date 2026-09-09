"use client";

/**
 * The Bursar's desk: the session's charges stated as a schedule, the
 * clearance scheme put in force under an instrument, and the references
 * students generated that wait on the bank's record. Every act is the
 * Bursar's; a student's charge is computed from what is stated here, never
 * typed against the student.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface ScheduleItem { id: string; item: string; amount: number; level: number | null; entry_mode: string | null; faculty_code: string | null; faculty_name: string | null; programme_code: string | null; programme_name: string | null; fee_group: string | null; fee_group_name: string | null; semester: number | null; ord: number }
export interface FeeGroup { code: string; name: string; applies_category: string | null }
export interface FeeItem { code: string; name: string }
export interface ProgrammeOption { code: string; name: string; category: string; faculty_code: string }
export interface Schedule {
  session: string;
  items: ScheduleItem[];
  scheme: { id?: string; instrument?: string; from_date?: string; until_date?: string | null; decided_by?: string; rules?: string };
  schemeInForce: boolean;
  position: { students_paying: number; confirmed: number; references_open: number };
}
export interface OpenReference { id: string; reference: string; session: string; purpose: string; amount: number; generated_at: string; expires_at: string; matric_no: string | null; admission_no: string | null; surname: string; other_names: string; programme: string; current_level: number }
export interface ApplicantFees { session: string; stated: boolean; applicationFee: number; portalCharge: number; acceptanceFee: number }

const naira = (n: number | string) => `₦${Number(n).toLocaleString("en-NG")}`;

export function FeeSchedule({ session, schedule, open, faculties, feeGroups, programmes, applicantFees, feeItems, sessions, actingOffice }: { session: string; schedule: Schedule; open: OpenReference[]; faculties: { code: string; name: string }[]; feeGroups: FeeGroup[]; programmes: ProgrammeOption[]; applicantFees: ApplicantFees | null; feeItems: FeeItem[]; sessions: string[]; actingOffice: string | null }) {
  const router = useRouter();
  const may = actingOffice === "bursar" || actingOffice === "super";
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [adding, setAdding] = useState(false);
  const [confirming, setConfirming] = useState<OpenReference | null>(null);
  const [scheming, setScheming] = useState(false);
  const [edits, setEdits] = useState<Record<string, string>>({});
  const val = (k: string, d = "") => edits[k] ?? d;
  const [af, setAf] = useState({
    applicationFee: String(applicantFees?.applicationFee ?? ""),
    portalCharge: String(applicantFees?.portalCharge ?? ""),
    acceptanceFee: String(applicantFees?.acceptanceFee ?? ""),
  });

  // the applicant fees live under admissions, not finance, so they have their own save
  async function saveApplicantFees(): Promise<void> {
    setBusy("af");
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/applicant-fees`, {
        method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Applicant / Post-UTME fees stated for ${session}`) },
        body: JSON.stringify({ applicationFee: Number(af.applicationFee) || 0, portalCharge: Number(af.portalCharge) || 0, acceptanceFee: Number(af.acceptanceFee) || 0 }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      router.refresh();
    } finally {
      setBusy(null);
    }
  }

  async function send(key: string, method: "POST" | "PUT", path: string, body: unknown, reason: string): Promise<boolean> {
    setBusy(key);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/finance${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return false; }
      router.refresh();
      return true;
    } finally {
      setBusy(null);
    }
  }

  const rules = schedule.scheme.rules ? (JSON.parse(schedule.scheme.rules) as Record<string, string>) : {};
  const total = schedule.items.filter((i) => !i.level && !i.entry_mode && !i.faculty_code && !i.programme_code).reduce((n, i) => n + Number(i.amount), 0);

  return (
    <>
      <Tiles items={[
        ["Items stated", String(schedule.items.length), null, `${session} · every item applies where its filters match`],
        ["Charge to everybody", naira(total), null, "Items with no filter"],
        ["Confirmed this session", naira(schedule.position.confirmed), "var(--green-ink)", `${schedule.position.students_paying} student${schedule.position.students_paying === 1 ? "" : "s"} paying`],
        ["References waiting", String(schedule.position.references_open), schedule.position.references_open ? "var(--red-ink)" : null, "Against the bank's record"],
      ]} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {schedule.schemeInForce ? (
        <Note kind="ok" title={`Clearance scheme in force under ${schedule.scheme.instrument}`}>
          From {schedule.scheme.from_date}{schedule.scheme.until_date ? ` to ${schedule.scheme.until_date}` : ""}. Registration releases at {rules.REGISTRATION ?? "—"}, the examination at {rules.EXAMINATION ?? "—"}, results at {rules.RESULTS ?? "—"}; arrears block everything.
        </Note>
      ) : (
        <Note kind="bad" title="No clearance scheme is in force, so no payment releases anything" action={<Btn kind="urgent" disabled={!may} onClick={() => { setScheming(true); setEdits({}); }}>Put the recommended scheme in force</Btn>}>
          The portal refuses rather than assumes what a payment releases. The recommended scheme: the first instalment, half the charge, opens registration, the identity card and the library; payment in full opens the examination, results, the transcript and convocation; arrears block everything. It is put in force under a minute, from a date.
        </Note>
      )}
      <Panel title={`The charges for ${session}`} right={<Btn kind="primary" disabled={!may} onClick={() => { setAdding(true); setEdits({}); }}>Add an item</Btn>}>
        <DTable cols={["Item", "Applies to", "Amount|num", "|num"]} rows={schedule.items.map((i) => [
          <strong key="i">{i.item}</strong>,
          <span className="sub2" key="a">{[i.fee_group_name, i.level ? `${i.level} Level` : null, i.entry_mode, i.faculty_name, i.programme_name, i.semester ? `Semester ${i.semester}` : null].filter(Boolean).join(" · ") || "Every student"}</span>,
          <span className="tnum" key="m">{naira(i.amount)}</span>,
          <Btn kind="ghost" key="e" disabled={!may || busy !== null} onClick={() => void send(`end-${i.id}`, "POST", `/sessions/${session}/schedule/${i.id}/end`, {}, `Fee item ended: ${i.item}`)}>{busy === `end-${i.id}` ? "Ending…" : "End"}</Btn>,
        ])} />
        {!schedule.items.length ? <PBody><div className="sub2">No charge is stated for {session}. Until one is, no student owes anything, no reference can be generated, and registration waits.</div></PBody> : null}
      </Panel>
      <Panel title="References waiting on the bank's record" right={`${open.length}`}>
        <DTable cols={["Reference", "Student", "Amount|num", "Generated|mid", "|num"]} rows={open.map((r) => [
          <span className="tnum" key="r">{r.reference}</span>,
          <Two key="s" a={`${r.surname}, ${r.other_names}`} b={`${r.matric_no ?? r.admission_no} · ${r.programme} · ${r.current_level} Level`} />,
          <span className="tnum" key="a">{naira(r.amount)}</span>,
          <span className="sub2 tnum" key="g">{new Date(r.generated_at).toLocaleString("en-GB")}</span>,
          <Btn kind="primary" key="c" disabled={!may} onClick={() => { setConfirming(r); setEdits({}); }}>Confirm</Btn>,
        ])} texts={open.map((r) => `${r.reference} ${r.surname} ${r.other_names} ${r.matric_no} ${r.admission_no}`)} />
        {!open.length ? <PBody><div className="sub2">Nothing waits. A reference a student generates appears here until the bank&rsquo;s record is matched to it, by the Bursary or by a gateway&rsquo;s webhook.</div></PBody> : null}
      </Panel>
      {adding ? (() => {
        const addSession = val("addSession", session);
        const facultyPick = val("faculty");
        const facultyName = faculties.find((f) => f.code === facultyPick)?.name;
        const facProgrammes = facultyPick ? programmes.filter((pr) => pr.faculty_code === facultyPick) : programmes;
        const itemName = val("item") === "__other__" ? val("itemOther").trim() : val("item");
        const selectedProgs = (val("progs") ? val("progs").split(",") : []).filter(Boolean);
        const toggleProg = (code: string) => { const s = new Set(selectedProgs); if (s.has(code)) s.delete(code); else s.add(code); setEdits({ ...edits, progs: [...s].join(",") }); };
        return (
        <Modal title="An item of the charge" sub={`${addSession} · applies where every filter it carries matches, or is blank`} onClose={() => setAdding(false)}
          foot={<><Btn kind="ghost" onClick={() => setAdding(false)}>Cancel</Btn><span style={{ flexGrow: 1 }} /><Btn kind="primary" disabled={!itemName || !val("amount") || busy !== null} onClick={async () => {
            const shared = { item: itemName, amount: Number(val("amount")), level: val("level") ? Number(val("level")) : null, entryMode: val("mode") || null, feeGroup: val("group") || null, semester: val("semester") ? Number(val("semester")) : null, ord: Number(val("ord") || "0"), facultyCode: val("faculty") || null };
            let ok = true;
            if (selectedProgs.length) {
              // one row per chosen programme; the fee applies to exactly those
              for (const code of selectedProgs) {
                ok = (await send(`add-${code}`, "POST", `/sessions/${addSession}/schedule`, { ...shared, programmeCode: code }, `Fee item stated for ${addSession}: ${itemName} · ${code}`)) && ok;
              }
            } else {
              // none chosen: the whole faculty (if one is set), else every programme
              ok = await send("add", "POST", `/sessions/${addSession}/schedule`, { ...shared, programmeCode: null }, `Fee item stated for ${addSession}: ${itemName}`);
            }
            if (ok) { setAdding(false); if (addSession !== session) router.push(`/finance/fees?session=${encodeURIComponent(addSession)}`); }
          }}>{busy === "add" || (busy ?? "").startsWith("add-") ? "Stating…" : "State the item"}</Btn></>}>
          <div className="grid grid--2">
            <Field id="fi" label="Payment item" hint="A payment category; choose Other to name a one-off">
              <select id="fi" className="ctl" value={val("item")} onChange={(e) => setEdits({ ...edits, item: e.target.value })}>
                <option value="">— choose an item —</option>
                {feeItems.map((it) => <option key={it.code} value={it.name}>{it.name}</option>)}
                <option value="__other__">Other (type a name)…</option>
              </select>
            </Field>
            <Field id="fa" label="Amount" hint="In naira"><input id="fa" className="ctl tnum" value={val("amount")} inputMode="numeric" onChange={(e) => setEdits({ ...edits, amount: e.target.value })} /></Field>
          </div>
          {val("item") === "__other__" ? <Field id="fio" label="Item name" hint="The name this charge appears under"><input id="fio" className="ctl" value={val("itemOther")} onChange={(e) => setEdits({ ...edits, itemOther: e.target.value })} placeholder="e.g. Faculty dues" /></Field> : null}
          <div className="grid grid--2">
            <Field id="fs" label="Session" hint="Which session this charge is for"><select id="fs" className="ctl" value={addSession} onChange={(e) => setEdits({ ...edits, addSession: e.target.value })}>{(sessions.length ? sessions : [session]).map((s) => <option key={s} value={s}>{s}</option>)}</select></Field>
            <Field id="fsem" label="Semester" hint="Blank for the whole session"><select id="fsem" className="ctl" value={val("semester")} onChange={(e) => setEdits({ ...edits, semester: e.target.value })}><option value="">Whole session</option><option value="1">First semester</option><option value="2">Second semester</option></select></Field>
          </div>
          <Field id="fg" label="Programme group" hint="Undergraduate, Postgraduate, GST, EPS — blank for every group">
            <select id="fg" className="ctl" value={val("group")} onChange={(e) => setEdits({ ...edits, group: e.target.value })}>
              <option value="">Every group</option>
              {feeGroups.map((g) => <option key={g.code} value={g.code}>{g.name}</option>)}
            </select>
          </Field>
          <div className="grid grid--2">
            <Field id="fl" label="Level" hint="Blank for every level"><select id="fl" className="ctl" value={val("level")} onChange={(e) => setEdits({ ...edits, level: e.target.value })}><option value="">Every level</option>{[100, 200, 300, 400, 500, 600].map((l) => <option key={l} value={l}>{l}</option>)}</select></Field>
            <Field id="fm" label="Entry mode" hint="Blank for every mode"><select id="fm" className="ctl" value={val("mode")} onChange={(e) => setEdits({ ...edits, mode: e.target.value })}><option value="">Every mode</option><option>UTME</option><option>DIRECT_ENTRY</option><option>TRANSFER</option></select></Field>
          </div>
          <Field id="ff" label="Faculty" hint="Choose a faculty to list its programmes"><select id="ff" className="ctl" value={val("faculty")} onChange={(e) => setEdits({ ...edits, faculty: e.target.value, progs: "" })}><option value="">Every faculty</option>{faculties.map((f) => <option key={f.code} value={f.code}>{f.name}</option>)}</select></Field>
          <Field id="fp" label="Programmes" hint={facultyPick ? `Tick a single programme, two or more, or none for all programmes in ${facultyName ?? "the faculty"}` : "Choose a faculty above to target specific programmes; otherwise the charge applies to every programme"}>
            {facultyPick ? (
              <>
                <div style={{ display: "flex", gap: 8, marginBottom: 6 }}>
                  <button type="button" className="btn btn--ghost btn--sm" onClick={() => setEdits({ ...edits, progs: facProgrammes.map((pr) => pr.code).join(",") })}>Select all</button>
                  {selectedProgs.length ? <button type="button" className="btn btn--ghost btn--sm" onClick={() => setEdits({ ...edits, progs: "" })}>Clear (all in faculty)</button> : null}
                  <span className="sub2" style={{ alignSelf: "center" }}>{selectedProgs.length ? `${selectedProgs.length} selected` : `All programmes in ${facultyName ?? "the faculty"}`}</span>
                </div>
                <div style={{ maxHeight: 180, overflowY: "auto", border: "1px solid var(--line-2)", borderRadius: 8, padding: 8, display: "grid", gap: 4 }}>
                  {facProgrammes.length ? facProgrammes.map((pr) => (
                    <label key={pr.code} className="sub2" style={{ display: "flex", gap: 8, alignItems: "center", cursor: "pointer" }}>
                      <input type="checkbox" className="pchk" checked={selectedProgs.includes(pr.code)} onChange={() => toggleProg(pr.code)} /> {pr.name}
                    </label>
                  )) : <span className="sub2">No programme in this faculty.</span>}
                </div>
              </>
            ) : <div className="sub2">Applies to every programme. Choose a faculty above to target one, two or more.</div>}
          </Field>
        </Modal>
        );
      })() : null}
      {confirming ? (
        <Modal title={`Confirm ${confirming.reference}`} sub={`${confirming.surname}, ${confirming.other_names} · ${naira(confirming.amount)}`} onClose={() => setConfirming(null)}
          foot={<><Btn kind="ghost" onClick={() => setConfirming(null)}>Cancel</Btn><span style={{ flexGrow: 1 }} /><Btn kind="go" disabled={!val("channel") || busy !== null} onClick={async () => { const ok = await send("confirm", "POST", `/references/${confirming.reference}/confirm`, { channel: val("channel"), note: val("note") || undefined }, `Payment ${confirming.reference} confirmed against the bank's record`); if (ok) setConfirming(null); }}>{busy === "confirm" ? "Confirming…" : "Confirm the payment"}</Btn></>}>
          <Field id="ch" label="Channel"><select id="ch" className="ctl" value={val("channel")} onChange={(e) => setEdits({ ...edits, channel: e.target.value })}><option value="">Choose…</option><option>Bank transfer</option><option>Bank branch</option><option>USSD</option><option>Card</option></select></Field>
          <Field id="nt" label="Note" hint="Teller number, transaction reference"><input id="nt" className="ctl" value={val("note")} onChange={(e) => setEdits({ ...edits, note: e.target.value })} /></Field>
          <Note kind="info" title="Confirmed against the bank's record, not by this page">The receipt is issued the moment you confirm, and the student is told by email and SMS.</Note>
        </Modal>
      ) : null}
      {scheming ? (
        <Modal title="Put the recommended clearance scheme in force" sub="Under a minute, from a date" onClose={() => setScheming(false)}
          foot={<><Btn kind="ghost" onClick={() => setScheming(false)}>Cancel</Btn><span style={{ flexGrow: 1 }} /><Btn kind="urgent" disabled={!val("instrument") || busy !== null} onClick={async () => { const ok = await send("scheme", "POST", "/clearance-scheme", { instrument: val("instrument"), from: val("from") || undefined }, `Clearance scheme put in force under ${val("instrument")}`); if (ok) setScheming(false); }}>{busy === "scheme" ? "Putting in force…" : "Put in force"}</Btn></>}>
          <Field id="si" label="Instrument" hint="The Council or Bursary minute that approved it"><input id="si" className="ctl" value={val("instrument")} onChange={(e) => setEdits({ ...edits, instrument: e.target.value })} placeholder="BUR/2026/04" /></Field>
          <Field id="sf" label="From" hint="Blank for today"><input id="sf" className="ctl tnum" type="date" value={val("from")} onChange={(e) => setEdits({ ...edits, from: e.target.value })} /></Field>
          <div className="sub2">Registration, identity card and library release at the first instalment; the examination, results, transcript and convocation at payment in full; hostel is not gated; arrears block everything. Two schemes cannot overlap in time.</div>
        </Modal>
      ) : null}
      <Panel title="Applicant · Post-UTME fees" right={applicantFees?.stated ? `Stated for ${session}` : `Default (not yet stated for ${session})`}>
        <PBody>
          <div className="sub2" style={{ marginBottom: 10 }}>
            The charges an applicant pays before they are a student &mdash; the Post-UTME screening fee (with the portal and payment charge) and the acceptance fee an offer carries. They are a payment item of their own, under <b>Applicant</b>, kept apart from the student charges above because an applicant is not yet on the register.
          </div>
          <div className="grid grid--3">
            <Field id="af-app" label="Post-UTME screening fee" hint="What the applicant pays to apply and be screened"><input id="af-app" className="ctl tnum" inputMode="numeric" value={af.applicationFee} onChange={(e) => setAf({ ...af, applicationFee: e.target.value.replace(/[^0-9.]/g, "") })} placeholder="2000" disabled={!may} /></Field>
            <Field id="af-port" label="Portal and payment charge" hint="Added to the screening fee at checkout"><input id="af-port" className="ctl tnum" inputMode="numeric" value={af.portalCharge} onChange={(e) => setAf({ ...af, portalCharge: e.target.value.replace(/[^0-9.]/g, "") })} placeholder="300" disabled={!may} /></Field>
            <Field id="af-acc" label="Acceptance fee" hint="Paid on an offer; credited to first-session charges"><input id="af-acc" className="ctl tnum" inputMode="numeric" value={af.acceptanceFee} onChange={(e) => setAf({ ...af, acceptanceFee: e.target.value.replace(/[^0-9.]/g, "") })} placeholder="30000" disabled={!may} /></Field>
          </div>
          <div style={{ display: "flex", gap: 9, alignItems: "center", flexWrap: "wrap", marginTop: 6 }}>
            <Btn kind="primary" disabled={!may || busy !== null || !af.applicationFee.trim()} onClick={() => void saveApplicantFees()}>{busy === "af" ? "Saving…" : "State the applicant fees"}</Btn>
            <span className="sub2">An applicant generating a reference is charged the screening fee plus the portal charge &mdash; {naira((Number(af.applicationFee) || 0) + (Number(af.portalCharge) || 0))} in all.</span>
          </div>
        </PBody>
      </Panel>
      <Pil kind="grey">Every act here is the Bursar&rsquo;s, on the record</Pil>
    </>
  );
}
