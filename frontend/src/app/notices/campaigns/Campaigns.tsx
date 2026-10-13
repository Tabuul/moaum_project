"use client";

/** t/campaigns (V426): a message to many. The recipients are never typed: students, staff, lecturers or applicants, filtered on
 *  the record; a preview counts them and their addresses; a test goes to one address; the send is a job the scheduler drains in
 *  batches, once per person and channel; a report counts what went. A Dean or Head addresses their own students only. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Campaign {
  id: string; name: string; template_key: string; template_label: string; audience: string; channels: string[]; vars: string; state: string;
  created_at: string; created_office: string | null; sent_at: string | null; sent_office: string | null; finished_at: string | null;
  cancelled_at: string | null; cancel_reason: string | null; recipients: number | null; job_id: string | null;
  job_state: string | null; reached: number | null; job_queued: number | null; runs: number | null; job_error: string | null;
  messages: number; messages_sent: number; messages_failed: number;
  report?: { channel: string; total: number; queued: number; sent: number; failed: number; invalid: number }[];
}
export interface CampaignsPage {
  campaigns: Campaign[];
  /** V438: the delivery switches on Notifications; a campaign sent while one is off waits in the outbox */
  delivery?: { dispatch_enabled: boolean; email_delivery: boolean; sms_delivery: boolean; portal_delivery: boolean };
  templates: { key: string; label: string; purpose: string; mandatory: boolean; email: boolean; sms: boolean; portal: boolean }[];
  faculties: { code: string; name: string }[];
  departments: { code: string; name: string; faculty_code: string }[];
  programmes: { code: string; name: string; dept_code: string; faculty_code: string }[];
  sessions: { name: string; state: string }[];
  offices: { code: string; label: string }[];
}
/** V444: what the campaign's SMS will cost, against the balance last read */
interface SmsCost { sms_on: boolean; sample: string | null; chars: number; units_each: number; recipients: number; units_total: number; balance: number | null; balance_at: string | null; covers: boolean | null }
interface Preview { sms?: SmsCost | null; total: number; emailOk: number; emailBad: number; emailMissing: number; phoneOk: number; phoneBad: number; phoneMissing: number; already: number; kinds: { kind: string; total: number }[] }

