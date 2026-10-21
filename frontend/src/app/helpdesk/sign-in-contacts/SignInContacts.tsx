"use client";

/** Sign-in help contacts (V599). A request from the sign-in page saves the e-mail or phone it gives to a student record that holds
 *  none (V596); since anyone may type any student's number, such a contact reaches no notice and no reset link until the student
 *  confirms it with a code when they sign in, or the desk confirms it with them. Here the desk sees every one within its reach,
 *  with the request and who asked, and confirms or refuses it. The Head and the Director of ICT also see the day's student-number
 *  checks on the sign-in page by connection — a connection stepping through numbers is collecting names — and set the figures. */
import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { fieldWord, figureOk, figureValue, lookupState, type Lookups, type SignInContacts as List } from "@/lib/sign-in-contacts";
import { Btn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { UploadedContact } from "../students/[id]/UploadedContact";

const when = (iso: string | null) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—");
const time = (iso: string | null) => (iso ? new Date(iso).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—");
const count = (n: number) => Number(n).toLocaleString("en-NG");

const STATE: Record<ReturnType<typeof lookupState>, [string, "bad" | "warn" | "info" | "grey"]> = {
  REFUSED: ["Day's figure reached — refused", "bad"], TOLD: ["Head told", "warn"], NEAR: ["Half the alert figure", "info"], QUIET: ["—", "grey"],
};

export function SignInContacts({ list, lookups, lookupsProblem }: { list: List; lookups: Lookups | null; lookupsProblem: Problem | null }) {
  const emails = list.rows.filter((r) => r.field === "EMAIL").length;
  return (
    <>
      <PageHead eyebrow="ICT Support Desk"
        description="E-mails and phones saved to student records from requests on the sign-in page. Anyone can type a student's number there, so such a contact reaches no notice and no reset link until the student confirms it with a code when they sign in, or you confirm it with them. Remove one that is not the student's." />
      <Tiles cls="grid--3" items={[
        ["Waiting to be confirmed", count(list.rows.length), list.rows.length ? "var(--amber-ink)" : null, list.scope ? `within ${list.scope}` : "within your reach"],
        ["E-mail addresses", count(emails), null, "no notice goes to them yet"],
        ["Phone numbers", count(list.rows.length - emails), null, "no SMS goes to them yet"],
      ]} />
      <Panel title="Contacts saved from the sign-in page" right={list.rows.length ? "Newest request first" : undefined}>
        {!list.mayDecide ? <PBody><Note kind="info" title="Contact editing is not on your posting">The Head of the Support Desk grants it; until then the contacts within your reach are not listed.</Note></PBody> : null}
        {list.rows.length ? (
          <DTable pageSize={50} cols={["Student", "Number", "Programme", "Saved", "Contact", "Request", "Asked by", "Decision|num"]} rows={list.rows.map((r) => [
            <Link key="s" className="lnk" href={`/helpdesk/students/${r.student_id}${r.ticket_id ? `?ticket=${encodeURIComponent(r.ticket_id)}` : ""}`}>{r.name}</Link>,
            <span key="m" className="tnum">{r.number ?? "—"}<div className="sub2">{r.level ? `${r.level} Level` : ""}</div></span>,
            <span key="p" className="sub2">{r.programme ?? "—"}<div>{r.department ?? ""}</div></span>,
            <span key="w" className="tnum sub2">{when(r.saved_at)}</span>,
            <span key="c"><span className="sub2">{fieldWord(r.field)}</span><div className="tnum b600" style={{ wordBreak: "break-all" }}>{r.value}</div></span>,
            r.ticket_id ? <span key="t"><Link className="lnk tnum" href={`/helpdesk/tickets/${r.ticket_id}`}>{r.ticket_number}</Link><div className="sub2">{(r.ticket_status ?? "").toLowerCase()}</div></span>
              : <span key="t" className="sub2">—</span>,
            <span key="a" className="sub2">{r.asked_by ?? "—"}<div style={{ wordBreak: "break-all" }}>{r.asked_email ?? ""}</div></span>,
            <UploadedContact key="d" id={r.student_id} field={r.field} may={list.mayDecide} ticket={null} source="SIGN_IN" request={null} />,
          ])} />
        ) : list.mayDecide ? <PBody><span className="sub2">No contact saved from the sign-in page is waiting within your reach.</span></PBody> : null}
      </Panel>
      {lookupsProblem ? <ProblemNotice problem={lookupsProblem} /> : null}
      {lookups ? <NumberChecks lookups={lookups} /> : null}
    </>
  );
}

/** the day's student-number checks on the sign-in page by connection, and the two figures */
function NumberChecks({ lookups }: { lookups: Lookups }) {
  const go = useQueryNav();
  const router = useRouter();
  const [daily, setDaily] = useState(lookups.daily == null ? "" : String(lookups.daily));
  const [alert, setAlert] = useState(lookups.alert == null ? "" : String(lookups.alert));
  const [busy, setBusy] = useState(false);
  const changed = daily !== (lookups.daily == null ? "" : String(lookups.daily)) || alert !== (lookups.alert == null ? "" : String(lookups.alert));
  const valid = figureOk(daily) && figureOk(alert);
  const found = lookups.rows.reduce((n, r) => n + Number(r.found), 0);

  async function save() {
    setBusy(true);
    try {
      const r = await fetch("/api/bff/api/v1/helpdesk/support/sign-in-contacts/lookups/figures", {
        method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Sign-in page number checks: the day's figure and the alert figure set") },
        body: JSON.stringify({ daily: figureValue(daily), alert: figureValue(alert) }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify("The figures are saved");
      router.refresh();
    } finally { setBusy(false); }
  }

  return (
    <Panel title="Student numbers checked on the sign-in page" right={`${count(lookups.rows.length)} connection${lookups.rows.length === 1 ? "" : "s"} · ${count(found)} students' numbers`}>
      <PBody>
        <div className="sub2">
          A number typed on Ask for help signing in that a student holds shows the student&apos;s name. Each check from a connection is kept for 180 days. A University
          network shares one address among many students, so a busy address is not always someone collecting names; one stepping through numbers is.
        </div>
        <form className="filterbar mt-2" onSubmit={(e) => { e.preventDefault(); if (valid && changed) void save(); }}>
          <Field id="lk-day" label="Day"><input id="lk-day" className="ctl" type="date" value={lookups.day} onChange={(e) => go(`/helpdesk/sign-in-contacts${e.target.value ? `?day=${e.target.value}` : ""}`)} /></Field>
          <Field id="lk-daily" label="Checks a connection may make in a day" hint="Empty for no daily figure"
            error={figureOk(daily) ? undefined : "A whole number from 1 to 10,000, or empty"}>
            <input id="lk-daily" className="ctl tnum" inputMode="numeric" placeholder="No figure" value={daily} onChange={(e) => setDaily(e.target.value)} />
          </Field>
          <Field id="lk-alert" label="Different numbers at which the Head is told" hint="Empty: no one is told"
            error={figureOk(alert) ? undefined : "A whole number from 1 to 10,000, or empty"}>
            <input id="lk-alert" className="ctl tnum" inputMode="numeric" placeholder="Never" value={alert} onChange={(e) => setAlert(e.target.value)} />
          </Field>
          <Btn kind="primary" size="sm" type="submit" disabled={busy || !valid || !changed}>{busy ? "Saving…" : "Save figures"}</Btn>
        </form>
      </PBody>
      {lookups.rows.length ? (
        <DTable pageSize={50} cols={["Connection", "Checks|num", "Different numbers|num", "Students' numbers|num", "First|mid", "Last|mid", "State"]} rows={lookups.rows.map((r) => {
          const [word, kind] = STATE[lookupState(r, lookups.alert)];
          return [
            <span key="s" className="tnum b600">{r.source}</span>,
            <span key="c" className="tnum">{count(r.checks)}</span>,
            <span key="n" className="tnum">{count(r.numbers)}</span>,
            <span key="f" className="tnum">{count(r.found)}</span>,
            <span key="a" className="tnum sub2">{time(r.first_at)}</span>,
            <span key="b" className="tnum sub2">{time(r.last_at)}</span>,
            kind === "grey" ? <span key="x" className="sub2">—</span> : <Pil key="x" kind={kind}>{word}</Pil>,
          ];
        })} />
      ) : <PBody><span className="sub2">No student number was checked on the sign-in page that day.</span></PBody>}
    </Panel>
  );
}
