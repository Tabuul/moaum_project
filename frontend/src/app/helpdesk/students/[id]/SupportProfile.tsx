"use client";
/** One student in support mode (V334). The banner says who is acting for whom and on which ticket; the tabs show the record
 *  the Registry's screens show, the registration through the engine's own view, the payments and documents the posting
 *  allows, the history of every act on the record, and the student's tickets. Every change takes a reason; a ticket opened
 *  from is carried on every act; what the posting does not carry is not offered, and the server refuses it anyway. */
import Link from "next/link";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tabs } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { statusWord } from "@/lib/cohorts";
import { ACTION_WORD, SECTION_WORD, SENSITIVE, capabilityFor, type SupportProfile as Profile } from "@/lib/support";
import type { RegistrationView } from "@/lib/student-portal";

type Tab = "profile" | "registration" | "payments" | "documents" | "history" | "tickets";
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
const naira = (v: unknown) => (v == null || v === "" ? "—" : `₦${Number(v).toLocaleString("en-NG", { minimumFractionDigits: 2 })}`);
const sem = (n: number) => (n === 1 ? "First" : n === 2 ? "Second" : "Third");

export function SupportProfile({ id, data, tab }: { id: string; data: Profile; tab: string }) {
  const router = useRouter();
  const go = useQueryNav();
  const s = data.record.student;
  const caps = new Set(data.capabilities);
  const portal = data.portal as Record<string, unknown>;
  const pos = data.position as Record<string, unknown> | null;
  const [busy, setBusy] = useState(false);
  const [edit, setEdit] = useState<{ field: string; label: string; value: string; reason: string; tier: string } | null>(null);
  const [photo, setPhoto] = useState<{ dataUrl: string; reason: string } | null>(null);
  const [photoVersion, setPhotoVersion] = useState(0);
  type Reg = { view: RegistrationView; history: { id: string; session: string; semester: number; status: string; level: number; units?: number; submitted_at?: string | null; approved_at?: string | null; entries?: { courseCode: string; title: string; units: number; status: string }[] }[]; manage: boolean };
  type Pay = { fees: Record<string, unknown> | null; session: string; references: Record<string, unknown>[] };
  type Docs = { admission: Record<string, unknown>[]; issued: Record<string, unknown>[]; receipts: Record<string, unknown>[] };
  const [reg, setReg] = useState<Reg | null>(null);
  const [regSel, setRegSel] = useState<{ session: string; semester: string }>({ session: String(portal.session ?? ""), semester: "1" });
  const [regReason, setRegReason] = useState("");
  const [pay, setPay] = useState<Pay | null>(null);
  const [docs, setDocs] = useState<Docs | null>(null);
  const ticket = data.ticket;

  async function call(method: "POST" | "PUT", path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/helpdesk/support/students/${id}${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = (await r.json().catch(() => null)) as Record<string, unknown> | null;
      if (!r.ok) { notifyProblem(j ? (j as unknown as Parameters<typeof notifyProblem>[0]) : { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      return j;
    } finally { setBusy(false); }
  }
  function openTab(t: Tab) {
    go(`/helpdesk/students/${id}?tab=${t}${ticket ? `&ticket=${encodeURIComponent(ticket.id)}` : ""}`);
  }
  /** a tab's data is read when the tab is opened, once; the registration again when the session or semester changes */
  function loadReg(session: string, semester: string) {
    setRegSel({ session, semester });
    setReg(null);
  }
  useEffect(() => {
    if (tab !== "registration" || reg !== null) return;
    let alive = true;
    void fetch(`/api/bff/api/v1/helpdesk/support/students/${id}/registration?session=${encodeURIComponent(regSel.session)}&semester=${regSel.semester}`).then(async (r) => {
      const j = (await r.json().catch(() => null)) as Reg | null;
      if (!alive) return;
      if (!r.ok) { notifyProblem((j as unknown as Parameters<typeof notifyProblem>[0]) ?? { status: r.status, title: r.statusText }); return; }
      setReg(j);
    });
    return () => { alive = false; };
  }, [tab, reg, regSel, id]);
  useEffect(() => {
    if (tab !== "payments" || pay !== null) return;
    let alive = true;
    void fetch(`/api/bff/api/v1/helpdesk/support/students/${id}/payments`).then(async (r) => { const j = (await r.json().catch(() => null)) as Pay | null; if (alive && r.ok) setPay(j); });
    return () => { alive = false; };
  }, [tab, pay, id]);
  useEffect(() => {
    if (tab !== "documents" || docs !== null) return;
    let alive = true;
    void fetch(`/api/bff/api/v1/helpdesk/support/students/${id}/documents`).then(async (r) => { const j = (await r.json().catch(() => null)) as Docs | null; if (alive && r.ok) setDocs(j); });
    return () => { alive = false; };
  }, [tab, docs, id]);

  async function regAct(verb: "add" | "drop" | "submit" | "choose", offering?: string, offerings?: string[]) {
    if (reg === null) return;
    if (!regReason.trim()) { notifyProblem({ status: 422, title: "A reason is needed", detail: "Say why the registration is changed — the ticket, or what the student reported." } as unknown as Parameters<typeof notifyProblem>[0]); return; }
    const j = await call("POST", `/registration/${verb}`, { session: reg.view.session, semester: reg.view.semester, offering, offerings, reason: regReason.trim(), ticket: ticket?.id ?? null },
      verb === "add" ? "Course added" : verb === "drop" ? "Course dropped" : verb === "submit" ? "Registration submitted" : "Courses chosen");
    if (j) { setReg({ ...reg, view: j.view as RegistrationView }); router.refresh(); }
  }

  const sections = ["personal", "contact", "origin", "family", "academic", "other"];
  const bySection = (sec: string) => data.record.biodata.filter((b) => (sections.includes(b.section) ? b.section : "other") === sec).sort((a, b) => a.ord - b.ord);
  const mayEdit = (b: { tier: string; section: string; field: string }) => { const c = capabilityFor(b.tier, b.section, b.field); return c ? caps.has(c) : false; };
  const asksRegistry = (b: { tier: string; field: string }) => b.tier === "approval" || SENSITIVE.has(b.field);
  const fullName = `${s.surname}, ${s.otherNames}`;

  return (
    <>
      <Note kind="info" title="SUPPORT MODE — you are managing this student's record on behalf of the student">
        <span className="row row--inline" style={{ gap: "var(--s-4)", flexWrap: "wrap" }}>
          <span><b>Agent</b> {data.agent}</span>
          <span><b>Student</b> {fullName} · <span className="tnum">{s.matricNo ?? s.admissionNo ?? id}</span></span>
          <span><b>Ticket</b> {ticket ? <Link href={`/helpdesk/tickets/${ticket.id}`} className="lnk tnum">{ticket.number}</Link> : <span className="sub2">none — give a reason with every change</span>}</span>
          <span><b>Reason for access</b> {ticket ? `${ticket.category}: ${ticket.subject}` : "Student support"}</span>
          <span><b>Since</b> {when(data.openedAt)}</span>
          <span><b>Scope</b> {data.scope || "—"}</span>
        </span>
      </Note>

      <PageHead title={fullName} eyebrow={<span className="tnum">{s.matricNo ?? "No matriculation number"}{s.jambRegNo ? ` · JAMB ${s.jambRegNo}` : ""}</span>}
        description={<>{s.programmeName} · {s.deptName ?? s.deptCode} · {s.facultyName ?? ""} · {s.currentLevel} Level · <Pil kind={s.status === "ACTIVE" ? "ok" : s.status === "GRADUATED" ? "info" : "grey"}>{statusWord(s.status)}</Pil>{pos?.classification ? <> <Pil kind={String(pos.classification) === "ACTIVE" ? "ok" : String(pos.classification).includes("SPILLOVER") ? "warn" : "grey"}>{String(pos.classification).charAt(0) + String(pos.classification).slice(1).toLowerCase().replace(/_/g, " ")}</Pil></> : null}</>}
        actions={<><LinkBtn href="/helpdesk/students">Student Support</LinkBtn>{ticket ? <LinkBtn href={`/helpdesk/tickets/${ticket.id}`}>Back to the ticket</LinkBtn> : null}<LinkBtn href="/helpdesk">Support Desk</LinkBtn></>} />

      <Tabs label="Section" value={(sections.includes(tab) || ["profile", "registration", "payments", "documents", "history", "tickets"].includes(tab) ? tab : "profile") as Tab} onChange={(v) => openTab(v)} items={[
        { id: "profile", label: "Profile" }, { id: "registration", label: "Course registration" },
        ...(caps.has("VIEW_PAYMENTS") ? [{ id: "payments" as Tab, label: "Payments" }] : []),
        ...(caps.has("VIEW_DOCUMENTS") ? [{ id: "documents" as Tab, label: "Documents" }] : []),
        { id: "history", label: "History", count: data.actions.length }, { id: "tickets", label: "Tickets", count: data.tickets.length },
      ]} />

      {tab === "profile" ? (
        <>
          <div className="grid grid--3">
            <Panel title="Photograph" right={caps.has("EDIT_PHOTO") ? <Btn kind="ghost" size="sm" onClick={() => setPhoto({ dataUrl: "", reason: "" })}>Replace</Btn> : null}>
              <PBody>
                {data.hasPassport ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={`/api/bff/api/v1/helpdesk/support/students/${id}/passport?v=${photoVersion}`} alt={`${fullName} — passport photograph`} style={{ width: 140, height: 160, objectFit: "cover", borderRadius: "var(--r-md)", border: "1px solid var(--line)" }} />
                ) : <div className="sub2">No photograph on the record.</div>}
              </PBody>
            </Panel>
            <Panel title="Academic">
              <PBody><div className="stack" style={{ gap: 4 }}>
                {([["Student ID", id], ["Matriculation number", s.matricNo], ["JAMB registration", s.jambRegNo], ["Admission number", s.admissionNo], ["Faculty", s.facultyName], ["Department", s.deptName], ["Programme", `${s.programmeName} (${s.programmeCode})`],
                  ["Level", s.currentLevel], ["Entry mode", s.entryMode], ["Admission session", s.entrySession], ["Current session", portal.session ?? pos?.current_session], ["Status", statusWord(s.status)],
                  ["Effective cohort", pos?.effective_cohort], ["Expected completion", pos?.expected_completion], ["Standing", portal.standing ?? "—"], ["CGPA", portal.cgpa ?? "—"]] as [string, unknown][]).map(([k, v]) => (
                  <div key={k} className="row row--between"><span className="sub2">{k}</span><span className="tnum" style={{ textAlign: "right" }}>{v == null || v === "" ? "—" : String(v)}</span></div>
                ))}
              </div></PBody>
            </Panel>
            <Panel title="Reach" right="Where the University reaches the student">
              <PBody><div className="stack" style={{ gap: 4 }}>
                {([["Phone", data.contact.phone ?? data.contact.reach_phone], ["Email", data.contact.email ?? data.contact.reach_email], ["Address", data.contact.address]] as [string, unknown][]).map(([k, v]) => (
                  <div key={k} className="row row--between"><span className="sub2">{k}</span><span className="tnum" style={{ textAlign: "right" }}>{v == null || v === "" ? "—" : String(v)}</span></div>
                ))}
                {data.record.pendingChanges.length ? <div className="mt-2"><div className="eyebrow">Awaiting the Registry</div>{data.record.pendingChanges.map((c) => <div key={c.id} className="sub2">{c.label}: {c.fromValue ?? "—"} → <b>{c.toValue}</b> · {c.state.toLowerCase()}</div>)}</div> : null}
              </div></PBody>
            </Panel>
          </div>
          {sections.filter((sec) => bySection(sec).length).map((sec) => (
            <Panel key={sec} title={SECTION_WORD[sec] ?? sec} right={sec === "origin" ? "Nationality, state of origin and LGA change only by the Registry's decision" : sec === "contact" ? "Open fields — written with a reason" : undefined}>
              <DTable pageSize={0} noPrint cols={["Field", "Value", "Tier|mid", "|num"]} rows={bySection(sec).map((b) => [
                <span key="l">{b.label}{b.hint ? <div className="sub2">{b.hint}</div> : null}</span>,
                <span key="v" className={b.value ? "" : "sub2"}>{b.value ?? "—"}</span>,
                <Pil key="t" kind={b.tier === "locked" ? "grey" : asksRegistry(b) ? "warn" : "ok"}>{b.tier === "locked" ? "Read from JAMB" : asksRegistry(b) ? "Registry decides" : "Open"}</Pil>,
                mayEdit(b) ? <Btn key="e" kind="ghost" size="sm" onClick={() => setEdit({ field: b.field, label: b.label, value: b.value ?? "", reason: "", tier: asksRegistry(b) ? "approval" : b.tier })}>{asksRegistry(b) ? "Request a change" : "Edit"}</Btn> : <span key="e" />,
              ])} />
            </Panel>
          ))}
          <Panel title="What the desk does not change" right="Routed to the office that owns it">
            <PBody><div className="sub2">Name, date of birth, gender and nationality beyond a Registry request; the matriculation number; the programme, department and faculty; the student&rsquo;s status; results and grades; any payment or balance. Escalate the ticket to the Academic Office, the Registry, the Examinations Office or the Bursary from the ticket&rsquo;s own screen.</div></PBody>
          </Panel>
        </>
      ) : null}

      {tab === "registration" ? (
        <Panel title="Course registration" right={<span className="row row--inline row--tight">
          <select className="ctl" value={regSel.session} onChange={(e) => { setRegSel({ ...regSel, session: e.target.value }); loadReg(e.target.value, regSel.semester); }} aria-label="Session">
            {Array.from(new Set([String(portal.session ?? ""), ...data.record.registrations.map((r) => r.session), ...data.record.enrolments.map((e) => e.session)].filter(Boolean))).map((x) => <option key={x} value={x}>{x}</option>)}
          </select>
          <select className="ctl" value={regSel.semester} onChange={(e) => { setRegSel({ ...regSel, semester: e.target.value }); loadReg(regSel.session, e.target.value); }} aria-label="Semester"><option value="1">First semester</option><option value="2">Second semester</option><option value="3">Third semester</option></select>
        </span>}>
          {reg === null ? <PBody><div className="sub2">Reading the registration…</div></PBody> : (
            <>
              <PBody>
                <div className="row row--base" style={{ flexWrap: "wrap", gap: "var(--s-4)" }}>
                  <span><b>{reg.view.session}</b> · {sem(reg.view.semester)} semester · {reg.view.level} Level</span>
                  <span>Status <Pil kind={reg.view.registration ? (reg.view.registration.status === "APPROVED" || reg.view.registration.status === "LOCKED" ? "ok" : reg.view.registration.status === "RETURNED" ? "bad" : "warn") : "grey"}>{reg.view.registration ? reg.view.registration.status.toLowerCase() : "not started"}</Pil></span>
                  <span>Window <Pil kind={reg.view.window?.open ? "ok" : "bad"}>{reg.view.window?.open ? "open" : "closed"}</Pil>{reg.view.window?.gate ? <span className="sub2"> · {reg.view.window.gate}</span> : null}</span>
                  <span>Fees <Pil kind={reg.view.clears ? "ok" : "warn"}>{reg.view.clears ? "cleared" : "not cleared"}</Pil></span>
                  <span className="sub2">Units {reg.view.registration?.units ?? 0} of {reg.view.limit.min_units}–{reg.view.limit.max_units}</span>
                  {reg.view.addDropOpen ? <Pil kind="info">Add/drop open</Pil> : null}
                </div>
                {!reg.view.window?.open ? <Note kind="bad" title="Course registration is closed for this semester">A change here needs the window open or the authorised exception the Registry grants; the engine refuses otherwise. Document the issue on the ticket and escalate it to the Academic Office.</Note> : null}
                {!reg.manage ? <Note kind="info" title="Read only">Your posting does not carry course registration management; the Head of the Support Desk grants it on the posting.</Note> : (
                  <Field id="rg-reason" label="Reason for the change" required hint={ticket ? `Recorded on ${ticket.number}` : "Recorded on the support ledger"}><input id="rg-reason" className="ctl" value={regReason} onChange={(e) => setRegReason(e.target.value)} maxLength={2000} placeholder="e.g. the portal returned an error when the student added the course" /></Field>
                )}
              </PBody>
              <PBody>
                <div className="eyebrow">Registered courses</div>
                {reg.view.registration?.entries.length ? <DTable pageSize={0} noPrint cols={["Code|mid", "Title", "Units|mid", "Kind|mid", "State|mid", "|num"]} rows={reg.view.registration.entries.map((e) => [
                  <b key="c" className="tnum">{e.courseCode}</b>, <span key="t">{e.title}</span>, <span key="u" className="tnum">{e.units}</span>, <span key="k" className="sub2">{e.entryType}</span>, <span key="s" className="sub2">{e.status.toLowerCase()}</span>,
                  reg.manage && e.entryType !== "CARRYOVER" && e.entryType !== "DEFERRED" ? <Btn key="d" kind="ghost" size="sm" disabled={busy} onClick={() => { if (window.confirm(`Remove ${e.courseCode} — ${e.title} (${e.units} units) from this registration? The engine refuses where a mark is recorded or the registration is locked.`)) void regAct("drop", e.offeringId); }}>Drop</Btn> : <span key="d" />,
                ])} /> : <div className="sub2">Nothing registered yet for this semester.</div>}
              </PBody>
              <PBody>
                <div className="eyebrow">Eligible courses — the engine&rsquo;s own menu for this student</div>
                {reg.view.menu.length ? <DTable pageSize={0} noPrint cols={["Code|mid", "Title", "Units|mid", "Basis|mid", "Owner", "Note", "|num"]} rows={reg.view.menu.map((m) => {
                  const on = reg.view.registration?.entries.some((e) => e.offeringId === m.offering_id) ?? false;
                  return [
                    <b key="c" className="tnum">{m.course_code}</b>, <span key="t">{m.title}</span>, <span key="u" className="tnum">{m.units}</span>, <span key="b" className="sub2">{m.basis}</span>, <span key="o" className="sub2">{m.owner_dept}</span>,
                    <span key="n" className="sub2">{on ? "Already registered" : m.gstLocked ? `GST fee: ${m.gstGate ?? "not paid"}` : m.carryover ? `Carry-over (failed in ${m.failed_in ?? "—"})` : m.deferred ? "Deferred course" : "Eligible"}</span>,
                    reg.manage && !on && !m.gstLocked ? <Btn key="a" kind="primary" size="sm" disabled={busy} onClick={() => void regAct("add", m.offering_id)}>Add</Btn> : <span key="a" />,
                  ];
                })} /> : <div className="sub2">The engine offers no course for this student in this semester — no offering is open, or the structure has nothing at this level.</div>}
                {reg.manage && reg.view.registration && ["DRAFT", "RETURNED"].includes(reg.view.registration.status) ? <div className="row mt-2"><Btn kind="secondary" disabled={busy} onClick={() => { if (window.confirm("Submit this registration for the department's approval? The engine checks the fees, the units and the GST gate.")) void regAct("submit"); }}>Submit the registration</Btn><span className="sub2">A submitted registration is returned only by the department&rsquo;s level adviser; the desk does not reopen it.</span></div> : null}
              </PBody>
              <PBody>
                <div className="eyebrow">Registration history</div>
                {reg.history?.length ? <DTable pageSize={0} noPrint cols={["Session", "Semester|mid", "Level|mid", "Status|mid", "Units|mid", "Submitted", "Approved", "Courses"]} rows={reg.history.map((h) => [
                  <span key="s" className="tnum">{h.session}</span>, <span key="m" className="tnum">{sem(h.semester)}</span>, <span key="l" className="tnum">{h.level}</span>, <span key="st" className="sub2">{h.status.toLowerCase()}</span>,
                  <span key="u" className="tnum">{h.units ?? ""}</span>, <span key="sb" className="sub2">{day(h.submitted_at)}</span>, <span key="ap" className="sub2">{day(h.approved_at)}</span>,
                  <span key="c" className="sub2">{(h.entries ?? []).map((e) => e.courseCode).join(", ")}</span>,
                ])} /> : <div className="sub2">No earlier registration.</div>}
              </PBody>
            </>
          )}
        </Panel>
      ) : null}

      {tab === "payments" && caps.has("VIEW_PAYMENTS") ? (
        <Panel title="Payments" right="Read only — the Bursary resolves a payment; escalate the ticket to it">
          {pay === null ? <PBody><div className="sub2">Reading the position…</div></PBody> : (
            <>
              {pay.fees ? <PBody><div className="row row--base" style={{ flexWrap: "wrap", gap: "var(--s-4)" }}>
                {Object.entries(pay.fees).filter(([k]) => ["session", "charged", "paid", "balance", "cleared", "clearsRegistration", "status"].includes(k)).map(([k, v]) => <span key={k}><span className="sub2">{k}</span> <b className="tnum">{typeof v === "number" ? naira(v) : String(v)}</b></span>)}
              </div></PBody> : null}
              <DTable pageSize={0} noPrint cols={["Reference|mid", "Session", "Purpose", "Amount|num", "Generated", "Confirmed", "Channel", "Receipt|mid"]} rows={pay.references.map((r, i) => [
                <span key={"r" + i} className="tnum">{String(r.reference)}</span>, <span key={"s" + i} className="tnum">{String(r.session ?? "")}</span>, <span key={"p" + i}>{String(r.purpose ?? "")}</span>,
                <span key={"a" + i} className="tnum">{naira(r.amount)}</span>, <span key={"g" + i} className="sub2">{day(r.generated_at as string)}</span>,
                <span key={"c" + i}>{r.confirmed_at ? <Pil kind="ok">{day(r.confirmed_at as string)}</Pil> : <Pil kind="warn">not confirmed</Pil>}</span>,
                <span key={"ch" + i} className="sub2">{String(r.channel ?? "")}</span>, <span key={"rc" + i} className="tnum">{String(r.receipt_no ?? "—")}</span>,
              ])} />
            </>
          )}
        </Panel>
      ) : null}

      {tab === "documents" && caps.has("VIEW_DOCUMENTS") ? (
        <div className="grid grid--2">
          <Panel title="Admission documents">
            {docs === null ? <PBody><div className="sub2">Reading…</div></PBody> : docs.admission.length ? <DTable pageSize={0} noPrint cols={["Kind", "Detail", "Source", "Received", "Status|mid"]} rows={docs.admission.map((d, i) => [<span key={"k" + i}>{String(d.kind)}</span>, <span key={"d" + i} className="sub2">{String(d.detail ?? "")}</span>, <span key={"s" + i} className="sub2">{String(d.source ?? "")}</span>, <span key={"r" + i} className="sub2">{day(d.received_on as string)}</span>, <span key={"st" + i} className="sub2">{String(d.status ?? "")}</span>])} /> : <PBody><div className="sub2">None on record.</div></PBody>}
          </Panel>
          <Panel title="Issued documents and receipts">
            {docs === null ? <PBody><div className="sub2">Reading…</div></PBody> : (
              <>
                {docs.issued.length ? <DTable pageSize={0} noPrint cols={["Document", "Issued", "Office", "Code|mid"]} rows={docs.issued.map((d, i) => [<span key={"k" + i}>{String(d.kind).replace(/_/g, " ")}{d.revoked ? <Pil kind="bad" className="ml-1">revoked</Pil> : null}</span>, <span key={"o" + i} className="sub2">{day(d.issued_on as string)}</span>, <span key={"f" + i} className="sub2">{String(d.issued_office ?? "")}</span>, <span key={"c" + i} className="tnum sub2">{String(d.verification_code ?? "")}</span>])} /> : <PBody><div className="sub2">No document issued yet.</div></PBody>}
                {docs.receipts.length ? <DTable pageSize={0} noPrint cols={["Receipt|mid", "Session", "Purpose", "Amount|num", "Paid"]} rows={docs.receipts.map((r, i) => [<span key={"r" + i} className="tnum">{String(r.receipt_no)}</span>, <span key={"s" + i} className="tnum">{String(r.session ?? "")}</span>, <span key={"p" + i}>{String(r.purpose ?? "")}</span>, <span key={"a" + i} className="tnum">{naira(r.amount)}</span>, <span key={"c" + i} className="sub2">{day(r.confirmed_at as string)}</span>])} /> : null}
              </>
            )}
          </Panel>
        </div>
      ) : null}

      {tab === "history" ? (
        <>
          <Panel title="Support acts on this record" right="The desk's ledger — who, for which ticket, what changed, why">
            {data.actions.length ? <DTable pageSize={0} noPrint cols={["When", "Agent", "Act", "Field", "From → to", "Reason", "Ticket|mid"]} rows={data.actions.map((x) => [
              <span key="w" className="sub2 tnum">{when(x.at)}</span>, <span key="a">{x.agent}<div className="sub2">{x.agent_office}</div></span>, <span key="k"><b>{ACTION_WORD[x.action] ?? x.action}</b>{x.session ? <div className="sub2 tnum">{x.session} · semester {x.semester}</div> : null}</span>,
              <span key="f" className="sub2">{x.field ?? ""}</span>, <span key="v" className="tnum">{x.old_value ?? "—"} → <b>{x.new_value ?? "—"}</b></span>, <span key="r" className="sub2">{x.reason}</span>,
              x.ticket_id ? <Link key="t" href={`/helpdesk/tickets/${x.ticket_id}`} className="lnk tnum">{x.ticket_number}</Link> : <span key="t" className="sub2">—</span>,
            ])} /> : <PBody><div className="sub2">No support act on this record yet.</div></PBody>}
          </Panel>
          <div className="grid grid--2">
            <Panel title="Status history and Registry decisions">
              {data.record.statusHistory.length || data.record.decidedChanges.length ? <DTable pageSize={0} noPrint cols={["When", "What", "Detail"]} rows={[
                ...data.record.statusHistory.map((h) => [<span key="w" className="sub2">{day(h.effectiveOn)}</span>, <span key="k">{statusWord(h.fromStatus ?? "")} → <b>{statusWord(h.toStatus)}</b></span>, <span key="d" className="sub2">{h.instrument ?? ""}{h.reason ? ` · ${h.reason}` : ""}</span>]),
                ...data.record.decidedChanges.map((c) => [<span key="w" className="sub2">{day(c.decidedAt)}</span>, <span key="k">{c.label}: {c.fromValue ?? "—"} → <b>{c.toValue}</b></span>, <span key="d" className="sub2">{c.state.toLowerCase()}{c.decision ? ` · ${c.decision}` : ""}</span>]),
              ]} /> : <PBody><div className="sub2">Nothing on record.</div></PBody>}
            </Panel>
            <Panel title="Audit trail" right="Every attributed write on this record">
              {data.history.length ? <DTable pageSize={0} noPrint cols={["When", "Who", "Action", "Reason"]} rows={data.history.map((h, i) => [<span key={"w" + i} className="sub2 tnum">{when(h.occurred_at)}</span>, <span key={"a" + i}>{h.actor_name ?? "—"}<div className="sub2">{h.actor_office}</div></span>, <span key={"k" + i} className="sub2">{h.action}<div className="tnum">{h.subject_type}</div></span>, <span key={"r" + i} className="sub2">{h.reason ?? ""}</span>])} /> : <PBody><div className="sub2">No entry yet.</div></PBody>}
            </Panel>
          </div>
        </>
      ) : null}

      {tab === "tickets" ? (
        <Panel title="The student's tickets" right={<LinkBtn size="sm" href={`/helpdesk?q=${encodeURIComponent(s.matricNo ?? s.surname)}`}>Find on the desk</LinkBtn>}>
          {data.tickets.length ? <DTable pageSize={0} noPrint cols={["Number|mid", "Subject", "Category", "Status|mid", "Priority|mid", "Agent", "Updated", "|num"]} rows={data.tickets.map((t) => [
            <span key="n" className="tnum">{t.number}</span>, <span key="s">{t.subject}</span>, <span key="c" className="sub2">{t.category}</span>, <Pil key="st" kind={t.status === "RESOLVED" || t.status === "CLOSED" ? "grey" : "warn"}>{t.status.toLowerCase().replace(/_/g, " ")}</Pil>,
            <span key="p" className="sub2">{t.priority.toLowerCase()}</span>, <span key="a" className="sub2">{t.agent ?? "—"}</span>, <span key="u" className="sub2">{when(t.updated_at)}</span>,
            <span key="o" className="row row--inline row--tight row--right"><LinkBtn size="sm" href={`/helpdesk/tickets/${t.id}`}>Open</LinkBtn><LinkBtn size="sm" kind="primary" href={`/helpdesk/students/${id}?ticket=${t.id}`}>Work from it</LinkBtn></span>,
          ])} /> : <PBody><div className="sub2">The student has raised no ticket.</div></PBody>}
        </Panel>
      ) : null}

      {edit ? (
        <Modal title={edit.tier === "approval" ? `Request a change of ${edit.label.toLowerCase()}` : `Edit ${edit.label.toLowerCase()}`} sub={edit.tier === "approval" ? "Goes to the Registry's biodata queue as a request; nothing changes until it decides" : `Written to the record in your name, with the reason${ticket ? `, on ${ticket.number}` : ""}; the student is told`} onClose={() => setEdit(null)}
          foot={<><Btn kind="ghost" onClick={() => setEdit(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !edit.value.trim() || edit.reason.trim().length < 5} onClick={async () => { const j = await call("PUT", `/biodata/${edit.field}`, { value: edit.value.trim(), reason: edit.reason.trim(), ticket: ticket?.id ?? null }, `${edit.label} ${edit.tier === "approval" ? "change requested" : "updated"}`); if (j) { setEdit(null); router.refresh(); } }}>{edit.tier === "approval" ? "Send to the Registry" : "Save"}</Btn></>}>
          <div className="stack">
            <Field id="ed-value" label={edit.label} required><input id="ed-value" className="ctl" value={edit.value} onChange={(e) => setEdit({ ...edit, value: e.target.value })} maxLength={4000} /></Field>
            <Field id="ed-reason" label="Reason" required hint="What the student reported, and the evidence sighted"><input id="ed-reason" className="ctl" value={edit.reason} onChange={(e) => setEdit({ ...edit, reason: e.target.value })} maxLength={2000} /></Field>
          </div>
        </Modal>
      ) : null}
      {photo ? (
        <Modal title="Replace the passport photograph" sub="JPEG or PNG up to 2 MB; previewed before it is saved; the student is told" onClose={() => setPhoto(null)}
          foot={<><Btn kind="ghost" onClick={() => setPhoto(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !photo.dataUrl || photo.reason.trim().length < 5} onClick={async () => { const j = await call("PUT", "/passport", { dataUrl: photo.dataUrl, reason: photo.reason.trim(), ticket: ticket?.id ?? null }, "Photograph replaced"); if (j) { setPhoto(null); setPhotoVersion((v) => v + 1); router.refresh(); } }}>Save</Btn></>}>
          <div className="stack">
            <Field id="ph-file" label="Photograph" required><input id="ph-file" className="ctl" type="file" accept="image/jpeg,image/png" onChange={(e) => { const f = e.target.files?.[0]; if (!f) return; const rd = new FileReader(); rd.onload = () => setPhoto({ ...photo, dataUrl: String(rd.result) }); rd.readAsDataURL(f); }} /></Field>
            {photo.dataUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={photo.dataUrl} alt="Preview of the replacement photograph" style={{ width: 140, height: 160, objectFit: "cover", borderRadius: "var(--r-md)", border: "1px solid var(--line)" }} />
            ) : null}
            <Field id="ph-reason" label="Reason" required><input id="ph-reason" className="ctl" value={photo.reason} onChange={(e) => setPhoto({ ...photo, reason: e.target.value })} maxLength={2000} /></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
