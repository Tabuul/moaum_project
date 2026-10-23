"use client";

/**
 * V642: the Academic Office student edit page — the record read whole and corrected from one place, each correction by the
 * workflow that owns it. Identity, admission and placement fields are saved here in one transaction (PUT …/edit); the level and
 * the spillover years, the status and the course registration through the page's own endpoints on the same functions the desks
 * use; the programme through the programme swap (check first, the impact shown, then made), the classification through its
 * decision, the matriculation number through Matriculation Correction, graduation through the graduation reconciliation. Every
 * save carries the reading of the record it was made on, and a reason; the change history lists them all.
 */
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState, type ReactNode } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tabs, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Biodata } from "../Biodata";
import type { StudentRecord } from "@/lib/student";
import type { RegistrationView } from "@/lib/student-portal";
import { TargetPicker, type Target } from "@/app/programme-swap/TargetPicker";
import { KIND_WORDS, refusalWords, type CheckResult, type Faculty, type SwapKind } from "@/lib/programme-swap";
import { recBatchPath } from "@/lib/graduation-reconciliation";
import {
  FIELD_WORD, SEVERITY, jambYear, reasonProblem, sessionYear, words,
  type EditPage, type HistoryRow, type Permission,
} from "@/lib/student-edit";

type Section = "identity" | "admission" | "placement" | "level" | "status" | "matriculation" | "registration" | "graduation" | "finance" | "history";
const SECTIONS: [Section, string][] = [
  ["identity", "Biodata"], ["admission", "Admission"], ["placement", "Academic placement"], ["level", "Level & spillover"], ["status", "Academic status"],
  ["matriculation", "Matriculation"], ["registration", "Registration & carry-over"], ["graduation", "Graduation"], ["finance", "Finance"], ["history", "Change history"],
];

type Answer<T> = { ok: true; data: T } | { ok: false; problem: Problem & { code?: string } };

async function call<T>(method: string, path: string, body: unknown, reason: string): Promise<Answer<T>> {
  const r = await fetch(`/api/bff${path}`, {
    method, cache: "no-store",
    headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) },
    body: method === "GET" ? undefined : JSON.stringify(body ?? {}),
  });
  const j = await r.json().catch(() => null);
  return r.ok ? { ok: true, data: j as T } : { ok: false, problem: (j && typeof j === "object" && "status" in j ? j : { status: r.status, title: r.statusText }) as Problem };
}

const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

export function StudentEdit({ page, record, faculties, actingOffice, initialSection }: {
  page: EditPage; record: StudentRecord | null; faculties: Faculty[]; actingOffice: string | null; initialSection?: string | null;
}) {
  const router = useRouter();
  const s = page.student;
  const may = (p: Permission) => page.permissions.includes(p);
  const [section, setSection] = useState<Section>(SECTIONS.some(([k]) => k === initialSection) ? (initialSection as Section) : "identity");
  const [stale, setStale] = useState(false);
  const name = `${s.surname}${s.other_names ? `, ${s.other_names}` : ""}`;

  function choose(k: Section) {
    setSection(k);
    try {
      const u = new URL(window.location.href);
      u.searchParams.set("section", k);
      window.history.replaceState(window.history.state, "", u.toString());
    } catch { /* the address stays */ }
  }

  /** a save's answer: done, refused, or refused because the record moved under it */
  function settle<T>(r: Answer<T>, done: (d: T) => void) {
    if (r.ok) { done(r.data); router.refresh(); return true; }
    if (r.problem.code === "STU_EDIT_STALE" || r.problem.code === "LEVEL_CHANGED") setStale(true);
    notifyProblem(r.problem);
    return false;
  }

  const summary: [ReactNode, ReactNode][] = [
    ["Programme type", s.programme_type_label ?? words(s.programme_type)], ["Admission route", words(s.admission_route ?? s.entry_mode)],
    ["Study mode", words(s.effective_study_mode)], ["Centre", s.centre ?? words(s.centre_code)],
    ["Faculty", s.faculty ?? "—"], ["Department", s.department ?? "—"], ["Programme", s.programme ?? s.programme_code],
    ["Level", `${s.current_level}${page.position?.spillover_state?.startsWith("SPILLOVER") ? ` · ${words(page.position.spillover_state)}` : ""}`],
    ["Academic status", words(s.status)], ["Current session", `${page.session} · ${page.semester === 2 ? "second" : "first"} semester`],
  ];

  return (
    <>
      <Panel title={<span>Student record · <span className="tnum">{s.matric_no ?? s.admission_no ?? s.jamb_reg_no ?? ""}</span></span>}
        right={<span className="row row--inline row--tight"><LinkBtn kind="ghost" href={`/students/${s.id}`}>Full record</LinkBtn><LinkBtn kind="ghost" href="/students/edit">Another student</LinkBtn></span>}>
        <PBody>
          <div className="row" style={{ alignItems: "baseline", flexWrap: "wrap", gap: "var(--s-3)" }}>
            <b style={{ fontSize: "1.15rem" }}>{name}</b>
            <span className="sub2 tnum">JAMB {s.jamb_reg_no ?? "—"} · Admission {s.admission_no ?? "—"} · Application {s.application_no ?? "—"}</span>
          </div>
          {page.enrolments.length > 1 ? (
            <div className="mt-2">
              <div className="eyebrow">Academic enrolment</div>
              <div className="row row--inline" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
                {page.enrolments.map((e) => e.id === s.id
                  ? <Pil key={e.id} kind="info">{e.programme_type ?? "Enrolment"} · {e.programme} · {words(e.status)} (this one)</Pil>
                  : <LinkBtn key={e.id} kind="ghost" href={`/students/${e.id}/edit`}>{e.programme_type ?? "Enrolment"} · {e.programme} · {words(e.status)}</LinkBtn>)}
              </div>
              <div className="sub2 mt-1">An academic change applies to the enrolment open here alone; the student&rsquo;s name and contacts are the person&rsquo;s, on every enrolment.</div>
            </div>
          ) : null}
          <div className="mt-3"><KvGrid cls="grid--5" pairs={summary} /></div>
        </PBody>
      </Panel>

      {stale ? (
        <Note kind="bad" title="This student record was updated by another user" action={<Btn kind="primary" onClick={() => { setStale(false); router.refresh(); }}>Refresh the record</Btn>}>
          Refresh the record before saving your changes. Nothing you were saving was written.
        </Note>
      ) : null}

      <div style={{ maxWidth: "100%", overflowX: "auto" }}>
        <Tabs look="line" label="Sections of the record" value={section} onChange={choose} items={SECTIONS.map(([id, label]) => ({ id, label }))} />
      </div>

      {section === "identity" ? <IdentitySection key={page.version} page={page} record={record} may={may} settle={settle} /> : null}
      {section === "admission" ? <AdmissionSection key={page.version} page={page} may={may} settle={settle} /> : null}
      {section === "placement" ? <PlacementSection key={page.version} page={page} faculties={faculties} may={may} settle={settle} /> : null}
      {section === "level" ? <LevelSection key={page.version} page={page} may={may} settle={settle} /> : null}
      {section === "status" ? <StatusSection key={page.version} page={page} may={may} settle={settle} /> : null}
      {section === "matriculation" ? <MatriculationSection page={page} may={may} /> : null}
      {section === "registration" ? <RegistrationSection page={page} may={may} /> : null}
      {section === "graduation" ? <GraduationSection page={page} may={may} actingOffice={actingOffice} /> : null}
      {section === "finance" ? <FinanceSection page={page} may={may} /> : null}
      {section === "history" ? <HistorySection page={page} may={may} /> : null}
    </>
  );
}

type Settle = <T>(r: Answer<T>, done: (d: T) => void) => boolean;
type May = (p: Permission) => boolean;

