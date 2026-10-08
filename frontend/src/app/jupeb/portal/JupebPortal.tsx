"use client";

/**
 * The JUPEB candidate's dashboard (V339–V342), applicant to student to result, in the portal's own shell.
 *
 * While the application is a draft (or returned for correction) it is a guided application of five steps — personal
 * information, O'Level (one or two sittings), documents (each sitting's result its own), the programme (Science or
 * Non-Science, and a subject combination the University offers for it), and the review with the application fee and the
 * submission. "Save & Continue" saves the step and moves on when the server finds it complete; otherwise it stays, with each
 * field to correct marked. The candidate resumes at the first incomplete step.
 *
 * Once submitted: admission status checking (the Bursary's fee, once, while the Directorate of ICT has checking open), the
 * acceptance fee and letter, screening, the school fees, the subjects, attendance, results, the document centre and support.
 * Every amount is the server's; every call is scoped to the signed-in candidate.
 */
import { useCallback, useEffect, useMemo, useRef, useState, type ChangeEvent, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, KvGrid } from "@/components/proto/ui";
import { Field, Steps as StepList } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { Shell, type Me as ShellMe } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PayByCard } from "@/app/applicant/common";
import { DocViewer, viewerClick, type ViewDoc } from "../DocViewer";
import { JupebCbt } from "./JupebCbt";
import QRCode from "qrcode";
import { MathText } from "@/components/proto/MathText";
import { IdCardPair, type IdCardData } from "@/components/proto/idcard";
import { TimetableGrid, printGrid, type Frame } from "../TimetableGrid";
import { SyllabusModal, UnitsBySemester, unitId, type UnitRow } from "../Syllabus";
import { EXAM_KIND, eventDates, type CalendarEvent, type ClearanceCheck, type MyExams } from "@/lib/jupeb";
import { STATES, lgasOf, NATIONALITIES } from "@/lib/nigeria";
import {
  ADMISSION_STATUS, CHANGE_KIND, CORRECTION_FIELDS, DOC_STATUS, EVENT_LABEL, FEE_KIND, REQUEST_STATE, laterSessions, OLEVEL_EXAMS, OLEVEL_GRADES, OLEVEL_SUBJECTS,
  SCREENING_LABEL, STATE_SHORT, day, feeCategoryLabel, fileBase64, fullName, jcall, naira, stateKind, streamLabel, when, type Announcement, type Candidate, type Combination,
  type Doc, type FeeRef, type PracticePaper, type RefundClaim, type Slot, type StepProblem,
} from "@/lib/jupeb";

type Tab = "overview" | "announcements" | "profile" | "admission" | "payments" | "subjects" | "timetable" | "practice" | "cbt" | "attendance" | "exams" | "results" | "documents" | "idcard"
  | "requests" | "password" | "support";
const TAB_IDS: Tab[] = ["overview", "announcements", "profile", "admission", "payments", "subjects", "timetable", "practice", "cbt", "attendance", "exams", "results", "documents", "idcard",
  "requests", "password", "support"];
/** each section is its own item in the side menu (Shell routes jupeb/portal/<section> to /jupeb/portal?tab=<section>) */
const routeOf = (t: Tab) => (t === "overview" ? "jupeb/portal" : `jupeb/portal/${t}`);
type Act = (path: string, method?: string, body?: unknown) => Promise<Candidate | null>;

interface Ticket { id: string; number: string; subject: string; category: string; status: string; created_at: string; updated_at: string; queue: string | null }
interface TicketDetail extends Ticket { description: string; resolution_summary: string | null; comments: { id: string; author_kind: string; author_name: string; body: string; created_at: string }[] }
interface Support { categories: { code: string; name: string; fields: string }[]; tickets: Ticket[] }

const ADMITTED = new Set(["ADMITTED", "STUDENT", "COMPLETED"]);
const STEP_ORDER = ["PERSONAL", "OLEVEL", "DOCUMENTS", "PROGRAMME", "REVIEW"] as const;
const STEP_TITLE: Record<string, string> = { PERSONAL: "Personal information", OLEVEL: "O’Level", DOCUMENTS: "Documents", PROGRAMME: "Programme", REVIEW: "Review & submit" };
const PHOTO = "/api/bff/api/v1/jupeb/me/documents/PASSPORT/content?format=jpeg";

/** the offered combinations that suit a programme (the server marks each one Science and/or Non-Science) */
const suiting = (all: Combination[] | undefined, stream: string | null) =>
  (all ?? []).filter((c) => c.offered && (stream === "SCIENCE" ? c.science : stream ? c.non_science : false));

export function JupebPortal({ tab: tabIn }: { tab?: string }) {
  const router = useRouter();
  const [me, setMe] = useState<Candidate | null>(null);
  const [loading, setLoading] = useState(true);
  const [signedOut, setSignedOut] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const tab: Tab = (TAB_IDS as string[]).includes(tabIn ?? "") ? (tabIn as Tab) : "overview";
  /** a section is opened from the side menu, or from a link on the page: the address says which, so it can be bookmarked */
  const setTab = useCallback((t: Tab) => router.push(t === "overview" ? "/jupeb/portal" : `/jupeb/portal?tab=${t}`), [router]);
  const [verifying, setVerifying] = useState(false);

  const load = useCallback(async () => {
    const r = await jcall<Candidate>("/api/v1/jupeb/me");
    if (!r.ok) {
      if (r.problem.status === 401 || r.problem.status === 403 || r.problem.status === 404) setSignedOut(true);
      else setProblem(r.problem);
    } else { setMe(r.data); setProblem(null); }
    setLoading(false);
  }, []);

  /* the gateway returns the payer with ?paid=REF: the gateway is asked, a few times, until the University has the payment */
  const pollConfirm = useCallback(async (ref: string, tries: number) => {
    for (let i = 0; i < tries; i++) {
      await jcall("/api/v1/payments/verify", "POST", { reference: ref });
      const r = await jcall<Candidate>("/api/v1/jupeb/me");
      if (r.ok) {
        setMe(r.data);
        if (r.data.references.some((x) => x.reference === ref && x.confirmed_at)) return true;
      }
      if (i < tries - 1) await new Promise((res) => setTimeout(res, 4000));
    }
    return false;
  }, []);

  useEffect(() => {
    const paid = new URLSearchParams(window.location.search).get("paid");
    void (async () => {
      await load();
      if (paid) {
        setVerifying(true);
        router.replace(`/jupeb/portal?tab=${paid.includes("CHK") || paid.includes("ACC") ? "admission" : "payments"}`);
        const ok = await pollConfirm(paid, 8);
        setVerifying(false);
        if (ok) notify("Payment confirmed — thank you.");
      }
    })();
  }, [load, pollConfirm, router]);

  /** one act; the record the server returns replaces the page's */
  const act: Act = useCallback(async (path, method = "POST", body) => {
    const r = await jcall<Candidate>(path, method, body);
    if (!r.ok) { notifyProblem(r.problem); return null; }
    setMe(r.data);
    return r.data;
  }, []);

  if (loading) return <Bare><Note kind="info" title="Loading your JUPEB record…">One moment.</Note></Bare>;
  if (signedOut || !me) {
    return (
      <Bare>
        {problem ? <ProblemNotice problem={problem} /> : null}
        <Note kind="info" title="Sign in to your JUPEB application">Sign in with the email you applied with, or your JUPEB application number, and your password.</Note>
        <div className="row mt-3"><LinkBtn kind="primary" href="/login?next=/jupeb/portal">Sign in</LinkBtn><LinkBtn kind="ghost" href="/jupeb/apply">Apply</LinkBtn></div>
      </Bare>
    );
  }

  const guided = me.state === "DRAFT" || me.state === "RETURNED";
  const admitted = ADMITTED.has(me.state);
  const studying = me.state === "STUDENT" || me.state === "COMPLETED";
  /* the side menu follows the record: the guided application while it is a draft; the studies once admitted */
  const shellMe: ShellMe = {
    actorId: "", activeOffice: "jupebcandidate", offices: ["jupebcandidate"], menu: guided ? "jupebapplicant" : admitted ? "jupebstudent" : "jupebcandidate",
    name: fullName(me), staffNumber: me.exam_no ?? me.application_no, sessionId: null, unit: `JUPEB ${me.session}`,
    waiting: {
      ...(me.requests.some((r) => r.state === "PENDING") ? { "jupeb/portal/requests": "1" } : {}),
      ...(me.unreadAnnouncements ? { "jupeb/portal/announcements": String(me.unreadAnnouncements) } : {}),
    },
  };
  /* V345: a temporary password handed out by the JUPEB Office is changed before anything else */
  if (me.must_change_password) {
    return (
      <Shell route="jupeb/portal/password" me={shellMe}>
        <Profile me={me} />
        <ChangePassword forced onDone={(fresh) => { setMe(fresh); notify("Your password is changed."); }} />
      </Shell>
    );
  }
  const notYet = (what: string, when: string) => <Note kind="info" title={`${what} opens ${when}`}>It appears here, in this same menu, the moment it applies to you.</Note>;
  /* the profile, the password and support are always open; while the application is a draft every other item is the guided application */
  const section = (() => {
    switch (tab) {
      case "profile": return <MyProfile me={me} act={act} onEdit={guided ? () => setTab("overview") : undefined} onRequests={() => setTab("requests")} />;
      case "password": return <ChangePassword onDone={(fresh) => { setMe(fresh); notify("Your password is changed."); }} />;
      case "support": return <SupportTab />;
      case "announcements": return <Announcements onRead={() => void load()} />;
      default: break;
    }
    if (guided) return <><Profile me={me} /><Guided me={me} act={act} /></>;
    switch (tab) {
      case "admission": return <Admission me={me} reload={load} />;
      case "payments": return <Payments me={me} reload={load} act={act} />;
      case "subjects": return admitted ? <Subjects me={me} act={act} /> : notYet("Subject registration", "once you are admitted");
      case "timetable": return studying ? <Timetable me={me} /> : notYet("The timetable", "once your studentship is activated by the school fee");
      case "practice": return admitted ? <Practice /> : notYet("Practice tests", "once you are admitted");
      /* V365: the University's one CBT engine, behind the JUPEB door */
      case "cbt": return admitted ? <JupebCbt who={{ name: `${me.surname.toUpperCase()} ${me.first_name}${me.middle_name ? ` ${me.middle_name}` : ""}`, number: me.exam_no ?? me.application_no }} /> : notYet("CBT examinations", "once you are admitted");
      case "attendance": return studying ? <Attendance /> : notYet("Attendance", "once your studentship is activated by the school fee");
      case "exams": return studying ? <Exams /> : notYet("The examination", "once your studentship is activated by the school fee");
      case "results": return admitted ? <><Results me={me} /><MyAssessment /></> : notYet("Results", "once you are admitted");
      case "documents": return <DocumentCentre me={me} act={act} />;
      case "idcard": return studying ? <IdCardSection me={me} /> : notYet("Your identity card", "once your studentship is activated by the school fee");
      case "requests": return <Requests me={me} act={act} />;
      default: return <><Profile me={me} /><Overview me={me} /></>;
    }
  })();

  return (
    <Shell route={routeOf(tab)} me={shellMe}>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {me.state === "WITHDRAWN" ? <Note kind="bad" title="Your application is withdrawn"
        action={me.refundClaim && tab !== "payments" ? <Btn kind="ghost" onClick={() => setTab("payments")}>{me.refundClaim.state.status === "AWAITING_DETAILS" ? "Give your account" : "See your refund"}</Btn> : undefined}>
        {`Withdrawn${me.withdrawn_at ? ` on ${day(me.withdrawn_at)}` : ""}. Your record is kept; any refund is the Bursary's decision under its own rules.${me.refundClaim ? " Your refund claim is with the Bursary." : ""}`}</Note> : null}
      {tab !== "attendance" ? <AttendanceWarning me={me} onOpen={() => setTab("attendance")} /> : null}
      {tab !== "documents" && !guided && me.documents.some((d) => d.status === "REPLACEMENT_REQUIRED" || d.status === "REJECTED") ? (
        <Note kind="bad" title="A document must be uploaded again" action={<Btn kind="ghost" onClick={() => setTab("documents")}>Open Documents</Btn>}>
          {`${me.documents.filter((d) => d.status === "REPLACEMENT_REQUIRED" || d.status === "REJECTED").map((d) => d.label).join(", ")}: see the note beside each and upload it again.`}
        </Note>
      ) : null}
      {me.state === "DEFERRED" ? <Note kind="info" title={`Your admission is deferred to ${me.deferred_to ?? "a later session"}`}>The JUPEB Office resumes it in that session; you will be told, and your payments stand.</Note> : null}
      {tab !== "announcements" && me.unreadAnnouncements ? (
        <Note kind="info" title={`${me.unreadAnnouncements} new announcement${me.unreadAnnouncements === 1 ? "" : "s"} from the JUPEB Office`}
          action={<Btn kind="ghost" onClick={() => setTab("announcements")}>Read</Btn>}>Notices for you: timetable changes, deadlines and the like.</Note>
      ) : null}
      {verifying ? <Note kind="info" title="Confirming your payment…">The page updates on its own once the payment reaches the University.</Note> : null}
      {section}
    </Shell>
  );
}

/* ── My Profile: everything the University holds about the candidate, read from the record ────────────────── */

function MyProfile({ me, act, onEdit, onRequests }: { me: Candidate; act: Act; onEdit?: () => void; onRequests: () => void }) {
  const sc = me.statusChecking;
  const status = sc.may_check && sc.status ? ADMISSION_STATUS[sc.status] : null;
  const v = (x: string | null | undefined) => (x && String(x).trim() ? x : "—");
  const nin = me.nin ? `${"•".repeat(Math.max(0, me.nin.length - 4))}${me.nin.slice(-4)}` : "—";
  const subjects = (me.subjects ?? []).map((x) => x.code).join(", ");
  return (
    <>
      <div className="card">
        <div className="card__body" style={{ display: "flex", flexDirection: "row", gap: "var(--s-4)", alignItems: "center", flexWrap: "wrap" }}>
          <Passport src={me.has_passport ? `${PHOTO}&v=${encodeURIComponent(me.updated_at)}` : null} />
          <div style={{ flex: 1, minWidth: 240 }}>
            <div className="b700" style={{ fontSize: 20 }}>{fullName(me)}</div>
            <div className="sub2">{me.application_no}{me.exam_no ? ` · JUPEB ${me.exam_no}` : ""} · {me.session}</div>
            <div className="row row--inline mt-1" style={{ gap: "var(--s-2)", flexWrap: "wrap" }}>
              <Pil kind={stateKind(me.state)}>{STATE_SHORT[me.state] ?? me.state}</Pil>
              {status ? <Pil kind={status[1]}>{status[0]}</Pil> : null}
              {me.legacy_source ? <Pil kind="grey">From the old portal</Pil> : null}
            </div>
          </div>
        </div>
      </div>
      <div className="grid grid--2">
        <Panel title="Personal information">
          <PBody>
            <KvGrid cls="grid--2" pairs={[
              ["Surname", v(me.surname)], ["First name", v(me.first_name)], ["Middle name", v(me.middle_name)], ["Sex", me.sex === "F" ? "Female" : me.sex === "M" ? "Male" : v(me.sex)],
              ["Date of birth", me.date_of_birth ? day(me.date_of_birth) : "—"], ["NIN", nin], ["Nationality", v(me.nationality)], ["State of origin", v(me.state_of_origin)],
              ["LGA", v(me.lga)], ["Home town", v(me.home_town)],
            ]} />
          </PBody>
        </Panel>
        <Panel title="Contact">
          <PBody>
            <KvGrid cls="grid--2" pairs={[
              ["Email", v(me.email)], ["Phone", v(me.phone)], ["Contact address", v(me.contact_address)], ["Permanent address", v(me.permanent_address)],
            ]} />
          </PBody>
        </Panel>
        <Panel title="Programme">
          <PBody>
            <KvGrid cls="grid--2" pairs={[
              ["Programme", streamLabel(me.stream)], ["Subject combination", me.combination_code ? `${me.combination_code}${me.combination_name ? ` — ${me.combination_name}` : ""}` : "Not yet chosen"],
              ["Subjects registered", subjects || "Not yet registered"], ["Class", v(me.class_name)],
              ["Session", me.session], ["JUPEB examination number", me.exam_no ?? "Not yet assigned"],
              ["Studentship activated", me.activated_at ? day(me.activated_at) : "—"], ["Admission accepted", me.accepted_at ? day(me.accepted_at) : "—"],
            ]} />
          </PBody>
        </Panel>
        <Panel title="Guardian and next of kin">
          <PBody>
            <KvGrid cls="grid--2" pairs={[
              ["Guardian", v(me.guardian_name)], ["Guardian's phone", v(me.guardian_phone)], ["Guardian's address", v(me.guardian_address)], ["Next of kin", v(me.next_of_kin_name)],
              ["Next of kin's phone", v(me.next_of_kin_phone)], ["Relationship", v(me.next_of_kin_relationship)],
            ]} />
          </PBody>
        </Panel>
      </div>
      <Panel title="O'Level">
        <PBody>
          <KvGrid cls="grid--4" pairs={[
            ["Sittings", String(me.olevelCheck?.sittings ?? me.olevel_sittings ?? 0)], ["Credits", String(me.olevelCheck?.credits ?? 0)],
            ["English", me.olevelCheck?.english ? "Credit" : "—"], ["Mathematics", me.olevelCheck?.mathematics ? "Credit" : "—"],
          ]} />
        </PBody>
      </Panel>
      {onEdit ? (
        <Note kind="info" title="Your application is still open to you" action={<Btn kind="ghost" onClick={onEdit}>Continue the application</Btn>}>Correct any detail in the application&rsquo;s steps before you submit it.</Note>
      ) : me.state === "WITHDRAWN" ? (
        <Note kind="info" title="Your application is withdrawn">Its details are kept as they stand; ask the JUPEB Office if one must change.</Note>
      ) : (
        <>
          <ContactDetails me={me} act={act} />
          <CorrectionRequest me={me} act={act} onRequests={onRequests} />
        </>
      )}
    </>
  );
}

