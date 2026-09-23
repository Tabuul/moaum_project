"use client";

/** The kept copy's own controls: back, Excel of the kept rows, print, and — until it is done —
 *  "Mark as filed": with whom the return went (NUC, JAMB, Council, the State treasury …). */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { buildXlsx, loadCrest } from "@/lib/xlsx";

export interface Dispatch { id: string; recipient: string; state: string; created_at: string; sent_at: string | null; last_error: string | null; files: string | null }

const dmy = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "");

export function FileReturn({ id, title, headers, rows, filedTo, dispatches }: {
  id: string; title: string; headers: string[]; rows: (string | number | null)[][]; filedTo: string | null; dispatches: Dispatch[];
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [to, setTo] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [mail, setMail] = useState(false);
  const [rcpt, setToList] = useState("");
  const [message, setMessage] = useState("");
  const [sending, setSending] = useState(false);
  const [sent, setSent] = useState<string | null>(null);
  const [mailErr, setMailErr] = useState<string | null>(null);

  async function send() {
    setSending(true); setMailErr(null);
    try {
      const list = rcpt.split(/[s,;]+/).map((x) => x.trim()).filter(Boolean);
      const r = await fetch(`/reports/snapshots/${id}/email`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ to: list, message: message.trim() || null }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setMailErr((j && (j.detail || j.title)) || `Could not send (${r.status})`); return; }
      setSent(`Queued to ${list.length} recipient${list.length === 1 ? "" : "s"} with the PDF and Excel attached — the outbox sends it within the minute.`);
      setMail(false); setToList(""); setMessage(""); router.refresh();
    } finally { setSending(false); }
  }

  async function file() {
    setBusy(true); setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/reports/snapshots/${id}/file`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": `Filed ${title} with ${to}` },
        body: JSON.stringify({ filedTo: to.trim(), note: note.trim() || null }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr((j && (j.detail || j.title)) || `Could not record the filing (${r.status})`); return; }
      setOpen(false); router.refresh();
    } finally { setBusy(false); }
  }

  function download() {
    void loadCrest().then((logo) => {
      const blob = buildXlsx(headers, rows, "Kept copy", {
        school: "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI", title,
        date: "Kept copy · exported " + new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }), logo: logo ?? undefined,
      });
      const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = `${title.replace(/[^\w]+/g, "-").toLowerCase()}-kept.xlsx`;
      document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    });
  }

  return (
    <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
      <Btn kind="ghost" onClick={() => router.push("/reports")}>← All returns</Btn>
      <span className="sub2">{filedTo ? `Filed with ${filedTo}` : "Kept, not yet filed"}{sent ? ` · ${sent}` : ""}</span>
      <span style={{ flexGrow: 1 }} />
      {!filedTo ? <Btn kind="go" onClick={() => { setErr(null); setOpen(true); }}>Mark as filed</Btn> : null}
      <Btn kind="ghost" onClick={() => { setMailErr(null); setMail(true); }}>Email this return</Btn>
      <Btn kind="ghost" onClick={download}>Download Excel</Btn>
      <Btn kind="primary" onClick={() => window.print()}>Print / Save as PDF</Btn>
      {dispatches.length ? (
        <div className="sub2" style={{ width: "100%", display: "grid", gap: 2 }}>
          {dispatches.slice(0, 8).map((d) => (
            <div key={d.id}>
              Sent to <b>{d.recipient}</b> · {dmy(d.created_at)} · {d.state === "SENT" ? <span style={{ color: "var(--green-ink)" }}>delivered to the mail server {dmy(d.sent_at)}</span> : d.state === "FAILED" ? <span style={{ color: "var(--red-ink)" }}>failed{d.last_error ? ` — ${d.last_error}` : ""}</span> : "queued"}{d.files ? ` · ${d.files}` : ""}
            </div>
          ))}
        </div>
      ) : null}
      {mail ? (
        <Modal title="Email this return" sub={`${title} — the PDF and the Excel workbook go attached, with the verification code`} onClose={() => setMail(false)}
          foot={<><Btn kind="ghost" onClick={() => setMail(false)}>Cancel</Btn><span style={{ flexGrow: 1 }} /><Btn kind="primary" disabled={sending || !rcpt.trim()} onClick={() => void send()}>{sending ? "Preparing the files…" : "Send"}</Btn></>}>
          {mailErr ? <div className="sub2" style={{ color: "var(--red-ink)", marginBottom: 8 }}>{mailErr}</div> : null}
          <Field id="em-to" label="To" hint="One or more email addresses, separated by commas">
            <input id="em-to" className="ctl" value={rcpt} onChange={(e) => setToList(e.target.value)} autoComplete="off" placeholder="registrar@…, nuc-liaison@…" />
          </Field>
          <Field id="em-msg" label="Message" hint="Goes above the attachment note — a covering line, a reference, what is asked of the reader">
            <textarea id="em-msg" className="ctl" rows={4} value={message} onChange={(e) => setMessage(e.target.value)} />
          </Field>
        </Modal>
      ) : null}
      {open ? (
        <Modal title="Record the filing" sub={title} onClose={() => setOpen(false)}
          foot={<><Btn kind="ghost" onClick={() => setOpen(false)}>Cancel</Btn><span style={{ flexGrow: 1 }} /><Btn kind="primary" disabled={busy || !to.trim()} onClick={() => void file()}>{busy ? "Recording…" : "Filed"}</Btn></>}>
          {err ? <div className="sub2" style={{ color: "var(--red-ink)", marginBottom: 8 }}>{err}</div> : null}
          <Field id="fr-to" label="Filed with" hint="The body the return went to — NUC, JAMB, Council, the State treasury, Senate, management">
            <input id="fr-to" className="ctl" value={to} onChange={(e) => setTo(e.target.value)} autoComplete="off" list="fr-to-list" />
            <datalist id="fr-to-list">{["NUC", "JAMB", "Council", "State treasury", "Senate", "Management", "School Board"].map((x) => <option key={x} value={x} />)}</datalist>
          </Field>
          <Field id="fr-note" label="Note" hint="Reference, covering letter number, or how it was sent — optional">
            <input id="fr-note" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} autoComplete="off" />
          </Field>
        </Modal>
      ) : null}
    </div>
  );
}