/** the reason, the effective session and semester, and — for a critical change — the officer's confirmation */
function ReasonBox({ id, reason, setReason, session, setSession, semester, setSemester, sessions, critical, confirmed, setConfirmed }: {
  id: string; reason: string; setReason: (v: string) => void; session?: string; setSession?: (v: string) => void; semester?: string; setSemester?: (v: string) => void;
  sessions?: { name: string; state: string }[]; critical?: boolean; confirmed?: boolean; setConfirmed?: (v: boolean) => void;
}) {
  const problem = reason.trim() ? reasonProblem(reason) : null;
  return (
    <>
      <Field id={`${id}-reason`} label="Reason for change" required full error={problem}
        hint="What was wrong, and where the right value comes from — the document, the list or the decision. Kept on the record's history.">
        <textarea id={`${id}-reason`} className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)}
          placeholder="Corrected migrated student level based on admission session and academic history." />
      </Field>
      {setSession && sessions ? (
        <div className="grid grid--2">
          <Field id={`${id}-es`} label="Effective session" hint="Blank: from now">
            <select id={`${id}-es`} className="ctl" value={session} onChange={(e) => setSession(e.target.value)}>
              <option value="">From now</option>
              {sessions.map((x) => <option key={x.name} value={x.name}>{x.name}{x.state === "CURRENT" ? " (current)" : ""}</option>)}
            </select>
          </Field>
          {setSemester ? (
            <Field id={`${id}-em`} label="Effective semester">
              <select id={`${id}-em`} className="ctl" value={semester} onChange={(e) => setSemester(e.target.value)}>
                <option value="">Not tied to a semester</option><option value="1">First semester</option><option value="2">Second semester</option>
              </select>
            </Field>
          ) : null}
        </div>
      ) : null}
      {critical && setConfirmed ? (
        <label className="row row--inline mt-2" style={{ gap: "var(--s-2)" }}>
          <input type="checkbox" checked={!!confirmed} onChange={(e) => setConfirmed(e.target.checked)} />
          <span><b>This is a critical change.</b> I have checked it against the University&rsquo;s documents and accept that it is kept in my name.</span>
        </label>
      ) : null}
    </>
  );
}

/** the fields corrected straight on the record, sent together: one transaction, or nothing */
function useFieldEdit(page: EditPage, settle: Settle) {
  const [busy, setBusy] = useState(false);
  async function save(changes: Record<string, string>, reason: string, confirmCritical: boolean, effectiveSession: string, effectiveSemester: string, what: string) {
    setBusy(true);
    try {
      const r = await call<{ changed: number; edits: { field: string; reference: string }[] }>("PUT", `/api/v1/student/students/${page.student.id}/edit`, {
        changes, reason: reason.trim(), version: page.version, confirmCritical,
        effectiveSession: effectiveSession || null, effectiveSemester: effectiveSemester ? Number(effectiveSemester) : null,
      }, `${what} corrected on the student edit page`);
      return settle(r, (d) => notify(`${d.changed} change${d.changed === 1 ? "" : "s"} saved · ${d.edits.map((e) => e.reference).join(", ")}`));
    } finally {
      setBusy(false);
    }
  }
  return { busy, save };
}

function diff(now: Record<string, string>, was: Record<string, string>) {
  const out: Record<string, string> = {};
  for (const k of Object.keys(now)) if ((now[k] ?? "").trim() !== (was[k] ?? "").trim()) out[k] = now[k].trim();
  return out;
}

/* ── biodata: the identity the record holds, corrected here; everything else in the biodata editor ── */

function IdentitySection({ page, record, may, settle }: { page: EditPage; record: StudentRecord | null; may: May; settle: Settle }) {
  const s = page.student;
  const was = useMemo(() => ({ surname: s.surname ?? "", other_names: s.other_names ?? "", sex: s.sex ?? "", date_of_birth: s.date_of_birth ?? "" }), [s]);
  const [f, setF] = useState(was);
  const [reason, setReason] = useState("");
  const { busy, save } = useFieldEdit(page, settle);
  const changes = diff(f, was);
  const can = may("EDIT_STUDENT_BIODATA");
  return (
    <>
      <Panel title="Identity" right={<span className="sub2">Student master data · the same on every enrolment</span>}>
        <PBody>
          {!can ? <Note kind="info" title="Read only">Your office does not hold EDIT_STUDENT_BIODATA.</Note> : null}
          <div className="grid grid--4">
            <Field id="id-sn" label={FIELD_WORD.surname}><input id="id-sn" className="ctl" disabled={!can} value={f.surname} onChange={(e) => setF({ ...f, surname: e.target.value })} /></Field>
            <Field id="id-on" label={FIELD_WORD.other_names}><input id="id-on" className="ctl" disabled={!can} value={f.other_names} onChange={(e) => setF({ ...f, other_names: e.target.value })} /></Field>
            <Field id="id-sx" label={FIELD_WORD.sex}>
              <select id="id-sx" className="ctl" disabled={!can} value={f.sex} onChange={(e) => setF({ ...f, sex: e.target.value })}>
                <option value="">—</option><option value="F">Female</option><option value="M">Male</option>
              </select>
            </Field>
            <Field id="id-db" label={FIELD_WORD.date_of_birth}><input id="id-db" type="date" className="ctl" disabled={!can} value={f.date_of_birth} onChange={(e) => setF({ ...f, date_of_birth: e.target.value })} /></Field>
          </div>
          {can && Object.keys(changes).length ? <ReasonBox id="id" reason={reason} setReason={setReason} /> : null}
          {can ? (
            <div className="row mt-2">
              <Btn kind="primary" busy={busy} busyLabel="Saving…" disabled={!Object.keys(changes).length || !!reasonProblem(reason)}
                onClick={async () => { if (await save(changes, reason, false, "", "", "Identity")) setReason(""); }}>Save identity</Btn>
              <span className="sub2">A name, sex or date of birth corrected here is kept with its reason; the names JAMB sent stay on the admission list.</span>
            </div>
          ) : null}
        </PBody>
      </Panel>
      {record ? <Biodata record={record} may={can} /> : <Note kind="info" title="The biodata could not be read">Open it from the full record.</Note>}
    </>
  );
}

/* ── admission ── */