/* ── V347: the contact details the student keeps; a change of identity is asked of the JUPEB Office ─────────── */

const PHONE = /^0\d{10}$/;

function ContactDetails({ me, act }: { me: Candidate; act: Act }) {
  const held = useMemo(() => ({
    phone: me.phone ?? "", contactAddress: me.contact_address ?? "", permanentAddress: me.permanent_address ?? "", guardianName: me.guardian_name ?? "",
    guardianPhone: me.guardian_phone ?? "", guardianAddress: me.guardian_address ?? "", nextOfKinName: me.next_of_kin_name ?? "",
    nextOfKinPhone: me.next_of_kin_phone ?? "", nextOfKinRelationship: me.next_of_kin_relationship ?? "",
  }), [me]);
  const [f, setF] = useState<Record<string, string>>(held);
  const [busy, setBusy] = useState(false);
  useEffect(() => { setF(held); }, [held]);
  const set = (k: string) => (e: ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setF({ ...f, [k]: e.target.value });
  const bad = (k: string, required = false) => {
    const v = (f[k] ?? "").trim();
    if (!v) return required ? "Keep a phone number on your record" : undefined;
    return PHONE.test(v) ? undefined : "Eleven digits, e.g. 08012345678";
  };
  const errors = { phone: bad("phone", true), guardianPhone: bad("guardianPhone"), nextOfKinPhone: bad("nextOfKinPhone") };
  const changed = Object.keys(held).some((k) => (f[k] ?? "").trim() !== (held as Record<string, string>)[k]);
  async function save() {
    setBusy(true);
    try {
      const body = Object.fromEntries(Object.entries(f).map(([k, v]) => [k, v.trim() === "" ? null : v.trim()]));
      if (await act("/api/v1/jupeb/me/contact", "PUT", body)) notify("Your contact details are saved.");
    } finally { setBusy(false); }
  }
  const input = (k: string, label: string, o: { max?: number; error?: string; required?: boolean } = {}) => (
    <Field id={`cd-${k}`} label={label} required={o.required} error={o.error}>
      <input id={`cd-${k}`} className="ctl" value={f[k] ?? ""} onChange={set(k)} maxLength={o.max ?? 120} />
    </Field>
  );
  return (
    <Panel title="Update your contact details" right={<span className="sub2">Saved at once; the JUPEB Office sees the change on your record</span>}>
      <PBody>
        <div className="grid grid--3">
          {input("phone", "Phone", { max: 11, error: errors.phone, required: true })}
          <Field id="cd-email" label="Email" hint="Your sign-in; ask ICT Support to change it"><input id="cd-email" className="ctl" value={me.email} disabled /></Field>
        </div>
        <div className="grid grid--2">
          <Field id="cd-ca" label="Contact address"><textarea id="cd-ca" className="ctl" rows={2} maxLength={300} value={f.contactAddress} onChange={set("contactAddress")} /></Field>
          <Field id="cd-pa" label="Permanent home address"><textarea id="cd-pa" className="ctl" rows={2} maxLength={300} value={f.permanentAddress} onChange={set("permanentAddress")} /></Field>
        </div>
        <div className="eyebrow mt-3">Parent or guardian</div>
        <div className="grid grid--3">{input("guardianName", "Name")}{input("guardianPhone", "Phone", { max: 11, error: errors.guardianPhone })}{input("guardianAddress", "Address", { max: 300 })}</div>
        <div className="eyebrow mt-3">Next of kin</div>
        <div className="grid grid--3">{input("nextOfKinName", "Name")}{input("nextOfKinPhone", "Phone", { max: 11, error: errors.nextOfKinPhone })}{input("nextOfKinRelationship", "Relationship", { max: 60 })}</div>
        <div className="row mt-2">
          <Btn kind="primary" disabled={busy || !changed || Object.values(errors).some(Boolean)} onClick={() => void save()}>{busy ? "Saving…" : "Save my contact details"}</Btn>
          {changed ? <Btn kind="ghost" onClick={() => setF(held)}>Undo my changes</Btn> : null}
        </div>
      </PBody>
    </Panel>
  );
}

function CorrectionRequest({ me, act, onRequests }: { me: Candidate; act: Act; onRequests: () => void }) {
  const present: Record<string, string> = {
    surname: me.surname, first_name: me.first_name, middle_name: me.middle_name ?? "", sex: me.sex ?? "", date_of_birth: me.date_of_birth ?? "", nin: me.nin ?? "",
    nationality: me.nationality ?? "", state_of_origin: me.state_of_origin ?? "", lga: me.lga ?? "",
  };
  const shown = (k: string, v: string) => (!v ? "—" : k === "sex" ? (v === "F" ? "Female" : v === "M" ? "Male" : v) : k === "date_of_birth" ? day(v)
    : k === "nin" ? `${"•".repeat(Math.max(0, v.length - 4))}${v.slice(-4)}` : v);
  const [to, setTo] = useState<Record<string, string>>({});
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const pending = me.requests.find((r) => r.state === "PENDING") ?? null;
  const picked = Object.keys(to);
  const toggle = (k: string, on: boolean) => {
    const next = { ...to };
    if (on) next[k] = k === "surname" || k === "first_name" || k === "middle_name" ? present[k] : "";
    else delete next[k];
    if (k === "state_of_origin" && !on) delete next.lga;
    setTo(next);
  };
  const stateFor = to.state_of_origin ?? present.state_of_origin;
  const problem = (k: string): string | undefined => {
    const v = (to[k] ?? "").trim();
    if (!v) return k === "middle_name" ? undefined : "Say what it should read";
    if (k === "nin" && !/^\d{11}$/.test(v)) return "Eleven digits";
    if (v.toUpperCase() === (present[k] ?? "").toUpperCase()) return "The same as your record";
    return undefined;
  };
  const ready = picked.length > 0 && picked.every((k) => !problem(k)) && reason.trim().length >= 10;
  async function send() {
    setBusy(true);
    try {
      const changes = Object.fromEntries(picked.map((k) => [k, (to[k] ?? "").trim()]));
      if (await act("/api/v1/jupeb/me/corrections", "POST", { changes, reason: reason.trim() })) {
        notify("Your correction is with the JUPEB Office. You will be told of its decision.");
        setTo({}); setReason("");
      }
    } finally { setBusy(false); }
  }
  if (pending) {
    return (
      <Note kind="info" title="A request of yours is with the JUPEB Office" action={<Btn kind="ghost" onClick={onRequests}>See your requests</Btn>}>
        {`You asked to ${pending.words}, on ${day(pending.requested_at)}. One request is open at a time; a correction of your details can be asked once it is decided.`}
      </Note>
    );
  }
  const editor = (k: string) => {
    const id = `cr-${k}`;
    const common = { id, className: "ctl", value: to[k] ?? "", onChange: (e: ChangeEvent<HTMLInputElement | HTMLSelectElement>) => setTo({ ...to, [k]: e.target.value, ...(k === "state_of_origin" && to.lga !== undefined ? { lga: "" } : {}) }) };
    switch (k) {
      case "sex": return <select {...common}><option value="">—</option><option value="F">Female</option><option value="M">Male</option></select>;
      case "date_of_birth": return <input {...common} type="date" />;
      case "nationality": return <select {...common}><option value="">—</option>{NATIONALITIES.map((n) => <option key={n} value={n}>{n}</option>)}</select>;
      case "state_of_origin": return <select {...common}><option value="">— Select a state —</option>{STATES.map((x) => <option key={x} value={x}>{x}</option>)}</select>;
      case "lga": return <select {...common} disabled={!stateFor}><option value="">{stateFor ? "— Select an LGA —" : "Select a state first"}</option>{lgasOf(stateFor).map((l) => <option key={l} value={l}>{l}</option>)}</select>;
      case "nin": return <input {...common} inputMode="numeric" maxLength={11} />;
      default: return <input {...common} maxLength={80} />;
    }
  };
  return (
    <Panel title="Ask for a correction of your personal details">
      <PBody>
        <p className="sub2">Your name, sex, date of birth, NIN, nationality, state of origin and LGA are corrected only by the JUPEB Office, on evidence (birth certificate, NIN slip, sworn affidavit or
          marriage certificate). Tick what is wrong and say what it should read; nothing changes until the Office approves.</p>
        <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", margin: "var(--s-2) 0" }}>
          {CORRECTION_FIELDS.map(([k, label]) => (
            <label key={k} className="row" style={{ gap: "var(--s-1)" }}><input type="checkbox" checked={k in to} onChange={(e) => toggle(k, e.target.checked)} /> {label}</label>
          ))}
        </div>
        {picked.length ? (
          <DTable noPrint pageSize={0} cols={["Detail", "Your record reads", "It should read"]} rows={CORRECTION_FIELDS.filter(([k]) => k in to).map(([k, label]) => [
            label, shown(k, present[k]),
            <Field key={k} id={`cr-${k}`} label="" error={problem(k)}>{editor(k)}</Field>,
          ])} />
        ) : null}
        <Field id="cr-reason" label="Why, and the evidence you hold" required hint="At least ten characters"><textarea id="cr-reason" className="ctl" rows={3} maxLength={1000} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        <div className="row mt-2"><Btn kind="primary" disabled={busy || !ready} onClick={() => void send()}>{busy ? "Sending…" : "Send the correction to the JUPEB Office"}</Btn></div>
      </PBody>
    </Panel>
  );
}

/* ── the profile: the passport, and who the candidate is ─────────────────────────────────────────── */

function Passport({ src }: { src: string | null }) {
  // a photograph the record names but cannot serve shows the empty frame, never a broken image
  const [failed, setFailed] = useState<string | null>(null);
  return src && failed !== src ? (
    // eslint-disable-next-line @next/next/no-img-element
    <img src={src} alt="Passport photograph" onError={() => setFailed(src)} style={{ width: 96, height: 120, objectFit: "contain", border: "1px solid var(--line-2)", borderRadius: "var(--r-sm)", background: "var(--bg)" }} />
  ) : (
    <div aria-label="No passport photograph" style={{ width: 96, height: 120, border: "1px dashed var(--line-2)", borderRadius: "var(--r-sm)", display: "grid", placeItems: "center", color: "var(--chrome)", fontSize: 11, textAlign: "center" }}>
      PASSPORT<br />PHOTOGRAPH
    </div>
  );
}

function Profile({ me }: { me: Candidate }) {
  const sc = me.statusChecking;
  const status = sc.may_check && sc.status ? ADMISSION_STATUS[sc.status] : null;
  return (
    <div className="card">
      <div className="card__body" style={{ display: "flex", flexDirection: "row", gap: "var(--s-4)", alignItems: "center", flexWrap: "wrap" }}>
        <Passport src={me.has_passport ? `${PHOTO}&v=${encodeURIComponent(me.updated_at)}` : null} />
        <div style={{ flex: 1, minWidth: 240 }}>
          <div className="b700" style={{ fontSize: 18 }}>{fullName(me)}</div>
          <KvGrid cls="grid--3" pairs={[
            ["Application number", me.application_no],
            ["JUPEB examination number", me.exam_no ?? "Not yet assigned"],
            ["Programme", `${streamLabel(me.stream)}${me.combination_code ? ` · ${me.combination_code}` : ""}`],
            ["Session", me.session],
            ["Application", <Pil key="s" kind={stateKind(me.state)}>{STATE_SHORT[me.state] ?? me.state}</Pil>],
            ["Admission status", status ? <Pil key="a" kind={status[1]}>{status[0]}</Pil> : <span key="a" className="sub2">{me.submitted_at ? "Not yet checked" : "—"}</span>],
          ]} />
        </div>
      </div>
    </div>
  );
}

/* ── the guided application ─────────────────────────────────────────────────────────────────────── */

function Guided({ me, act }: { me: Candidate; act: Act }) {
  const startAt = Math.max(0, STEP_ORDER.indexOf((me.steps?.current ?? "PERSONAL") as (typeof STEP_ORDER)[number]));
  const [step, setStep] = useState<number>(startAt);
  const [shown, setShown] = useState<StepProblem[]>([]);
  const status = (n: number) => me.steps.steps.find((s) => s.step === STEP_ORDER[n]);

  /** after a save: on to the next step when the server finds this one complete; otherwise stay, with what to correct */
  const advance = useCallback((fresh: Candidate | null, n: number) => {
    if (!fresh) return;
    const st = fresh.steps.steps.find((s) => s.step === STEP_ORDER[n]);
    if (st && st.ok) {
      setShown([]);
      setStep(Math.min(n + 1, STEP_ORDER.length - 1));
      window.scrollTo({ top: 0, behavior: "smooth" });
    } else {
      setShown(st?.problems ?? []);
      notifyProblem({ status: 422, title: "Some things on this step still need your attention." });
    }
  }, []);
  const back = () => { setShown([]); setStep((n) => Math.max(0, n - 1)); };
  const errors = useMemo(() => Object.fromEntries(shown.map((p) => [p.field, p.message])), [shown]);

  return (
    <>
      {me.state === "RETURNED" && me.return_note ? <Note kind="bad" title="The JUPEB Office returned your application">{me.return_note} Correct it below and submit again.</Note> : null}
      <div style={{ display: "flex", gap: "var(--s-2)" }} role="list" aria-label="Application steps">
        {STEP_ORDER.map((k, i) => {
          const done = status(i)?.ok, cur = step === i;
          return (
            <button key={k} type="button" role="listitem" aria-current={cur ? "step" : undefined} onClick={() => { setShown([]); setStep(i); }}
              style={{ flex: 1, textAlign: "left", background: "none", border: "none", padding: 0, cursor: "pointer" }}>
              <div style={{ height: 5, borderRadius: "var(--r-sm)", background: done ? "var(--green-ink)" : cur ? "var(--chrome)" : "var(--line-2)" }} />
              <div className="sub2 mt-2" style={{ fontWeight: cur ? 700 : 500, color: cur || done ? "var(--ink)" : "var(--chrome)" }}>{i + 1}. {STEP_TITLE[k]}{done ? " ✓" : ""}</div>
            </button>
          );
        })}
      </div>
      {shown.length ? <Note kind="bad" title="Please correct the following">{shown.map((p) => p.message).join(" · ")}</Note> : null}
      {step === 0 ? <PersonalStep me={me} act={act} errors={errors} onSaved={(f) => advance(f, 0)} /> : null}
      {step === 1 ? <OlevelStep me={me} act={act} errors={errors} onSaved={(f) => advance(f, 1)} onBack={back} /> : null}
      {step === 2 ? <DocumentsStep me={me} act={act} errors={errors} onContinue={() => advance(me, 2)} onBack={back} /> : null}
      {step === 3 ? <ProgrammeStep me={me} act={act} errors={errors} onSaved={(f) => advance(f, 3)} onBack={back} /> : null}
      {step === 4 ? <ReviewStep me={me} act={act} onBack={back} onGo={(n) => { setShown([]); setStep(n); }} /> : null}
    </>
  );
}

function StepFoot({ onBack, children }: { onBack?: () => void; children: ReactNode }) {
  return (
    <div className="row mt-3">
      {onBack ? <Btn kind="ghost" onClick={onBack}>← Back</Btn> : null}
      <span className="grow" />
      {children}
    </div>
  );
}

function PersonalStep({ me, act, errors, onSaved }: { me: Candidate; act: Act; errors: Record<string, string>; onSaved: (c: Candidate | null) => void }) {
  const [f, setF] = useState<Record<string, string>>(() => ({
    middleName: me.middle_name ?? "", sex: me.sex ?? "", dob: me.date_of_birth ?? "", nin: me.nin ?? "", phone: me.phone ?? "",
    nationality: me.nationality ?? "Nigerian", stateOfOrigin: me.state_of_origin ?? "", lga: me.lga ?? "", contactAddress: me.contact_address ?? "",
    permanentAddress: me.permanent_address ?? "", homeTown: me.home_town ?? "", guardianName: me.guardian_name ?? "", guardianPhone: me.guardian_phone ?? "",
    guardianAddress: me.guardian_address ?? "", nextOfKinName: me.next_of_kin_name ?? "", nextOfKinPhone: me.next_of_kin_phone ?? "", nextOfKinRelationship: me.next_of_kin_relationship ?? "",
  }));
  const [busy, setBusy] = useState(false);
  const set = (k: string) => (e: ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) => setF({ ...f, [k]: e.target.value });
  const nigerian = f.nationality === "Nigerian";
  async function save() {
    setBusy(true);
    try {
      const body = Object.fromEntries(Object.entries(f).map(([k, v]) => [k, v.trim() === "" ? null : v.trim()]));
      onSaved(await act("/api/v1/jupeb/me/biodata", "PUT", body));
    } finally { setBusy(false); }
  }
  const input = (k: string, label: string, o: { max?: number; type?: string; required?: boolean; hint?: string } = {}) => (
    <Field id={`p-${k}`} label={label} required={o.required} hint={o.hint} error={errors[k]}>
      <input id={`p-${k}`} className="ctl" type={o.type ?? "text"} value={f[k] ?? ""} onChange={set(k)} maxLength={o.max ?? 120} />
    </Field>
  );
  return (
    <Panel title="Step 1 · Personal information">
      <PBody>
        <KvGrid pairs={[["Surname", me.surname], ["First name", me.first_name], ["Email", me.email], ["Application number", me.application_no]]} />
        <div className="grid grid--3 mt-3">
          {input("middleName", "Middle name", { max: 80 })}
          <Field id="p-sex" label="Sex" required error={errors.sex}><select id="p-sex" className="ctl" value={f.sex} onChange={set("sex")}><option value="">—</option><option value="F">Female</option><option value="M">Male</option></select></Field>
          {input("dob", "Date of birth", { type: "date", required: true })}
          {input("nin", "NIN", { max: 11, required: true, hint: "Eleven digits" })}
          {input("phone", "Phone", { max: 11, required: true, hint: "e.g. 08012345678" })}
          <Field id="p-nat" label="Nationality">
            <select id="p-nat" className="ctl" value={f.nationality} onChange={(e) => setF({ ...f, nationality: e.target.value, ...(e.target.value === "Nigerian" ? {} : { stateOfOrigin: "", lga: "" }) })}>
              {NATIONALITIES.map((n) => <option key={n} value={n}>{n}</option>)}
            </select>
          </Field>
          <Field id="p-state" label="State of origin" required hint="Decides the indigene school fee" error={errors.stateOfOrigin}>
            <select id="p-state" className="ctl" value={f.stateOfOrigin} onChange={(e) => setF({ ...f, stateOfOrigin: e.target.value, lga: "" })} disabled={!nigerian}>
              <option value="">— Select a state —</option>{STATES.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </Field>
          <Field id="p-lga" label="Local government" required error={errors.lga}>
            <select id="p-lga" className="ctl" value={f.lga} onChange={set("lga")} disabled={!nigerian || !f.stateOfOrigin}>
              <option value="">{f.stateOfOrigin ? "— Select an LGA —" : "Select a state first"}</option>{lgasOf(f.stateOfOrigin).map((l) => <option key={l} value={l}>{l}</option>)}
            </select>
          </Field>
          {input("homeTown", "Home town", { max: 80 })}
        </div>
        <div className="grid grid--2">
          <Field id="p-ca" label="Contact address" required error={errors.contactAddress}><textarea id="p-ca" className="ctl" rows={2} maxLength={300} value={f.contactAddress} onChange={set("contactAddress")} /></Field>
          <Field id="p-pa" label="Permanent home address"><textarea id="p-pa" className="ctl" rows={2} maxLength={300} value={f.permanentAddress} onChange={set("permanentAddress")} /></Field>
        </div>
        <div className="eyebrow mt-3">Parent or guardian</div>
        <div className="grid grid--3">{input("guardianName", "Name")}{input("guardianPhone", "Phone", { max: 11 })}{input("guardianAddress", "Address", { max: 300 })}</div>
        <div className="eyebrow mt-3">Next of kin</div>
        <div className="grid grid--3">{input("nextOfKinName", "Name", { required: true })}{input("nextOfKinPhone", "Phone", { max: 11, required: true })}{input("nextOfKinRelationship", "Relationship", { max: 60 })}</div>
        <StepFoot><Btn kind="primary" size="md" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : "Save & Continue"}</Btn></StepFoot>
      </PBody>
    </Panel>
  );
}

interface Line { subject: string; grade: string }
interface Sitting { examType: string; examNumber: string; examYear: string; lines: Line[] }

function OlevelStep({ me, act, errors, onSaved, onBack }: { me: Candidate; act: Act; errors: Record<string, string>; onSaved: (c: Candidate | null) => void; onBack: () => void }) {
  const init = (n: number): Sitting => {
    const rows = me.olevel.filter((o) => o.sitting === n);
    return {
      examType: rows[0]?.exam_type ?? (n === 1 ? "WAEC" : "NECO"), examNumber: rows[0]?.exam_number ?? "", examYear: rows[0]?.exam_year ? String(rows[0].exam_year) : "",
      lines: rows.length ? rows.map((r) => ({ subject: r.subject, grade: r.grade })) : ["English Language", "Mathematics", "", "", ""].map((s) => ({ subject: n === 1 ? s : "", grade: "" })),
    };
  };
  const [count, setCount] = useState<number>(me.olevel_sittings ?? (me.olevel.some((o) => o.sitting === 2) ? 2 : 1));
  const [s, setS] = useState<Sitting[]>(() => [init(1), init(2)]);
  const [busy, setBusy] = useState(false);
  const upd = (i: number, patch: Partial<Sitting>) => setS(s.map((x, j) => (j === i ? { ...x, ...patch } : x)));
  const updLine = (i: number, k: number, patch: Partial<Line>) => upd(i, { lines: s[i].lines.map((l, m) => (m === k ? { ...l, ...patch } : l)) });
  async function save() {
    const grades = s.slice(0, count).flatMap((x, i) => x.lines.filter((l) => l.subject.trim() && l.grade).map((l) => ({
      sitting: i + 1, examType: x.examType, examNumber: x.examNumber.trim() || null, examYear: x.examYear ? Number(x.examYear) : null, subject: l.subject.trim(), grade: l.grade,
    })));
    setBusy(true);
    try { onSaved(await act("/api/v1/jupeb/me/olevel", "PUT", { sittings: count, grades })); } finally { setBusy(false); }
  }
  const c = me.olevelCheck;
  return (
    <div className="stack">
      <Panel title="Step 2 · O’Level results">
        <PBody>
          <p className="sub2">At least five credits including English Language and Mathematics, in no more than two sittings. With two sittings, enter each sitting&rsquo;s results separately; you upload each result in the next step.</p>
          <Field id="o-count" label="Number of sittings" required error={errors.olevelSittings}>
            <select id="o-count" className="ctl" style={{ maxWidth: 220 }} value={count} onChange={(e) => setCount(Number(e.target.value))}>
              <option value={1}>One sitting</option><option value={2}>Two sittings</option>
            </select>
          </Field>
          {c.sittings > 0 ? <Note kind={c.ok ? "ok" : "info"} title={c.ok ? `Requirement met — ${c.credits} credits` : "Not yet meeting the requirement"}>{c.ok ? "Your combined O’Level meets the JUPEB requirement." : c.reasons.join("; ") + "."}</Note> : null}
        </PBody>
      </Panel>
      <datalist id="olevel-subjects">{OLEVEL_SUBJECTS.map((x) => <option key={x} value={x} />)}</datalist>
      {s.slice(0, count).map((x, i) => (
        <Panel key={i} title={i === 0 ? "First sitting" : "Second sitting"}>
          <PBody>
            <div className="grid grid--3">
              <Field id={`ex-${i}`} label="Examination body" required><select id={`ex-${i}`} className="ctl" value={x.examType} onChange={(e) => upd(i, { examType: e.target.value })}>{OLEVEL_EXAMS.map((t) => <option key={t}>{t}</option>)}</select></Field>
              <Field id={`en-${i}`} label="Examination number" required><input id={`en-${i}`} className="ctl" maxLength={30} value={x.examNumber} onChange={(e) => upd(i, { examNumber: e.target.value })} /></Field>
              <Field id={`ey-${i}`} label="Year" required><input id={`ey-${i}`} className="ctl tnum" inputMode="numeric" maxLength={4} value={x.examYear} onChange={(e) => upd(i, { examYear: e.target.value.replace(/\D/g, "") })} /></Field>
            </div>
            {x.lines.map((l, k) => (
              <div key={k} className="row" style={{ gap: "var(--s-2)", marginTop: "var(--s-2)" }}>
                <input className="ctl grow" list="olevel-subjects" placeholder="Subject" aria-label={`Sitting ${i + 1} subject ${k + 1}`} value={l.subject} onChange={(e) => updLine(i, k, { subject: e.target.value })} maxLength={60} />
                <select className="ctl" style={{ width: 110 }} aria-label={`Sitting ${i + 1} grade ${k + 1}`} value={l.grade} onChange={(e) => updLine(i, k, { grade: e.target.value })}>
                  <option value="">Grade</option>{OLEVEL_GRADES.map((g) => <option key={g}>{g}</option>)}
                </select>
                <Btn kind="ghost" onClick={() => upd(i, { lines: x.lines.filter((_, m) => m !== k) })} aria-label="Remove subject">&times;</Btn>
              </div>
            ))}
            {x.lines.length < 12 ? <div className="mt-2"><Btn kind="ghost" onClick={() => upd(i, { lines: [...x.lines, { subject: "", grade: "" }] })}>Add a subject</Btn></div> : null}
          </PBody>
        </Panel>
      ))}
      <StepFoot onBack={onBack}><Btn kind="primary" size="md" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : "Save & Continue"}</Btn></StepFoot>
    </div>
  );
}

