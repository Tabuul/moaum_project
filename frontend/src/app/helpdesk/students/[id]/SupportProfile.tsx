"use client";
/** One student in support mode (V334, V346). The banner says who is acting for whom and on which ticket; the Support Action
 *  Center offers only what the agent's postings allow on this student; the tabs show the record the Registry's screens
 *  show, the registration through the engine's own view — every course added or dropped after the engine's rules are
 *  shown and judged, the window and the menu set aside only by a recorded support override on the ticket — the payments
 *  with their diagnosis, the documents, the Support Action History and the tickets. Every change takes a reason; the ticket
 *  opened from is carried on every act; what the postings do not carry is not offered, and the server refuses it anyway. */
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tabs } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { statusWord } from "@/lib/cohorts";
import {
  ACTION_WORD, MODULE_WORD, OFFICE_WORD, RESULT_WORD, SECTION_WORD, SENSITIVE, capabilityFor,
  type Checks, type CurrentRegistration, type Rule, type SupportProfile as Profile,
} from "@/lib/support";
import type { RegistrationView } from "@/lib/student-portal";
import type { GstEpsExplain } from "@/lib/gst";
import { GstEligibilityView } from "@/components/gst/GstEligibilityView";

type Tab = "profile" | "registration" | "payments" | "documents" | "history" | "tickets";
const TABS: Tab[] = ["profile", "registration", "payments", "documents", "history", "tickets"];
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
const naira = (v: unknown) => (v == null || v === "" ? "—" : `₦${Number(v).toLocaleString("en-NG", { minimumFractionDigits: 2 })}`);
const sem = (n: number) => (n === 1 ? "First" : n === 2 ? "Second" : "Third");
type Problem = Parameters<typeof notifyProblem>[0];

interface HistoryRow { id: string; session: string; semester: number; status: string; level: number; units?: number; submitted_at?: string | null; approved_at?: string | null; entries?: { courseCode: string; title: string; units: number; status: string }[] }
interface Reg { view: RegistrationView; current: CurrentRegistration; issues: string[]; history: { history?: HistoryRow[] } | HistoryRow[]; manage: boolean; override: boolean }
interface Pay { fees: Record<string, unknown> | null; session: string; capabilities: string[]; gstEps?: GstEpsExplain | null; references: { reference: string; session: string; purpose: string; amount: number; generated_at: string; confirmed_at: string | null; channel: string | null; receipt_no: string | null; status: string; gateway: string | null; gateway_ref: string | null; gateway_outcome: string | null }[] }
interface Docs { admission: Record<string, unknown>[]; issued: Record<string, unknown>[]; receipts: Record<string, unknown>[] }
interface CourseAct { verb: "add" | "drop" | "restore"; offering: string; code: string; title: string; units: number; checks: Checks | null; reason: string; override: boolean; description: string }
interface TicketField { key: string; label: string; type?: string; required?: boolean; options?: string[]; hint?: string }

/** the engine's rules for one course, judged: what passes, what blocks, what an override may set aside, what only informs */
function RulesTable({ rules }: { rules: Rule[] }) {
  return (
    <DTable pageSize={0} noPrint cols={["Rule", "Judged|mid", "What the engine says"]} rows={rules.map((r) => [
      <span key="l">{r.label}</span>,
      r.advisory ? <Pil key="p" kind="info">Note</Pil> : r.passed ? <Pil key="p" kind="ok">Passes</Pil> : r.overridable ? <Pil key="p" kind="warn">Blocks — override may apply</Pil> : <Pil key="p" kind="bad">Blocks</Pil>,
      <span key="m" className="sub2">{r.message}</span>,
    ])} />
  );
}