function AdmissionSection({ page, may, settle }: { page: EditPage; may: May; settle: Settle }) {
  const s = page.student;
  const was = useMemo(() => ({ jamb_reg_no: s.jamb_reg_no ?? "", admission_no: s.admission_no ?? "", entry_session: s.entry_session ?? "",
    entry_mode: s.entry_mode ?? "", entry_level: s.entry_level ? String(s.entry_level) : "" }), [s]);
  const [f, setF] = useState(was);
  const [reason, setReason] = useState("");
  const [confirmed, setConfirmed] = useState(false);
  const { busy, save } = useFieldEdit(page, settle);
  const changes = diff(f, was);
  const can = may("EDIT_STUDENT_ADMISSION");
  const canSession = may("EDIT_STUDENT_SESSION");
  const critical = "jamb_reg_no" in changes || "admission_no" in changes;
  const levels = Array.from({ length: Math.max(1, (s.final_level ?? 400) / 100) }, (_, i) => String((i + 1) * 100));
  const original = page.programmeHistory.find((h) => h.kind === "ORIGINAL_ADMISSION") ?? page.programmeHistory[0] ?? null;
  const admissionYear = s.admission_no && /^MOAUM\/ADM\/(\d{2})\//.test(s.admission_no) ? `20${s.admission_no.slice(10, 12)}` : null;
  return (
    <Panel title="Admission information" right={<span className="sub2">The original admission is kept; a correction is recorded beside it</span>}>
      <PBody>
        <KvGrid pairs={[
          ["Application number", s.application_no ?? "—"], ["Admission list session", s.admission_list_session ?? "—"],
          ["Admitted programme (JAMB list)", s.admitted_programme ?? "—"], ["Admission status", words(s.admission_status)],
          ["Admission date", day(s.admitted_on)], ["Original programme", original ? `${original.programme} · ${original.level ?? "—"} Level` : "—"],
          ["JAMB year", page.position?.jamb_year ?? jambYear(s.jamb_reg_no) ?? "—"], ["Entry year", sessionYear(s.entry_session) ?? "—"],
          ["Admission year", admissionYear ?? "—"], ["Matriculation year", page.position?.matric_year ?? (s.matriculated_at ? new Date(s.matriculated_at).getFullYear() : "—")],
        ]} />
        <div className="eyebrow mt-3">Correct the admission</div>
        {!can ? <Note kind="info" title="Read only">Your office does not hold EDIT_STUDENT_ADMISSION.</Note> : null}
        <div className="grid grid--3">
          <Field id="ad-jamb" label={FIELD_WORD.jamb_reg_no} hint="Critical: confirmed before it is saved"><input id="ad-jamb" className="ctl tnum" disabled={!can} value={f.jamb_reg_no} onChange={(e) => setF({ ...f, jamb_reg_no: e.target.value.toUpperCase() })} /></Field>
          <Field id="ad-adm" label={FIELD_WORD.admission_no} hint="MOAUM/ADM/YY/NNNNNN · critical"><input id="ad-adm" className="ctl tnum" disabled={!can} value={f.admission_no} onChange={(e) => setF({ ...f, admission_no: e.target.value.toUpperCase() })} /></Field>
          <Field id="ad-ses" label={FIELD_WORD.entry_session}>
            <select id="ad-ses" className="ctl" disabled={!canSession} value={f.entry_session} onChange={(e) => setF({ ...f, entry_session: e.target.value })}>
              {was.entry_session && !page.lists.sessions.some((x) => x.name === was.entry_session) ? <option value={was.entry_session}>{was.entry_session} (not on the calendar)</option> : null}
              {page.lists.sessions.map((x) => <option key={x.name} value={x.name}>{x.name}</option>)}
            </select>
          </Field>
          <Field id="ad-mode" label="Entry mode (admission route)">
            <select id="ad-mode" className="ctl" disabled={!can} value={f.entry_mode} onChange={(e) => setF({ ...f, entry_mode: e.target.value })}>
              {page.lists.entryModes.map((m) => <option key={m} value={m}>{words(m)}</option>)}
            </select>
          </Field>
          <Field id="ad-lvl" label={FIELD_WORD.entry_level}>
            <select id="ad-lvl" className="ctl" disabled={!can} value={f.entry_level} onChange={(e) => setF({ ...f, entry_level: e.target.value })}>
              {levels.map((l) => <option key={l} value={l}>{l}</option>)}
            </select>
          </Field>
        </div>
        {Object.keys(changes).length ? (
          <>
            <Note kind={critical ? "bad" : "info"} title={`${Object.keys(changes).length} change${Object.keys(changes).length === 1 ? "" : "s"} to save`}>
              {Object.entries(changes).map(([k, v]) => <div key={k}>{FIELD_WORD[k] ?? k}: <b>{(was as Record<string, string>)[k] || "—"}</b> to <b>{v || "—"}</b></div>)}
            </Note>
            <ReasonBox id="ad" reason={reason} setReason={setReason} critical={critical} confirmed={confirmed} setConfirmed={setConfirmed} />
          </>
        ) : null}
        {can || canSession ? (
          <div className="row mt-2">
            <Btn kind="primary" busy={busy} busyLabel="Saving…" disabled={!Object.keys(changes).length || !!reasonProblem(reason) || (critical && !confirmed)}
              onClick={async () => { if (await save(changes, reason, confirmed, "", "", "Admission")) { setReason(""); setConfirmed(false); } }}>Save admission</Btn>
          </div>
        ) : null}
      </PBody>
    </Panel>
  );
}

/* ── academic placement: the classification, the study mode and centre, and the programme by the programme swap ── */

function PlacementSection({ page, faculties, may, settle }: { page: EditPage; faculties: Faculty[]; may: May; settle: Settle }) {
  const s = page.student;
  const router = useRouter();
  const was = useMemo(() => ({ study_mode: s.study_mode ?? "", centre_code: s.centre_code ?? "", curriculum_track: s.curriculum_track ?? "" }), [s]);
  const [f, setF] = useState(was);
  const [reason, setReason] = useState("");
  const { busy, save } = useFieldEdit(page, settle);
  const changes = diff(f, was);
  const can = may("EDIT_STUDENT_ACADEMIC_PLACEMENT");

  // the classification, by its own decision (StudentClassificationController)
  const [cls, setCls] = useState({ programmeType: s.programme_type ?? "", admissionRoute: s.admission_route ?? "", reason: "" });
  const [clsBusy, setClsBusy] = useState(false);
  const canCls = may("EDIT_STUDENT_CLASSIFICATION");

  // the programme, by the programme swap: checked first, the impact shown, then made
  const [target, setTarget] = useState<Target>({ faculty: "", dept: "", programme: "", level: "" });
  const [swapSession, setSwapSession] = useState("");
  const [kind, setKind] = useState<SwapKind>("PROGRAMME_CORRECTION");
  const [swapReason, setSwapReason] = useState("");
  const [check, setCheck] = useState<CheckResult | null>(null);
  const [swapBusy, setSwapBusy] = useState(false);
  const canProgramme = may("EDIT_STUDENT_PROGRAMME");

  async function runCheck() {
    setSwapBusy(true);
    try {
      const r = await call<CheckResult>("POST", "/api/v1/programme-swaps/check", { studentId: s.id, toProgramme: target.programme, toLevel: Number(target.level), session: swapSession || null },
        "Programme change checked on the student edit page");
      if (r.ok) setCheck(r.data); else notifyProblem(r.problem);
    } finally { setSwapBusy(false); }
  }

  return (
    <>
      <Panel title="Faculty, department and programme" right={<span className="sub2">By the programme swap — the history is kept, nothing deleted</span>}>
        <PBody>
          <KvGrid pairs={[["Faculty", s.faculty ?? "—"], ["Department", s.department ?? "—"], ["Programme", `${s.programme ?? s.programme_code} (${s.programme_code})`], ["Level", s.current_level]]} />
          {!canProgramme ? <Note kind="info" title="Read only">Your office does not hold EDIT_STUDENT_PROGRAMME.</Note> : (
            <>
              <div className="eyebrow mt-3">Move the student to</div>
              <TargetPicker faculties={faculties} value={target} onChange={(t) => { setTarget(t); setCheck(null); }} idPrefix="pl" />
              <div className="grid grid--2">
                <Field id="pl-ses" label="Effective session" hint="Blank: the current session">
                  <select id="pl-ses" className="ctl" value={swapSession} onChange={(e) => { setSwapSession(e.target.value); setCheck(null); }}>
                    <option value="">The current session</option>
                    {page.lists.sessions.map((x) => <option key={x.name} value={x.name}>{x.name}</option>)}
                  </select>
                </Field>
                <Field id="pl-kind" label="Change type">
                  <select id="pl-kind" className="ctl" value={kind} onChange={(e) => setKind(e.target.value as SwapKind)}>
                    {(Object.keys(KIND_WORDS) as SwapKind[]).map((k) => <option key={k} value={k}>{KIND_WORDS[k]}</option>)}
                  </select>
                </Field>
              </div>
              <div className="row mt-2"><Btn kind="secondary" busy={swapBusy && !check} disabled={!target.programme || !target.level} onClick={() => void runCheck()}>Check the change</Btn></div>
              {check ? (
                <div className="mt-3">
                  {check.refusals.length ? (
                    <Note kind="bad" title="The change is refused">{check.refusals.map((r) => <div key={r}>{refusalWords(r)}</div>)}</Note>
                  ) : (
                    <>
                      <Note kind="bad" title="Warning: programme change impact">
                        This student has existing registrations, results and financial records associated with the current programme. Historical records will be preserved.
                        New academic activities will use the new programme after the effective date ({check.session}).
                        {check.registration ? <div className="mt-1">{check.registration.registered} course{check.registration.registered === 1 ? "" : "s"} registered, {check.registration.applicable} applicable to the new programme, {check.registration.missingCore.length} core course{check.registration.missingCore.length === 1 ? "" : "s"} of the new programme missing.</div> : null}
                        {check.fees ? <div className="mt-1">School fees for {check.fees.session}: ₦{Number(check.fees.current).toLocaleString()} now, ₦{Number(check.fees.new).toLocaleString()} on the new programme.</div> : null}
                        {check.warnings.map((w) => <div key={w.code} className="mt-1">{w.text}</div>)}
                      </Note>
                      <ReasonBox id="pl" reason={swapReason} setReason={setSwapReason} />
                      <div className="row mt-2">
                        <Btn kind="primary" busy={swapBusy} busyLabel="Moving…" disabled={!!reasonProblem(swapReason)} onClick={async () => {
                          setSwapBusy(true);
                          try {
                            const r = await call<{ swap_ref?: string; status?: string }>("POST", "/api/v1/programme-swaps", {
                              studentId: s.id, toProgramme: target.programme, toLevel: Number(target.level), session: swapSession || null, kind, reason: swapReason.trim(),
                            }, `Programme change made on the student edit page: ${s.programme_code} to ${target.programme}`);
                            if (r.ok) { notify(`Programme changed${r.data.swap_ref ? ` · ${r.data.swap_ref}` : ""}`); setCheck(null); setSwapReason(""); setTarget({ faculty: "", dept: "", programme: "", level: "" }); router.refresh(); }
                            else notifyProblem(r.problem);
                          } finally { setSwapBusy(false); }
                        }}>Confirm the programme change</Btn>
                      </div>
                    </>
                  )}
                </div>
              ) : null}
            </>
          )}
        </PBody>
      </Panel>

      <Panel title="Programme type and admission route" right={<span className="sub2">The classification decision · {words(s.classification_status)}</span>}>
        <PBody>
          <div className="grid grid--2">
            <Field id="pl-pt" label="Programme type">
              <select id="pl-pt" className="ctl" disabled={!canCls} value={cls.programmeType} onChange={(e) => setCls({ ...cls, programmeType: e.target.value })}>
                <option value="">—</option>
                {page.lists.programmeTypes.map((t) => <option key={t.code} value={t.code}>{t.label}</option>)}
              </select>
            </Field>
            <Field id="pl-ar" label="Admission route" hint="As the classification holds it — UTME, DIRECT_ENTRY, TRANSFER …">
              <input id="pl-ar" className="ctl" disabled={!canCls} value={cls.admissionRoute} onChange={(e) => setCls({ ...cls, admissionRoute: e.target.value.toUpperCase() })} />
            </Field>
          </div>
          {canCls && (cls.programmeType !== (s.programme_type ?? "") || cls.admissionRoute !== (s.admission_route ?? "")) ? (
            <>
              <ReasonBox id="pl-cls" reason={cls.reason} setReason={(v) => setCls({ ...cls, reason: v })} />
              <div className="row mt-2">
                <Btn kind="primary" busy={clsBusy} busyLabel="Saving…" disabled={!cls.programmeType || !!reasonProblem(cls.reason)} onClick={async () => {
                  setClsBusy(true);
                  try {
                    const r = await call("POST", `/api/v1/student-classification/${s.id}`, { programmeType: cls.programmeType, admissionRoute: cls.admissionRoute || null, centre: f.centre_code || null, reason: cls.reason.trim() },
                      "Student classification decided on the student edit page");
                    if (r.ok) { notify("Classification saved"); setCls({ ...cls, reason: "" }); router.refresh(); } else notifyProblem(r.problem);
                  } finally { setClsBusy(false); }
                }}>Save classification</Btn>
              </div>
            </>
          ) : null}
        </PBody>
      </Panel>

      <Panel title="Study mode, centre and curriculum">
        <PBody>
          {!can ? <Note kind="info" title="Read only">Your office does not hold EDIT_STUDENT_ACADEMIC_PLACEMENT.</Note> : null}
          <div className="grid grid--3">
            <Field id="pl-sm" label={FIELD_WORD.study_mode}>
              <select id="pl-sm" className="ctl" disabled={!can} value={f.study_mode} onChange={(e) => setF({ ...f, study_mode: e.target.value })}>
                <option value="">As the classification reads it</option>
                {page.lists.studyModes.map((m) => <option key={m} value={m}>{words(m)}</option>)}
              </select>
            </Field>
            <Field id="pl-ce" label={FIELD_WORD.centre_code}>
              <select id="pl-ce" className="ctl" disabled={!can} value={f.centre_code} onChange={(e) => setF({ ...f, centre_code: e.target.value })}>
                <option value="">—</option>
                {was.centre_code && !page.lists.centres.some((c) => c.code === was.centre_code) ? <option value={was.centre_code}>{was.centre_code}</option> : null}
                {page.lists.centres.map((c) => <option key={c.code} value={c.code}>{c.name}</option>)}
              </select>
            </Field>
            <Field id="pl-tr" label={FIELD_WORD.curriculum_track}>
              <select id="pl-tr" className="ctl" disabled={!can} value={f.curriculum_track} onChange={(e) => setF({ ...f, curriculum_track: e.target.value })}>
                <option value="">The programme&rsquo;s own</option>
                {page.lists.tracks.map((t) => <option key={t} value={t}>{t}</option>)}
              </select>
            </Field>
          </div>
          {can && Object.keys(changes).length ? <ReasonBox id="pl-f" reason={reason} setReason={setReason} /> : null}
          {can ? (
            <div className="row mt-2">
              <Btn kind="primary" busy={busy} busyLabel="Saving…" disabled={!Object.keys(changes).length || !!reasonProblem(reason)}
                onClick={async () => { if (await save(changes, reason, false, "", "", "Academic placement")) setReason(""); }}>Save academic placement</Btn>
            </div>
          ) : null}
        </PBody>
      </Panel>
    </>
  );
}