const sittingQ = (d: Doc) => (d.sitting ? `?sitting=${d.sitting}` : "");
const docUrl = (d: Doc) => `/api/bff/api/v1/jupeb/me/documents/${d.kind}/content${sittingQ(d)}`;

/** the candidate's own uploaded documents, viewed in a pop-up */
function useViewer(docs: Doc[]) {
  const [viewing, setViewing] = useState<number | null>(null);
  const viewable = docs.filter((d) => d.filename);
  const list: ViewDoc[] = viewable.map((d) => ({
    key: `${d.kind}:${d.sitting ?? ""}`, label: d.label, filename: d.filename, url: docUrl(d),
    sub: <>{d.exam_body ? `${d.exam_body}${d.exam_year ? ` ${d.exam_year}` : ""} · ` : ""}{d.status ? DOC_STATUS[d.status] ?? d.status : "Uploaded"}</>,
  }));
  const link = (d: Doc, key: string) => (
    <a key={key} href={docUrl(d)} target="_blank" rel="noreferrer" title="View the document" onClick={viewerClick(() => setViewing(viewable.indexOf(d)))}>{d.filename}</a>
  );
  const viewer = viewing != null && list.length ? <DocViewer docs={list} index={viewing} onIndex={setViewing} onClose={() => setViewing(null)} /> : null;
  return { link, viewer };
}

function DocumentRows({ me, act, editable, errors }: { me: Candidate; act: Act; editable: boolean; errors?: Record<string, string> }) {
  const [busy, setBusy] = useState<string | null>(null);
  const { link, viewer } = useViewer(me.documents);
  const key = (d: Doc) => `${d.kind}:${d.sitting ?? ""}`;
  async function upload(d: Doc, file: File | undefined) {
    if (!file) return;
    if (file.size > 5 * 1024 * 1024) { notifyProblem({ status: 400, title: "A document is at most 5 MB." }); return; }
    setBusy(key(d));
    try {
      const base64 = await fileBase64(file);
      const r = await act(`/api/v1/jupeb/me/documents/${d.kind}${sittingQ(d)}`, "POST", { filename: file.name, contentType: file.type || "application/octet-stream", base64 });
      if (r) notify(`${d.label} uploaded.`);
    } finally { setBusy(null); }
  }
  return (
    <>
    {viewer}
    <DTable noPrint pageSize={0} cols={["Document", "Status", "File", "Uploaded", "Action|mid"]} rows={me.documents.map((d) => {
      const replace = d.status === "REJECTED" || d.status === "REPLACEMENT_REQUIRED";
      const can = editable || replace;
      const err = errors?.[`doc:${d.kind}${d.sitting ? `:${d.sitting}` : ""}`];
      return [
        <span key="l"><b>{d.label}</b>{d.required ? <span className="sub2"> · required</span> : null}{d.exam_body ? <div className="sub2">{d.exam_body}{d.exam_year ? ` ${d.exam_year}` : ""}</div> : null}
          {d.review_note ? <div className="sub2">{d.review_note}</div> : null}{err ? <div className="ferr">{err}</div> : null}</span>,
        d.status ? <Pil key="s" kind={stateKind(d.status)}>{DOC_STATUS[d.status] ?? d.status}</Pil> : <Pil key="s" kind={err ? "bad" : "grey"}>Not uploaded</Pil>,
        d.filename ? link(d, "f") : "—",
        day(d.uploaded_at),
        <span key="a" className="row" style={{ gap: "var(--s-1)", justifyContent: "center" }}>
          {can ? (
            <label className="btn btn--secondary btn--sm" style={{ cursor: busy ? "wait" : "pointer" }}>
              {busy === key(d) ? "Uploading…" : d.filename ? "Replace" : "Upload"}
              <input type="file" hidden accept={d.image ? "image/jpeg,image/png" : "application/pdf,image/jpeg,image/png"} onChange={(e) => void upload(d, e.target.files?.[0])} disabled={!!busy} />
            </label>
          ) : null}
          {editable && d.filename ? <Btn kind="ghost" onClick={() => void act(`/api/v1/jupeb/me/documents/${d.kind}${sittingQ(d)}`, "DELETE")}>Remove</Btn> : null}
        </span>,
      ];
    })} />
    </>
  );
}