const when = (s: string | null) => (s ? new Date(s).toLocaleString("en-GB", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" }) : "");

interface Form {
  name: string; templateKey: string; students: boolean; staff: boolean; lecturers: boolean; applicants: boolean;
  session: string; faculty: string; department: string; programme: string; level: string; entryMode: string; status: string; office: string;
  migrated: boolean; neverSignedIn: boolean; firstPassword: boolean; email: boolean; sms: boolean; portal: boolean;
  title: string; message: string; smsMessage: string; signature: string;
}

function parse(c: Campaign): Form {
  let a: Record<string, unknown> = {};
  let v: Record<string, string> = {};
  try { a = JSON.parse(c.audience) as Record<string, unknown>; } catch { a = {}; }
  try { v = JSON.parse(c.vars) as Record<string, string>; } catch { v = {}; }
  const f = (a.filters ?? {}) as Record<string, unknown>;
  const s = (k: string) => (f[k] == null ? "" : String(f[k]));
  return {
    name: c.name, templateKey: c.template_key, students: !!a.students, staff: !!a.staff, lecturers: !!a.lecturers, applicants: !!a.applicants,
    session: s("session"), faculty: s("faculty"), department: s("department"), programme: s("programme"), level: s("level"), entryMode: s("entry_mode"), status: s("status"), office: s("office"),
    migrated: f.migrated === true, neverSignedIn: f.never_signed_in === true, firstPassword: f.first_password === true,
    email: c.channels.includes("EMAIL"), sms: c.channels.includes("SMS"), portal: c.channels.includes("PORTAL"),
    title: v.TITLE ?? "", message: v.MESSAGE ?? "", smsMessage: v.SMS_MESSAGE ?? "", signature: v.SIGNATURE ?? "",
  };
}

const EMPTY: Form = {
  name: "", templateKey: "ANNOUNCEMENT", students: true, staff: false, lecturers: false, applicants: false,
  session: "", faculty: "", department: "", programme: "", level: "", entryMode: "", status: "", office: "",
  migrated: false, neverSignedIn: false, firstPassword: false, email: true, sms: true, portal: true, title: "", message: "", smsMessage: "", signature: "",
};

async function send<T>(path: string, method: string, body: unknown, reason: string): Promise<{ ok: true; data: T } | { ok: false; problem: Problem }> {
  const r = await fetch(`/api/bff/api/v1/notices/campaigns${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: body === undefined ? undefined : JSON.stringify(body) });
  const j = await r.json().catch(() => null);
  if (!r.ok) return { ok: false, problem: (j as Problem) ?? { status: r.status, title: r.statusText } };
  return { ok: true, data: j as T };
}

export function Campaigns({ d, actingOffice, open }: { d: CampaignsPage; actingOffice: string | null; open: string | null }) {
  const router = useRouter();
  const wide = ["ict", "admin", "super", "registrar", "dregistrar", "dsa", "academic"].includes(actingOffice ?? "");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [editing, setEditing] = useState<string | null>(open && open !== "new" ? open : null);
  const [creating, setCreating] = useState(open === "new");
  const opened = d.campaigns.find((c) => c.id === editing) ?? null;
  const [f, setF] = useState<Form>(opened ? parse(opened) : EMPTY);
  const [preview, setPreview] = useState<Preview | null>(null);
  const [testTo, setTestTo] = useState({ email: "", phone: "" });
  const draft = !opened || opened.state === "DRAFT";

  function begin(c: Campaign | null) {
    setEditing(c ? c.id : null); setCreating(!c); setF(c ? parse(c) : EMPTY); setPreview(null); setProblem(null);
  }

  function payload() {
    return {
      name: f.name, templateKey: f.templateKey, students: f.students, staff: f.staff, lecturers: f.lecturers, applicants: f.applicants,
      filters: { session: f.session, faculty: f.faculty, department: f.department, programme: f.programme, level: f.level, entry_mode: f.entryMode, status: f.status, office: f.office, migrated: f.migrated, never_signed_in: f.neverSignedIn, first_password: f.firstPassword },
      channels: [f.email ? "EMAIL" : null, f.sms ? "SMS" : null, f.portal ? "PORTAL" : null].filter(Boolean),
      vars: f.templateKey === "ANNOUNCEMENT" ? { TITLE: f.title, MESSAGE: f.message, SMS_MESSAGE: f.smsMessage || f.message, SIGNATURE: f.signature } : {},
    };
  }

  async function save(): Promise<string | null> {
    setBusy(true); setProblem(null);
    try {
      const r = opened ? await send<Campaign>(`/${opened.id}`, "PUT", payload(), `Campaign ${f.name} edited`) : await send<Campaign>("", "POST", payload(), `Campaign ${f.name} written`);
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return null; }
      notify("Campaign saved");
      if (!opened) { router.push(`/notices/campaigns?open=${r.data.id}`); }
      router.refresh();
      return r.data.id;
    } finally { setBusy(false); }
  }

  async function doPreview() {
    const id = opened ? opened.id : await save();
    if (!id) return;
    setBusy(true); setProblem(null);
    try {
      if (opened) { const s = await send<Campaign>(`/${id}`, "PUT", payload(), "Campaign edited before preview"); if (!s.ok) { setProblem(s.problem); return; } }
      const r = await send<Preview>(`/${id}/preview`, "POST", {}, "Campaign previewed");
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      setPreview(r.data);
    } finally { setBusy(false); }
  }

  async function doTest() {
    if (!opened) return;
    setBusy(true); setProblem(null);
    try {
      const r = await send<{ queued: number }>(`/${opened.id}/test`, "POST", { email: testTo.email || null, phone: testTo.phone || null }, "Campaign test message");
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      notify(r.data.queued ? `${r.data.queued} test message(s) queued` : "Nothing queued: the address is not one, or the template has no text for that channel");
    } finally { setBusy(false); }
  }

  async function doSend() {
    if (!opened) return;
    if (!preview) { await doPreview(); if (!preview) { /* the preview is shown first; the office sends from it */ } }
    const sms = preview?.sms;
    const cost = sms?.sms_on ? ` The SMS take about ${sms.units_total} units (${sms.recipients} messages of ${sms.units_each} page${sms.units_each === 1 ? "" : "s"})${sms.balance != null ? `; the account held ${sms.balance} when last read` : ""}.` : "";
    if (!window.confirm(`Send "${opened.name}" now? The messages go out in batches and cannot be recalled once queued.${cost}`)) return;
    setBusy(true); setProblem(null);
    try {
      let r = await send<Campaign>(`/${opened.id}/send`, "POST", {}, `Campaign ${opened.name} sent`);
      // V444: a known shortfall of SMS credit refuses the send; the office may send anyway, the SMS stopping when the credit runs out
      if (!r.ok && (r.problem as { code?: string }).code === "CAMPAIGN_SMS_CREDIT"
          && window.confirm(`${r.problem.detail ?? "The SMS credit does not cover this campaign."}\n\nSend anyway? The e-mail and portal messages all go; the SMS stop when the credit runs out.`)) {
        r = await send<Campaign>(`/${opened.id}/send`, "POST", { acceptShortfall: true }, `Campaign ${opened.name} sent, accepting the SMS credit shortfall`);
      }
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      notify("Sending: the first batch has gone; the rest follows within minutes");
      router.refresh();
    } finally { setBusy(false); }
  }

  async function doCancel() {
    if (!opened) return;
    const reason = window.prompt("Why is the campaign cancelled?") ?? "";
    setBusy(true); setProblem(null);
    try {
      const r = await send<Campaign>(`/${opened.id}/cancel`, "POST", { reason }, `Campaign ${opened.name} cancelled`);
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      notify("Campaign cancelled");
      router.refresh();
    } finally { setBusy(false); }
  }

  const t = d.templates.find((x) => x.key === f.templateKey);
  const depts = d.departments.filter((x) => !f.faculty || x.faculty_code === f.faculty);
  const progs = d.programmes.filter((x) => (!f.faculty || x.faculty_code === f.faculty) && (!f.department || x.dept_code === f.department));
  const stateOf = (c: Campaign) => c.state === "SENT" ? <Pil kind="ok">Sent</Pil> : c.state === "SENDING" ? <Pil kind="info">Sending · {c.reached ?? 0} reached</Pil> : c.state === "CANCELLED" ? <Pil kind="grey">Cancelled</Pil> : <Pil kind="warn">Draft</Pil>;

  return (
    <>
      {d.delivery && (!d.delivery.dispatch_enabled || !d.delivery.email_delivery || !d.delivery.sms_delivery) ? (
        <Note kind="bad" title={!d.delivery.dispatch_enabled ? "Queue processing is paused" : `${!d.delivery.email_delivery && !d.delivery.sms_delivery ? "E-mail and SMS delivery are" : !d.delivery.email_delivery ? "E-mail delivery is" : "SMS delivery is"} switched off`}>
          A campaign sent now is queued but waits in the outbox until delivery is switched on again on <a href="/notices">Notifications</a>; the portal notices are made as usual.
        </Note>
      ) : null}
      <Note kind="info" title="A message to many, read from the record">
        Nobody is typed in: the students, staff, lecturers or applicants the filters name are read from the register when the campaign is sent, once per person and channel.
        {wide ? " Preview first: it counts who would be reached, and whose address is missing or not one." : " A Dean or Head writes to the students of their own faculty or department."}
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Panel title="Campaigns" right={<Btn kind="primary" size="sm" onClick={() => begin(null)}>New campaign</Btn>}>
        {d.campaigns.length ? (
          <DTable cols={["When|mid", "Campaign", "Template", "Channels|mid", "Recipients|num", "Messages|num", "State|mid", "|num"]} rows={d.campaigns.map((c) => [
            <span className="tnum sub2" key="w">{when(c.created_at)}</span>,
            <span key="n"><b>{c.name}</b><div className="sub2">{c.created_office ?? ""}</div></span>,
            <span className="sub2" key="t">{c.template_label}</span>,
            <span className="sub2" key="c">{c.channels.map((x) => x === "PORTAL" ? "Portal" : x === "EMAIL" ? "Email" : "SMS").join(" · ")}</span>,
            <span className="tnum" key="r">{c.recipients ?? ""}</span>,
            <span className="tnum" key="m">{c.messages}{c.messages_failed ? <span className="sub2"> · {c.messages_failed} failed</span> : null}</span>,
            <span key="s">{stateOf(c)}</span>,
            <Btn key="o" kind="ghost" size="sm" onClick={() => begin(c)}>{c.state === "DRAFT" ? "Edit" : "Open"}</Btn>,
          ])} texts={d.campaigns.map((c) => `${c.name} ${c.template_label} ${c.state}`)} />
        ) : <PBody><div className="sub2">No campaign yet. The first is usually the welcome to the new portal, to everyone who came over.</div></PBody>}
      </Panel>

      {creating || opened ? (
        <Panel title={opened ? opened.name : "New campaign"} right={<span className="row row--inline row--tight">{opened ? stateOf(opened) : null}<Btn kind="ghost" size="sm" onClick={() => { setEditing(null); setCreating(false); }}>Close</Btn></span>}>
          <PBody>
            <div className="grid grid--2">
              <Field id="cname" label="Name"><input id="cname" className="ctl" value={f.name} disabled={!draft} onChange={(e) => setF({ ...f, name: e.target.value })} /></Field>
              <Field id="ctpl" label="Template" hint={t?.purpose}>
                <select id="ctpl" className="ctl" value={f.templateKey} disabled={!draft} onChange={(e) => setF({ ...f, templateKey: e.target.value })}>
                  {d.templates.map((x) => <option key={x.key} value={x.key}>{x.label} ({x.key})</option>)}
                </select>
              </Field>
              {f.templateKey === "ANNOUNCEMENT" ? (
                <>
                  <Field id="ctitle" label="Title" full><input id="ctitle" className="ctl" value={f.title} disabled={!draft} onChange={(e) => setF({ ...f, title: e.target.value })} /></Field>
                  <Field id="cmsg" label="Message" full><textarea id="cmsg" className="ctl" rows={5} value={f.message} disabled={!draft} onChange={(e) => setF({ ...f, message: e.target.value })} /></Field>
                  <Field id="csms" label="SMS text" hint="Short; the message above is used when blank"><textarea id="csms" className="ctl" rows={2} value={f.smsMessage} disabled={!draft} onChange={(e) => setF({ ...f, smsMessage: e.target.value })} /></Field>
                  <Field id="csig" label="Signature" hint="e.g. Office of the Registrar"><input id="csig" className="ctl" value={f.signature} disabled={!draft} onChange={(e) => setF({ ...f, signature: e.target.value })} /></Field>
                </>
              ) : null}
            </div>
            <div className="b600 mt-3">Who</div>
            <div className="row row--wrap row--tight mt-1">
              <label className="row row--inline row--tight"><input type="checkbox" checked={f.students} disabled={!draft} onChange={(e) => setF({ ...f, students: e.target.checked })} /> Students</label>
              {wide ? <>
                <label className="row row--inline row--tight"><input type="checkbox" checked={f.staff} disabled={!draft} onChange={(e) => setF({ ...f, staff: e.target.checked })} /> Staff</label>
                <label className="row row--inline row--tight"><input type="checkbox" checked={f.lecturers} disabled={!draft} onChange={(e) => setF({ ...f, lecturers: e.target.checked })} /> Lecturers</label>
                <label className="row row--inline row--tight"><input type="checkbox" checked={f.applicants} disabled={!draft} onChange={(e) => setF({ ...f, applicants: e.target.checked })} /> Applicants</label>
              </> : null}
            </div>
            <div className="grid grid--4 mt-2">
              <Field id="fses" label="Session" hint="Students in the session; applicants of it">
                <select id="fses" className="ctl" value={f.session} disabled={!draft} onChange={(e) => setF({ ...f, session: e.target.value })}>
                  <option value="">Any</option>{d.sessions.map((s) => <option key={s.name} value={s.name}>{s.name}</option>)}
                </select>
              </Field>
              <Field id="ffac" label="Faculty">
                <select id="ffac" className="ctl" value={f.faculty} disabled={!draft} onChange={(e) => setF({ ...f, faculty: e.target.value, department: "", programme: "" })}>
                  <option value="">Any</option>{d.faculties.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
                </select>
              </Field>
              <Field id="fdep" label="Department">
                <select id="fdep" className="ctl" value={f.department} disabled={!draft} onChange={(e) => setF({ ...f, department: e.target.value, programme: "" })}>
                  <option value="">Any</option>{depts.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
                </select>
              </Field>
              <Field id="fprog" label="Programme">
                <select id="fprog" className="ctl" value={f.programme} disabled={!draft} onChange={(e) => setF({ ...f, programme: e.target.value })}>
                  <option value="">Any</option>{progs.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
                </select>
              </Field>
              <Field id="flvl" label="Level">
                <select id="flvl" className="ctl" value={f.level} disabled={!draft} onChange={(e) => setF({ ...f, level: e.target.value })}>
                  <option value="">Any</option>{[100, 200, 300, 400, 500, 600].map((l) => <option key={l} value={String(l)}>{l}</option>)}
                </select>
              </Field>
              <Field id="fmode" label="Entry mode">
                <select id="fmode" className="ctl" value={f.entryMode} disabled={!draft} onChange={(e) => setF({ ...f, entryMode: e.target.value })}>
                  <option value="">Any</option><option value="UTME">UTME</option><option value="DIRECT_ENTRY">Direct entry</option><option value="CCE">CCE</option><option value="POSTGRADUATE">Postgraduate</option>
                </select>
              </Field>
              <Field id="fstat" label="Student status" hint="Blank: on the register and in the portal's use">
                <select id="fstat" className="ctl" value={f.status} disabled={!draft} onChange={(e) => setF({ ...f, status: e.target.value })}>
                  <option value="">Any applicable</option><option value="ADMITTED">Admitted</option><option value="ACTIVE">Active</option><option value="PROBATION">Probation</option><option value="DEFERRED">Deferred</option>
                </select>
              </Field>
              {wide ? (
                <Field id="foff" label="Office (staff)">
                  <select id="foff" className="ctl" value={f.office} disabled={!draft} onChange={(e) => setF({ ...f, office: e.target.value })}>
                    <option value="">Any</option>{d.offices.map((x) => <option key={x.code} value={x.code}>{x.label}</option>)}
                  </select>
                </Field>
              ) : null}
            </div>
            <div className="row row--wrap row--tight mt-2">
              <label className="row row--inline row--tight"><input type="checkbox" checked={f.migrated} disabled={!draft} onChange={(e) => setF({ ...f, migrated: e.target.checked })} /> Only those who came over from the old portal</label>
              <label className="row row--inline row--tight"><input type="checkbox" checked={f.neverSignedIn} disabled={!draft} onChange={(e) => setF({ ...f, neverSignedIn: e.target.checked })} /> Only those who have never signed in</label>
              <label className="row row--inline row--tight"><input type="checkbox" checked={f.firstPassword} disabled={!draft} onChange={(e) => setF({ ...f, firstPassword: e.target.checked })} /> Only those still on their first password (their own number opens the account)</label>
            </div>
            <div className="b600 mt-3">Channels</div>
            <div className="row row--wrap row--tight mt-1">
              <label className="row row--inline row--tight"><input type="checkbox" checked={f.email} disabled={!draft || !t?.email} onChange={(e) => setF({ ...f, email: e.target.checked })} /> Email</label>
              <label className="row row--inline row--tight"><input type="checkbox" checked={f.sms} disabled={!draft || !t?.sms} onChange={(e) => setF({ ...f, sms: e.target.checked })} /> SMS</label>
              <label className="row row--inline row--tight"><input type="checkbox" checked={f.portal} disabled={!draft || !t?.portal} onChange={(e) => setF({ ...f, portal: e.target.checked })} /> Portal</label>
              {t && !t.mandatory ? <span className="sub2">Optional message: a person who switched a channel off is not reached on it.</span> : null}
            </div>
            {draft ? (
              <div className="row row--wrap row--tight mt-3">
                <Btn kind="secondary" disabled={busy || !f.name.trim()} onClick={() => void save()}>Save</Btn>
                <Btn kind="secondary" disabled={busy || !f.name.trim()} onClick={() => void doPreview()}>Preview recipients</Btn>
                {opened ? <>
                  <input className="ctl" placeholder="Test e-mail" value={testTo.email} onChange={(e) => setTestTo({ ...testTo, email: e.target.value })} style={{ width: 200 }} />
                  <input className="ctl tnum" placeholder="Test phone" value={testTo.phone} onChange={(e) => setTestTo({ ...testTo, phone: e.target.value })} style={{ width: 150 }} />
                  <Btn kind="ghost" disabled={busy || (!testTo.email && !testTo.phone)} onClick={() => void doTest()}>Send a test</Btn>
                  <Btn kind="primary" disabled={busy || !preview} onClick={() => void doSend()}>Send to {preview ? preview.total : "…"}</Btn>
                  <Btn kind="ghost" disabled={busy} onClick={() => void doCancel()}>Cancel campaign</Btn>
                </> : null}
              </div>
            ) : opened && opened.state === "SENDING" ? (
              <div className="row row--wrap row--tight mt-3"><Btn kind="ghost" disabled={busy} onClick={() => void doCancel()}>Stop sending</Btn><Btn kind="ghost" onClick={() => router.refresh()}>Refresh</Btn></div>
            ) : null}
            {preview ? (
              <div className="mt-3">
                <Tiles items={[
                  ["Recipients", String(preview.total), null, preview.kinds.filter((k) => k.total).map((k) => `${k.total} ${k.kind === "student" ? "students" : k.kind === "person" ? "staff" : "applicants"}`).join(" · ") || "nobody"],
                  ["Valid e-mail", String(preview.emailOk), null, `${preview.emailBad} not an address · ${preview.emailMissing} none on file`],
                  ["Valid phone", String(preview.phoneOk), null, `${preview.phoneBad} not a number · ${preview.phoneMissing} none on file`],
                  ["Already reached", String(preview.already), null, "By this campaign"],
                  ...(preview.sms?.sms_on ? [[
                    "SMS credit needed", `≈ ${preview.sms.units_total}`, preview.sms.covers === false ? "var(--red-ink)" : null,
                    `${preview.sms.recipients} × ${preview.sms.units_each} page${preview.sms.units_each === 1 ? "" : "s"} (≈ ${preview.sms.chars} characters) · `
                      + (preview.sms.balance != null ? `${preview.sms.covers === false ? "more than" : "within"} the ${preview.sms.balance} units held` : "balance not read yet"),
                  ] as [string, string, string | null, string]] : []),
                ]} />
                {preview.sms?.sms_on && preview.sms.covers === false ? (
                  <div className="sub2 mt-1" style={{ color: "var(--red-ink)" }}>The SMS credit does not cover this campaign: top up the account, drop SMS from the channels, or narrow the audience. Send asks before going ahead.</div>
                ) : null}
              </div>
            ) : null}
            {opened && opened.report?.length ? (
              <div className="mt-3">
                <DTable cols={["Channel", "Queued|num", "Sent|num", "Waiting|num", "Failed|num", "Bad addresses|num"]} rows={opened.report.map((r) => [
                  <b key="c">{r.channel === "PORTAL" ? "Portal" : r.channel === "EMAIL" ? "Email" : "SMS"}</b>,
                  <span className="tnum" key="t">{r.total}</span>, <span className="tnum" key="s">{r.sent}</span>, <span className="tnum" key="q">{r.queued}</span>,
                  <span className="tnum" key="f">{r.failed}</span>, <span className="tnum" key="i">{r.invalid}</span>])} />
                <div className="sub2 mt-1">{opened.sent_at ? `Sent ${when(opened.sent_at)} by ${opened.sent_office ?? ""}` : ""}{opened.finished_at ? ` · finished ${when(opened.finished_at)}` : ""}{opened.job_error ? ` · ${opened.job_error}` : ""}</div>
              </div>
            ) : null}
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