/* ── level and spillover: stored against calculated, and the correction ── */

function LevelSection({ page, may, settle }: { page: EditPage; may: May; settle: Settle }) {
  const s = page.student;
  const o = page.levelOptions;
  const p = page.position;
  const [action, setAction] = useState<"CORRECTION" | "PROGRESS" | "SPILLOVER">("CORRECTION");
  const [level, setLevel] = useState("");
  const [year, setYear] = useState("");
  const [reason, setReason] = useState("");
  const [ack, setAck] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const canLevel = may("EDIT_STUDENT_LEVEL");
  const canSpill = may("EDIT_STUDENT_SPILLOVER");
  const differs = p && p.computed_level != null && p.computed_level !== s.current_level;
  const recommendation = !p ? "—" : differs || (p.confidence && p.confidence !== "HIGH") ? "REVIEW" : "AS STORED";
  const ready = !reasonProblem(reason) && (action === "PROGRESS" ? !!o.nextLevel : action === "CORRECTION" ? !!level : year !== "");

  async function apply(acknowledge: boolean) {
    setBusy(true);
    try {
      const r = await call<{ previousLevel: number; newLevel: number; reference?: string }>("POST", `/api/v1/student/students/${s.id}/edit/level`, {
        action, level: action === "CORRECTION" ? Number(level) : action === "PROGRESS" ? o.nextLevel : null, spilloverYear: action === "SPILLOVER" ? Number(year) : null,
        expected: s.current_level, reason: reason.trim(), acknowledgeRegistration: acknowledge, version: page.version,
      }, `Student level ${action.toLowerCase()} on the student edit page`);
      if (!r.ok && r.problem.code === "LEVEL_REGISTRATION_ACK") { setAck(r.problem.detail ?? "The student has registered for the session."); return; }
      if (settle(r, (d) => notify(`Level ${d.previousLevel} to ${d.newLevel}${d.reference ? ` · ${d.reference}` : ""}`))) { setReason(""); setLevel(""); setYear(""); setAck(null); }
    } finally { setBusy(false); }
  }

  return (
    <>
      <Panel title="Where the student stands" right={<span className="sub2">The cohort engine&rsquo;s reading, against the record</span>}>
        <PBody>
          <div className="grid grid--3">
            <div className="card" style={{ padding: "var(--s-3)" }}><div className="eyebrow">Stored</div><b style={{ fontSize: "1.6rem" }} className="tnum">{s.current_level}</b><div className="sub2">{words(s.status)}</div></div>
            <div className="card" style={{ padding: "var(--s-3)" }}><div className="eyebrow">Calculated</div><b style={{ fontSize: "1.6rem" }} className="tnum">{p?.computed_level ?? "—"}{p?.spillover_state?.startsWith("SPILLOVER_YEAR_") ? ` · SP${p.spillover_state.slice(-1)}` : ""}</b><div className="sub2">{words(p?.spillover_state)}</div></div>
            <div className="card" style={{ padding: "var(--s-3)" }}><div className="eyebrow">Recommendation</div><b style={{ fontSize: "1.6rem" }}>{recommendation}</b><div className="sub2">{p?.rule ? words(p.rule) : "—"}{p?.confidence ? ` · ${words(p.confidence)} confidence` : ""}</div></div>
          </div>
          <div className="mt-3"><KvGrid pairs={[["Admission session", p?.entry_session ?? s.entry_session ?? "—"], ["Effective cohort", p?.effective_cohort ?? "—"],
            ["Programme duration", p?.duration_years ? `${p.duration_years} years (${p.final_level} Level)` : "—"], ["Expected completion", p?.expected_completion ?? "—"],
            ["Spillover years", p?.spillover_years != null ? `${p.spillover_years} of ${p.max_spillover ?? 2} allowed` : "—"], ["Graduation reading", words(p?.graduation_state)],
            ["Proposed status", words(p?.proposed_status)], ["Last session registered", p?.last_session ?? "—"]]} /></div>
        </PBody>
      </Panel>
      <Panel title="Correct the level" right={<span className="sub2">The programme&rsquo;s levels: {o.levels.join(", ")}</span>}>
        <PBody>
          {!canLevel && !canSpill ? <Note kind="info" title="Read only">Your office does not hold EDIT_STUDENT_LEVEL or EDIT_STUDENT_SPILLOVER.</Note> : (
            <>
              <div className="row row--inline" style={{ gap: "var(--s-3)", flexWrap: "wrap" }}>
                {canLevel ? <label className="row row--inline"><input type="radio" checked={action === "CORRECTION"} onChange={() => setAction("CORRECTION")} /> Correct the level</label> : null}
                {canLevel && o.nextLevel ? <label className="row row--inline"><input type="radio" checked={action === "PROGRESS"} onChange={() => setAction("PROGRESS")} /> Progress to {o.nextLevel}</label> : null}
                {canSpill && !o.postgraduate ? <label className="row row--inline"><input type="radio" checked={action === "SPILLOVER"} onChange={() => setAction("SPILLOVER")} /> SP1, SP2 or the final year</label> : null}
              </div>
              {action === "CORRECTION" ? (
                o.correctRefusal ? <Note kind="bad" title="Not correctable now">{refusalWords(o.correctRefusal)}</Note> : (
                  <Field id="lv-l" label={<>Current <b className="tnum">{s.current_level}</b> · new level</>}>
                    <select id="lv-l" className="ctl" value={level} onChange={(e) => setLevel(e.target.value)}>
                      <option value="">Choose</option>
                      {o.otherLevels.map((l) => <option key={l} value={l}>{l}</option>)}
                    </select>
                  </Field>
                )
              ) : null}
              {action === "PROGRESS" && o.progressRefusal ? <Note kind="bad" title="Not progressed now">{refusalWords(o.progressRefusal)}</Note> : null}
              {action === "SPILLOVER" ? (
                <Field id="lv-sp" label="Spillover year" hint={`At the final level (${o.finalLevel}); the expected completion is pinned so the cohort engine counts this session as that year`}>
                  <select id="lv-sp" className="ctl" value={year} onChange={(e) => setYear(e.target.value)}>
                    <option value="">Choose</option>
                    <option value="0">The final year</option>
                    {(o.spilloverChoices ?? []).map((c) => <option key={c.year} value={c.year}>SP{c.year} (expected completion {c.completion})</option>)}
                  </select>
                </Field>
              ) : null}
              <ReasonBox id="lv" reason={reason} setReason={setReason} />
              {ack ? (
                <Note kind="bad" title="The student has registered for this session" action={<Btn kind="primary" busy={busy} onClick={() => void apply(true)}>I have seen this — apply</Btn>}>{ack}</Note>
              ) : (
                <div className="row mt-2"><Btn kind="primary" busy={busy} busyLabel="Saving…" disabled={!ready} onClick={() => void apply(false)}>Save level</Btn></div>
              )}
            </>
          )}
        </PBody>
      </Panel>
    </>
  );
}