function DocumentsStep({ me, act, errors, onContinue, onBack }: { me: Candidate; act: Act; errors: Record<string, string>; onContinue: () => void; onBack: () => void }) {
  return (
    <Panel title="Step 3 · Documents" right={<span className="sub2">PDF, JPEG or PNG · at most 5 MB · the passport photograph is an image</span>}>
      <PBody>
        {(me.olevel_sittings ?? 1) === 2 ? <Note kind="info" title="Two sittings">Upload each sitting&rsquo;s O&rsquo;Level result on its own line — both are required.</Note> : null}
        <DocumentRows me={me} act={act} editable errors={errors} />
        <StepFoot onBack={onBack}><Btn kind="primary" size="md" onClick={onContinue}>Save & Continue</Btn></StepFoot>
      </PBody>
    </Panel>
  );
}

/** the subject combinations offered for a programme, grouped by the Board's areas, with the three subjects of each */
function CombinationPicker({ list, value, onChange, id, error }: { list: Combination[]; value: string; onChange: (id: string) => void; id: string; error?: string }) {
  const areas = [...new Set(list.map((c) => c.area ?? "Other"))];
  const chosen = list.find((c) => c.id === value) ?? null;
  return (
    <>
      <Field id={id} label="Subject combination" required error={error} hint={list.length ? "The three subjects you will study and be examined in by the Board." : "No combination is offered for this programme yet."}>
        <select id={id} className="ctl" value={value} onChange={(e) => onChange(e.target.value)} disabled={!list.length}>
          <option value="">— Choose a combination —</option>
          {areas.map((a) => (
            <optgroup key={a} label={a}>
              {list.filter((c) => (c.area ?? "Other") === a).map((c) => <option key={c.id} value={c.id}>{c.code} — {c.subject1}, {c.subject2}, {c.subject3}</option>)}
            </optgroup>
          ))}
        </select>
      </Field>
      {chosen ? <DTable noPrint pageSize={0} cols={["Code", "Subject"]} rows={[[chosen.subject1_code, chosen.subject1], [chosen.subject2_code, chosen.subject2], [chosen.subject3_code, chosen.subject3]]} /> : null}
    </>
  );
}

function ProgrammeStep({ me, act, errors, onSaved, onBack }: { me: Candidate; act: Act; errors: Record<string, string>; onSaved: (c: Candidate | null) => void; onBack: () => void }) {
  const [stream, setStream] = useState<string>(me.stream === "ARTS" ? "NON_SCIENCE" : me.stream ?? "");
  const offered = suiting(me.combinations, stream || null);
  const held = me.combination_id && offered.some((c) => c.id === me.combination_id) ? me.combination_id : "";
  const [combination, setCombination] = useState<string>(held);
  const [busy, setBusy] = useState(false);
  const heldButGone = !!me.combination_id && !held && me.stream === stream;
  async function save() {
    if (!stream) { onSaved(me); return; }
    setBusy(true);
    try { onSaved(await act("/api/v1/jupeb/me/choice", "PUT", { stream, combination: combination || null })); } finally { setBusy(false); }
  }
  return (
    <Panel title="Step 4 · Programme and subject combination">
      <PBody>
        <Field id="g-stream" label="Programme" required error={errors.stream}>
          <select id="g-stream" className="ctl" style={{ maxWidth: 320 }} value={stream}
            onChange={(e) => { setStream(e.target.value); if (!suiting(me.combinations, e.target.value).some((c) => c.id === combination)) setCombination(""); }}>
            <option value="">— Science or Non-Science —</option><option value="SCIENCE">Science</option><option value="NON_SCIENCE">Non-Science</option>
          </select>
        </Field>
        {heldButGone ? <Note kind="bad" title={`${me.combination_code} is no longer offered`}>The University no longer offers the combination you chose. Choose another below.</Note> : null}
        {stream ? <CombinationPicker id="g-comb" list={offered} value={combination} onChange={setCombination} error={errors.combination} /> : null}
        <StepFoot onBack={onBack}><Btn kind="primary" size="md" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : "Save & Continue"}</Btn></StepFoot>
      </PBody>
    </Panel>
  );
}

function ReviewStep({ me, act, onBack, onGo }: { me: Candidate; act: Act; onBack: () => void; onGo: (n: number) => void }) {
  const [busy, setBusy] = useState(false);
  const [ref, setRef] = useState<{ reference: string; amount: number } | null>(null);
  const incomplete = me.steps.steps.filter((s) => s.step !== "REVIEW" && !s.ok);
  const comb = (me.combinations ?? []).find((c) => c.id === me.combination_id);
  async function payFee() {
    const r = await jcall<{ reference: string; amount: number }>("/api/v1/jupeb/me/fee-reference?kind=APPLICATION", "POST");
    if (!r.ok) { notifyProblem(r.problem); return; }
    setRef(r.data);
  }
  async function submit() {
    setBusy(true);
    try {
      const r = await act("/api/v1/jupeb/me/submit");
      if (r) notify("Your application is submitted. We have emailed you.");
    } finally { setBusy(false); }
  }
  return (
    <div className="stack">
      <Panel title="Step 5 · Review your application">
        <PBody>
          {incomplete.length ? <Note kind="bad" title="Not ready to submit">{incomplete.map((s) => (
            <span key={s.step}><a href="#" onClick={(e) => { e.preventDefault(); onGo(STEP_ORDER.indexOf(s.step)); }}>{STEP_TITLE[s.step]}</a>: {s.problems.map((p) => p.message).join("; ")}. </span>
          ))}</Note> : <Note kind="ok" title="Everything is in">Check the details below, then submit. Once submitted, the application cannot be changed unless the JUPEB Office returns it.</Note>}
          <div className="eyebrow mt-2">Personal information</div>
          <KvGrid pairs={[["Name", fullName(me)], ["Sex", me.sex === "F" ? "Female" : me.sex === "M" ? "Male" : "—"], ["Date of birth", day(me.date_of_birth)], ["NIN", me.nin ?? "—"],
            ["Phone", me.phone ?? "—"], ["State / LGA", `${me.state_of_origin ?? "—"} / ${me.lga ?? "—"}`], ["Contact address", me.contact_address ?? "—"], ["Next of kin", me.next_of_kin_name ? `${me.next_of_kin_name} (${me.next_of_kin_phone ?? ""})` : "—"]]} />
          <div className="eyebrow mt-3">O&rsquo;Level ({me.olevel_sittings === 2 ? "two sittings" : "one sitting"})</div>
          <DTable noPrint pageSize={0} cols={["Sitting|num", "Examination", "Number", "Year", "Subject", "Grade|mid"]} rows={me.olevel.map((o) => [o.sitting, o.exam_type, o.exam_number ?? "—", o.exam_year ?? "—", o.subject, o.grade])} />
          <div className="eyebrow mt-3">Documents</div>
          <DTable noPrint pageSize={0} cols={["Document", "File", "Status"]} rows={me.documents.map((d) => [d.label, d.filename ?? "Not uploaded", d.status ? DOC_STATUS[d.status] ?? d.status : "—"])} />
          <div className="eyebrow mt-3">Programme and fee</div>
          <KvGrid pairs={[["Programme", streamLabel(me.stream)], ["Subject combination", comb ? `${comb.code} — ${comb.subject1}, ${comb.subject2}, ${comb.subject3}` : me.combination_code ?? "—"],
            ["Application fee", me.fee_confirmed_at ? `Paid ${day(me.fee_confirmed_at)}` : `Unpaid · ${naira(me.application_fee)}`]]} />
          {!me.fee_confirmed_at ? (
            <div className="mt-3">
              {ref ? (
                <><PayByCard reference={ref.reference} amount={Number(ref.amount)} /><div className="sub2 mt-1">Reference <b className="tnum">{ref.reference}</b>. The page confirms the payment when you return from the gateway.</div></>
              ) : <Btn kind="secondary" onClick={() => void payFee()}>Pay the application fee ({naira(me.application_fee)})</Btn>}
            </div>
          ) : null}
        </PBody>
      </Panel>
      <StepFoot onBack={onBack}><Btn kind="go" size="md" disabled={busy || !me.steps.complete} onClick={() => void submit()}>{busy ? "Submitting…" : me.state === "RETURNED" ? "Submit again" : "Submit application"}</Btn></StepFoot>
    </div>
  );
}

/* ── after submission ───────────────────────────────────────────────────────────────────────────── */

function Overview({ me }: { me: Candidate }) {
  const sc = me.statusChecking;
  const screeningDone = me.screening_state === "CLEARED" || !me.screeningSetting.screening_required;
  const steps: ["done" | "now" | "todo", string, string][] = [
    ["done", "Application submitted", day(me.submitted_at)],
    [sc.paid ? "done" : sc.window_open ? "now" : "todo", "Admission status checked", sc.paid ? day(sc.paid_at) : sc.window_open ? "Checking is open — pay and check" : "Checking is not open yet"],
    [me.accepted_at ? "done" : sc.may_check && sc.status === "ADMITTED" ? "now" : "todo", "Admission accepted (acceptance fee)", me.accepted_at ? day(me.accepted_at) : "—"],
    [me.accepted_at && screeningDone ? "done" : me.accepted_at ? "now" : "todo", "Screening", me.screening_state ? SCREENING_LABEL[me.screening_state] ?? me.screening_state : me.screeningSetting.screening_required ? "Required" : "Not required"],
    [me.activated_at ? "done" : me.accepted_at ? "now" : "todo", "School fee paid — studentship activated", me.activated_at ? day(me.activated_at) : "—"],
    [me.subjects_registered_at ? "done" : me.state === "STUDENT" ? "now" : "todo", "Subject combination registered", me.subjects_registered_at ? day(me.subjects_registered_at) : "—"],
    [me.exam_no ? "done" : "todo", "JUPEB examination number", me.exam_no ?? "—"],
    [me.state === "COMPLETED" ? "done" : "todo", "Results published", me.resultsPublished ? "Published" : "—"],
  ];
  return (
    <>
    <div className="grid grid--2">
      <Panel title="Your progress"><PBody><StepList list={steps} /></PBody></Panel>
      <Panel title="What has happened">
        <PBody>
          <ul style={{ listStyle: "none", margin: 0, padding: 0 }}>
            {[...me.events].reverse().map((e, i) => (
              <li key={i} style={{ padding: "var(--s-2) 0", borderBottom: "1px solid var(--line)" }}>
                <div className="b600">{EVENT_LABEL[e.kind] ?? e.kind}</div>
                <div className="sub2">{e.note ? `${e.note} · ` : ""}{when(e.at)}</div>
              </li>
            ))}
          </ul>
        </PBody>
      </Panel>
    </div>
    <DatesToKnow />
    {me.state === "STUDENT" ? <MyClearance /> : null}
    </>
  );
}

/** a fee's payment: the reference is made by the server, on the Bursary's amount; confirmation is the gateway's, never the page's */
function PayBox({ kind, amount, me, reload, label }: { kind: string; amount: number; me: Candidate; reload: () => Promise<void>; label: string }) {
  const [ref, setRef] = useState<{ reference: string; amount: number } | null>(null);
  const [busy, setBusy] = useState(false);
  const open = me.references.find((x) => x.kind === kind && !x.confirmed_at && new Date(x.expires_at) > new Date());
  async function prepare() {
    setBusy(true);
    try {
      const r = await jcall<{ reference: string; amount: number }>(`/api/v1/jupeb/me/fee-reference?kind=${kind}`, "POST");
      if (!r.ok) { notifyProblem(r.problem); return; }
      setRef(r.data);
    } finally { setBusy(false); }
  }
  async function check(reference: string) {
    setBusy(true);
    try { await jcall("/api/v1/payments/verify", "POST", { reference }); await reload(); } finally { setBusy(false); }
  }
  const r = ref ?? (open ? { reference: open.reference, amount: open.amount } : null);
  return r ? (
    <>
      <PayByCard reference={r.reference} amount={Number(r.amount)} />
      <div className="row mt-2"><Btn kind="secondary" disabled={busy} onClick={() => void check(r.reference)}>{busy ? "Checking…" : "I’ve paid — check now"}</Btn><span className="sub2">Reference <b className="tnum">{r.reference}</b></span></div>
    </>
  ) : <Btn kind="primary" disabled={busy} onClick={() => void prepare()}>{label} ({naira(amount)})</Btn>;
}

function Admission({ me, reload }: { me: Candidate; reload: () => Promise<void> }) {
  const sc = me.statusChecking;
  const status = sc.status ? ADMISSION_STATUS[sc.status] : null;
  const ss = me.screeningSetting;
  return (
    <div className="stack">
      <Panel title="Admission status" right={sc.may_check && status ? <Pil kind={status[1]}>{status[0]}</Pil> : null}>
        <PBody>
          {sc.may_check && status ? (
            <>
              <Note kind={status[1] === "warn" ? "info" : status[1]} title={`Your admission status: ${status[0]}`}>
                {sc.status === "ADMITTED" ? `You are offered provisional admission into the JUPEB programme${me.admission_ref ? ` (${me.admission_ref})` : ""}. ${me.admission_note ?? ""}`
                  : sc.status === "NOT_ADMITTED" ? (me.admission_note ?? me.eligibility_note ?? "You were not offered admission this session.")
                  : sc.status === "PENDING" ? (me.admission_note ?? "A decision on your application is pending.")
                  : sc.status === "REQUIRES_REVIEW" ? "Your application needs your attention: see the return note."
                  : "Your application is being processed. Check again later; you will not pay again."}
              </Note>
              <div className="row">
                <LinkBtn kind="ghost" href="/jupeb/pdf/status">Admission status slip</LinkBtn>
                {sc.status === "ADMITTED" ? <LinkBtn kind="ghost" href="/jupeb/pdf/letter">Admission letter</LinkBtn> : null}
              </div>
            </>
          ) : !sc.valid ? <p className="sub2">Status checking is for a submitted application whose fee is paid.</p>
            : !sc.window_open ? <Note kind="info" title="Admission status checking is not open yet">The Directorate of ICT opens it when admissions are ready. You will pay a status checking fee of {naira(me.feeRule.checking_fee)} once, then check your status as often as you like.</Note>
            : (
              <>
                <p>Pay the admission status checking fee once ({naira(me.feeRule.checking_fee)}) to see your admission status. You will not pay it again.</p>
                <PayBox kind="STATUS_CHECKING" amount={me.feeRule.checking_fee} me={me} reload={reload} label="Pay and check my status" />
              </>
            )}
        </PBody>
      </Panel>
      {sc.may_check && sc.status === "ADMITTED" ? (
        <Panel title="Acceptance" right={me.accepted_at ? <Pil kind="ok">Accepted {day(me.accepted_at)}</Pil> : <Pil kind="warn">Not yet accepted</Pil>}>
          <PBody>
            {me.accepted_at ? (
              <div className="row"><LinkBtn kind="primary" href="/jupeb/pdf/acceptance">Download acceptance letter</LinkBtn><span className="sub2">Your school fees are next (Payments).</span></div>
            ) : (
              <>
                <p>Accept your admission by paying the acceptance fee of {naira(me.feeRule.acceptance_fee)}. Your acceptance letter is issued once the payment is confirmed; school fees follow.</p>
                <PayBox kind="ACCEPTANCE" amount={me.feeRule.acceptance_fee} me={me} reload={reload} label="Pay the acceptance fee" />
              </>
            )}
          </PBody>
        </Panel>
      ) : null}
      {sc.may_check && ADMITTED.has(me.state) && (ss.screening_required || me.screening_state) ? (
        <Panel title="Screening" right={me.screening_state ? <Pil kind={stateKind(me.screening_state)}>{SCREENING_LABEL[me.screening_state] ?? me.screening_state}</Pil> : null}>
          <PBody>
            <KvGrid pairs={[["Venue", me.screening_venue ?? ss.screening_venue ?? "—"], ["When", me.screening_at ? when(me.screening_at) : ss.screening_starts_on ? `${day(ss.screening_starts_on)} – ${day(ss.screening_ends_on)}` : "—"]]} />
            {ss.screening_instructions ? <p className="mt-2" style={{ whiteSpace: "pre-line" }}>{ss.screening_instructions}</p> : null}
            {me.screening_reason ? <Note kind={me.screening_state === "CLEARED" ? "ok" : "bad"} title="From the screening desk">{me.screening_reason}</Note> : null}
          </PBody>
        </Panel>
      ) : null}
    </div>
  );
}

