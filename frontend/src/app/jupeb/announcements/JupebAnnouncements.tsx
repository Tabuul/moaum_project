"use client";

/**
 * The JUPEB Office's announcements (V349): a notice to a session's candidates — everyone, those not yet admitted, the admitted,
 * the active students, one class, one subject combination or one programme. It shows on each reached candidate's dashboard at
 * once (pinned first, until it expires), and is emailed and texted when the Office asks. The page says how many it will reach
 * before it is published, and how many have read it after. A notice is withdrawn with a reason, never deleted; one already
 * emailed or texted cannot be called back, so the Office reads it twice before publishing.
 */
import { useEffect, useState } from "react";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { AUDIENCE, day, jcall, streamLabel, when } from "@/lib/jupeb";

interface Row {
  id: string; session: string; audience: string; audience_ref: string | null; audience_name: string | null; title: string; body: string; pinned: boolean;
  send_email: boolean; send_sms: boolean; expires_on: string | null; published_at: string; notified: number | null; withdrawn_at: string | null;
  withdrawn_reason: string | null; created_by_name: string | null; reach: number; reads: number;
}
interface Data { session: string; sessions: { session: string; applications: number }[]; announcements: Row[]; classes: { id: string; name: string }[]; combinations: { code: string; name: string }[];
  subjects?: { id: string; code: string; title: string }[] }
interface Form { audience: string; ref: string; title: string; body: string; pinned: boolean; email: boolean; sms: boolean; expiresOn: string }
const EMPTY: Form = { audience: "STUDENTS", ref: "", title: "", body: "", pinned: false, email: true, sms: false, expiresOn: "" };
const NEEDS_REF = new Set(["CLASS", "COMBINATION", "PROGRAMME", "SUBJECT"]);