/* ── academic status ── */

function StatusSection({ page, may, settle }: { page: EditPage; may: May; settle: Settle }) {
  const s = page.student;
  const [to, setTo] = useState("");
  const [instrument, setInstrument] = useState("");
  const [effectiveOn, setEffectiveOn] = useState("");
  const [session, setSession] = useState("");
  const [semester, setSemester] = useState("");
  const [reason, setReason] = useState("");
  const [confirmed, setConfirmed] = useState(false);
  const [busy, setBusy] = useState(false);
  const can = may("EDIT_STUDENT_STATUS");
  return (
    <>
      <Panel title="Academic status" right={<Pil kind={s.status === "ACTIVE" ? "ok" : s.status === "GRADUATED" ? "info" : "warn"}>{words(s.status)}</Pil>}>
        <PBody>
          {s.status === "GRADUATED" ? <Note kind="info" title="Graduated">A graduated record leaves that status only through a graduation correction by the Registrar.</Note> : null}
          {!can ? <Note kind="info" title="Read only">Your office does not hold EDIT_STUDENT_STATUS.</Note> : s.status !== "GRADUATED" ? (
            <>
              <div className="grid grid--3">
                <Field id="st-to" label={<>Previous <b>{words(s.status)}</b> · new status</>}>
                  <select id="st-to" className="ctl" value={to} onChange={(e) => setTo(e.target.value)}>
                    <option value="">Choose</option>
                    {page.statuses.filter((x) => x !== s.status).map((x) => <option key={x} value={x}>{words(x)}</option>)}
                  </select>
                </Field>
                <Field id="st-in" label="Instrument" hint="The Senate minute, the letter, the Registrar's decision"><input id="st-in" className="ctl" value={instrument} onChange={(e) => setInstrument(e.target.value)} /></Field>
                <Field id="st-on" label="Effective date"><input id="st-on" type="date" className="ctl" value={effectiveOn} onChange={(e) => setEffectiveOn(e.target.value)} /></Field>
              </div>
              <div className="sub2">Graduation is applied from the Graduation section, never by setting the status.</div>
              <ReasonBox id="st" reason={reason} setReason={setReason} session={session} setSession={setSession} semester={semester} setSemester={setSemester}
                sessions={page.lists.sessions} critical confirmed={confirmed} setConfirmed={setConfirmed} />
              <div className="row mt-2">
                <Btn kind="primary" busy={busy} busyLabel="Saving…" disabled={!to || !instrument.trim() || !!reasonProblem(reason) || !confirmed} onClick={async () => {
                  setBusy(true);
                  try {
                    const r = await call<{ from: string; to: string; reference: string }>("POST", `/api/v1/student/students/${s.id}/edit/status`, {
                      to, instrument: instrument.trim(), effectiveOn: effectiveOn || null, effectiveSession: session || null, effectiveSemester: semester ? Number(semester) : null,
                      reason: reason.trim(), confirmCritical: confirmed, version: page.version,
                    }, `Student status changed to ${to} on the student edit page`);
                    if (settle(r, (d) => notify(`Status ${words(d.from)} to ${words(d.to)} · ${d.reference}`))) { setTo(""); setInstrument(""); setReason(""); setConfirmed(false); }
                  } finally { setBusy(false); }
                }}>Save status</Btn>
              </div>
            </>
          ) : null}
        </PBody>
      </Panel>
      <Panel title="Status history">
        {page.statusHistory.length ? <DTable pageSize={10} cols={["Effective|mid", "From", "To", "Instrument", "Reason"]} rows={page.statusHistory.map((h, i) => [
          <span key={`d${i}`} className="tnum">{day(h.effective_on)}</span>, words(h.from_status), <b key={`t${i}`}>{words(h.to_status)}</b>, h.instrument, <span key={`r${i}`} className="sub2">{h.reason ?? "—"}</span>,
        ])} /> : <PBody><div className="sub2">No change of status on record.</div></PBody>}
      </Panel>
    </>
  );
}

/* ── matriculation: read here, corrected by Matriculation Correction ── */

function MatriculationSection({ page, may }: { page: EditPage; may: May }) {
  const s = page.student;
  return (
    <Panel title="Matriculation">
      <PBody>
        <KvGrid pairs={[["Matriculation number", <b key="m" className="tnum">{s.matric_no ?? "—"}</b>], ["Status", s.matric_no ? "Matriculated" : "Not yet matriculated"],
          ["Date issued", day(s.matriculated_at)], ["Matriculation year", page.position?.matric_year ?? (s.matriculated_at ? new Date(s.matriculated_at).getFullYear() : "—")],
          ["Matriculation run", s.matriculation_run ?? "—"], ["Admission session", s.entry_session ?? "—"]]} />
        <Note kind="info" title="An issued matriculation number is corrected by Matriculation Correction"
          action={may("EDIT_STUDENT_MATRICULATION") && s.matric_no ? <LinkBtn kind="primary" href={`/matriculation/corrections?student=${s.id}`}>Correct the matriculation number</LinkBtn> : undefined}>
          It is not overwritten from this page: the correction checks the number, keeps the old one as an alias, and is kept with its approval and audit.
        </Note>
      </PBody>
    </Panel>
  );
}