/** the candidate's own password: forced after a temporary one from the JUPEB Office, otherwise when they wish */
function ChangePassword({ forced, onDone }: { forced?: boolean; onDone: (c: Candidate) => void }) {
  const [f, setF] = useState({ current: "", next: "", again: "" });
  const [busy, setBusy] = useState(false);
  const short = f.next.length > 0 && f.next.length < 8;
  const differs = f.again.length > 0 && f.again !== f.next;
  async function save() {
    setBusy(true);
    try {
      const r = await jcall<Candidate>("/api/v1/jupeb/me/password", "POST", { currentPassword: f.current, newPassword: f.next });
      if (!r.ok) { notifyProblem(r.problem); return; }
      setF({ current: "", next: "", again: "" });
      onDone(r.data);
    } finally { setBusy(false); }
  }
  return (
    <Panel title={forced ? "Choose your own password" : "Change your password"}>
      <PBody>
        {forced ? <Note kind="info" title="You signed in with a temporary password">The JUPEB Office set up your account from the old portal&rsquo;s register. Choose your own password to continue; the temporary one stops working.</Note> : null}
        <div className="grid grid--3">
          <Field id="pw-cur" label={forced ? "Temporary password" : "Current password"} required><input id="pw-cur" className="ctl" type="password" autoComplete="current-password" value={f.current} onChange={(e) => setF({ ...f, current: e.target.value })} /></Field>
          <Field id="pw-new" label="New password" required hint="At least eight characters" error={short ? "At least eight characters" : undefined}><input id="pw-new" className="ctl" type="password" autoComplete="new-password" value={f.next} onChange={(e) => setF({ ...f, next: e.target.value })} /></Field>
          <Field id="pw-again" label="New password again" required error={differs ? "The two do not match" : undefined}><input id="pw-again" className="ctl" type="password" autoComplete="new-password" value={f.again} onChange={(e) => setF({ ...f, again: e.target.value })} /></Field>
        </div>
        <div className="row"><Btn kind="primary" disabled={busy || !f.current || f.next.length < 8 || f.next !== f.again} onClick={() => void save()}>{busy ? "Saving…" : "Save my password"}</Btn></div>
      </PBody>
    </Panel>
  );
}

/* ── V350: the refund claim a withdrawal opened: the fees paid, the account to pay into, the Bursary's decision ── */

const CLAIM_WORDS: Record<string, [string, "ok" | "info" | "bad" | "grey" | "warn", string]> = {
  AWAITING_DETAILS: ["Give your account", "warn", "Give the bank account a refund would be paid into; the Bursary then decides."],
  WITH_BURSARY: ["With the Bursary", "info", "The Bursary is considering your claim under its rules."],
  REFUND_PROPOSED: ["Refund being approved", "info", "The Bursary has raised a refund; a second officer approves it before it is paid."],
  REFUND_APPROVED: ["Refund approved", "info", "Your refund is approved and will be paid into the account you gave."],
  REFUND_PAID: ["Refund paid", "ok", "Your refund has been paid into the account you gave."],
  DECLINED: ["Declined", "bad", "The Bursary decided not to refund your fees."],
};
const REFUND_STATE: Record<string, string> = { PROPOSED: "Awaiting approval", APPROVED: "Approved, to be paid", PAID: "Paid", REJECTED: "Not approved" };

function RefundClaimPanel({ claim, act }: { claim: RefundClaim; act: Act }) {
  const locked = !!claim.declined_at || claim.refunds.some((r) => r.state !== "REJECTED");
  const [f, setF] = useState({ bankName: claim.bank_name ?? "", accountName: claim.account_name ?? "", accountNumber: "" });
  const [busy, setBusy] = useState(false);
  const w = CLAIM_WORDS[claim.state.status] ?? [claim.state.status, "grey", ""];
  async function save() {
    setBusy(true);
    try {
      if (await act("/api/v1/jupeb/me/refund-details", "PUT", { bankName: f.bankName.trim(), accountName: f.accountName.trim(), accountNumber: f.accountNumber.trim() })) {
        notify("Your account is with the Bursary for the refund decision.");
        setF({ ...f, accountNumber: "" });
      }
    } finally { setBusy(false); }
  }
  return (
    <Panel title="Refund of your JUPEB fees" right={<Pil kind={w[1]}>{w[0]}</Pil>}>
      <PBody>
        <p className="sub2">{w[2]} Any refund is the Bursary&rsquo;s decision under its own rules; you are told of it by email and here.</p>
        {claim.declined_reason ? <Note kind="bad" title="The Bursary's reason">{claim.declined_reason}</Note> : null}
        <DTable noPrint pageSize={0} cols={["Fee paid", "Reference", "Amount|num", "Paid on"]} rows={claim.payments.map((p) => [FEE_KIND[p.kind] ?? p.kind, p.reference, naira(p.amount), day(p.paidOn)])} />
        {claim.refunds.length ? (
          <DTable noPrint pageSize={0} cols={["Refund", "Against", "Amount|num", "Status"]} rows={claim.refunds.map((r) => [r.reference, r.source, naira(r.amount),
            <Pil key="s" kind={r.state === "PAID" ? "ok" : r.state === "REJECTED" ? "grey" : "info"}>{REFUND_STATE[r.state] ?? r.state}</Pil>])} />
        ) : null}
        {locked ? (
          claim.account_number ? <p className="sub2 mt-1">{`Paid into: ${claim.bank_name} · ${claim.account_name} · ${claim.account_number}`}</p> : null
        ) : (
          <>
            <div className="eyebrow mt-2">The account a refund is paid into{claim.account_number ? ` (now ${claim.bank_name} · ${claim.account_number})` : ""}</div>
            <div className="grid grid--3">
              <Field id="rf-bank" label="Bank" required><input id="rf-bank" className="ctl" maxLength={120} value={f.bankName} onChange={(e) => setF({ ...f, bankName: e.target.value })} /></Field>
              <Field id="rf-name" label="Account name" required hint="As the bank holds it"><input id="rf-name" className="ctl" maxLength={200} value={f.accountName} onChange={(e) => setF({ ...f, accountName: e.target.value })} /></Field>
              <Field id="rf-num" label="Account number" required hint="Ten digits (NUBAN)" error={f.accountNumber && !/^\d{10}$/.test(f.accountNumber) ? "Ten digits" : undefined}>
                <input id="rf-num" className="ctl" inputMode="numeric" maxLength={10} autoComplete="off" value={f.accountNumber} onChange={(e) => setF({ ...f, accountNumber: e.target.value.replace(/\D/g, "") })} /></Field>
            </div>
            <div className="row"><Btn kind="primary" disabled={busy || f.bankName.trim().length < 2 || f.accountName.trim().length < 2 || !/^\d{10}$/.test(f.accountNumber)} onClick={() => void save()}>
              {busy ? "Saving…" : claim.account_number ? "Change the account" : "Give the account"}</Btn></div>
          </>
        )}
      </PBody>
    </Panel>
  );
}

function Payments({ me, reload, act }: { me: Candidate; reload: () => Promise<void>; act: Act }) {
  const f = me.fees;
  /* V350: a withdrawn candidate's refund claim comes first */
  const claim = me.refundClaim ? <RefundClaimPanel claim={me.refundClaim} act={act} /> : null;
  const admitted = !!f && ADMITTED.has(me.state);
  const screeningFirst = me.screeningSetting.screening_required && me.state === "ADMITTED" && me.screening_state !== "CLEARED";
  const rule = me.feeRule;
  /* V347: once the JUPEB Office has put the old portal's payments on the record, the fees read as everyone's — what is paid and what is still owed */
  const oldOnRecord = me.references.some((x) => x.channel === "Old portal");
  if (me.legacy_source && !oldOnRecord) {
    return (
      <div className="stack">
        {claim}
        <Note kind="info" title="Your fees were handled on the old portal">{`You were registered on the old portal (${me.legacy_ref ?? me.application_no}). Fees you paid there are kept by the Bursary; if you are told a balance is owed here, the JUPEB Office will guide you.`}</Note>
        {me.references.length ? (
          <Panel title="Payments made here">
            <PBody><DTable noPrint pageSize={0} cols={["Fee", "Reference", "Amount|num", "Confirmed", "Receipt|mid"]} rows={me.references.map((x: FeeRef) => [
              FEE_KIND[x.kind] ?? x.kind, x.reference, naira(x.amount), x.confirmed_at ? day(x.confirmed_at) : "—",
              x.confirmed_at ? <a key="a" href={`/jupeb/pdf/receipt?ref=${encodeURIComponent(x.reference)}`} target="_blank" rel="noreferrer">Receipt</a> : "—"])} /></PBody>
          </Panel>
        ) : null}
      </div>
    );
  }
  return (
    <div className="stack">
      {claim}
      {me.legacy_source && oldOnRecord ? <Note kind="info" title="Your old-portal payments are on your record">The payments you made on the old portal are listed below as &ldquo;Old portal&rdquo;. Anything still owed is paid here.</Note> : null}
      <Panel title="Payment summary">
        <PBody>
          <DTable noPrint pageSize={0} cols={["Fee", "Amount|num", "Status"]} rows={[
            ["Application fee", naira(rule.application_fee), me.fee_confirmed_at ? <Pil key="a" kind="ok">Paid</Pil> : <Pil key="a" kind="warn">Unpaid</Pil>],
            ["Admission status checking fee", naira(rule.checking_fee), me.checking_paid_at ? <Pil key="b" kind="ok">Paid</Pil> : <Pil key="b" kind="grey">When checking opens</Pil>],
            ["Acceptance fee", naira(rule.acceptance_fee), me.accepted_at ? <Pil key="c" kind="ok">Paid</Pil> : <Pil key="c" kind="grey">If admitted</Pil>],
            ["School fees", f ? naira(f.total) : "—", f && admitted ? <Pil key="d" kind={stateKind(f.status)}>{f.status.replace("_", " ").toLowerCase()}</Pil> : <Pil key="d" kind="grey">After acceptance</Pil>],
          ]} />
        </PBody>
      </Panel>
      {admitted && f ? (
        <Panel title="School fees">
          <PBody>
            <KvGrid pairs={[
              ["Category", `${feeCategoryLabel(f.category)} · ${f.indigene ? `${rule.indigene_state} indigene` : "non-indigene"}`],
              ["School fee", naira(f.total)], ["Paid", naira(f.paid)], ["Outstanding", naira(f.outstanding)],
              [`First semester (${Number(f.first_percent)}%)`, `${naira(f.first_amount)}${f.first_paid ? " · paid" : ""}`],
              [`Second semester (${100 - Number(f.first_percent)}%)`, `${naira(f.second_amount)}${f.second_paid ? " · paid" : ""}`],
            ]} />
            {!me.accepted_at && me.state === "ADMITTED" ? <Note kind="info" title="Acceptance first">Pay the acceptance fee (Admission tab); school fees follow it.</Note>
              : screeningFirst ? <Note kind="info" title="Screening first">School fees open once you are cleared at screening.</Note>
              : f.status !== "PAID" ? (
                <div className="row mt-3" style={{ flexWrap: "wrap", gap: "var(--s-3)" }}>
                  {!f.first_paid ? <PayBox kind="SCHOOL_FIRST" amount={Number(f.first_amount)} me={me} reload={reload} label="Pay first semester" /> : null}
                  {/* V347: the second instalment is the balance the server charges — the second share, or what an old-portal instalment left owing */}
                  {f.first_paid && !f.second_paid && Number(f.outstanding) > 0 ? <PayBox kind="SCHOOL_SECOND" amount={Number(f.outstanding)} me={me} reload={reload}
                    label={Number(f.outstanding) === Number(f.second_amount) ? "Pay second semester" : "Pay the balance"} /> : null}
                  {f.allow_full && Number(f.paid) === 0 ? <PayBox kind="SCHOOL_FULL" amount={Number(f.total)} me={me} reload={reload} label="Pay in full" /> : null}
                </div>
              ) : null}
            {me.accepted_at ? <div className="row mt-2"><LinkBtn kind="ghost" href="/jupeb/pdf/invoice">School fees invoice</LinkBtn></div> : null}
          </PBody>
        </Panel>
      ) : null}
      <Panel title="Payment history">
        <PBody>
          <DTable noPrint pageSize={0} cols={["Fee", "Reference", "Amount|num", "Generated", "Confirmed", "Receipt|mid"]} rows={me.references.map((x: FeeRef) => [
            FEE_KIND[x.kind] ?? x.kind, <span key="r" className="tnum">{x.reference}</span>, naira(x.amount), day(x.created_at),
            x.confirmed_at ? `${day(x.confirmed_at)}${x.channel ? ` · ${x.channel}` : ""}` : <Pil key="p" kind="grey">{new Date(x.expires_at) < new Date() ? "Expired" : "Awaiting payment"}</Pil>,
            x.confirmed_at ? <a key="a" href={`/jupeb/pdf/receipt?ref=${encodeURIComponent(x.reference)}`} target="_blank" rel="noreferrer">Receipt</a> : "—",
          ])} />
        </PBody>
      </Panel>
    </div>
  );
}

function Subjects({ me, act }: { me: Candidate; act: Act }) {
  /* a student from the old portal has no programme recorded: every offered combination, and the one chosen decides it */
  const offered = me.stream ? suiting(me.combinations, me.stream) : (me.combinations ?? []).filter((c) => c.offered);
  const [busy, setBusy] = useState(false);
  const [choice, setChoice] = useState<string>(me.combination_id && offered.some((c) => c.id === me.combination_id) ? me.combination_id : "");
  const chosen = offered.find((c) => c.id === choice) ?? null;
  const open = me.state === "STUDENT" && !me.subjects_registered_at;
  const heldButGone = open && !!me.combination_id && !offered.some((c) => c.id === me.combination_id);
  const rows = me.registered.length ? me.registered.map((r) => [r.code, r.title])
    : chosen ? [[chosen.subject1_code, chosen.subject1], [chosen.subject2_code, chosen.subject2], [chosen.subject3_code, chosen.subject3]]
    : me.subjects.map((s) => [s.code, s.title]);
  return (
    <>
    <Panel title="Subject registration" right={me.subjects_registered_at ? <Pil kind="ok">Registered {day(me.subjects_registered_at)}</Pil> : null}>
      <PBody>
        <KvGrid pairs={[["Programme", streamLabel(me.stream)], ["Combination", me.combination_code ?? "Not yet chosen"], ["Class", me.class_name ?? "Not yet placed"], ["JUPEB examination number", me.exam_no ?? "Not yet assigned"]]} />
        {heldButGone ? <Note kind="bad" title={`${me.combination_code} is no longer offered`}>The University no longer offers the combination you chose on your application. Choose another to register.</Note> : null}
        {open ? (
          <Field id="s-comb" label={`Your subject combination (${streamLabel(me.stream)})`} hint={offered.length ? "The combination you chose on your application is selected; you may choose another until you register." : "No combination is offered for your programme yet; the JUPEB Office will add them."}>
            <select id="s-comb" className="ctl" value={choice} onChange={(e) => setChoice(e.target.value)} disabled={!offered.length}>
              <option value="">— Choose a combination —</option>
              {offered.map((c) => <option key={c.id} value={c.id}>{c.code} — {c.subject1}, {c.subject2}, {c.subject3}</option>)}
            </select>
          </Field>
        ) : null}
        {rows.length ? <DTable noPrint pageSize={0} cols={["Code", "Subject"]} rows={rows} /> : null}
        {open ? (
          <div className="row mt-3"><Btn kind="primary" disabled={busy || !choice} onClick={() => { setBusy(true); void act("/api/v1/jupeb/me/register-subjects", "POST", { combination: choice }).finally(() => setBusy(false)); }}>{busy ? "Registering…" : "Register these three subjects"}</Btn></div>
        ) : me.state === "ADMITTED" ? <p className="hint mt-2">You register your subjects once your school fee activates your studentship.</p> : null}
        {me.subjects_registered_at ? <div className="row mt-3"><LinkBtn kind="ghost" href="/jupeb/pdf/slip">Download registration slip</LinkBtn></div> : null}
      </PBody>
    </Panel>
    {me.subjects_registered_at ? <YourCourses me={me} act={act} /> : null}
    </>
  );
}

