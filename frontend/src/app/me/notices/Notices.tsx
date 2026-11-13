"use client";

/** Notifications — the notices the portal sent about this member of staff or to them, read back from the outbox
 *  (GET /api/v1/me/notices, V749's platform.person_notices): the notices filed about them (an appointment, a clearance
 *  reminder); the e-mail sent to the address they verified (a ticket answered, a report); and some notices of their work
 *  (a course allocated, a sheet returned, a transfer, a deferment) sent to an address or phone no other record holds.
 *  Other mail to an address not yet verified is listed once it is verified, and a message carrying a code or a sign-in
 *  link never is: the screen says so while the address waits (lib/identity noticesAwaitEmail). Each is the very notice the email or text carried. Read-only:
 *  nothing is composed or deleted on this screen. */
import { useState } from "react";
import type { StaffNotice } from "@/lib/lecturer";
import { LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { whenAt } from "@/lib/lecturer";
import { NOTICES_AWAIT_EMAIL } from "@/lib/identity";

const STATE: Record<StaffNotice["state"], [string, "ok" | "grey" | "bad"]> = { SENT: ["Delivered", "ok"], QUEUED: ["Waiting to send", "grey"], FAILED: ["Not delivered", "bad"] };
const KIND: Record<string, string> = {
  person: "About you", ticket: "ICT support ticket", sheet: "Score sheet", application: "Application", student: "Student",
  // V749: the kinds GET /api/v1/me/notices (platform.person_notices) now lists by what they are about
  clearance_chase: "Clearance reminder", offering: "Course allocation", score_sheet: "Score sheet", transfer: "Transfer", clearance_document: "Clearance document",
  putme_score_export: "Post-UTME scores", deferment: "Deferment", report_snapshot: "Report snapshot",
};
/** what a notice is about, in words: an office's notice (admissions.tell_office marks it OFFICE_TELL, V749) is filed 'application' as an
 *  applicant's own message is, and is told from it by the mark */
const kindOf = (n: StaffNotice) => (n.about_kind === "application" && n.template_key === "OFFICE_TELL" ? "Office notice" : n.about_kind ? KIND[n.about_kind] ?? n.about_kind : "");

/** awaitEmail: the address on the person's record is not verified (lib/identity noticesAwaitEmail), so mail sent to it is not listed */
export function Notices({ items, awaitEmail = false }: { items: StaffNotice[]; awaitEmail?: boolean }) {
  const [now] = useState(() => Date.now());
  const [q, setQ] = useState("");
  const [channel, setChannel] = useState("");
  const [open, setOpen] = useState<string | null>(items[0]?.id ?? null);
  const needle = q.trim().toLowerCase();
  const shown = items.filter((n) => (!channel || n.channel === channel) && (!needle || `${n.subject} ${n.body}`.toLowerCase().includes(needle)));
  const week = items.filter((n) => now - new Date(n.created_at).getTime() < 7 * 86400000).length;

  return (
    <>
      <PageHead title="Notifications" description="Newest first" />
      <Tiles items={[
        ["All notices", String(items.length), null, "About you and your work"],
        ["This week", String(week), week ? "var(--chrome)" : null, "Sent in the last seven days"],
        ["By email", String(items.filter((n) => n.channel === "EMAIL").length), null, awaitEmail ? "About you or your work" : "About you, or to the address you verified"],
        ["Not delivered", String(items.filter((n) => n.state === "FAILED").length), items.some((n) => n.state === "FAILED") ? "var(--red-ink)" : null, "The Directorate of ICT retries these"],
      ]} />
      {awaitEmail ? (
        <Note kind="info" title={NOTICES_AWAIT_EMAIL} action={<LinkBtn kind="primary" href="/me/identity#email">Verify at My identity</LinkBtn>}>
          Until then this list holds the notices about you and some notices of your work.
        </Note>
      ) : null}
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
          <PBody>
            <Note kind="info" title="No notices for you yet">
              Notices about you, e-mail sent to the address you verified, and some notices of your work (a course allocated, a score sheet,
              a transfer, a deferment) appear here.
            </Note>
          </PBody>
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
                      <div className="sub2">{whenAt(n.created_at)}{kindOf(n) ? ` · ${kindOf(n)}` : ""}</div>
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
