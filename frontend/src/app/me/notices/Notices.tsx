"use client";

/** Notifications — what the portal has sent this member of staff: a sheet returned, a deadline, a ticket
 *  answered, an appointment. Each is the very notice the email or text carried, read back from the outbox, so
 *  the list here and the inbox never disagree. Read-only: nothing is composed or deleted on this screen. */
import { useState } from "react";
import type { StaffNotice } from "@/lib/lecturer";
import { Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { whenAt } from "@/lib/lecturer";

const STATE: Record<StaffNotice["state"], [string, "ok" | "grey" | "bad"]> = { SENT: ["Delivered", "ok"], QUEUED: ["Waiting to send", "grey"], FAILED: ["Not delivered", "bad"] };
const KIND: Record<string, string> = { person: "About you", ticket: "ICT support ticket", sheet: "Score sheet", application: "Application", student: "Student" };

export function Notices({ items }: { items: StaffNotice[] }) {
  const [now] = useState(() => Date.now());
  const [q, setQ] = useState("");
  const [channel, setChannel] = useState("");
  const [open, setOpen] = useState<string | null>(items[0]?.id ?? null);
  const needle = q.trim().toLowerCase();
  const shown = items.filter((n) => (!channel || n.channel === channel) && (!needle || `${n.subject} ${n.body}`.toLowerCase().includes(needle)));
  const week = items.filter((n) => now - new Date(n.created_at).getTime() < 7 * 86400000).length;

  return (
    <>
      <PageHead title="Notifications" description="Every notice the portal has sent you, newest first. Each one is the same message your email or phone received." />
      <Tiles items={[
        ["All notices", String(items.length), null, "On your record"],
        ["This week", String(week), week ? "var(--chrome)" : null, "Sent in the last seven days"],
        ["By email", String(items.filter((n) => n.channel === "EMAIL").length), null, "To the address on your record"],
        ["Not delivered", String(items.filter((n) => n.state === "FAILED").length), items.some((n) => n.state === "FAILED") ? "var(--red-ink)" : null, "The Directorate of ICT retries these"],
      ]} />
      <div className="scope">
        <div className="scope__f grow"><Field id="nt-q" label="Search">
          <input id="nt-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} placeholder="A subject or a word in the notice" />
        </Field></div>
        <div className="scope__f"><Field id="nt-ch" label="Channel">
          <select id="nt-ch" className="ctl" value={channel} onChange={(e) => setChannel(e.target.value)}>
            <option value="">Email and SMS</option><option value="EMAIL">Email</option><option value="SMS">SMS</option>
          </select>
        </Field></div>
      </div>
      <Panel title="Notices" right={`${shown.length} of ${items.length}`}>
        {items.length === 0 ? (
          <PBody><Note kind="info" title="Nothing has been sent to you yet">A notice is filed here when a score sheet is returned to you, a deadline approaches, a result is published, a support ticket is answered or an office writes to you.</Note></PBody>
        ) : shown.length === 0 ? (
          <PBody><div className="sub2">Nothing matches.</div></PBody>
        ) : (
          <ul className="plain">
            {shown.map((n) => {
              const [word, kind] = STATE[n.state] ?? ["", "grey"];
              const isOpen = open === n.id;
              return (
                <li key={n.id} style={{ borderBottom: "1px solid var(--line)" }}>
                  <button type="button" className="row row--between" onClick={() => setOpen(isOpen ? null : n.id)} aria-expanded={isOpen}
                    style={{ width: "100%", textAlign: "left", background: "none", border: 0, padding: "12px var(--s-4)", cursor: "pointer", gap: "var(--s-3)", font: "inherit", color: "inherit" }}>
                    <span style={{ minWidth: 0 }}>
                      <strong>{n.subject}</strong>
                      <div className="sub2">{whenAt(n.created_at)}{n.about_kind ? ` · ${KIND[n.about_kind] ?? n.about_kind}` : ""}</div>
                    </span>
                    <span className="row row--inline row--tight"><Pil kind="grey">{n.channel === "SMS" ? "SMS" : "Email"}</Pil><Pil kind={kind} title={n.sent_at ? `Sent ${whenAt(n.sent_at)}` : undefined}>{word}</Pil></span>
                  </button>
                  {isOpen ? <div style={{ whiteSpace: "pre-wrap", padding: "0 var(--s-4) 14px", fontSize: 13.5, lineHeight: 1.55 }}>{n.body}</div> : null}
                </li>
              );
            })}
          </ul>
        )}
      </Panel>
    </>
  );
}