export function JupebAnnouncements({ canWrite }: { canWrite: boolean }) {
  const [session, setSession] = useState("");
  const [data, setData] = useState<Data | null>(null);
  const [tick, setTick] = useState(0);
  const [form, setForm] = useState<Form>(EMPTY);
  const [reach, setReach] = useState<{ key: string; count: number } | null>(null);
  const [confirm, setConfirm] = useState(false);
  const [withdraw, setWithdraw] = useState<{ row: Row; reason: string } | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let live = true;
    void jcall<Data>(`/api/v1/jupeb/office/announcements${session ? `?session=${encodeURIComponent(session)}` : ""}`).then((r) => {
      if (!live) return;
      if (r.ok) { setData(r.data); if (!session) setSession(r.data.session); } else notifyProblem(r.problem);
    });
    return () => { live = false; };
  }, [session, tick]);

  const reachKey = `${session}|${form.audience}|${form.ref}`;
  useEffect(() => {
    if (!session || (NEEDS_REF.has(form.audience) && !form.ref)) return;
    let live = true;
    const qs = new URLSearchParams({ session, audience: form.audience, ...(form.ref ? { ref: form.ref } : {}) });
    void jcall<{ count: number }>(`/api/v1/jupeb/office/announcements/reach?${qs.toString()}`).then((r) => { if (live && r.ok) setReach({ key: `${session}|${form.audience}|${form.ref}`, count: r.data.count }); });
    return () => { live = false; };
  }, [session, form.audience, form.ref]);
  const count = NEEDS_REF.has(form.audience) && !form.ref ? null : reach && reach.key === reachKey ? reach.count : null;

  const ready = form.title.trim().length >= 3 && form.body.trim().length >= 3 && (!NEEDS_REF.has(form.audience) || !!form.ref);
  async function publish() {
    setBusy(true);
    try {
      const r = await jcall<{ id: string; reach: number; notified: number }>("/api/v1/jupeb/office/announcements", "POST", {
        session, audience: form.audience, audienceRef: NEEDS_REF.has(form.audience) ? form.ref : null, title: form.title.trim(), body: form.body.trim(),
        pinned: form.pinned, email: form.email, sms: form.sms, expiresOn: form.expiresOn || null,
      }, `JUPEB announcement: ${form.title.trim()}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`Published to ${r.data.reach} candidate${r.data.reach === 1 ? "" : "s"}${r.data.notified ? `; ${r.data.notified} emailed or texted` : ""}.`);
      setForm(EMPTY); setConfirm(false); setTick((t) => t + 1);
    } finally { setBusy(false); }
  }
  async function doWithdraw() {
    if (!withdraw) return;
    setBusy(true);
    try {
      const r = await jcall(`/api/v1/jupeb/office/announcements/${withdraw.row.id}/withdraw`, "POST", { reason: withdraw.reason.trim() }, `Announcement withdrawn: ${withdraw.row.title}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify("The notice is withdrawn; it no longer shows on the dashboards.");
      setWithdraw(null); setTick((t) => t + 1);
    } finally { setBusy(false); }
  }
  const audienceWords = (a: Row) => a.audience === "PROGRAMME" ? `Programme: ${streamLabel(a.audience_ref)}` : a.audience === "CLASS" ? `Class: ${a.audience_name ?? "—"}`
    : a.audience === "STUDENT" ? `Student: ${a.audience_name ?? "—"} (advice)`
    : a.audience === "COMBINATION" ? `Combination: ${a.audience_ref}` : a.audience === "SUBJECT" ? `Subject: ${a.audience_name ?? "—"}` : AUDIENCE[a.audience] ?? a.audience;
  const today = new Date().toISOString().slice(0, 10);

  return (
    <>
      <PageHead title="JUPEB announcements" description="Withdrawn with a reason, never deleted."
        actions={<select className="ctl" aria-label="Session" value={session} onChange={(e) => setSession(e.target.value)}>
          {(data?.sessions ?? []).map((x) => <option key={x.session} value={x.session}>{x.session} ({x.applications})</option>)}</select>} />
      {canWrite ? (
        <Panel title="New announcement" right={count == null ? null : <Pil kind={count ? "info" : "grey"}>{`Reaches ${count} candidate${count === 1 ? "" : "s"}`}</Pil>}>
          <PBody>
            <div className="grid grid--3">
              <Field id="an-aud" label="To"><select id="an-aud" className="ctl" value={form.audience} onChange={(e) => setForm({ ...form, audience: e.target.value, ref: "" })}>
                {Object.entries(AUDIENCE).filter(([k]) => k !== "STUDENT").map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
              {form.audience === "CLASS" ? (
                <Field id="an-ref" label="Class" required><select id="an-ref" className="ctl" value={form.ref} onChange={(e) => setForm({ ...form, ref: e.target.value })}>
                  <option value="">— Choose —</option>{(data?.classes ?? []).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select></Field>
              ) : form.audience === "COMBINATION" ? (
                <Field id="an-ref" label="Combination" required><select id="an-ref" className="ctl" value={form.ref} onChange={(e) => setForm({ ...form, ref: e.target.value })}>
                  <option value="">— Choose —</option>{(data?.combinations ?? []).map((c) => <option key={c.code} value={c.code}>{c.code} — {c.name}</option>)}</select></Field>
              ) : form.audience === "SUBJECT" ? (
                <div className="grid grid--2">
                  <Field id="an-ref" label="Subject" required><select id="an-ref" className="ctl" value={form.ref.split("/")[0]} onChange={(e) => setForm({ ...form, ref: e.target.value })}>
                    <option value="">— Choose —</option>{(data?.subjects ?? []).map((x) => <option key={x.id} value={x.id}>{x.title} ({x.code})</option>)}</select></Field>
                  <Field id="an-ref2" label="Class"><select id="an-ref2" className="ctl" value={form.ref.split("/")[1] ?? ""} disabled={!form.ref}
                    onChange={(e) => setForm({ ...form, ref: e.target.value ? `${form.ref.split("/")[0]}/${e.target.value}` : form.ref.split("/")[0] })}>
                    <option value="">Every class</option>{(data?.classes ?? []).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select></Field>
                </div>
              ) : form.audience === "PROGRAMME" ? (
                <Field id="an-ref" label="Programme" required><select id="an-ref" className="ctl" value={form.ref} onChange={(e) => setForm({ ...form, ref: e.target.value })}>
                  <option value="">— Choose —</option><option value="SCIENCE">Science</option><option value="NON_SCIENCE">Non-Science</option></select></Field>
              ) : <div />}
              <Field id="an-exp" label="Show until" hint="Leave empty to keep it until withdrawn"><input id="an-exp" type="date" className="ctl" min={today} value={form.expiresOn} onChange={(e) => setForm({ ...form, expiresOn: e.target.value })} /></Field>
            </div>
            <Field id="an-title" label="Title" required><input id="an-title" className="ctl" maxLength={160} value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} /></Field>
            <Field id="an-body" label="Message" required hint={`${form.body.length}/5000`}><textarea id="an-body" className="ctl" rows={6} maxLength={5000} value={form.body} onChange={(e) => setForm({ ...form, body: e.target.value })} /></Field>
            <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-4)" }}>
              <label className="row row--inline row--tight"><input type="checkbox" checked={form.pinned} onChange={(e) => setForm({ ...form, pinned: e.target.checked })} /> Pin to the top</label>
              <label className="row row--inline row--tight"><input type="checkbox" checked={form.email} onChange={(e) => setForm({ ...form, email: e.target.checked })} /> Email it too</label>
              <label className="row row--inline row--tight"><input type="checkbox" checked={form.sms} onChange={(e) => setForm({ ...form, sms: e.target.checked })} /> Text them (the title, and a pointer to the portal)</label>
              <span className="grow" />
              <Btn kind="primary" disabled={busy || !ready || count === 0} onClick={() => setConfirm(true)}>Publish…</Btn>
            </div>
          </PBody>
        </Panel>
      ) : <Note kind="info" title="The JUPEB Office publishes announcements">You may read what has been published below.</Note>}
      <Panel title={`Published in ${session || "…"}`}>
        {!data ? <PBody><p className="sub2">Loading…</p></PBody> : !data.announcements.length ? <PBody><p className="sub2">No announcement in this session yet.</p></PBody> : (
          <DTable pageSize={20} cols={["Published", "Title", "To", "Reach|num", "Read|num", "Sent", "Status", ...(canWrite ? [""] : [])]}
            texts={data.announcements.map((a) => `${a.title} ${a.body}`)}
            rows={data.announcements.map((a) => {
              const expired = !!a.expires_on && a.expires_on < today;
              return [when(a.published_at), <span key="t"><b>{a.title}</b>{a.pinned ? <> <Pil kind="info">Pinned</Pil></> : null}<div className="sub2" style={{ whiteSpace: "pre-line" }}>{a.body.length > 160 ? a.body.slice(0, 160) + "…" : a.body}</div></span>,
                audienceWords(a), Number(a.reach), `${Number(a.reads)}${Number(a.reach) ? ` (${Math.round((100 * Number(a.reads)) / Number(a.reach))}%)` : ""}`,
                [a.send_email ? "Email" : null, a.send_sms ? "SMS" : null].filter(Boolean).join(" + ") + (a.notified != null && (a.send_email || a.send_sms) ? ` · ${a.notified}` : "") || "Dashboard only",
                a.withdrawn_at ? <span key="s"><Pil kind="grey">Withdrawn</Pil><div className="sub2">{a.withdrawn_reason}</div></span>
                  : expired ? <Pil key="s" kind="grey">Ended {day(a.expires_on)}</Pil> : <Pil key="s" kind="ok">{a.expires_on ? `Showing until ${day(a.expires_on)}` : "Showing"}</Pil>,
                ...(canWrite ? [a.withdrawn_at ? "" : <Btn key="w" kind="ghost" onClick={() => setWithdraw({ row: a, reason: "" })}>Withdraw</Btn>] : [])];
            })} />
        )}
      </Panel>
      {confirm ? (
        <Modal title="Publish this announcement?" onClose={() => setConfirm(false)}
          foot={<><Btn kind="ghost" onClick={() => setConfirm(false)}>Not yet</Btn><Btn kind="primary" disabled={busy} onClick={() => void publish()}>{busy ? "Publishing…" : "Publish"}</Btn></>}>
          <p>{`It shows at once on the dashboards of ${count ?? "the"} candidate${count === 1 ? "" : "s"} it reaches${form.email || form.sms ? `, and is ${[form.email ? "emailed" : null, form.sms ? "texted" : null].filter(Boolean).join(" and ")} to them` : ""}.`}</p>
          {form.email || form.sms ? <Note kind="info" title="An email or a text cannot be called back">Withdrawing later takes it off the dashboards only.</Note> : null}
          <div className="card mt-2"><div className="card__body"><div className="b700">{form.title}</div><p style={{ whiteSpace: "pre-line", margin: "var(--s-2) 0 0" }}>{form.body}</p></div></div>
        </Modal>
      ) : null}
      {withdraw ? (
        <Modal title={`Withdraw "${withdraw.row.title}"`} onClose={() => setWithdraw(null)}
          foot={<><Btn kind="ghost" onClick={() => setWithdraw(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || withdraw.reason.trim().length < 5} onClick={() => void doWithdraw()}>Withdraw</Btn></>}>
          <Field id="an-wr" label="Why" required hint="At least five characters; kept on the notice"><textarea id="an-wr" className="ctl" rows={3} maxLength={600} value={withdraw.reason} onChange={(e) => setWithdraw({ ...withdraw, reason: e.target.value })} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