/* ── course registration and carry-over: the registration engine's own acts ── */

type RegCurrent = { registration: { id: string; status: string; level: number; units: number; returned_comment: string | null } | null;
  courses: { offering_id: string; course_code: string; title: string; units: number; basis: string; level: number; semester: number; status: string; support_override_at: string | null; support_override_reason: string | null }[] };
type RegData = { view: RegistrationView & { window?: { open?: boolean; gate?: string | null } ; clears?: boolean }; current: RegCurrent; manage: boolean; override: boolean };
type Rule = { ord: number; rule: string; passed: boolean; overridable: boolean; detail: string | null };
type Act = { verb: "add" | "drop" | "restore"; offering: string; code: string; title: string; rules: Rule[] | null; allowed: boolean; overridable: boolean; mayOverride: boolean };

function RegistrationSection({ page, may }: { page: EditPage; may: May }) {
  const s = page.student;
  const [sel, setSel] = useState({ session: page.session, semester: String(page.semester) });
  const [reg, setReg] = useState<RegData | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [act, setAct] = useState<Act | null>(null);
  const [reason, setReason] = useState("");
  const [override, setOverride] = useState(false);
  const [description, setDescription] = useState("");
  const [busy, setBusy] = useState(false);
  const [q, setQ] = useState("");
  const [found, setFound] = useState<{ offering_id: string; course_code: string; title: string; units: number }[]>([]);
  const base = `/api/v1/student/students/${s.id}/edit/registration`;

  useEffect(() => {
    let live = true;
    void call<RegData>("GET", `${base}?session=${encodeURIComponent(sel.session)}&semester=${sel.semester}`, null, "Registration read").then((r) => {
      if (!live) return;
      if (r.ok) { setReg(r.data); setProblem(null); } else setProblem(r.problem);
    });
    return () => { live = false; };
  }, [base, sel.session, sel.semester]);

  async function open(verb: Act["verb"], offering: string, code: string, title: string) {
    setReason(""); setOverride(false); setDescription("");
    setAct({ verb, offering, code, title, rules: null, allowed: false, overridable: false, mayOverride: false });
    const r = await call<{ rules: Rule[]; allowed: boolean; overridable: boolean; mayOverride: boolean }>("GET",
      `${base}/checks?session=${encodeURIComponent(sel.session)}&semester=${sel.semester}&offering=${offering}&verb=${verb === "drop" ? "drop" : "add"}`, null, "Registration rules read");
    if (r.ok) setAct({ verb, offering, code, title, ...r.data }); else { notifyProblem(r.problem); setAct(null); }
  }

  async function perform(verb: string, offering: string | null) {
    setBusy(true);
    try {
      const r = await call<{ reference: string; view: RegData["view"]; current: RegCurrent }>("POST", `${base}/${verb}`, {
        session: sel.session, semester: Number(sel.semester), offering, reason: reason.trim(), override, description: override ? description.trim() : null,
      }, `Course registration ${verb} on the student edit page`);
      if (r.ok) { notify(`Registration updated · ${r.data.reference}`); setReg(reg ? { ...reg, view: r.data.view, current: r.data.current } : reg); setAct(null); setReason(""); }
      else notifyProblem(r.problem);
    } finally { setBusy(false); }
  }

  const live = reg?.current.courses.filter((c) => c.status !== "DROPPED") ?? [];
  const canManage = may("EDIT_STUDENT_REGISTRATION");
  return (
    <>
      <Panel title="Carry-over courses" right={`${page.carryovers.length}`}>
        {page.carryovers.length ? <DTable pageSize={10} cols={["Course code|mid", "Course title", "Units|mid", "Failed in"]} rows={page.carryovers.map((c) => [
          <b key="c" className="tnum">{c.course_code}</b>, c.title, <span key="u" className="tnum">{c.units}</span>, c.failed_in,
        ])} /> : <PBody><div className="sub2">No carry-over: no published failure that is not passed since.</div></PBody>}
      </Panel>
      <Panel title="Registrations" right={`${page.registrations.length}`}>
        {page.registrations.length ? <DTable pageSize={10} cols={["Session|mid", "Semester|mid", "Level|mid", "Courses|num", "Units|num", "Status|mid"]} rows={page.registrations.map((r) => [
          <span key="s" className="tnum">{r.session}</span>, r.semester === 2 ? "Second" : "First", r.level, r.courses, r.units, <Pil key="p" kind={r.status === "APPROVED" || r.status === "LOCKED" ? "ok" : "warn"}>{words(r.status)}</Pil>,
        ])} /> : <PBody><div className="sub2">No course registration on record.</div></PBody>}
      </Panel>
      <Panel title="Manage course registration" right={<span className="row row--inline row--tight">
        <select aria-label="Session" className="ctl" value={sel.session} onChange={(e) => setSel({ ...sel, session: e.target.value })}>
          {page.lists.sessions.map((x) => <option key={x.name} value={x.name}>{x.name}</option>)}
        </select>
        <select aria-label="Semester" className="ctl" value={sel.semester} onChange={(e) => setSel({ ...sel, semester: e.target.value })}>
          <option value="1">First semester</option><option value="2">Second semester</option>
        </select></span>}>
        {problem ? <PBody><ProblemNotice problem={problem} /></PBody> : reg === null ? <PBody><div className="sub2">Reading the registration…</div></PBody> : (
          <PBody>
            {!canManage ? <Note kind="info" title="Read only">Your office does not hold EDIT_STUDENT_REGISTRATION.</Note> : null}
            <div className="row row--inline" style={{ gap: "var(--s-3)", flexWrap: "wrap" }}>
              <span><b>{reg.view.session}</b> · {reg.view.semester === 2 ? "second" : "first"} semester · {reg.view.level} Level</span>
              <span>Status <Pil kind="info">{words(reg.current.registration?.status ?? "NONE")}</Pil></span>
              <span className="sub2">Units {reg.current.registration?.units ?? 0} of {reg.view.limit.min_units}–{reg.view.limit.max_units}</span>
            </div>
            <div className="eyebrow mt-3">Current courses</div>
            {reg.current.courses.length ? <DTable pageSize={0} noPrint cols={["Code|mid", "Title", "Units|mid", "Basis|mid", "Status|mid", "|num"]} rows={reg.current.courses.map((c) => [
              <b key="c" className="tnum">{c.course_code}</b>, <Two key="t" a={c.title} b={c.support_override_at ? `Override: ${c.support_override_reason ?? ""}` : ""} />, c.units, words(c.basis),
              <Pil key="s" kind={c.status === "DROPPED" ? "grey" : "ok"}>{words(c.status)}</Pil>,
              canManage ? (c.status === "DROPPED"
                ? <Btn key="a" kind="ghost" size="sm" onClick={() => void open("restore", c.offering_id, c.course_code, c.title)}>Restore</Btn>
                : <Btn key="a" kind="ghost" size="sm" onClick={() => void open("drop", c.offering_id, c.course_code, c.title)}>Remove</Btn>) : <span key="a" />,
            ])} /> : <div className="sub2">No course registered for this semester.</div>}
            {canManage && live.length ? <div className="row mt-2"><Btn kind="secondary" disabled={busy} onClick={() => { setAct(null); setReason(""); setOverride(false); void perform("submit", null); }}>Submit the registration</Btn><span className="sub2">Submitting needs a reason below first.</span></div> : null}
            {canManage ? (
              <>
                <div className="eyebrow mt-3">Eligible courses — the engine&rsquo;s own menu</div>
                {reg.view.menu.length ? <DTable pageSize={10} noPrint cols={["Code|mid", "Title", "Units|mid", "Basis|mid", "|num"]} rows={reg.view.menu.map((m) => [
                  <b key="c" className="tnum">{m.course_code}</b>, m.title, m.units, words(m.basis),
                  live.some((e) => e.offering_id === m.offering_id) ? <span key="a" className="sub2">Registered</span> : <Btn key="a" kind="ghost" size="sm" onClick={() => void open("add", m.offering_id, m.course_code, m.title)}>Add course</Btn>,
                ])} /> : <div className="sub2">The menu is empty for this semester.</div>}
                <div className="eyebrow mt-3">A course missing from the menu</div>
                <div className="row row--inline">
                  <input aria-label="Find a course" className="ctl" placeholder="Course code or title" value={q} onChange={(e) => setQ(e.target.value)} />
                  <Btn kind="ghost" disabled={q.trim().length < 2} onClick={async () => {
                    const r = await call<typeof found>("GET", `${base}/offerings?session=${encodeURIComponent(sel.session)}&semester=${sel.semester}&q=${encodeURIComponent(q.trim())}`, null, "Courses found");
                    if (r.ok) setFound(r.data); else notifyProblem(r.problem);
                  }}>Find</Btn>
                </div>
                {found.length ? <DTable pageSize={0} noPrint cols={["Code|mid", "Title", "Units|mid", "|num"]} rows={found.map((m) => [
                  <b key="c" className="tnum">{m.course_code}</b>, m.title, m.units, <Btn key="a" kind="ghost" size="sm" onClick={() => void open("add", m.offering_id, m.course_code, m.title)}>Add course</Btn>,
                ])} /> : null}
                <ReasonBox id="rg" reason={reason} setReason={setReason} />
              </>
            ) : null}
          </PBody>
        )}
      </Panel>
      {act ? (
        <Modal title={`${act.verb === "drop" ? "Remove" : act.verb === "restore" ? "Restore" : "Add"} ${act.code}`} sub={act.title} onClose={() => setAct(null)}
          foot={<><Btn kind="ghost" onClick={() => setAct(null)}>Cancel</Btn>
            <Btn kind="primary" busy={busy} busyLabel="Saving…" disabled={!act.rules || (!act.allowed && !(act.overridable && act.mayOverride && override)) || !!reasonProblem(reason) || (override && description.trim().length < 15)}
              onClick={() => void perform(act.verb, act.offering)}>{override ? "Apply with academic override" : "Apply"}</Btn></>}>
          {!act.rules ? <div className="sub2">Reading the rules…</div> : (
            <>
              <DTable pageSize={0} noPrint cols={["Rule", "|mid"]} rows={act.rules.map((r) => [<Two key="r" a={r.rule} b={r.detail ?? ""} />,
                <Pil key="p" kind={r.passed ? "ok" : r.overridable ? "warn" : "bad"}>{r.passed ? "Passes" : r.overridable ? "Fails · may be overridden" : "Fails"}</Pil>])} />
              {!act.allowed && !act.overridable ? <Note kind="bad" title="Refused">A rule that is not overridable fails; the office that owns it decides.</Note> : null}
              {!act.allowed && act.overridable ? (act.mayOverride ? (
                <>
                  <label className="row row--inline mt-2"><input type="checkbox" checked={override} onChange={(e) => setOverride(e.target.checked)} /> <b>Academic override</b>: set the failing rule aside for this course</label>
                  {override ? (
                    <Field id="rg-ov" label="Override justification" required full hint="Which rule fails, and why it is set aside — the migration, the historical record, the decision">
                      <textarea id="rg-ov" className="ctl" rows={3} value={description} onChange={(e) => setDescription(e.target.value)} />
                    </Field>
                  ) : null}
                </>
              ) : <Note kind="bad" title="Override not held">Your office does not hold OVERRIDE_STUDENT_REGISTRATION.</Note>) : null}
              <ReasonBox id="rg-m" reason={reason} setReason={setReason} />
            </>
          )}
        </Modal>
      ) : null}
    </>
  );
}

