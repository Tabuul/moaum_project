"use client";

/** t/templates — the notification engine's desk (V425): the templates every message comes from, edited by ICT and the
 *  administrators with a preview on sample values and a test to one address; the engine's settings (the portal address, the
 *  job batch, the weekly biodata reminder and the review period); the jobs it ran. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Template {
  key: string; label: string; purpose: string; email_subject: string | null; email_body: string | null; sms_body: string | null;
  portal_title: string | null; portal_body: string | null; variables: string[]; mandatory: boolean; priority: string; enabled: boolean;
  updated_at: string; updated_office: string | null; sent_30d: number;
}
export interface Settings {
  portal_url: string | null; job_batch: number; remind_enabled: boolean; review_days: number | null; gate_enabled: boolean; staff_contact_remind?: boolean;
  /** V438: the reminders three days and one day before a fees or registration window closes */
  closing_reminders?: boolean;
  counts: { total: number; up_to_date: number; incomplete: number; review_required: number; outdated: number; no_email: number; no_phone: number; migrated: number } | null;
}
export interface Job { id: string; kind: string; payload: string; state: string; created_at: string; created_office: string | null; started_at: string | null; finished_at: string | null; reached: number; queued: number; runs: number; error: string | null }

type Rendered = { subject: string | null; body: string | null } | null;
type Preview = { email: Rendered; sms: Rendered; portal: Rendered };