export function SupportProfile({ id, data, tab }: { id: string; data: Profile; tab: string }) {
  const router = useRouter();
  const go = useQueryNav();
  const s = data.record.student;
  const caps = new Set(data.capabilities);
  const centre = new Set(data.center.map((c) => c.code));
  const portal = data.portal as Record<string, unknown>;
  const pos = data.position as Record<string, unknown> | null;
  const ticket = data.ticket;
  const fullName = `${s.surname}, ${s.otherNames}`;
  const [busy, setBusy] = useState(false);
  const [edit, setEdit] = useState<{ field: string; label: string; value: string; reason: string; tier: string } | null>(null);
  const [photo, setPhoto] = useState<{ dataUrl: string; reason: string } | null>(null);
  const [photoVersion, setPhotoVersion] = useState(0);
  const [reg, setReg] = useState<Reg | null>(null);
  const [regSel, setRegSel] = useState<{ session: string; semester: string }>({ session: String(data.academic?.session ?? portal.session ?? ""), semester: String(data.academic?.semester ?? 1) });
  const [pay, setPay] = useState<Pay | null>(null);
  const [docs, setDocs] = useState<Docs | null>(null);
  const [course, setCourse] = useState<CourseAct | null>(null);
  const [submit, setSubmit] = useState<{ reason: string; override: boolean; description: string } | null>(null);
  const [find, setFind] = useState<{ q: string; rows: { offering_id: string; course_code: string; title: string; units: number; level: number; kind: string; department: string | null }[] } | null>(null);
  const [reset, setReset] = useState<{ method: "LINK" | "TEMPORARY"; reason: string; result: Record<string, unknown> | null } | null>(null);
  const [raise, setRaise] = useState<{ category: string; subject: string; description: string; details: Record<string, string> } | null>(null);
  const [escalate, setEscalate] = useState<{ office: string; reason: string } | null>(null);
  const [resolve, setResolve] = useState<{ summary: string; details: string } | null>(null);
  const tabNow: Tab = (TABS as string[]).includes(tab) ? (tab as Tab) : "profile";
  /** the latest course search typed: an answer to an earlier keystroke that arrives late is dropped */
  const searchSeq = useRef(0);

  async function call(method: "POST" | "PUT", path: string, body: unknown, reason: string, quiet = false): Promise<Record<string, unknown> | null> {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/helpdesk/support/students/${id}${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = (await r.json().catch(() => null)) as Record<string, unknown> | null;
      if (!r.ok) { notifyProblem(j ? (j as unknown as Problem) : { status: r.status, title: r.statusText } as Problem); return null; }
      if (!quiet) notify(reason);
      return j;
    } finally { setBusy(false); }
  }
  function openTab(t: Tab) {
    go(`/helpdesk/students/${id}?tab=${t}${ticket ? `&ticket=${encodeURIComponent(ticket.id)}` : ""}`);
  }
  /** a tab's data is read when the tab is opened, once; the registration again when the session or semester changes or after an act */
  function loadReg(session: string, semester: string) {
    setRegSel({ session, semester });
    setReg(null);
  }
  useEffect(() => {
    if (tabNow !== "registration" || reg !== null) return;
    let alive = true;
    void fetch(`/api/bff/api/v1/helpdesk/support/students/${id}/registration?session=${encodeURIComponent(regSel.session)}&semester=${regSel.semester}`).then(async (r) => {
      const j = (await r.json().catch(() => null)) as Reg | null;
      if (!alive) return;
      if (!r.ok) { notifyProblem((j as unknown as Problem) ?? ({ status: r.status, title: r.statusText } as Problem)); return; }
      setReg(j);
    });
    return () => { alive = false; };
  }, [tabNow, reg, regSel, id]);
  useEffect(() => {
    if (tabNow !== "payments" || pay !== null) return;
    let alive = true;
    void fetch(`/api/bff/api/v1/helpdesk/support/students/${id}/payments`).then(async (r) => { const j = (await r.json().catch(() => null)) as Pay | null; if (alive && r.ok) setPay(j); });
    return () => { alive = false; };
  }, [tabNow, pay, id]);
  useEffect(() => {
    if (tabNow !== "documents" || docs !== null) return;
    let alive = true;
    void fetch(`/api/bff/api/v1/helpdesk/support/students/${id}/documents`).then(async (r) => { const j = (await r.json().catch(() => null)) as Docs | null; if (alive && r.ok) setDocs(j); });
    return () => { alive = false; };
  }, [tabNow, docs, id]);

  /* ── course registration: every act after the engine's rules are read ── */
  async function openCourse(verb: "add" | "drop" | "restore", offering: string, code: string, title: string, units: number) {
    if (!reg) return;
    setCourse({ verb, offering, code, title, units, checks: null, reason: "", override: false, description: "" });
    const r = await fetch(`/api/bff/api/v1/helpdesk/support/students/${id}/registration/checks?session=${encodeURIComponent(reg.view.session)}&semester=${reg.view.semester}&offering=${offering}&verb=${verb === "drop" ? "drop" : "add"}`);
    const j = (await r.json().catch(() => null)) as Checks | null;
    if (!r.ok || !j) { notifyProblem((j as unknown as Problem) ?? ({ status: r.status, title: r.statusText } as Problem)); setCourse(null); return; }
    setCourse((c) => (c && c.offering === offering ? { ...c, checks: j, override: !j.allowed && j.overridable && j.mayOverride } : c));
  }
  async function confirmCourse() {
    if (!course || !reg) return;
    const label = course.verb === "drop" ? `${course.code} dropped` : course.verb === "restore" ? `${course.code} restored` : `${course.code} added`;
    const j = await call("POST", `/registration/${course.verb}`, {
      session: reg.view.session, semester: reg.view.semester, offering: course.offering, reason: course.reason.trim(), ticket: ticket?.id ?? null,
      override: course.override, description: course.override ? course.description.trim() : null,
    }, course.override ? `${label} by support override` : label);
    if (j) { setCourse(null); setReg(null); router.refresh(); }
  }
  async function confirmSubmit() {
    if (!submit || !reg) return;
    const j = await call("POST", "/registration/submit", { session: reg.view.session, semester: reg.view.semester, reason: submit.reason.trim(), ticket: ticket?.id ?? null, override: submit.override, description: submit.override ? submit.description.trim() : null },
      submit.override ? "Registration submitted by support override" : "Registration submitted");
    if (j) { setSubmit(null); setReg(null); router.refresh(); }
  }
  async function searchOfferings(q: string) {
    if (!reg) return;
    const n = ++searchSeq.current;
    setFind({ q, rows: q.trim().length < 2 ? [] : find?.rows ?? [] });
    if (q.trim().length < 2) return;
    const r = await fetch(`/api/bff/api/v1/helpdesk/support/students/${id}/registration/offerings?session=${encodeURIComponent(reg.view.session)}&semester=${reg.view.semester}&q=${encodeURIComponent(q.trim())}`);
    const rows = r.ok ? await r.json() : null;
    if (rows && n === searchSeq.current) setFind({ q, rows });
  }

  /* ── password, tickets ── */
  async function confirmReset() {
    if (!reset) return;
    const j = await call("POST", "/password", { method: reset.method, reason: reset.reason.trim(), ticket: ticket?.id ?? null }, reset.method === "LINK" ? "Password reset link sent" : "Temporary password issued", true);
    if (j) { setReset({ ...reset, result: j }); router.refresh(); }
  }
  const category = raise ? data.categories.find((c) => c.code === raise.category) : undefined;
  const categoryFields: TicketField[] = (() => { try { return category ? (JSON.parse(category.fields) as TicketField[]) : []; } catch { return []; } })();
  async function confirmRaise() {
    if (!raise) return;
    const j = await call("POST", "/tickets", { category: raise.category, subject: raise.subject.trim(), description: raise.description.trim(), details: raise.details }, "Ticket raised for the student");
    if (j) { setRaise(null); go(`/helpdesk/students/${id}?tab=tickets&ticket=${encodeURIComponent(String(j.id))}`); router.refresh(); }
  }
  async function confirmEscalate() {
    if (!escalate || !ticket) return;
    const j = await call("POST", "/escalate", { ticket: ticket.id, office: escalate.office, reason: escalate.reason.trim() }, `Escalated to ${OFFICE_WORD[escalate.office] ?? escalate.office}`);
    if (j) { setEscalate(null); router.refresh(); }
  }
  async function confirmResolve() {
    if (!resolve || !ticket) return;
    setBusy(true);
    try {
      // the desk resolves a ticket that is being worked: one still new or merely opened is moved to in progress first, as the ticket screen does
      for (const to of ticket.status === "SUBMITTED" ? ["OPENED", "IN_PROGRESS"] : ["OPENED", "REOPENED", "WAITING_FOR_STUDENT"].includes(ticket.status) ? ["IN_PROGRESS"] : []) {
        const st = await fetch(`/api/bff/api/v1/helpdesk/tickets/${ticket.id}/status`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${ticket.number}: worked from the student's record`) }, body: JSON.stringify({ status: to, reason: "Worked from the student's record" }) });
        if (!st.ok) { notifyProblem((await st.json().catch(() => null)) ?? { status: st.status, title: st.statusText }); return; }
      }
      const r = await fetch(`/api/bff/api/v1/helpdesk/tickets/${ticket.id}/resolve`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${ticket.number} resolved`) }, body: JSON.stringify({ summary: resolve.summary.trim(), details: resolve.details.trim() }) });
      if (!r.ok) { notifyProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }); return; }
      notify(`${ticket.number} resolved; the student is asked to confirm`);
      setResolve(null);
      router.refresh();
    } finally { setBusy(false); }
  }
  function openResolve() {
    if (!ticket) return;
    const acts = data.actions.filter((a) => a.ticket_id === ticket.id && a.action !== "TICKET_CREATED");
    const done = acts.map((a) => a.summary ?? ACTION_WORD[a.action] ?? a.action);
    // the summary is the act the ticket was about: a course for a registration ticket, a payment for a payment ticket, a reset for a login one
    const kindOf = ({ REGISTRATION: "COURSE_REGISTRATION", PAYMENT: "PAYMENT", GST: "PAYMENT", LOGIN: "AUTHENTICATION", ACCOUNT: "AUTHENTICATION" } as Record<string, string>)[ticket.category_code];
    const main = acts.find((a) => a.module === kindOf) ?? acts[0];
    setResolve({ summary: main ? (main.summary ?? ACTION_WORD[main.action] ?? main.action).slice(0, 300) : "", details: done.length ? `Action taken:\n${done.map((d) => `- ${d}`).join("\n")}` : "" });
  }

  /* ── the Support Action Center ── */
  function centreAct(code: string) {
    switch (code) {
      case "RESET_PASSWORD": setReset({ method: "LINK", reason: "", result: null }); break;
      case "CREATE_TICKET": setRaise({ category: data.categories[0]?.code ?? "", subject: "", description: "", details: {} }); break;
      case "ESCALATE": if (ticket) setEscalate({ office: data.escalateTo[0] ?? "bursar", reason: "" }); else notifyProblem({ status: 422, title: "Escalation is made on a ticket", detail: "Open the student from their ticket, or raise one for them first." } as Problem); break;
      case "VIEW_REGISTRATION": case "ADD_COURSE": case "DROP_COURSE": case "OVERRIDE_REGISTRATION": openTab("registration"); break;
      case "INVESTIGATE_PAYMENT": case "VERIFY_PAYMENT": case "REFRESH_ENTITLEMENT": case "REGENERATE_RECEIPT": openTab("payments"); break;
      case "VIEW_DOCUMENTS": openTab("documents"); break;
      case "VIEW_TICKETS": openTab("tickets"); break;
      case "EDIT_RECORD": openTab("profile"); document.getElementById("sp-record")?.scrollIntoView({ behavior: "smooth" }); break;
    }
  }

  const sections = ["personal", "contact", "origin", "family", "academic", "other"];
  const bySection = (sec: string) => data.record.biodata.filter((b) => (sections.includes(b.section) ? b.section : "other") === sec).sort((a, b) => a.ord - b.ord);
  const mayEdit = (b: { tier: string; section: string; field: string }) => { const c = capabilityFor(b.tier, b.section, b.field); return c ? caps.has(c) : false; };
  const asksRegistry = (b: { tier: string; field: string }) => b.tier === "approval" || SENSITIVE.has(b.field);
  const history: HistoryRow[] = reg ? (Array.isArray(reg.history) ? reg.history : reg.history.history ?? []) : [];
  const live = reg?.current.courses.filter((c) => c.status !== "DROPPED") ?? [];
  const regStatus = reg?.current.registration?.status ?? null;

  return (
    <>
      <Note kind="info" title="SUPPORT MODE — you are managing this student's record on behalf of the student"
        action={ticket ? <span className="row row--inline row--tight">
          <Btn kind="secondary" disabled={busy} onClick={() => setEscalate({ office: data.escalateTo[0] ?? "bursar", reason: "" })}>Escalate</Btn>
          <Btn kind="primary" disabled={busy || ticket.status === "RESOLVED" || ticket.status === "CLOSED"} onClick={openResolve}>Resolve ticket</Btn>
        </span> : undefined}>
        <span className="row row--inline" style={{ gap: "var(--s-4)", flexWrap: "wrap" }}>
          <span><b>Agent</b> {data.agent}</span>
          <span><b>Student</b> {fullName} · <span className="tnum">{s.matricNo ?? s.admissionNo ?? id}</span></span>
          <span><b>Ticket</b> {ticket ? <Link href={`/helpdesk/tickets/${ticket.id}`} className="lnk tnum">{ticket.number}</Link> : <span className="sub2">none — give a reason with every change</span>}{ticket ? <span className="sub2"> · {ticket.status.toLowerCase().replace(/_/g, " ")}</span> : null}</span>
          <span><b>Reason for access</b> {ticket ? `${ticket.category}: ${ticket.subject}` : "Student support"}</span>
          <span><b>Since</b> {when(data.openedAt)}</span>
          <span><b>Scope</b> {data.scope || "—"}</span>
        </span>
      </Note>

      <PageHead title={fullName} eyebrow={<span className="tnum">{s.matricNo ?? "No matriculation number"}{s.jambRegNo ? ` · JAMB ${s.jambRegNo}` : ""}{data.academic?.application_no ? ` · Application ${data.academic.application_no}` : ""}</span>}
        description={<>{s.programmeName} · {s.deptName ?? s.deptCode} · {s.facultyName ?? ""} · {s.currentLevel} Level · <Pil kind={s.status === "ACTIVE" ? "ok" : s.status === "GRADUATED" ? "info" : "grey"}>{statusWord(s.status)}</Pil>{pos?.classification ? <> <Pil kind={String(pos.classification) === "ACTIVE" ? "ok" : String(pos.classification).includes("SPILLOVER") ? "warn" : "grey"}>{String(pos.classification).charAt(0) + String(pos.classification).slice(1).toLowerCase().replace(/_/g, " ")}</Pil></> : null}</>}
        actions={<><LinkBtn href="/helpdesk/students">Student Support</LinkBtn>{ticket ? <LinkBtn href={`/helpdesk/tickets/${ticket.id}`}>Back to the ticket</LinkBtn> : null}<LinkBtn href="/helpdesk">Support Desk</LinkBtn></>} />

      <Panel title="Support actions" right="Only what your postings allow on this student — the server checks every act again">
        <PBody>
          <div className="row row--inline" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
            {data.center.map((c) => (
              <Btn key={c.code} kind={["RESET_PASSWORD", "CREATE_TICKET", "ESCALATE"].includes(c.code) ? "secondary" : "ghost"} disabled={busy || (c.code === "ESCALATE" && !ticket)} onClick={() => centreAct(c.code)}
                title={c.code === "ESCALATE" && !ticket ? "Escalation is made on a ticket" : undefined}>{c.label}</Btn>
            ))}
          </div>
        </PBody>
      </Panel>

      <Tabs label="Section" value={tabNow} onChange={(v) => openTab(v)} items={[
        { id: "profile", label: "Profile" }, { id: "registration", label: "Course registration" },
        ...(caps.has("VIEW_PAYMENTS") || caps.has("INVESTIGATE_PAYMENT") ? [{ id: "payments" as Tab, label: "Payments" }] : []),
        ...(caps.has("VIEW_DOCUMENTS") ? [{ id: "documents" as Tab, label: "Documents" }] : []),
        { id: "history", label: "Support history", count: data.actions.length }, { id: "tickets", label: "Tickets", count: data.tickets.length },
      ]} />

      {tabNow === "profile" ? (
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
                {([["Student ID", id], ["Matriculation number", s.matricNo], ["JAMB registration", s.jambRegNo], ["Application number", data.academic?.application_no], ["Admission number", s.admissionNo],
                  ["Faculty", s.facultyName], ["Department", s.deptName], ["Programme", `${s.programmeName} (${s.programmeCode})`], ["Level", s.currentLevel], ["Entry mode", s.entryMode],
                  ["Admission session", s.entrySession], ["Current session", data.academic?.session ?? portal.session ?? pos?.current_session], ["Current semester", data.academic?.semester ? `${sem(data.academic.semester)} semester` : null],
                  ["Status", statusWord(s.status)], ["Effective cohort", pos?.effective_cohort], ["Expected completion", pos?.expected_completion], ["Standing", portal.standing ?? "—"], ["CGPA", portal.cgpa ?? "—"]] as [string, unknown][]).map(([k, v]) => (
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
          {portal.fees && typeof portal.fees === "object" ? (
            <Panel title="Payment summary" right={<LinkBtn size="sm" href={`/helpdesk/students/${id}?tab=payments${ticket ? `&ticket=${encodeURIComponent(ticket.id)}` : ""}`}>Payments</LinkBtn>}>
              <PBody><div className="row row--base" style={{ flexWrap: "wrap", gap: "var(--s-4)" }}>
                {Object.entries(portal.fees as Record<string, unknown>).filter(([k]) => ["session", "charged", "paid", "balance", "clearsRegistration"].includes(k)).map(([k, v]) => (
                  <span key={k}><span className="sub2">{k === "clearsRegistration" ? "Cleared for registration" : k.charAt(0).toUpperCase() + k.slice(1)}</span> <b className="tnum">{typeof v === "number" ? naira(v) : typeof v === "boolean" ? (v ? "Yes" : "No") : String(v ?? "—")}</b></span>
                ))}
              </div></PBody>
            </Panel>
          ) : null}
          <div id="sp-record" />
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
            <PBody><div className="sub2">Name, date of birth, gender and nationality beyond a Registry request; the matriculation and JAMB numbers; the admission decision; the programme, department and faculty; the student&rsquo;s status and graduation; results, grades, CGPA and transcripts; any payment, amount, fee or refund. Escalate the ticket to the office that owns it — the Registry, Examinations and Records, the Academic Office or the Bursary.</div></PBody>
          </Panel>
        </>
      ) : null}

      {tabNow === "registration" ? (
        <Panel title="Manage course registration" right={<span className="row row--inline row--tight">
          <select className="ctl" value={regSel.session} onChange={(e) => loadReg(e.target.value, regSel.semester)} aria-label="Session">
            {Array.from(new Set([String(data.academic?.session ?? portal.session ?? ""), ...data.record.registrations.map((r) => r.session), ...data.record.enrolments.map((e) => e.session)].filter(Boolean))).map((x) => <option key={x} value={x}>{x}</option>)}
          </select>
          <select className="ctl" value={regSel.semester} onChange={(e) => loadReg(regSel.session, e.target.value)} aria-label="Semester"><option value="1">First semester</option><option value="2">Second semester</option><option value="3">Third semester</option></select>
        </span>}>
          {reg === null ? <PBody><div className="sub2">Reading the registration…</div></PBody> : (
            <>
              <PBody>
                <div className="row row--base" style={{ flexWrap: "wrap", gap: "var(--s-4)" }}>
                  <span><b>{reg.view.session}</b> · {sem(reg.view.semester)} semester · {reg.view.level} Level</span>
                  <span>Status <Pil kind={regStatus ? (regStatus === "APPROVED" || regStatus === "LOCKED" ? "ok" : regStatus === "RETURNED" ? "bad" : "warn") : "grey"}>{regStatus ? regStatus.toLowerCase() : "not started"}</Pil></span>
                  <span>Window <Pil kind={reg.view.window?.open ? "ok" : "bad"}>{reg.view.window?.open ? "open" : "closed"}</Pil></span>
                  <span>Fees <Pil kind={reg.view.clears ? "ok" : "warn"}>{reg.view.clears ? "cleared" : "not cleared"}</Pil></span>
                  <span className="sub2">Units {reg.current.registration?.units ?? 0} of {reg.view.limit.min_units}–{reg.view.limit.max_units}</span>
                  {reg.view.addDropOpen ? <Pil kind="info">Add/drop open</Pil> : null}
                  {reg.override ? <Pil kind="warn">Your postings carry the support override</Pil> : null}
                </div>
                {reg.issues.length ? <Note kind="bad" title="Outstanding registration issues">{reg.issues.map((x, i) => <span key={i} style={{ display: "block" }}>{x}</span>)}</Note> : <Note kind="ok" title="No outstanding registration issue">The engine raises nothing against this registration.</Note>}
                {!reg.manage ? <Note kind="info" title="Read only">Your postings do not carry course registration management for this student; the Head of the Support Desk grants it on the posting.</Note> : null}
              </PBody>
              <PBody>
                <div className="eyebrow">Current course registration</div>
                {reg.current.courses.length ? <DTable pageSize={0} noPrint cols={["Course code|mid", "Course title", "Units|mid", "Course type|mid", "Core/elective|mid", "Level|mid", "Semester|mid", "Registration status|mid", "Date registered", "|num"]} rows={reg.current.courses.map((c) => [
                  <b key="c" className="tnum">{c.course_code}</b>,
                  <span key="t">{c.title}{c.support_override_at ? <div><Pil kind="warn">Support override</Pil> <span className="sub2">{c.support_override_reason}</span></div> : null}{c.marked ? <div className="sub2">A mark is recorded — examination history</div> : null}</span>,
                  <span key="u" className="tnum">{c.units}</span>, <span key="ty" className="sub2">{c.entry_type.toLowerCase()}</span>, <span key="k" className="sub2">{c.basis}</span>,
                  <span key="l" className="tnum">{c.level}</span>, <span key="s" className="sub2">{sem(c.semester)}</span>,
                  <Pil key="st" kind={c.status === "DROPPED" ? "grey" : c.status === "APPROVED" ? "ok" : "info"}>{c.status.toLowerCase()}</Pil>,
                  <span key="d" className="sub2">{day(c.registered_at)}</span>,
                  reg.manage ? (c.status === "DROPPED"
                    ? <Btn key="a" kind="ghost" size="sm" disabled={busy} onClick={() => void openCourse("restore", c.offering_id, c.course_code, c.title, c.units)}>Restore</Btn>
                    : c.entry_type !== "CARRYOVER" && c.entry_type !== "DEFERRED" && !c.marked
                      ? <Btn key="a" kind="ghost" size="sm" disabled={busy} onClick={() => void openCourse("drop", c.offering_id, c.course_code, c.title, c.units)}>Drop</Btn> : <span key="a" />) : <span key="a" />,
                ])} /> : <div className="sub2">Nothing registered yet for this semester.</div>}
                {reg.manage && (!regStatus || ["DRAFT", "RETURNED"].includes(regStatus)) && live.length ? (
                  <div className="row mt-2"><Btn kind="secondary" disabled={busy} onClick={() => setSubmit({ reason: "", override: false, description: "" })}>Submit the registration</Btn><span className="sub2">The engine checks the fees, the units and the GST gate. A submitted registration is returned only by the department&rsquo;s level adviser.</span></div>
                ) : null}
              </PBody>
              <PBody>
                <div className="eyebrow">Eligible courses — the engine&rsquo;s own menu for this student</div>
                {reg.view.menu.length ? <DTable pageSize={0} noPrint cols={["Code|mid", "Title", "Units|mid", "Basis|mid", "Owner", "Note", "|num"]} rows={reg.view.menu.map((m) => {
                  const on = live.some((e) => e.offering_id === m.offering_id);
                  return [
                    <b key="c" className="tnum">{m.course_code}</b>, <span key="t">{m.title}</span>, <span key="u" className="tnum">{m.units}</span>, <span key="b" className="sub2">{m.basis}</span>, <span key="o" className="sub2">{m.owner_dept}</span>,
                    <span key="n" className="sub2">{on ? "Already registered" : m.gstLocked ? `GST fee: ${m.gstGate ?? "not paid"}` : m.carryover ? `Carry-over (failed in ${m.failed_in ?? "—"})` : m.deferred ? "Deferred course" : "Eligible"}</span>,
                    reg.manage && !on ? <Btn key="a" kind="primary" size="sm" disabled={busy} onClick={() => void openCourse("add", m.offering_id, m.course_code, m.title, m.units)}>Add course</Btn> : <span key="a" />,
                  ];
                })} /> : <div className="sub2">The engine offers no course for this student in this semester — no offering is open, or the structure has nothing at this level.</div>}
              </PBody>
              {reg.manage ? (
                <PBody>
                  <div className="eyebrow">A course missing from the menu</div>
                  <div className="sub2 mb-1">When a valid course is missing from the student&rsquo;s list — a course mapped wrongly, a portal fault — find it here. Its rules are shown before anything is done; the menu is set aside only by a support override on the student&rsquo;s ticket.</div>
                  <input className="ctl" type="search" placeholder="Course code or title offered this semester" value={find?.q ?? ""} onChange={(e) => void searchOfferings(e.target.value)} style={{ maxWidth: 420 }} />
                  {find?.rows.length ? <DTable pageSize={0} noPrint cols={["Code|mid", "Title", "Units|mid", "Level|mid", "Kind|mid", "Department", "|num"]} rows={find.rows.map((o) => [
                    <b key="c" className="tnum">{o.course_code}</b>, <span key="t">{o.title}</span>, <span key="u" className="tnum">{o.units}</span>, <span key="l" className="tnum">{o.level}</span>,
                    <span key="k" className="sub2">{o.kind}</span>, <span key="d" className="sub2">{o.department ?? ""}</span>,
                    <Btn key="a" kind="ghost" size="sm" disabled={busy} onClick={() => void openCourse("add", o.offering_id, o.course_code, o.title, o.units)}>Check and add</Btn>,
                  ])} /> : null}
                </PBody>
              ) : null}
              <PBody>
                <div className="eyebrow">Registration history — earlier sessions are history and are never changed here</div>
                {history.length ? <DTable pageSize={0} noPrint cols={["Session", "Semester|mid", "Level|mid", "Status|mid", "Units|mid", "Submitted", "Approved", "Courses"]} rows={history.map((h) => [
                  <span key="s" className="tnum">{h.session}</span>, <span key="m" className="tnum">{sem(h.semester)}</span>, <span key="l" className="tnum">{h.level}</span>, <span key="st" className="sub2">{h.status.toLowerCase()}</span>,
                  <span key="u" className="tnum">{h.units ?? ""}</span>, <span key="sb" className="sub2">{day(h.submitted_at)}</span>, <span key="ap" className="sub2">{day(h.approved_at)}</span>,
                  <span key="c" className="sub2">{(h.entries ?? []).map((e) => e.courseCode).join(", ")}</span>,
                ])} /> : <div className="sub2">No earlier registration.</div>}
              </PBody>
            </>
          )}
        </Panel>
      ) : null}

      {tabNow === "payments" && (caps.has("VIEW_PAYMENTS") || caps.has("INVESTIGATE_PAYMENT")) ? (
        <Panel title="Payments" right={caps.has("INVESTIGATE_PAYMENT") ? <LinkBtn size="sm" href={`/helpdesk/payments?q=${encodeURIComponent(s.matricNo ?? s.admissionNo ?? id)}${ticket ? `&ticket=${encodeURIComponent(ticket.id)}` : ""}`}>Payment Support</LinkBtn> : "Read only — the Bursary decides a payment"}>
          {pay === null ? <PBody><div className="sub2">Reading the position…</div></PBody> : (
            <>
              {pay.fees ? <PBody><div className="row row--base" style={{ flexWrap: "wrap", gap: "var(--s-4)" }}>
                {Object.entries(pay.fees).filter(([k]) => ["session", "charged", "paid", "balance", "cleared", "clearsRegistration", "status"].includes(k)).map(([k, v]) => <span key={k}><span className="sub2">{k}</span> <b className="tnum">{typeof v === "number" ? naira(v) : String(v)}</b></span>)}
              </div></PBody> : null}
              <DTable pageSize={0} noPrint cols={["Payment reference|mid", "Session", "Payment type", "Amount|num", "Generated", "Status|mid", "Gateway", "Receipt|mid", "|num"]} rows={pay.references.map((r) => [
                <span key="r" className="tnum">{r.reference}</span>, <span key="s" className="tnum">{r.session}</span>, <span key="p">{r.purpose}</span>,
                <span key="a" className="tnum">{naira(r.amount)}</span>, <span key="g" className="sub2">{day(r.generated_at)}</span>,
                <span key="c">{r.confirmed_at ? <Pil kind="ok">paid {day(r.confirmed_at)}</Pil> : <Pil kind={r.status === "EXPIRED" ? "grey" : "warn"}>{r.status.toLowerCase()}</Pil>}</span>,
                <span key="gw" className="sub2">{r.gateway ? `${r.gateway} · ${(r.gateway_outcome ?? "").toLowerCase().replace(/_/g, " ")}` : "—"}{r.gateway_ref ? <div className="tnum">{r.gateway_ref}</div> : null}</span>,
                <span key="rc" className="tnum">{r.receipt_no ?? "—"}</span>,
                caps.has("INVESTIGATE_PAYMENT") ? <LinkBtn key="i" size="sm" kind="primary" href={`/helpdesk/payments/${encodeURIComponent(r.reference)}${ticket ? `?ticket=${encodeURIComponent(ticket.id)}` : ""}`}>Investigate</LinkBtn> : <span key="i" />,
              ])} />
            </>
          )}
        </Panel>
      ) : null}
      {/* V366: "I am seeing a GST fee but I don't offer GST" — why the student owes GST/EPS or not, from the answer the fee and the gate read; nothing here marks a payment */}
      {tabNow === "payments" && pay?.gstEps ? (
        <Panel title={`GST & EPS eligibility · ${pay.gstEps.session}`} right={<span className="sub2">Read only — a payment is the Bursary&rsquo;s; a missing course, the Academic Office&rsquo;s</span>}>
          <PBody><GstEligibilityView data={pay.gstEps} /></PBody>
        </Panel>
      ) : null}

      {tabNow === "documents" && caps.has("VIEW_DOCUMENTS") ? (
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

      {tabNow === "history" ? (
        <>
          <Panel title="Support action history" right="The support audit trail — not the student's academic history">
            {data.actions.length ? <DTable pageSize={0} noPrint cols={["Date", "Agent", "Module", "Action", "Ticket|mid", "Reason", "Result|mid"]} rows={data.actions.map((x) => [
              <span key="w" className="sub2 tnum">{when(x.at)}</span>,
              <span key="a">{x.agent}<div className="sub2">{x.agent_office}</div></span>,
              <span key="m" className="sub2">{MODULE_WORD[x.module] ?? x.module}</span>,
              <span key="k"><b>{x.summary ?? ACTION_WORD[x.action] ?? x.action}</b>
                {x.override ? <div><Pil kind="warn">Support override</Pil><div className="sub2">Normal rule: registration blocked because {x.normal_rule}</div><div className="sub2">Support action: override approved because {x.reason}</div>{x.description ? <div className="sub2">Problem found: {x.description}</div> : null}</div> : null}
                {!x.summary && x.field ? <div className="sub2">{x.field}: {x.old_value ?? "—"} → {x.new_value ?? "—"}</div> : null}
                {x.session ? <div className="sub2 tnum">{x.session}{x.semester ? ` · semester ${x.semester}` : ""}</div> : null}</span>,
              x.ticket_id ? <Link key="t" href={`/helpdesk/tickets/${x.ticket_id}`} className="lnk tnum">{x.ticket_number}</Link> : <span key="t" className="sub2">—</span>,
              <span key="r" className="sub2">{x.reason}</span>,
              <Pil key="res" kind={RESULT_WORD[x.result]?.[1] ?? "grey"}>{RESULT_WORD[x.result]?.[0] ?? x.result}</Pil>,
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

      {tabNow === "tickets" ? (
        <Panel title="The student's tickets" right={<span className="row row--inline row--tight">
          {centre.has("CREATE_TICKET") ? <Btn kind="primary" size="sm" disabled={busy} onClick={() => centreAct("CREATE_TICKET")}>Create support ticket</Btn> : null}
          <LinkBtn size="sm" href={`/helpdesk?q=${encodeURIComponent(s.matricNo ?? s.surname)}`}>Find on the desk</LinkBtn>
        </span>}>
          {data.tickets.length ? <DTable pageSize={0} noPrint cols={["Number|mid", "Subject", "Category", "Status|mid", "Priority|mid", "Agent", "Updated", "|num"]} rows={data.tickets.map((t) => [
            <span key="n" className="tnum">{t.number}</span>, <span key="s">{t.subject}</span>, <span key="c" className="sub2">{t.category}</span>,
            <Pil key="st" kind={t.status === "RESOLVED" || t.status === "CLOSED" ? "grey" : "warn"}>{t.status.toLowerCase().replace(/_/g, " ")}{t.escalated_office ? ` · ${OFFICE_WORD[t.escalated_office] ?? t.escalated_office}` : ""}</Pil>,
            <span key="p" className="sub2">{t.priority.toLowerCase()}</span>, <span key="a" className="sub2">{t.agent ?? "—"}</span>, <span key="u" className="sub2">{when(t.updated_at)}</span>,
            <span key="o" className="row row--inline row--tight row--right"><LinkBtn size="sm" href={`/helpdesk/tickets/${t.id}`}>Open</LinkBtn><LinkBtn size="sm" kind="primary" href={`/helpdesk/students/${id}?ticket=${t.id}`}>Work from it</LinkBtn></span>,
          ])} /> : <PBody><div className="sub2">The student has raised no ticket.</div></PBody>}
        </Panel>
      ) : null}

      {/* ── add, drop or restore a course: the rules first, then the act ── */}
      {course && reg ? (
        <Modal wide title={course.verb === "drop" ? "DROP COURSE?" : course.verb === "restore" ? "RESTORE COURSE?" : "ADD COURSE"}
          sub={course.verb === "drop" ? "The course leaves the current registration and is kept as dropped; earlier sessions and results are untouched" : "Through the registration engine, after every rule it applies"}
          onClose={() => setCourse(null)}
          foot={<>
            <Btn kind="ghost" onClick={() => setCourse(null)}>Cancel</Btn>
            {course.checks && (course.checks.allowed || (course.override && course.checks.overridable && course.checks.mayOverride)) ? (
              <Btn kind={course.override ? "urgent" : "primary"} disabled={busy || course.reason.trim().length < 5 || (course.override && (!ticket || course.description.trim().length < 10))} onClick={() => void confirmCourse()}>
                {course.override ? "Apply support override" : course.verb === "drop" ? "Confirm Drop" : course.verb === "restore" ? "Confirm Restore" : "Confirm Add"}
              </Btn>
            ) : null}
          </>}>
          <div className="stack">
            <div className="grid grid--3">
              {([["Student", `${fullName} · ${s.matricNo ?? s.admissionNo ?? ""}`], ["Course", `${course.code} — ${course.title}`], ["Session", reg.view.session], ["Semester", `${sem(reg.view.semester)} semester`], ["Units", String(course.units)], ["Support ticket", ticket ? ticket.number : "None"]] as [string, string][]).map(([k, v]) => (
                <div key={k} className="kv"><span className="k">{k}</span><span className="v tnum">{v}</span></div>
              ))}
            </div>
            {course.checks === null ? <div className="sub2">Reading the engine&rsquo;s rules…</div> : (
              <>
                <RulesTable rules={course.checks.rules} />
                {course.checks.allowed ? <Note kind="ok" title="The engine's rules allow it">Nothing is set aside; the act goes through the same functions the student&rsquo;s own form uses.</Note>
                  : course.checks.overridable ? (course.checks.mayOverride
                    ? <Note kind="bad" title={`NORMAL RULE: Registration blocked because ${course.checks.rules.filter((r) => !r.passed && r.overridable).map((r) => r.message).join(" ")}`}>Only a genuine portal problem justifies a support override — a portal error, a course missing or wrongly mapped, a registration interrupted. It is made on the student&rsquo;s ticket, written with the rule it sets aside, and the student is told.</Note>
                    : <Note kind="bad" title="Blocked by the registration window or the engine's menu">Your postings do not carry the support override. Document the problem on the ticket and escalate it, or ask an agent who carries the override.</Note>)
                  : <Note kind="bad" title="The engine's rule stands">A rule a support override never sets aside blocks this — fees, units, GST, a lock, a mark, a closed semester or a course that is not offered this semester. Escalate the ticket to the office that owns it.</Note>}
              </>
            )}
            {course.checks && (course.checks.allowed || (course.checks.overridable && course.checks.mayOverride)) ? (
              <>
                {course.override ? (
                  <>
                    {!ticket ? <Note kind="bad" title="A support override is made on the student's ticket">Open the student from their ticket, or raise one for them first.</Note> : null}
                    <Field id="co-desc" label="Description — the problem found" required hint="What the portal did wrong; kept on the ledger"><textarea id="co-desc" className="ctl" rows={3} value={course.description} onChange={(e) => setCourse({ ...course, description: e.target.value })} maxLength={4000} /></Field>
                  </>
                ) : null}
                <Field id="co-reason" label={course.override ? "SUPPORT ACTION: Override approved because" : "Reason"} required hint={ticket ? `Recorded on ${ticket.number}` : "Recorded on the support ledger"}>
                  <input id="co-reason" className="ctl" value={course.reason} onChange={(e) => setCourse({ ...course, reason: e.target.value })} maxLength={2000}
                    placeholder={course.override ? "e.g. the department confirms the course; the programme mapping omits it" : "e.g. the portal returned an error when the student registered"} />
                </Field>
              </>
            ) : null}
          </div>
        </Modal>
      ) : null}

      {submit && reg ? (
        <Modal title="Submit the registration" sub="For the department's approval; the engine checks the fees, the units, the GST gate and the probation ceiling" onClose={() => setSubmit(null)}
          foot={<><Btn kind="ghost" onClick={() => setSubmit(null)}>Cancel</Btn><Btn kind={submit.override ? "urgent" : "primary"} disabled={busy || submit.reason.trim().length < 5 || (submit.override && (!ticket || submit.description.trim().length < 10))} onClick={() => void confirmSubmit()}>{submit.override ? "Submit by support override" : "Submit"}</Btn></>}>
          <div className="stack">
            {reg.view.window?.gate ? (reg.override
              ? <Note kind="bad" title={`NORMAL RULE: Registration blocked because ${reg.view.window.gate}`}>If the registration was interrupted by a portal fault, the window may be set aside on the student&rsquo;s ticket. The engine still refuses unpaid fees and an out-of-range load.
                  <label className="row row--inline row--tight mt-1"><input type="checkbox" className="chk" checked={submit.override} onChange={(e) => setSubmit({ ...submit, override: e.target.checked })} /> Apply the support override</label></Note>
              : <Note kind="bad" title="The registration window is closed">Your postings do not carry the support override; the engine refuses the submission.</Note>) : null}
            {submit.override ? <Field id="sb-desc" label="Description — the problem found" required><textarea id="sb-desc" className="ctl" rows={3} value={submit.description} onChange={(e) => setSubmit({ ...submit, description: e.target.value })} maxLength={4000} /></Field> : null}
            <Field id="sb-reason" label={submit.override ? "SUPPORT ACTION: Override approved because" : "Reason"} required><input id="sb-reason" className="ctl" value={submit.reason} onChange={(e) => setSubmit({ ...submit, reason: e.target.value })} maxLength={2000} /></Field>
          </div>
        </Modal>
      ) : null}

      {/* ── the password: never seen, never recorded ── */}
      {reset ? (
        <Modal title="RESET STUDENT PASSWORD" sub="Through the portal's own reset; the student's password is never shown and never recorded" onClose={() => setReset(null)}
          foot={reset.result ? <Btn kind="primary" onClick={() => setReset(null)}>Done</Btn> : <><Btn kind="ghost" onClick={() => setReset(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || reset.reason.trim().length < 5 || (reset.method === "TEMPORARY" && !ticket)} onClick={() => void confirmReset()}>Reset password</Btn></>}>
          <div className="stack">
            <div className="grid grid--2">
              <div className="kv"><span className="k">Student</span><span className="v">{fullName}</span></div>
              <div className="kv"><span className="k">Matric number</span><span className="v tnum">{s.matricNo ?? s.admissionNo ?? "—"}</span></div>
            </div>
            {reset.result ? (reset.result.method === "TEMPORARY_PASSWORD" ? (
              <Note kind="ok" title="Temporary password — give it to the student now">
                <span className="tnum" style={{ display: "block", fontSize: 22, letterSpacing: 2, margin: "6px 0" }}>{String(reset.result.temporaryPassword)}</span>
                <span className="sub2" style={{ display: "block" }}>It is not shown again and is kept only as a hash. It opens one sign-in until {when(String(reset.result.expiresAt))}, and the student must choose a new password there.</span>
              </Note>
            ) : <Note kind="ok" title="Reset link sent">A one-hour, single-use link went to {String(reset.result.sentTo)}. The student sets the new password; ICT Support never sees it.</Note>) : (
              <>
                <Field id="pw-method" label="Method">
                  <div className="stack" style={{ gap: 4 }}>
                    <label className="row row--inline row--tight"><input type="radio" name="pw-method" checked={reset.method === "LINK"} onChange={() => setReset({ ...reset, method: "LINK" })} /> Send a secure reset link to the student&rsquo;s email and phone (preferred)</label>
                    <label className="row row--inline row--tight"><input type="radio" name="pw-method" checked={reset.method === "TEMPORARY"} onChange={() => setReset({ ...reset, method: "TEMPORARY" })} /> Issue a temporary password at the desk — random, one sign-in, 24 hours, changed at once (on a ticket)</label>
                  </div>
                </Field>
                {reset.method === "TEMPORARY" && !ticket ? <Note kind="bad" title="A temporary password is issued on the student's ticket">Open the student from their ticket, or raise one for them first.</Note> : null}
                <Field id="pw-reason" label="Reason" required hint={ticket ? `Recorded on ${ticket.number}` : "Recorded on the support ledger"}><input id="pw-reason" className="ctl" value={reset.reason} onChange={(e) => setReset({ ...reset, reason: e.target.value })} maxLength={2000} placeholder="e.g. identity checked at the desk; the student cannot reach the reset email" /></Field>
              </>
            )}
          </div>
        </Modal>
      ) : null}

      {raise ? (
        <Modal title="Create support ticket" sub={`For ${fullName}, raised at the desk; routed to its queue and answered on the student's email`} onClose={() => setRaise(null)}
          foot={<><Btn kind="ghost" onClick={() => setRaise(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !raise.category || raise.subject.trim().length < 3 || raise.description.trim().length < 5 || categoryFields.some((f) => f.required && f.type !== "file" && !(raise.details[f.key] ?? "").trim())} onClick={() => void confirmRaise()}>Create ticket</Btn></>}>
          <div className="stack">
            <Field id="rt-cat" label="Category" required><select id="rt-cat" className="ctl" value={raise.category} onChange={(e) => setRaise({ ...raise, category: e.target.value, details: {} })}>{data.categories.map((c) => <option key={c.code} value={c.code}>{c.name}</option>)}</select></Field>
            <Field id="rt-subj" label="Subject" required><input id="rt-subj" className="ctl" value={raise.subject} onChange={(e) => setRaise({ ...raise, subject: e.target.value })} maxLength={200} /></Field>
            <Field id="rt-desc" label="Description" required><textarea id="rt-desc" className="ctl" rows={3} value={raise.description} onChange={(e) => setRaise({ ...raise, description: e.target.value })} maxLength={8000} /></Field>
            {categoryFields.filter((f) => f.type !== "file").map((f) => (
              <Field key={f.key} id={`rt-${f.key}`} label={f.label} required={f.required} hint={f.hint}>
                {f.type === "select" && f.options ? (
                  <select id={`rt-${f.key}`} className="ctl" value={raise.details[f.key] ?? ""} onChange={(e) => setRaise({ ...raise, details: { ...raise.details, [f.key]: e.target.value } })}><option value="">—</option>{f.options.map((o) => <option key={o} value={o}>{o}</option>)}</select>
                ) : (
                  <input id={`rt-${f.key}`} className="ctl" type={f.type === "date" ? "date" : f.type === "number" ? "number" : "text"} value={raise.details[f.key] ?? ""}
                    onChange={(e) => setRaise({ ...raise, details: { ...raise.details, [f.key]: e.target.value } })}
                    placeholder={f.type === "session" ? String(data.academic?.session ?? "2025/2026") : f.type === "semester" ? "1" : f.type === "level" ? String(s.currentLevel) : undefined} />
                )}
              </Field>
            ))}
          </div>
        </Modal>
      ) : null}

      {escalate && ticket ? (
        <Modal title="Escalate the ticket" sub={`${ticket.number} goes to the office that decides and waits on it`} onClose={() => setEscalate(null)}
          foot={<><Btn kind="ghost" onClick={() => setEscalate(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || escalate.reason.trim().length < 5} onClick={() => void confirmEscalate()}>Escalate</Btn></>}>
          <div className="stack">
            <Field id="es-office" label="To"><select id="es-office" className="ctl" value={escalate.office} onChange={(e) => setEscalate({ ...escalate, office: e.target.value })}>
              {data.escalateTo.map((o) => <option key={o} value={o}>{OFFICE_WORD[o] ?? o}{o === "bursar" ? " — a financial decision" : o === "records" ? " — a result problem" : o === "ict" ? " — a system-wide technical fault" : ""}</option>)}
            </select></Field>
            <Field id="es-reason" label="What the office should decide" required><textarea id="es-reason" className="ctl" rows={4} value={escalate.reason} onChange={(e) => setEscalate({ ...escalate, reason: e.target.value })} maxLength={2000} /></Field>
          </div>
        </Modal>
      ) : null}

      {resolve && ticket ? (
        <Modal title={`Resolve ${ticket.number}`} sub="The student is told and asked to confirm; the acts done are written on the ticket already" onClose={() => setResolve(null)}
          foot={<><Btn kind="ghost" onClick={() => setResolve(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !resolve.summary.trim() || !resolve.details.trim()} onClick={() => void confirmResolve()}>Resolve ticket</Btn></>}>
          <div className="stack">
            <Field id="rs-sum" label="Summary" required><input id="rs-sum" className="ctl" value={resolve.summary} onChange={(e) => setResolve({ ...resolve, summary: e.target.value })} maxLength={300} /></Field>
            <Field id="rs-det" label="Details" required><textarea id="rs-det" className="ctl" rows={5} value={resolve.details} onChange={(e) => setResolve({ ...resolve, details: e.target.value })} maxLength={8000} /></Field>
          </div>
        </Modal>
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