/** V353: the student's courses, semester by semester, as the Board's syllabus has them — with each course's syllabus, and the
 *  option they take of an either/or subject (theirs to choose until the examination number is assigned) */
function YourCourses({ me, act }: { me: Candidate; act: Act }) {
  const [d, setD] = useState<{ units: UnitRow[]; syllabus: string | null } | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const chosen = me.registered.map((r) => r.board_subject_id ?? "").join(",");
  useEffect(() => {
    let live = true;
    void jcall<{ units: UnitRow[]; syllabus: string | null }>("/api/v1/jupeb/me/units").then((r) => { if (live && r.ok) setD(r.data); });
    return () => { live = false; };
  }, [chosen]);
  const either = me.registered.filter((r) => r.options?.length);
  async function choose(subjectId: string | undefined, board: string) {
    if (!subjectId || !board) return;
    setBusy(true);
    try { await act("/api/v1/jupeb/me/subject-option", "PUT", { subjectId, boardSubjectId: board }); } finally { setBusy(false); }
  }
  if (!d || !d.units.length) return null;
  return (
    <Panel title={`Your courses${d.syllabus ? ` — ${d.syllabus}` : ""}`}>
      <PBody>
        <p className="sub2">The course units of your three subjects, two in each semester, as the Board&rsquo;s syllabus lists them. Open a course to read what it covers.</p>
        {either.map((r) => (
          <Field key={r.code} id={`opt-${r.code}`} label={`${r.title}: which do you take?`}
            hint={me.exam_no ? "Your examination number is assigned, so the JUPEB Office changes this now." : "Choose the one you will be examined in. You may change it until your examination number is assigned."}>
            <select id={`opt-${r.code}`} className="ctl" style={{ maxWidth: 360 }} disabled={busy || !!me.exam_no} value={r.board_subject_id ?? ""} onChange={(e) => void choose(r.subject_id, e.target.value)}>
              <option value="">— Choose —</option>{(r.options ?? []).map((o) => <option key={o.id} value={o.id}>{`${o.title} (${o.prefix})`}</option>)}
            </select>
          </Field>
        ))}
        <UnitsBySemester units={d.units} showSubject onOpen={(u) => setOpen(unitId(u))} />
      </PBody>
      {open ? <SyllabusModal url={`/api/v1/jupeb/me/units/${open}/syllabus`} onClose={() => setOpen(null)} /> : null}
    </Panel>
  );
}

/** V354: the dates of the session's calendar the JUPEB Office shows the students — what is on, what comes next */
function DatesToKnow() {
  const [d, setD] = useState<{ session: string; today: string; events: CalendarEvent[] } | null>(null);
  useEffect(() => {
    let live = true;
    void jcall<{ session: string; today: string; events: CalendarEvent[] }>("/api/v1/jupeb/me/calendar").then((r) => { if (live && r.ok) setD(r.data); });
    return () => { live = false; };
  }, []);
  if (!d || !d.events.length) return null;
  const today = d.today;
  const ahead = d.events.filter((e) => (e.ends_on ?? e.starts_on) >= today);
  return (
    <Panel title={`Dates to know — ${d.session}`}>
      <PBody>
        {!ahead.length ? <p className="sub2">The session&rsquo;s dates are past.</p> : (
          <DTable noPrint pageSize={0} cols={["When", "What"]} rows={ahead.map((e) => [<span key="d" style={{ whiteSpace: "nowrap" }}>{eventDates(e)}</span>,
            <span key="t">{e.title}{e.starts_on <= today ? <> <Pil kind="ok">On now</Pil></> : null}{e.planned ? <span className="sub2"> (planned — the date may change)</span> : null}</span>])} />
        )}
      </PBody>
    </Panel>
  );
}

/** V354: the student's own clearance to sit the examination — each item, done or what is outstanding */
function MyClearance() {
  const [d, setD] = useState<{ cleared: boolean; checks: ClearanceCheck[] } | null>(null);
  useEffect(() => {
    let live = true;
    void jcall<{ cleared: boolean; checks: ClearanceCheck[] }>("/api/v1/jupeb/me/clearance").then((r) => { if (live && r.ok) setD(r.data); });
    return () => { live = false; };
  }, []);
  if (!d) return null;
  return (
    <Panel title="Your clearance for the examination" right={d.cleared ? <Pil kind="ok">Cleared</Pil> : <Pil kind="warn">Not yet</Pil>}>
      <PBody>
        <p className="sub2">To sit the JUPEB examination your record must be complete. Where something is outstanding, see to it, or ask the JUPEB Office.</p>
        <DTable noPrint pageSize={0} cols={["", "Item", "Note"]} rows={d.checks.map((c) => [<Pil key="p" kind={c.ok ? "ok" : "warn"}>{c.ok ? "Done" : "Outstanding"}</Pil>, c.label, c.ok ? (c.note ?? "—") : c.note ?? "—"])} />
      </PBody>
    </Panel>
  );
}

interface AttendanceRow { session: string; semester: number; code: string; title: string; total: number; present: number; absent: number; late: number; excused: number; rate: number | null; min_percent: number | null; verdict: string | null; at_risk: boolean; counted: number }

/** V344: below the minimum (or close to it) in a subject — said where the student will see it */
function AttendanceWarning({ me, onOpen }: { me: Candidate; onOpen: () => void }) {
  const below = (me.attendanceStanding ?? []).filter((r) => r.verdict === "NOT_ELIGIBLE");
  const risk = (me.attendanceStanding ?? []).filter((r) => r.at_risk);
  const list = (rows: typeof below) => rows.map((r) => `${r.title} ${r.rate == null ? "—" : `${Number(r.rate)}%`}`).join(", ");
  if (below.length) {
    return <Note kind="bad" title={`Your attendance is below the minimum of ${Number(below[0].min_percent)}%`} action={<Btn kind="ghost" onClick={onOpen}>See your attendance</Btn>}>
      {`In ${list(below)}. Attend every class from now on; if you were absent for a good reason, see the JUPEB Office (an excused absence does not count against you).`}</Note>;
  }
  if (risk.length) {
    return <Note kind="info" title="Your attendance is close to the minimum" action={<Btn kind="ghost" onClick={onOpen}>See your attendance</Btn>}>
      {`In ${list(risk)} (minimum ${Number(risk[0].min_percent)}%). Missing more classes would take you below it.`}</Note>;
  }
  return null;
}
interface AttendanceMine { subjects: AttendanceRow[]; recent: { held_on: string; session: string; semester: number; code: string; title: string; status: string; marked_time: string | null; remarks: string | null }[] }

function Attendance() {
  const [data, setData] = useState<AttendanceMine | null>(null);
  const [subject, setSubject] = useState("");
  const [semester, setSemester] = useState("");
  useEffect(() => {
    let live = true;
    void jcall<AttendanceMine>("/api/v1/jupeb/me/attendance").then((r) => { if (live && r.ok) setData(r.data); });
    return () => { live = false; };
  }, []);
  if (!data) return <Note kind="info" title="Loading your attendance…">One moment.</Note>;
  const rows = data.subjects.filter((r) => (!subject || r.code === subject) && (!semester || String(r.semester) === semester));
  const sum = rows.reduce((a, r) => ({ total: a.total + r.total, present: a.present + r.present, absent: a.absent + r.absent, late: a.late + r.late, excused: a.excused + r.excused }), { total: 0, present: 0, absent: 0, late: 0, excused: 0 });
  const rate = sum.total - sum.excused > 0 ? Math.round((10000 * (sum.present + sum.late)) / (sum.total - sum.excused)) / 100 : null;
  return (
    <div className="stack">
      <Panel title="Attendance summary">
        <PBody>
          <div className="row" style={{ gap: "var(--s-2)", marginBottom: "var(--s-2)", flexWrap: "wrap" }}>
            <select className="ctl" style={{ width: 220 }} aria-label="Subject" value={subject} onChange={(e) => setSubject(e.target.value)}><option value="">All subjects</option>{[...new Set(data.subjects.map((r) => r.code))].map((c) => <option key={c} value={c}>{data.subjects.find((r) => r.code === c)?.title}</option>)}</select>
            <select className="ctl" style={{ width: 180 }} aria-label="Semester" value={semester} onChange={(e) => setSemester(e.target.value)}><option value="">Both semesters</option><option value="1">First semester</option><option value="2">Second semester</option></select>
          </div>
          <KvGrid cls="grid--3" pairs={[["Total classes", sum.total], ["Present", sum.present], ["Late", sum.late], ["Absent", sum.absent], ["Excused", sum.excused], ["Attendance rate", rate == null ? "—" : `${rate}%`]]} />
          <DTable noPrint pageSize={0} cols={["Subject", "Semester|num", "Classes|num", "Present|num", "Late|num", "Absent|num", "Excused|num", "Rate|num", "Standing"]} rows={rows.map((r) => [
            r.title, r.semester, r.total, r.present, r.late, r.absent, r.excused, r.rate == null ? "—" : `${Number(r.rate)}%`,
            r.verdict === "NOT_ELIGIBLE" ? <Pil key="v" kind="bad">Below the minimum</Pil> : r.at_risk ? <Pil key="v" kind="warn">Close to the minimum</Pil>
              : r.verdict === "ELIGIBLE" ? <Pil key="v" kind="ok">Meets the minimum</Pil> : r.verdict === "REQUIRES_REVIEW" ? <Pil key="v" kind="grey">All excused</Pil> : <span key="v" className="sub2">—</span>,
          ])} />
        </PBody>
      </Panel>
      <Panel title="Recent classes">
        <PBody><DTable pageSize={20} cols={["Date", "Subject", "Status", "Time", "Remarks"]} rows={data.recent.filter((r) => !subject || r.code === subject).map((r) => [day(r.held_on), r.title,
          <Pil key="s" kind={r.status === "PRESENT" ? "ok" : r.status === "ABSENT" ? "bad" : r.status === "LATE" ? "warn" : "grey"}>{r.status.toLowerCase()}</Pil>, r.marked_time ?? "—", r.remarks ?? "—"])} /></PBody>
      </Panel>
    </div>
  );
}

/* ── V347: the week's lectures, and the practice tests ──────────────────────────────────────────────── */

function Timetable({ me }: { me: Candidate }) {
  const [data, setData] = useState<{ session: string; slots: Slot[]; frames?: Frame[]; semester?: number } | null>(null);
  const [semester, setSemester] = useState("1");
  useEffect(() => {
    let live = true;
    void jcall<{ session: string; slots: Slot[]; frames?: Frame[]; semester?: number }>("/api/v1/jupeb/me/timetable").then((r) => {
      if (!live) return;
      if (r.ok) {
        setData(r.data);
        const sem = r.data.semester ?? 1;
        setSemester(String(r.data.slots.some((x) => x.semester === sem) || !r.data.slots.length ? sem : r.data.slots[0].semester));
      } else notifyProblem(r.problem);
    });
    return () => { live = false; };
  }, []);
  if (!data) return <Note kind="info" title="Loading your timetable…">One moment.</Note>;
  const rows = data.slots.filter((x) => String(x.semester) === semester);
  const frame = data.frames?.find((f) => String(f.semester) === semester);
  return (
    <Panel title={`Lecture timetable · ${semester === "1" ? "first" : "second"} semester ${data.session}`} right={<span className="row">
      <select className="ctl" style={{ width: 180 }} aria-label="Semester" value={semester} onChange={(e) => setSemester(e.target.value)}><option value="1">First semester</option><option value="2">Second semester</option></select>
      {rows.length ? <Btn kind="ghost" onClick={() => printGrid(rows, data.session, Number(semester), `${fullName(me)} · ${me.application_no}${me.class_name ? ` · ${me.class_name}` : ""}`, frame)}>Print / PDF</Btn> : null}
    </span>}>
      <PBody>
        {!rows.length ? <Note kind="info" title="No lectures on the timetable yet">The JUPEB Office publishes the timetable of your subjects here{me.class_name ? ` for ${me.class_name}` : ""}.</Note> : (
          <>
            <p className="sub2">The lectures and practicals of your subjects. Hover a lecture for the Office&rsquo;s note.</p>
            <TimetableGrid slots={rows} frame={frame} />
          </>
        )}
      </PBody>
    </Panel>
  );
}

interface PracticeTest {
  id: string; title: string; instructions: string | null; duration_minutes: number; questions_per_attempt: number; attempts_allowed: number; show_answers: boolean;
  code: string; subject: string; questions: number; used: number; best: number | null; open_attempt: string | null; attempts: string;
  kind?: "PRACTICE" | "MOCK"; opens_at?: string | null; closes_at?: string | null; results_released_at?: string | null;
}
interface PastAttempt { id: string; number: number; submittedAt: string; score: number | null; total: number; percentage: number | null }
interface TopicStanding { topic_id: string; subject_code: string; label: string; answered: number; correct: number; percentage: number }

function Practice() {
  const [tests, setTests] = useState<PracticeTest[] | null>(null);
  const [paper, setPaper] = useState<PracticePaper | null>(null);
  const [busy, setBusy] = useState(false);
  const [tick, setTick] = useState(0);
  const [topics, setTopics] = useState<TopicStanding[]>([]);
  const [now, setNow] = useState("");
  useEffect(() => {
    let live = true;
    void jcall<{ tests: PracticeTest[] }>("/api/v1/jupeb/me/practice").then((r) => { if (live) { if (r.ok) { setTests(r.data.tests); setNow(new Date().toISOString()); } else notifyProblem(r.problem); } });
    void jcall<TopicStanding[]>("/api/v1/jupeb/me/practice/topics").then((r) => { if (live && r.ok) setTopics(r.data); });
    return () => { live = false; };
  }, [tick]);
  async function open(path: string, method = "GET") {
    setBusy(true);
    try {
      const r = await jcall<PracticePaper>(path, method, method === "POST" ? {} : undefined);
      if (r.ok) setPaper(r.data); else notifyProblem(r.problem);
    } finally { setBusy(false); }
  }
  if (paper) return <PracticeRunner paper={paper} setPaper={setPaper} onClose={() => { setPaper(null); setTick((t) => t + 1); }} />;
  if (!tests) return <Note kind="info" title="Loading your practice tests…">One moment.</Note>;
  const past = (t: PracticeTest): PastAttempt[] => { try { return JSON.parse(t.attempts) as PastAttempt[]; } catch { return []; } };
  return (
    <div className="stack">
      <Note kind="info" title="Practice, not examination">Practice tests prepare you for the JUPEB examination. They are timed and marked at once, and never count towards your result.
        A mock examination is sat once, within its window, and its result is shown when the JUPEB Office releases it.</Note>
      <Panel title="Practice tests of your subjects">
        <PBody>
          {!tests.length ? <p className="sub2">No practice test is open for your subjects yet. The JUPEB Office adds them here.</p> : (
            <DTable noPrint pageSize={0} cols={["Subject", "Test", "Questions|num", "Time", "Attempts|num", "Best|num", ""]} rows={tests.map((t) => {
              const left = t.attempts_allowed - Number(t.used);
              const mock = t.kind === "MOCK";
              const notYetOpen = mock && !!t.opens_at && !!now && t.opens_at > now;
              const closed = mock && !!t.closes_at && !!now && t.closes_at <= now;
              return [`${t.code} · ${t.subject}`, <span key="t">{t.title}{mock ? <span className="sub2" style={{ display: "block" }}>{`Mock examination · ${when(t.opens_at ?? "")} – ${when(t.closes_at ?? "")}`}</span> : null}</span>,
                Math.min(t.questions_per_attempt, Number(t.questions)), `${t.duration_minutes} min`, `${t.used}/${t.attempts_allowed}`,
                mock && !t.results_released_at ? (Number(t.used) ? <Pil key="h" kind="info">Result held</Pil> : "—") : t.best == null ? "—" : `${Number(t.best)}%`,
                t.open_attempt ? <Btn key="b" kind="primary" disabled={busy} onClick={() => void open(`/api/v1/jupeb/me/practice/attempts/${t.open_attempt}`)}>Resume</Btn>
                  : notYetOpen ? <span key="b" className="sub2">{`Opens ${when(t.opens_at ?? "")}`}</span>
                  : closed && left > 0 ? <span key="b" className="sub2">Closed</span>
                  : left > 0 ? <Btn key="b" kind="secondary" disabled={busy} onClick={() => void open(`/api/v1/jupeb/me/practice/${t.id}/start`, "POST")}>Start</Btn>
                  : <span key="b" className="sub2">No attempts left</span>];
            })} />
          )}
        </PBody>
      </Panel>
      {topics.length ? (
        <Panel title="Your topics, weakest first">
          <PBody>
            <p className="sub2">How you have answered the questions of each topic of the syllabus in your practice — the topics to read again come first.</p>
            <DTable noPrint pageSize={10} cols={["Subject", "Topic", "Answered|num", "Right|num", "Score|num"]} rows={topics.map((x) => [x.subject_code, x.label, x.answered, x.correct,
              <Pil key="p" kind={Number(x.percentage) >= 70 ? "ok" : Number(x.percentage) >= 50 ? "info" : "warn"}>{`${Number(x.percentage)}%`}</Pil>])} />
          </PBody>
        </Panel>
      ) : null}
      {tests.some((t) => past(t).length) ? (
        <Panel title="Your past attempts">
          <PBody>
            <DTable noPrint pageSize={0} cols={["Test", "Attempt|num", "Submitted", "Score|num", "", ""]} rows={tests.flatMap((t) => past(t).map((a) => [
              t.title, a.number, when(a.submittedAt), a.score == null ? "Held" : `${a.score}/${a.total}`, a.percentage == null ? "—" : `${Number(a.percentage)}%`,
              <Btn key="r" kind="ghost" disabled={busy} onClick={() => void open(`/api/v1/jupeb/me/practice/attempts/${a.id}`)}>Review</Btn>,
            ]))} />
          </PBody>
        </Panel>
      ) : null}
    </div>
  );
}