const when = (s: string | null) => (s ? new Date(s).toLocaleString("en-GB", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" }) : "");

function describe(j: Job): string {
  try {
    const p = JSON.parse(j.payload) as Record<string, string>;
    if (j.kind === "WINDOW") return `${p.type?.replace(/_/g, " ").toLowerCase()} · ${p.session}${p.semester ? ` semester ${p.semester}` : ""} · ${p.action?.toLowerCase()}`;
    return j.kind.toLowerCase();
  } catch {
    return j.kind.toLowerCase();
  }
}

async function send<T>(path: string, method: string, body: unknown, reason: string): Promise<{ ok: true; data: T } | { ok: false; problem: Problem }> {
  const r = await fetch(`/api/bff/api/v1/notices${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: body === undefined ? undefined : JSON.stringify(body) });
  const j = await r.json().catch(() => null);
  if (!r.ok) return { ok: false, problem: (j as Problem) ?? { status: r.status, title: r.statusText } };
  return { ok: true, data: j as T };
}

export function Templates({ templates, settings, jobs, actingOffice }: { templates: Template[]; settings: Settings | null; jobs: Job[]; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["ict", "admin", "super"].includes(actingOffice ?? "");
  const [open, setOpen] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [f, setF] = useState<Template | null>(null);
  const [preview, setPreview] = useState<Preview | null>(null);
  const [testTo, setTestTo] = useState({ email: "", phone: "" });
  const [newKey, setNewKey] = useState("");
  const [s, setS] = useState({
    portalUrl: settings?.portal_url ?? "", jobBatch: String(settings?.job_batch ?? 2000),
    remindEnabled: settings?.remind_enabled ?? false, reviewDays: settings?.review_days ? String(settings.review_days) : "",
    staffContactRemind: settings?.staff_contact_remind ?? false,
    closingReminders: settings?.closing_reminders ?? true,
  });

  function edit(t: Template) {
    setOpen(t.key); setF({ ...t }); setPreview(null); setProblem(null);
  }

  function blank(key: string) {
    const k = key.trim().toUpperCase();
    const t: Template = { key: k, label: "", purpose: "", email_subject: "", email_body: "", sms_body: "", portal_title: "", portal_body: "",
      variables: ["FIRST_NAME", "LAST_NAME", "FULL_NAME", "PORTAL_URL", "UNIVERSITY_NAME", "UNIVERSITY_SHORT"], mandatory: true, priority: "NORMAL", enabled: true, updated_at: "", updated_office: null, sent_30d: 0 };
    setOpen(k); setF(t); setPreview(null); setProblem(null);
  }

  async function save() {
    if (!f) return;
    setBusy(true); setProblem(null);
    try {
      const r = await send<Template>(`/templates/${encodeURIComponent(f.key)}`, "PUT", {
        label: f.label, purpose: f.purpose, emailSubject: f.email_subject || null, emailBody: f.email_body || null, smsBody: f.sms_body || null,
        portalTitle: f.portal_title || null, portalBody: f.portal_body || null, variables: f.variables, mandatory: f.mandatory, priority: f.priority, enabled: f.enabled,
      }, `Notification template ${f.key} edited`);
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      notify(`${f.key} saved`);
      router.refresh();
    } finally { setBusy(false); }
  }

  async function showPreview() {
    if (!f) return;
    setBusy(true); setProblem(null);
    try {
      // the preview reads the saved words: save first, then render
      const saved = await send<Template>(`/templates/${encodeURIComponent(f.key)}`, "PUT", {
        label: f.label, purpose: f.purpose, emailSubject: f.email_subject || null, emailBody: f.email_body || null, smsBody: f.sms_body || null,
        portalTitle: f.portal_title || null, portalBody: f.portal_body || null, variables: f.variables, mandatory: f.mandatory, priority: f.priority, enabled: f.enabled,
      }, `Notification template ${f.key} previewed`);
      if (!saved.ok) { setProblem(saved.problem); notifyProblem(saved.problem); return; }
      const r = await send<Preview>(`/templates/${encodeURIComponent(f.key)}/preview`, "POST", {}, "Template preview");
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      setPreview(r.data);
    } finally { setBusy(false); }
  }

  async function test() {
    if (!f) return;
    setBusy(true); setProblem(null);
    try {
      const r = await send<{ queued: number }>(`/templates/${encodeURIComponent(f.key)}/test`, "POST", { email: testTo.email || null, phone: testTo.phone || null }, `Test of template ${f.key}`);
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      notify(r.data.queued ? `${r.data.queued} test message(s) queued; the outbox shows them under test messages` : "Nothing queued: the address is not one, or the template has no text for that channel");
    } finally { setBusy(false); }
  }

  async function saveSettings() {
    setBusy(true); setProblem(null);
    try {
      const r = await send<Settings>("/settings", "PUT", {
        portalUrl: s.portalUrl, jobBatch: Number(s.jobBatch) || undefined, remindEnabled: s.remindEnabled, reviewDays: s.reviewDays === "" ? 0 : Number(s.reviewDays),
        staffContactRemind: s.staffContactRemind, closingReminders: s.closingReminders,
      }, "Notification settings");
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      notify("Settings saved");
      router.refresh();
    } finally { setBusy(false); }
  }

  async function remindNow() {
    setBusy(true); setProblem(null);
    try {
      const r = await send<{ reminded: number }>("/biodata-reminders/run", "POST", {}, "Weekly biodata reminder run now");
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      notify(`${r.data.reminded} student(s) reminded`);
      router.refresh();
    } finally { setBusy(false); }
  }

  async function remindStaffNow() {
    setBusy(true); setProblem(null);
    try {
      const r = await send<{ reminded: number }>("/staff-contact-reminders/run", "POST", {}, "Weekly staff contact reminder run now");
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      notify(`${r.data.reminded} staff member(s) reminded`);
      router.refresh();
    } finally { setBusy(false); }
  }

  const c = settings?.counts ?? null;
  const groups = new Map<string, Template[]>();
  for (const t of templates) {
    const base = t.key.split(":")[0];
    groups.set(base, [...(groups.get(base) ?? []), t]);
  }

  return (
    <>
      <Note kind="info" title="Every message the portal sends comes from one of these templates">
        A <span className="tnum">[TOKEN]</span> is filled from the record when the message is sent: the person&rsquo;s name, number, programme and session, the window, the dates, the
        University&rsquo;s name and the portal address. A key with a suffix, such as <span className="tnum">WINDOW_CLOSED:SCHOOL_FEES_PAYMENT</span>, overrides the base key for that window.
        The same event never reaches a person twice on a channel, however often it is raised.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}

      {c ? (
        <Tiles items={[
          ["Students", String(c.total), null, "On the register"],
          ["Biodata up to date", String(c.up_to_date), "var(--green-ink)", `${c.incomplete} incomplete · ${c.review_required} to review · ${c.outdated} outdated`],
          ["No e-mail on file", String(c.no_email), c.no_email ? "var(--red-ink)" : null, `${c.no_phone} with no phone`],
          ["Came over from the old portal", String(c.migrated), null, "Matriculation numbers the portal did not issue"],
        ]} />
      ) : null}

      <Panel title="Templates" right={may ? (
        <span className="row row--inline row--tight">
          <input className="ctl tnum" placeholder="NEW_KEY or BASE:VARIANT" value={newKey} onChange={(e) => setNewKey(e.target.value)} style={{ width: 240 }} />
          <Btn kind="secondary" size="sm" disabled={!newKey.trim()} onClick={() => blank(newKey)}>New template</Btn>
        </span>
      ) : `${templates.length} templates`}>
        <DTable cols={["Key", "Name", "Channels|mid", "Priority|mid", "Sent, 30 days|num", "State|mid", "|num"]} rows={[...groups.values()].flat().map((t) => [
          <span className="tnum" key="k" style={t.key.includes(":") ? { paddingLeft: 16 } : undefined}>{t.key}</span>,
          <span key="l"><b>{t.label}</b><div className="sub2">{t.purpose}</div></span>,
          <span className="sub2" key="c">{[t.email_body ? "Email" : null, t.sms_body ? "SMS" : null, t.portal_body ? "Portal" : null].filter(Boolean).join(" · ")}</span>,
          <span className="sub2" key="p">{t.priority}{t.mandatory ? "" : " · optional"}</span>,
          <span className="tnum" key="n">{t.sent_30d}</span>,
          t.enabled ? <Pil kind="ok" key="s">On</Pil> : <Pil kind="grey" key="s">Off</Pil>,
          <Btn key="e" kind="ghost" size="sm" onClick={() => edit(t)}>{may ? "Edit" : "View"}</Btn>,
        ])} texts={templates.map((t) => `${t.key} ${t.label} ${t.purpose}`)} />
      </Panel>

      {open && f ? (
        <Panel title={`${f.key}${f.label ? " — " + f.label : ""}`} right={<Btn kind="ghost" size="sm" onClick={() => { setOpen(null); setF(null); }}>Close</Btn>}>
          <PBody>
            <div className="grid grid--2">
              <Field id="label" label="Name"><input id="label" className="ctl" value={f.label} disabled={!may} onChange={(e) => setF({ ...f, label: e.target.value })} /></Field>
              <Field id="priority" label="Priority" hint="Critical and high messages leave the outbox first">
                <select id="priority" className="ctl" value={f.priority} disabled={!may} onChange={(e) => setF({ ...f, priority: e.target.value })}>
                  <option>CRITICAL</option><option>HIGH</option><option>NORMAL</option><option>LOW</option>
                </select>
              </Field>
              <Field id="purpose" label="When it is sent" full><input id="purpose" className="ctl" value={f.purpose} disabled={!may} onChange={(e) => setF({ ...f, purpose: e.target.value })} /></Field>
              <Field id="es" label="E-mail subject" full><input id="es" className="ctl" value={f.email_subject ?? ""} disabled={!may} onChange={(e) => setF({ ...f, email_subject: e.target.value })} /></Field>
              <Field id="eb" label="E-mail text" full><textarea id="eb" className="ctl" rows={7} value={f.email_body ?? ""} disabled={!may} onChange={(e) => setF({ ...f, email_body: e.target.value })} /></Field>
              <Field id="sms" label="SMS text" hint={`${(f.sms_body ?? "").length} characters before the tokens are filled; keep it to one message`} full>
                <textarea id="sms" className="ctl" rows={2} value={f.sms_body ?? ""} disabled={!may} onChange={(e) => setF({ ...f, sms_body: e.target.value })} />
              </Field>
              <Field id="pt" label="Portal title"><input id="pt" className="ctl" value={f.portal_title ?? ""} disabled={!may} onChange={(e) => setF({ ...f, portal_title: e.target.value })} /></Field>
              <Field id="pb" label="Portal text"><textarea id="pb" className="ctl" rows={2} value={f.portal_body ?? ""} disabled={!may} onChange={(e) => setF({ ...f, portal_body: e.target.value })} /></Field>
            </div>
            <div className="row row--wrap row--tight mt-2">
              <label className="row row--inline row--tight"><input type="checkbox" checked={f.enabled} disabled={!may} onChange={(e) => setF({ ...f, enabled: e.target.checked })} /> Enabled</label>
              <label className="row row--inline row--tight"><input type="checkbox" checked={f.mandatory} disabled={!may} onChange={(e) => setF({ ...f, mandatory: e.target.checked })} /> Mandatory (never switched off by a preference)</label>
            </div>
            <div className="sub2 mt-2">Tokens this template may use: {f.variables.map((v) => <span key={v} className="tnum" style={{ marginRight: 8 }}>[{v}]</span>)}</div>
            {may ? (
              <div className="row row--wrap row--tight mt-3">
                <Btn kind="primary" disabled={busy || !f.label.trim()} onClick={() => void save()}>Save</Btn>
                <Btn kind="secondary" disabled={busy || !f.label.trim()} onClick={() => void showPreview()}>Save and preview</Btn>
                <input className="ctl" placeholder="Test e-mail" value={testTo.email} onChange={(e) => setTestTo({ ...testTo, email: e.target.value })} style={{ width: 220 }} />
                <input className="ctl tnum" placeholder="Test phone" value={testTo.phone} onChange={(e) => setTestTo({ ...testTo, phone: e.target.value })} style={{ width: 160 }} />
                <Btn kind="ghost" disabled={busy || (!testTo.email && !testTo.phone)} onClick={() => void test()}>Send a test</Btn>
              </div>
            ) : null}
            {preview ? (
              <div className="mt-3">
                {(["email", "sms", "portal"] as const).map((ch) => preview[ch] ? (
                  <div key={ch} className="mt-2">
                    <div className="b600">{ch === "email" ? "E-mail" : ch === "sms" ? "SMS" : "Portal"} · {preview[ch]?.subject}</div>
                    <pre className="sub2" style={{ whiteSpace: "pre-wrap", margin: 0 }}>{preview[ch]?.body}</pre>
                  </div>
                ) : null)}
              </div>
            ) : null}
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Settings" right={settings?.gate_enabled ? <Pil kind="warn">Biodata gate ON</Pil> : <Pil kind="grey">Biodata gate OFF</Pil>}>
        <PBody>
          <div className="grid grid--2">
            <Field id="url" label="Portal address" hint="Written into messages as [PORTAL_URL]"><input id="url" className="ctl" value={s.portalUrl} disabled={!may} onChange={(e) => setS({ ...s, portalUrl: e.target.value })} /></Field>
            <Field id="batch" label="People a job reaches per run" hint="Every half-minute; 100 to 20,000"><input id="batch" className="ctl tnum" value={s.jobBatch} disabled={!may} onChange={(e) => setS({ ...s, jobBatch: e.target.value })} /></Field>
            <Field id="review" label="Biodata outdated after (days)" hint="Blank: a record never goes outdated on its own"><input id="review" className="ctl tnum" value={s.reviewDays} disabled={!may} onChange={(e) => setS({ ...s, reviewDays: e.target.value })} /></Field>
            <Field id="remind" label="Weekly biodata reminder" hint="Monday mornings, to each student whose biodata is not up to date, at most once a week; it also runs while the gate is ON">
              <label className="row row--inline row--tight"><input id="remind" type="checkbox" checked={s.remindEnabled} disabled={!may} onChange={(e) => setS({ ...s, remindEnabled: e.target.checked })} /> On while the gate is OFF</label>
            </Field>
            <Field id="staffremind" label="Weekly staff contact reminder" hint="Tuesday mornings, to each staff member or lecturer whose e-mail or phone is missing or not usable, by the channel they have; HR told once a week how many cannot be reached at all">
              <label className="row row--inline row--tight"><input id="staffremind" type="checkbox" checked={s.staffContactRemind} disabled={!may} onChange={(e) => setS({ ...s, staffContactRemind: e.target.checked })} /> On</label>
            </Field>
            <Field id="closing" label="Reminders before a window closes" hint="Every morning at eight: three days and one day before a school fees payment or course registration window closes, to the students of the session who have not yet paid in full or submitted a registration; once per deadline and day (WINDOW_CLOSING)">
              <label className="row row--inline row--tight"><input id="closing" type="checkbox" checked={s.closingReminders} disabled={!may} onChange={(e) => setS({ ...s, closingReminders: e.target.checked })} /> On</label>
            </Field>
          </div>
          {may ? (
            <div className="row row--wrap row--tight mt-3">
              <Btn kind="primary" disabled={busy} onClick={() => void saveSettings()}>Save settings</Btn>
              <Btn kind="ghost" disabled={busy} onClick={() => void remindNow()}>Run the biodata reminder now</Btn>
              <Btn kind="ghost" disabled={busy} onClick={() => void remindStaffNow()}>Run the staff contact reminder now</Btn>
              <Btn kind="ghost" disabled={busy} onClick={async () => { const r = await send<{ queued: number }>("/closing-reminders/run", "POST", {}, "Window closing reminders run now"); if (r.ok) notify(`${r.data.queued} window reminder job${r.data.queued === 1 ? "" : "s"} queued`); else notifyProblem(r.problem); }}>Run the closing reminders now</Btn>
            </div>
          ) : null}
        </PBody>
      </Panel>

      <Panel title="Jobs" right="Big sends, drained in batches by the scheduler">
        {jobs.length ? (
          <DTable cols={["Queued|mid", "What", "By|mid", "Reached|num", "Messages|num", "State|mid"]} rows={jobs.map((j) => [
            <span className="tnum sub2" key="w">{when(j.created_at)}</span>,
            <span key="d">{describe(j)}{j.error ? <div className="sub2" style={{ color: "var(--red-ink)" }}>{j.error}</div> : null}</span>,
            <span className="sub2" key="o">{j.created_office ?? ""}</span>,
            <span className="tnum" key="r">{j.reached}</span>,
            <span className="tnum" key="q">{j.queued}</span>,
            j.state === "DONE" ? <Pil kind="ok" key="s">Done{j.finished_at ? ` · ${when(j.finished_at)}` : ""}</Pil> : j.state === "FAILED" ? <Pil kind="bad" key="s">Failed</Pil> : <Pil kind="info" key="s">{j.state === "RUNNING" ? `Running · ${j.runs} run(s)` : "Waiting"}</Pil>,
          ])} />
        ) : <PBody><div className="sub2">No job has run yet.</div></PBody>}
      </Panel>
    </>
  );
}