/* ── graduation: the reconciliation's reading, and its application for this student ── */

type GradView = {
  candidate: { confidence: string; expected_completion: string | null; maximum_session: string | null; current_session: string | null; spillover_years: number | null; reasons?: string[] } | null;
  position: Record<string, unknown> | null;
  reconciliations: { batch_ref: string; previous_status: string; new_status: string; reconciled_at: string; reconciled_by: string | null; graduation_session: string | null }[];
};

function GraduationSection({ page, may, actingOffice }: { page: EditPage; may: May; actingOffice: string | null }) {
  const s = page.student;
  const router = useRouter();
  const [g, setG] = useState<GradView | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let live = true;
    void call<GradView>("GET", `/api/v1/graduation/reconciliation/students/${s.id}`, null, "Graduation reading").then((r) => {
      if (!live) return;
      if (r.ok) setG(r.data); else setProblem(r.problem);
    });
    return () => { live = false; };
  }, [s.id]);
  const p = page.position;
  const entryYear = Number(sessionYear(p?.entry_session ?? s.entry_session) ?? 0);
  const dur = p?.duration_years ?? 0;
  const sessionOf = (y: number) => (y ? `${y}/${y + 1}` : "—");
  const canAct = may("EDIT_STUDENT_GRADUATION_STATUS") && ["academic", "registrar", "dregistrar"].includes(actingOffice ?? "");
  return (
    <>
      <Panel title="Calculated academic position" right={<span className="sub2">From the cohort engine and the graduation reconciliation</span>}>
        <PBody>
          <KvGrid pairs={[["Admission session", p?.entry_session ?? s.entry_session ?? "—"], ["Programme duration", dur ? `${dur} years` : "—"],
            ["Expected completion", p?.expected_completion ?? (entryYear && dur ? sessionOf(entryYear + dur - 1) : "—")],
            ["SP1", entryYear && dur ? sessionOf(entryYear + dur) : "—"], ["SP2", entryYear && dur ? sessionOf(entryYear + dur + 1) : "—"],
            ["Current session", p?.current_session ?? page.session], ["Graduation reading", words(p?.graduation_state)],
            ["Recommendation", g?.candidate ? `GRADUATED · ${words(g.candidate.confidence)} confidence` : words(p?.proposed_status)]]} />
          {problem ? <ProblemNotice problem={problem} /> : null}
          {s.status === "GRADUATED" ? <Note kind="ok" title="Graduated">The record is graduated. A correction is the Registrar&rsquo;s graduation correction.</Note>
            : g?.candidate ? (
              canAct ? (
                <>
                  <Note kind="bad" title="The student is outside the maximum academic period">
                    Applying the recommendation graduates the student through a graduation-status reconciliation batch of one: the status, the graduation session and the
                    clearance are set by the reconciliation, and the student is told.
                  </Note>
                  <ReasonBox id="gr" reason={reason} setReason={setReason} />
                  <div className="row mt-2">
                    <Btn kind="primary" busy={busy} busyLabel="Applying…" disabled={!!reasonProblem(reason)} onClick={async () => {
                      setBusy(true);
                      try {
                        const opened = await call<{ batch_ref: string }>("POST", "/api/v1/graduation/reconciliation/batches",
                          { description: `${s.surname} ${s.other_names ?? ""}: ${reason.trim()}`.slice(0, 300), studentIds: [s.id], includeMedium: true }, "Graduation reconciliation opened from the student edit page");
                        if (!opened.ok) { notifyProblem(opened.problem); return; }
                        const run = await call<{ graduated: number; refused: unknown[] }>("POST", `/api/v1/graduation/reconciliation/batches/${recBatchPath(opened.data.batch_ref)}/run`,
                          { reason: reason.trim() }, `Graduation reconciliation ${opened.data.batch_ref} executed from the student edit page`);
                        if (!run.ok) { notifyProblem(run.problem); return; }
                        notify(run.data.graduated ? `Graduated · ${opened.data.batch_ref}` : `Not graduated · ${opened.data.batch_ref}: see the batch on Graduation Management`);
                        router.refresh();
                      } finally { setBusy(false); }
                    }}>Apply the recommendation</Btn>
                    <LinkBtn kind="ghost" href="/graduation/manage">Graduation Management</LinkBtn>
                  </div>
                </>
              ) : <Note kind="info" title="A graduation candidate">The Academic Office or the Registry applies it from this page or from Graduation Management.</Note>
            ) : <div className="sub2 mt-2">Not a candidate for graduation by status reconciliation now.</div>}
        </PBody>
      </Panel>
      <Panel title="Academic timeline" right={<span className="sub2">Programme, level and status, as recorded</span>}>
        {page.programmeHistory.length || page.statusHistory.length ? <DTable pageSize={0} cols={["When|mid", "Session|mid", "What", "Programme", "Level|mid"]} rows={[
          ...page.programmeHistory.map((h, i) => [<span key={`a${i}`} className="tnum">{day(h.at)}</span>, h.session ?? "—", words(h.kind), h.programme, h.level ?? "—"]),
          ...page.statusHistory.map((h, i) => [<span key={`b${i}`} className="tnum">{day(h.effective_on)}</span>, "—", `Status: ${words(h.to_status)}`, h.instrument, "—"]),
        ]} /> : <PBody><div className="sub2">Nothing recorded yet.</div></PBody>}
      </Panel>
      {g && g.reconciliations.length ? (
        <Panel title="Graduation reconciliations">
          <DTable pageSize={0} cols={["Batch", "From", "To", "Graduation session|mid", "When", "By"]} rows={g.reconciliations.map((r) => [
            <span key="b" className="tnum">{r.batch_ref}</span>, words(r.previous_status), words(r.new_status), r.graduation_session ?? "—", when(r.reconciled_at), r.reconciled_by ?? "—"])} />
        </Panel>
      ) : null}
    </>
  );
}