function PracticeRunner({ paper, setPaper, onClose }: { paper: PracticePaper; setPaper: (p: PracticePaper) => void; onClose: () => void }) {
  const over = !!paper.attempt.submittedAt;
  const [at, setAt] = useState(0);
  const [left, setLeft] = useState(paper.attempt.secondsLeft);
  const [busy, setBusy] = useState(false);
  const deadline = useRef(0);
  const submitted = useRef(false);
  const submit = useCallback(async () => {
    if (submitted.current) return;
    submitted.current = true;
    setBusy(true);
    try {
      const r = await jcall<PracticePaper>(`/api/v1/jupeb/me/practice/attempts/${paper.attempt.id}/submit`, "POST", {});
      if (r.ok) { setPaper(r.data); setAt(0); } else { submitted.current = false; notifyProblem(r.problem); }
    } finally { setBusy(false); }
  }, [paper.attempt.id, setPaper]);
  useEffect(() => {
    if (over) return;
    deadline.current = Date.now() + paper.attempt.secondsLeft * 1000;
    const t = setInterval(() => {
      const s = Math.max(0, Math.round((deadline.current - Date.now()) / 1000));
      setLeft(s);
      if (s === 0) { clearInterval(t); void submit(); }
    }, 1000);
    return () => clearInterval(t);
  }, [over, paper.attempt.secondsLeft, submit]);
  const qs = paper.questions;
  const q = qs[at];
  async function choose(letter: string) {
    if (over || !q) return;
    setPaper({ ...paper, questions: qs.map((x) => (x.id === q.id ? { ...x, chosen: letter } : x)) });
    const r = await jcall(`/api/v1/jupeb/me/practice/attempts/${paper.attempt.id}/answers/${q.id}`, "PUT", { choice: letter });
    if (!r.ok) notifyProblem(r.problem);
  }
  const answered = qs.filter((x) => x.chosen).length;
  const mm = `${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}`;
  return (
    <div className="stack">
      <Panel title={`${paper.test.title} · ${paper.test.kind === "MOCK" ? "mock examination" : `attempt ${paper.attempt.number}`}`} right={over
        ? <span className="row">{paper.attempt.resultsHeld ? <Pil kind="info">Submitted — result held</Pil>
          : <Pil kind={Number(paper.attempt.percentage) >= 50 ? "ok" : "warn"}>{`${paper.attempt.score}/${paper.attempt.total} · ${Number(paper.attempt.percentage)}%`}</Pil>}<Btn kind="ghost" onClick={onClose}>Back to the tests</Btn></span>
        : <span className="row"><Pil kind={left < 60 ? "bad" : left < 300 ? "warn" : "info"}>{`Time left ${mm}`}</Pil><span className="sub2">{answered}/{qs.length} answered</span></span>}>
        <PBody>
          {paper.test.instructions && !over ? <p className="sub2" style={{ whiteSpace: "pre-line" }}>{paper.test.instructions}</p> : null}
          {over && paper.attempt.resultsHeld ? <Note kind="info" title="Your mock examination is submitted">Its result is shown here when the JUPEB Office releases the results.</Note>
            : over && !paper.test.showAnswers ? <Note kind="info" title="Marked">This test shows which you got right, not the answers.</Note> : null}
          <div className="row" style={{ flexWrap: "wrap", gap: 6, marginBottom: "var(--s-3)" }}>
            {qs.map((x, i) => (
              <button key={x.id} type="button" aria-label={`Question ${x.n}`} onClick={() => setAt(i)} className="btn btn--sm"
                style={{ minWidth: 34, fontWeight: i === at ? 700 : 400, outline: i === at ? "2px solid var(--primary)" : undefined,
                  background: over && !paper.attempt.resultsHeld ? (x.correct ? "var(--green-bg)" : "var(--red-bg)") : x.chosen ? "var(--sky-bg)" : undefined }}>{x.n}</button>
            ))}
          </div>
          {q ? (
            <div className="card"><div className="card__body">
              <div className="sub2">Question {q.n} of {qs.length}</div>
              <div className="b600" style={{ margin: "var(--s-2) 0" }}><MathText text={q.stem} /></div>
              {q.image ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={`/api/bff/api/v1/jupeb/me/practice/attempts/${paper.attempt.id}/questions/${q.id}/image`} alt={`Diagram for question ${q.n}`}
                  style={{ width: "auto", height: "auto", maxWidth: "100%", maxHeight: 360, objectFit: "contain", border: "1px solid var(--line)", borderRadius: "var(--r-sm)", background: "#fff", marginBottom: "var(--s-2)" }} />
              ) : null}
              <div className="stack" style={{ gap: "var(--s-2)" }}>
                {Object.entries(q.options).map(([letter, text]) => {
                  const mark = over && q.answer ? (letter === q.answer ? "ok" : letter === q.chosen ? "bad" : null) : null;
                  return (
                    <label key={letter} className="row" style={{ gap: "var(--s-2)", alignItems: "flex-start", cursor: over ? "default" : "pointer", padding: "6px 8px", borderRadius: "var(--r-sm)",
                      border: `1px solid ${mark === "ok" ? "var(--green)" : mark === "bad" ? "var(--red)" : "var(--line)"}` }}>
                      <input type="radio" name={`q-${q.id}`} checked={q.chosen === letter} disabled={over || busy} onChange={() => void choose(letter)} />
                      <span><b>{letter}.</b> <MathText text={text} /></span>
                    </label>
                  );
                })}
              </div>
              {over && !paper.attempt.resultsHeld ? (
                <p className="mt-2">{q.correct ? <Pil kind="ok">Correct</Pil> : <Pil kind="bad">{q.chosen ? "Not correct" : "Not answered"}</Pil>}
                  {q.answer ? <span className="sub2">{` The answer is ${q.answer}. `}<MathText text={q.explanation} /></span> : null}</p>
              ) : null}
            </div></div>
          ) : null}
          <div className="row mt-3">
            <Btn kind="ghost" disabled={at === 0} onClick={() => setAt(at - 1)}>Previous</Btn>
            <Btn kind="ghost" disabled={at >= qs.length - 1} onClick={() => setAt(at + 1)}>Next</Btn>
            <span className="grow" />
            {!over ? <Btn kind="primary" disabled={busy} onClick={() => {
              if (answered < qs.length && !window.confirm(`${qs.length - answered} question${qs.length - answered === 1 ? " is" : "s are"} not answered. Submit anyway?`)) return;
              void submit();
            }}>{busy ? "Marking…" : "Submit"}</Btn> : null}
          </div>
        </PBody>
      </Panel>
    </div>
  );
}

/* ── V349: the JUPEB Office's announcements, and the identity card ───────────────────────────────────── */

function Announcements({ onRead }: { onRead: () => void }) {
  const [list, setList] = useState<Announcement[] | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let live = true;
    void jcall<{ announcements: Announcement[] }>("/api/v1/jupeb/me/announcements").then((r) => { if (live) { if (r.ok) setList(r.data.announcements); else notifyProblem(r.problem); } });
    return () => { live = false; };
  }, []);
  async function read(ids: string[]) {
    setBusy(true);
    try {
      for (const id of ids) await jcall(`/api/v1/jupeb/me/announcements/${id}/read`, "POST", {});
      setList((l) => (l ? l.map((a) => (ids.includes(a.id) ? { ...a, read: true } : a)) : l));
      onRead();
    } finally { setBusy(false); }
  }
  if (!list) return <Note kind="info" title="Loading the announcements…">One moment.</Note>;
  const unread = list.filter((a) => !a.read);
  return (
    <Panel title="Announcements from the JUPEB Office" right={unread.length ? <Btn kind="ghost" disabled={busy} onClick={() => void read(unread.map((a) => a.id))}>Mark all as read</Btn> : null}>
      <PBody>
        {!list.length ? <p className="sub2">No announcement for you yet. Notices from the JUPEB Office appear here, and by email or text when the Office sends them.</p> : (
          <div className="stack">
            {list.map((a) => (
              <div key={a.id} className="card" style={{ borderLeft: `3px solid ${a.read ? "var(--line)" : "var(--primary)"}` }}><div className="card__body">
                <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
                  <span className={a.read ? "b600" : "b700"}>{a.title}</span>
                  {a.pinned ? <Pil kind="info">Pinned</Pil> : null}{!a.read ? <Pil kind="warn">New</Pil> : null}
                  <span className="grow" /><span className="sub2">{when(a.published_at)}{a.expires_on ? ` · until ${day(a.expires_on)}` : ""}</span>
                </div>
                <p style={{ whiteSpace: "pre-line", margin: "var(--s-2) 0 0" }}>{a.body}</p>
                {!a.read ? <div className="row mt-2"><Btn kind="ghost" disabled={busy} onClick={() => void read([a.id])}>Mark as read</Btn></div> : null}
              </div></div>
            ))}
          </div>
        )}
      </PBody>
    </Panel>
  );
}

function IdCardSection({ me }: { me: Candidate }) {
  const [card, setCard] = useState<{ code: string; issued_at: string; issued_office: string | null } | null>(null);
  const [qr, setQr] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  useEffect(() => {
    let live = true;
    void jcall<{ code: string; issued_at: string; issued_office: string | null }>("/api/v1/jupeb/me/id-card", "POST", {}).then(async (r) => {
      if (!live) return;
      if (!r.ok) { setProblem(r.problem); return; }
      setCard(r.data);
      const url = `${window.location.origin}/verify/jupeb/${r.data.code}`;
      const img = await QRCode.toDataURL(url, { errorCorrectionLevel: "M", margin: 1, width: 220 });
      if (live) setQr(img);
    });
    return () => { live = false; };
  }, []);
  if (problem) return <ProblemNotice problem={problem} />;
  if (!card) return <Note kind="info" title="Loading your identity card…">One moment.</Note>;
  const data: IdCardData = {
    name: `${me.surname.toUpperCase()} ${me.first_name}${me.middle_name ? ` ${me.middle_name}` : ""}`, matric: me.application_no,
    barcode: me.application_no.replace(/[^A-Za-z0-9]/g, ""), serial: card.code, faculty: "", prog: streamLabel(me.stream), level: "", session: me.session,
    admitted: "", graduates: "", blood: "", expiresShort: "", kinPhone: me.next_of_kin_phone ?? "—",
    photoSrc: me.has_passport ? `${PHOTO}&v=${encodeURIComponent(me.updated_at)}` : null, tag: "JUPEB",
    rows: [["Programme", streamLabel(me.stream)], ["Combination", me.combination_code ?? "—", true], ["Class", me.class_name ?? "—"],
      ["Exam No.", me.exam_no ?? "—", true], ["Subjects", me.registered.map((r) => r.code).join(", ") || "—", true], ["Session", me.session, true]],
    validity: "valid for the session", qrSrc: qr, verifyText: `${typeof window === "undefined" ? "" : window.location.host}/verify/jupeb`, signatory: "JUPEB Office",
  };
  return (
    <>
      <Note kind="info" title="This is a picture of your card">The JUPEB Office prints and issues the card itself. Its QR code opens the University&rsquo;s record, so a card that is altered or lost and replaced does not verify.</Note>
      <Panel title="Your JUPEB identity card" right={<span className="sub2 tnum">{card.code}</span>}>
        <PBody><IdCardPair c={data} big /></PBody>
      </Panel>
    </>
  );
}

function Results({ me }: { me: Candidate }) {
  if (!me.resultsPublished) return <Note kind="info" title="Results not yet published">Your JUPEB results appear here once the JUPEB Office publishes them. You will be told by email.</Note>;
  const gp = me.gradePoint;
  return (
    <Panel title="JUPEB results" right={<LinkBtn kind="ghost" href="/jupeb/pdf/result">Statement of result</LinkBtn>}>
      <PBody>
        <KvGrid pairs={[["Examination number", me.exam_no ?? "—"], ["Combination", me.combination_code ?? "—"], ["Grade point", gp ? `${Number(gp.total)}/${gp.out_of}` : "—"], ["Session", me.session]]} />
        <DTable noPrint pageSize={0} cols={["Subject", "Grade|mid", "Grade point|num"]} rows={me.registered.map((r) => [r.title, r.grade ?? "—", r.points == null ? "—" : Number(r.points).toFixed(1)])} />
        {gp && gp.bonus ? <p className="hint">One point added: all three subjects are passed.</p> : null}
      </PBody>
    </Panel>
  );
}

/** V355: the continuous assessment of each subject, once the JUPEB Office has locked it */
function MyAssessment() {
  const [d, setD] = useState<{ components: { id: string; code: string; title: string; max_score: number }[]; subjects: { id: string; code: string; title: string; locked_at: string | null; scores: Record<string, number | null>; total: number | null }[] } | null>(null);
  useEffect(() => {
    let live = true;
    void jcall<NonNullable<typeof d>>("/api/v1/jupeb/me/ca").then((r) => { if (live && r.ok) setD(r.data); });
    return () => { live = false; };
  }, []);
  if (!d || !d.components.length || !d.subjects.some((s) => s.locked_at)) return null;
  const outOf = d.components.reduce((n, c) => n + Number(c.max_score), 0);
  const fmt = (n: number | null | undefined) => (n == null ? "—" : String(Number(n)));
  return (
    <Panel title="Continuous assessment">
      <PBody>
        <p className="sub2">Your continuous assessment in each subject, as the JUPEB Office has made it final for the Board. A subject not yet final shows nothing.</p>
        <DTable noPrint pageSize={0} cols={["Subject", ...d.components.map((c) => `${c.title} /${Number(c.max_score)}|num`), `Total /${outOf}|num`]}
          rows={d.subjects.map((s) => [s.title, ...d.components.map((c) => (s.locked_at ? fmt(s.scores?.[c.id]) : "")), s.locked_at ? fmt(s.total) : <span key="n" className="sub2">Not yet final</span>])} />
      </PBody>
    </Panel>
  );
}

/** V355: the examination — the dates, the papers of the student's subjects once the JUPEB Office publishes the timetable, and the admit card */
function Exams() {
  const [d, setD] = useState<MyExams | null>(null);
  useEffect(() => {
    let live = true;
    void jcall<MyExams>("/api/v1/jupeb/me/exams").then((r) => { if (!live) return; if (r.ok) setD(r.data); else notifyProblem(r.problem); });
    return () => { live = false; };
  }, []);
  if (!d) return <Note kind="info" title="Loading your examination…">One moment.</Note>;
  return (
    <div className="stack">
      {d.examinations ? <Note kind="info" title={`The JUPEB examination: ${day(d.examinations.starts_on)}${d.examinations.ends_on && d.examinations.ends_on !== d.examinations.starts_on ? ` – ${day(d.examinations.ends_on)}` : ""}`}>
        {`${d.examinations.title}. Your examination number: ${d.examNo ?? "not yet assigned"}.`}</Note> : null}
      <Panel title={`Your examination timetable · ${d.session}`} right={d.admitCard ? <LinkBtn kind="primary" href="/jupeb/pdf/admit">Admit card</LinkBtn> : null}>
        <PBody>
          {!d.published ? <p className="sub2">The JUPEB Office publishes the timetable of the examination here once the Board releases it. You are told when it is published.</p>
            : !d.papers.length ? <p className="sub2">No paper of your subjects is on the published timetable. Ask the JUPEB Office.</p> : (
              <DTable noPrint pageSize={0} cols={["Day", "Time", "Subject", "Paper", "Centre"]} rows={d.papers.map((x) => [day(x.day), `${x.starts_at}${x.ends_at ? ` – ${x.ends_at}` : ""}`,
                `${x.subject_title}${x.option_title ? ` (${x.option_title})` : ""}`, `${x.title} · ${EXAM_KIND[x.kind] ?? x.kind}`, x.centre ?? "—"])} />
            )}
          {d.published && !d.admitCard ? <p className="sub2 mt-2">{d.cleared ? "Your admit card is issued when your examination number is assigned." : "Your admit card is issued once you are cleared for the examination — see your clearance on the overview."}</p> : null}
        </PBody>
      </Panel>
    </div>
  );
}

function DocumentCentre({ me, act }: { me: Candidate; act: Act }) {
  const sc = me.statusChecking;
  const items: [string, string | null, string][] = [
    ["Application acknowledgement", me.submitted_at ? "/jupeb/pdf/acknowledgement" : null, "after submission"],
    ["Application summary", "/jupeb/pdf/summary", ""],
    ["Admission status slip", sc.may_check ? "/jupeb/pdf/status" : null, "after checking your status"],
    ["Admission letter", sc.may_check && sc.status === "ADMITTED" ? "/jupeb/pdf/letter" : null, "if admitted"],
    ["Acceptance letter", me.accepted_at ? "/jupeb/pdf/acceptance" : null, "after the acceptance fee"],
    ["School fees invoice", me.accepted_at ? "/jupeb/pdf/invoice" : null, "after acceptance"],
    ["Registration slip", me.subjects_registered_at ? "/jupeb/pdf/slip" : null, "after subject registration"],
    ["Statement of result", me.resultsPublished && me.registered.length ? "/jupeb/pdf/result" : null, "once results are published"],
  ];
  return (
    <div className="stack">
      <Panel title="Your JUPEB documents">
        <PBody>
          <DTable noPrint pageSize={0} cols={["Document", "Available"]} rows={items.map(([label, href, later]) => [label,
            href ? <a key="a" href={href} target="_blank" rel="noreferrer">Download</a> : <span key="a" className="sub2">{later ? `Available ${later}` : "—"}</span>])} />
        </PBody>
      </Panel>
      <Panel title="Receipts">
        <PBody>
          <DTable noPrint pageSize={0} cols={["Fee", "Reference", "Amount|num", "Receipt|mid"]} rows={me.references.filter((x) => x.confirmed_at).map((x) => [FEE_KIND[x.kind] ?? x.kind, x.reference, naira(x.amount),
            <a key="r" href={`/jupeb/pdf/receipt?ref=${encodeURIComponent(x.reference)}`} target="_blank" rel="noreferrer">Receipt</a>])} />
        </PBody>
      </Panel>
      <Panel title="Your uploaded documents">
        <PBody>
          {/* a document the JUPEB Office asked to be replaced (or one lost from storage, V348) is uploaded again here */}
          <DocumentRows me={me} act={act} editable={false} />
        </PBody>
      </Panel>
    </div>
  );
}

/** V343: after submission, a change is asked for — never made — and the JUPEB Office decides it */
function Requests({ me, act }: { me: Candidate; act: Act }) {
  const st = me.state;
  const open = me.requests.find((r) => r.state === "PENDING") ?? null;
  const kinds = [
    ...(st !== "COMPLETED" && st !== "WITHDRAWN" ? ["WITHDRAW"] : []),
    ...(st === "ADMITTED" && me.accepted_at ? ["DEFER"] : []),
    ...(!me.exam_no && ["SUBMITTED", "UNDER_REVIEW", "ELIGIBLE", "PENDING", "ADMITTED", "STUDENT", "DEFERRED"].includes(st) ? ["CHANGE_COMBINATION"] : []),
    ...(!me.fees?.frozen && ["SUBMITTED", "UNDER_REVIEW", "ELIGIBLE", "PENDING", "ADMITTED", "DEFERRED"].includes(st) ? ["CHANGE_PROGRAMME"] : []),
  ];
  const [kind, setKind] = useState<string>(kinds.includes("CHANGE_COMBINATION") ? "CHANGE_COMBINATION" : kinds[0] ?? "");
  const [stream, setStream] = useState<string>(me.stream === "SCIENCE" ? "NON_SCIENCE" : "SCIENCE");
  const [comb, setComb] = useState("");
  const [toSession, setToSession] = useState(laterSessions(me.session)[0] ?? "");
  const [reason, setReason] = useState("");
  const [sure, setSure] = useState(false);
  const [busy, setBusy] = useState(false);
  const list = kind === "CHANGE_PROGRAMME" ? suiting(me.combinations, stream) : suiting(me.combinations, me.stream).filter((c) => c.id !== me.combination_id);
  async function send() {
    setBusy(true);
    try {
      const r = await act("/api/v1/jupeb/me/requests", "POST", {
        kind, stream: kind === "CHANGE_PROGRAMME" ? stream : null, combination: kind === "CHANGE_COMBINATION" || kind === "CHANGE_PROGRAMME" ? comb || null : null,
        toSession: kind === "DEFER" ? toSession : null, reason: reason.trim(),
      });
      if (r) { notify("Your request is with the JUPEB Office. You will be told of its decision."); setReason(""); setComb(""); setSure(false); }
    } finally { setBusy(false); }
  }
  return (
    <div className="stack">
      {open ? (
        <Note kind="info" title="Your request is with the JUPEB Office" action={<Btn kind="ghost" onClick={() => void act(`/api/v1/jupeb/me/requests/${open.id}/cancel`)}>Cancel the request</Btn>}>
          {`You asked to ${open.words}, on ${day(open.requested_at)}. One request is open at a time.`}
        </Note>
      ) : kinds.length ? (
        <Panel title="Ask the JUPEB Office for a change">
          <PBody>
            <p className="sub2">Your submitted application is changed only by the JUPEB Office. Say what you need and why; you will be told of the decision by email and here.</p>
            <Field id="rq-kind" label="What do you need?">
              <select id="rq-kind" className="ctl" style={{ maxWidth: 420 }} value={kind} onChange={(e) => { setKind(e.target.value); setComb(""); setSure(false); }}>
                {kinds.map((k) => <option key={k} value={k}>{CHANGE_KIND[k]}</option>)}
              </select>
            </Field>
            {kind === "CHANGE_PROGRAMME" ? (
              <Field id="rq-stream" label="New programme">
                <select id="rq-stream" className="ctl" style={{ maxWidth: 320 }} value={stream} onChange={(e) => { setStream(e.target.value); setComb(""); }}>
                  {me.stream !== "SCIENCE" ? <option value="SCIENCE">Science</option> : null}{me.stream === "SCIENCE" ? <option value="NON_SCIENCE">Non-Science</option> : null}
                </select>
              </Field>
            ) : null}
            {kind === "CHANGE_COMBINATION" || kind === "CHANGE_PROGRAMME" ? <CombinationPicker id="rq-comb" list={list} value={comb} onChange={setComb} /> : null}
            {kind === "DEFER" ? (
              <Field id="rq-session" label="Defer to" hint="Your acceptance and payments stand; school fees are paid in that session.">
                <select id="rq-session" className="ctl" style={{ maxWidth: 220 }} value={toSession} onChange={(e) => setToSession(e.target.value)}>
                  {laterSessions(me.session).map((x) => <option key={x}>{x}</option>)}
                </select>
              </Field>
            ) : null}
            {kind === "WITHDRAW" ? (
              <Note kind="bad" title="Withdrawing ends your application">Your record is kept, but you will not continue in the JUPEB programme. Any refund is the Bursary&rsquo;s decision under its own rules.</Note>
            ) : null}
            <Field id="rq-reason" label="Why?" required hint="At least ten characters"><textarea id="rq-reason" className="ctl" rows={3} maxLength={1000} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
            {kind === "WITHDRAW" ? <label className="row" style={{ gap: "var(--s-1)" }}><input type="checkbox" checked={sure} onChange={(e) => setSure(e.target.checked)} /> I understand and want to withdraw</label> : null}
            <div className="row mt-2"><Btn kind="primary" disabled={busy || reason.trim().length < 10 || ((kind === "CHANGE_COMBINATION" || kind === "CHANGE_PROGRAMME") && list.length > 0 && !comb) || (kind === "WITHDRAW" && !sure)}
              onClick={() => void send()}>{busy ? "Sending…" : "Send the request"}</Btn></div>
          </PBody>
        </Panel>
      ) : <Note kind="info" title="No change can be asked for now">Your record as it stands takes no change request.</Note>}
      {!open && me.state !== "WITHDRAWN" ? <p className="sub2">To correct your name, sex, date of birth, NIN, nationality, state or LGA, ask from My Profile; your phone, addresses, guardian and next of kin you update there yourself.</p> : null}
      <Panel title="Your requests">
        <PBody>
          <DTable noPrint pageSize={0} cols={["Asked", "Request", "Why", "Decision", "Note"]} rows={me.requests.map((r) => [
            day(r.requested_at), r.words, r.reason,
            <Pil key="s" kind={(REQUEST_STATE[r.state] ?? [r.state, "grey"])[1]}>{(REQUEST_STATE[r.state] ?? [r.state])[0]}</Pil>,
            r.decision_note ? `${r.decision_note}${r.decided_at ? ` · ${day(r.decided_at)}` : ""}` : r.decided_at ? day(r.decided_at) : "—",
          ])} />
        </PBody>
      </Panel>
    </div>
  );
}

function SupportTab() {
  const [data, setData] = useState<Support | null>(null);
  const [open, setOpen] = useState<TicketDetail | null>(null);
  const [f, setF] = useState<Record<string, string>>({ issue: "Application" });
  const [reply, setReply] = useState("");
  const [busy, setBusy] = useState(false);
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let live = true;
    void jcall<Support>("/api/v1/jupeb/me/support").then((r) => { if (live && r.ok) setData(r.data); });
    return () => { live = false; };
  }, [tick]);
  const options: string[] = (() => {
    try { const fields = JSON.parse(data?.categories[0]?.fields ?? "[]") as { key: string; options?: string[] }[]; return fields.find((x) => x.key === "jupeb_issue")?.options ?? []; } catch { return []; }
  })();
  async function raise() {
    if (!f.subject?.trim() || !f.description?.trim()) { notifyProblem({ status: 400, title: "Give the ticket a subject and describe the problem." }); return; }
    setBusy(true);
    try {
      const r = await jcall<{ number: string }>("/api/v1/jupeb/me/support", "POST", { category: "JUPEB", subject: f.subject, description: f.description, details: { jupeb_issue: f.issue, payment_reference: f.reference ?? "" } });
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`Ticket ${r.data.number} raised. The JUPEB support desk will answer by email and here.`);
      setF({ issue: "Application" });
      setTick((t) => t + 1);
    } finally { setBusy(false); }
  }
  async function view(id: string) { const r = await jcall<TicketDetail>(`/api/v1/jupeb/me/support/${id}`); if (r.ok) setOpen(r.data); else notifyProblem(r.problem); }
  async function say() {
    if (!open || !reply.trim()) return;
    const r = await jcall<TicketDetail>(`/api/v1/jupeb/me/support/${open.id}/comments`, "POST", { body: reply });
    if (r.ok) { setOpen(r.data); setReply(""); } else notifyProblem(r.problem);
  }
  return (
    <div className="grid grid--2">
      <Panel title="Raise a support ticket">
        <PBody>
          <Field id="t-issue" label="What it is about"><select id="t-issue" className="ctl" value={f.issue} onChange={(e) => setF({ ...f, issue: e.target.value })}>{options.map((o) => <option key={o}>{o}</option>)}</select></Field>
          <Field id="t-subject" label="Subject"><input id="t-subject" className="ctl" maxLength={200} value={f.subject ?? ""} onChange={(e) => setF({ ...f, subject: e.target.value })} /></Field>
          <Field id="t-ref" label="Payment reference, if a payment"><input id="t-ref" className="ctl" maxLength={60} value={f.reference ?? ""} onChange={(e) => setF({ ...f, reference: e.target.value })} /></Field>
          <Field id="t-desc" label="Describe the problem"><textarea id="t-desc" className="ctl" rows={4} maxLength={8000} value={f.description ?? ""} onChange={(e) => setF({ ...f, description: e.target.value })} /></Field>
          <Btn kind="primary" disabled={busy} onClick={() => void raise()}>{busy ? "Sending…" : "Raise ticket"}</Btn>
        </PBody>
      </Panel>
      <Panel title="Your tickets">
        <PBody>
          {open ? (
            <div className="stack">
              <div className="row"><b>{open.number}</b><Pil kind={stateKind(open.status)}>{open.status.replace(/_/g, " ").toLowerCase()}</Pil><span className="grow" /><Btn kind="ghost" onClick={() => setOpen(null)}>Back</Btn></div>
              <div className="b600">{open.subject}</div><p style={{ whiteSpace: "pre-line" }}>{open.description}</p>
              {open.comments.map((c) => <div key={c.id} className="card"><div className="card__body"><div className="sub2">{c.author_name} · {when(c.created_at)}</div><div style={{ whiteSpace: "pre-line" }}>{c.body}</div></div></div>)}
              {open.status !== "CLOSED" ? <><textarea className="ctl" rows={3} aria-label="Reply" value={reply} onChange={(e) => setReply(e.target.value)} /><Btn kind="secondary" onClick={() => void say()}>Reply</Btn></> : null}
            </div>
          ) : data && data.tickets.length ? (
            <DTable noPrint pageSize={0} cols={["Ticket", "Subject", "Status", "Updated"]} rows={data.tickets.map((t) => [
              <a key="n" href="#" onClick={(e) => { e.preventDefault(); void view(t.id); }}>{t.number}</a>, t.subject, t.status.replace(/_/g, " ").toLowerCase(), day(t.updated_at),
            ])} />
          ) : <p className="sub2">No tickets yet.</p>}
        </PBody>
      </Panel>
    </div>
  );
}

function Bare({ children }: { children: ReactNode }) {
  return <div style={{ maxWidth: 640, margin: "var(--s-6) auto", padding: "0 var(--s-4)", display: "grid", gap: "var(--s-3)" }}>{children}</div>;
}