/* ── finance: shown, never corrected here; a problem is reported to the Bursary ── */

function FinanceSection({ page, may }: { page: EditPage; may: May }) {
  const s = page.student;
  const f = page.finance as Record<string, number | string | null> | null;
  const [subject, setSubject] = useState("");
  const [description, setDescription] = useState("");
  const [busy, setBusy] = useState(false);
  const n = (v: unknown) => (v == null ? "—" : `₦${Number(v).toLocaleString()}`);
  return (
    <>
      <Panel title={`School fees · ${page.session}`} right={<LinkBtn kind="ghost" href={`/students/${s.id}?tab=finance`}>Payments and receipts</LinkBtn>}>
        <PBody>
          {f ? <KvGrid pairs={[["Due", n(f.due ?? f.total_due)], ["Paid", n(f.paid ?? f.total_paid)], ["Outstanding", n(f.balance ?? f.outstanding)], ["Session", page.session]]} />
            : <div className="sub2">No fee position for the session.</div>}
          <Note kind="info" title="Finance is the Bursary's">The Academic Office reads the fees and payments here and corrects none of them: payments, gateway records, refunds, the ledger, fee lines and wallets stay with the Bursary.</Note>
        </PBody>
      </Panel>
      {may("EDIT_STUDENT_ACADEMIC_RECORD") ? (
        <Panel title="Report financial issue" right={<span className="sub2">A Payment ticket for the Bursary and ICT Support</span>}>
          <PBody>
            <Field id="fi-s" label="Subject" required><input id="fi-s" className="ctl" maxLength={200} value={subject} onChange={(e) => setSubject(e.target.value)} placeholder="School fees paid on the old portal not showing for 2025/2026" /></Field>
            <Field id="fi-d" label="What looks wrong" required full hint="The payment, the session, the reference, and what you expected">
              <textarea id="fi-d" className="ctl" rows={3} value={description} onChange={(e) => setDescription(e.target.value)} />
            </Field>
            <div className="row mt-2">
              <Btn kind="primary" busy={busy} busyLabel="Reporting…" disabled={!subject.trim() || description.trim().length < 15} onClick={async () => {
                setBusy(true);
                try {
                  const r = await call<{ ticket: string; reference: string }>("POST", `/api/v1/student/students/${s.id}/edit/financial-issue`, { subject: subject.trim(), description: description.trim() },
                    "Financial issue reported from the student edit page");
                  if (r.ok) { notify(`Ticket ${r.data.ticket} raised · ${r.data.reference}`); setSubject(""); setDescription(""); } else notifyProblem(r.problem);
                } finally { setBusy(false); }
              }}>Report financial issue</Btn>
            </div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}

/* ── the change history, from every workflow, searchable ── */

function HistorySection({ page, may }: { page: EditPage; may: May }) {
  const s = page.student;
  const [f, setF] = useState({ from: "", to: "", user: "", field: "", type: "", q: "" });
  const [pageNo, setPageNo] = useState(0);
  const [data, setData] = useState<{ total: number; rows: HistoryRow[]; types: string[] } | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const qs = useMemo(() => {
    const p = new URLSearchParams();
    Object.entries(f).forEach(([k, v]) => { if (v.trim()) p.set(k, v.trim()); });
    p.set("page", String(pageNo));
    p.set("size", "50");
    return p.toString();
  }, [f, pageNo]);
  useEffect(() => {
    if (!may("VIEW_STUDENT_EDIT_HISTORY")) return;
    let live = true;
    const t = setTimeout(() => {
      void call<{ total: number; rows: HistoryRow[]; types: string[] }>("GET", `/api/v1/student/students/${s.id}/edit/history?${qs}`, null, "Change history read").then((r) => {
        if (!live) return;
        if (r.ok) { setData(r.data); setProblem(null); } else setProblem(r.problem);
      });
    }, 250);
    return () => { live = false; clearTimeout(t); };
  }, [qs, s.id, may]);
  if (!may("VIEW_STUDENT_EDIT_HISTORY")) return <Note kind="info" title="Not for your office">Your office does not hold VIEW_STUDENT_EDIT_HISTORY.</Note>;
  return (
    <Panel title="Change history" right={data ? `${data.total} change${data.total === 1 ? "" : "s"}` : ""}>
      <PBody>
        <div className="grid grid--3">
          <Field id="h-from" label="From"><input id="h-from" type="date" className="ctl" value={f.from} onChange={(e) => { setF({ ...f, from: e.target.value }); setPageNo(0); }} /></Field>
          <Field id="h-to" label="To"><input id="h-to" type="date" className="ctl" value={f.to} onChange={(e) => { setF({ ...f, to: e.target.value }); setPageNo(0); }} /></Field>
          <Field id="h-type" label="Change type">
            <select id="h-type" className="ctl" value={f.type} onChange={(e) => { setF({ ...f, type: e.target.value }); setPageNo(0); }}>
              <option value="">Any</option>
              {(data?.types ?? []).map((t) => <option key={t} value={t}>{words(t)}</option>)}
            </select>
          </Field>
          <Field id="h-user" label="User or office"><input id="h-user" className="ctl" value={f.user} onChange={(e) => { setF({ ...f, user: e.target.value }); setPageNo(0); }} /></Field>
          <Field id="h-field" label="Field"><input id="h-field" className="ctl" value={f.field} onChange={(e) => { setF({ ...f, field: e.target.value }); setPageNo(0); }} placeholder="level, programme, status …" /></Field>
          <Field id="h-q" label="Old value, new value, reason or reference"><input id="h-q" className="ctl" value={f.q} onChange={(e) => { setF({ ...f, q: e.target.value }); setPageNo(0); }} /></Field>
        </div>
      </PBody>
      {problem ? <PBody><ProblemNotice problem={problem} /></PBody> : !data ? <PBody><div className="sub2">Reading the history…</div></PBody> : data.rows.length ? (
        <>
          <DTable pageSize={0} cols={["Date", "Reference", "Field", "Old value", "New value", "Reason", "Changed by", "Severity|mid", "Source"]} rows={data.rows.map((h, i) => [
            <span key={`d${i}`} className="tnum">{when(h.at)}</span>, <span key={`r${i}`} className="tnum">{h.reference ?? "—"}</span>,
            <Two key={`f${i}`} a={FIELD_WORD[h.field] ?? h.field} b={words(h.change_type)} />, h.old_value ?? "—", <b key={`n${i}`}>{h.new_value ?? "—"}</b>,
            <span key={`w${i}`} className="sub2">{h.reason ?? "—"}</span>, <Two key={`b${i}`} a={h.by_name ?? "—"} b={h.office ?? ""} />,
            <Pil key={`s${i}`} kind={(SEVERITY[h.severity] ?? ["grey"])[0]}>{(SEVERITY[h.severity] ?? ["grey", h.severity])[1]}</Pil>, <span key={`o${i}`} className="sub2">{h.source}</span>,
          ])} />
          <PBody>
            <div className="row">
              <Btn kind="ghost" disabled={pageNo === 0} onClick={() => setPageNo(pageNo - 1)}>Newer</Btn>
              <span className="sub2">Page {pageNo + 1} of {Math.max(1, Math.ceil(data.total / 50))}</span>
              <Btn kind="ghost" disabled={(pageNo + 1) * 50 >= data.total} onClick={() => setPageNo(pageNo + 1)}>Older</Btn>
            </div>
          </PBody>
        </>
      ) : <PBody><div className="sub2">No change matches.</div></PBody>}
    </Panel>
  );
}
