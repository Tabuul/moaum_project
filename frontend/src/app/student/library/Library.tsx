"use client";

/** sLibrary — proto/part8.html: on loan to you, the fine, the catalogue — from the loans and the rule in force (V031). */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import type { StudentLibrary } from "@/lib/library";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { naira, onDay, useAct } from "../common";

export function Library({ l, q }: { l: StudentLibrary; q: string }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const { act, busy, problem } = useAct();
  const [query, setQuery] = useState(q);
  const [said, setSaid] = useState<string | null>(null);
  const open = l.loans.filter((x) => !x.returned_at);
  const fines = l.loans.filter((x) => x.returned_at && x.fine && !x.fine_settled_at && !x.fine_waived_at);
  const overdue = open.filter((x) => x.days_overdue > 0);

  return (
    <>
      <Panel title="On loan to you" right={`${open.length} item${open.length === 1 ? "" : "s"} · up to ${l.setting.max_loans}, ${l.setting.loan_days} days each`}>
        {open.length ? (
          <DTable cols={["Item", "Accession|mid", "Due", "Status|num"]} rows={open.map((x) => [
            <Two key="i" a={`${x.title}${x.edition ? `, ${x.edition}` : ""}`} b={x.author ?? ""} />,
            <span className="tnum" key="a">{x.accession}</span>,
            <span className="tnum" key="d">{onDay(x.due_on)}</span>,
            <span key="s">{x.days_overdue > 0 ? <Pil kind="bad">{x.days_overdue} day{x.days_overdue === 1 ? "" : "s"} overdue</Pil> : <Pil kind="ok">{x.days_left} day{x.days_left === 1 ? "" : "s"}</Pil>}{" "}
              {x.days_overdue === 0 && x.renewals < l.setting.max_renewals ? <Btn kind="ghost" disabled={busy !== null} onClick={async () => { const r = await act("renew", "POST", `/me/library/loans/${x.id}/renew`, {}, `Renewed ${x.accession}`); if (r) setSaid(`Renewed to ${onDay(String(r.dueOn))}`); }}>Renew</Btn> : null}</span>,
          ])} />
        ) : <PBody><div className="sub2">Nothing on loan to you.</div></PBody>}
      </Panel>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record.</Note> : null}
      {overdue.length ? (
        <Note kind="bad" title={`${overdue.length} item${overdue.length === 1 ? " is" : "s are"} overdue`}>
          A fine of {naira(l.setting.fine_per_day)} per day is posted to your account when the item is returned. Library clearance is required before a transcript or certificate is released, and nothing is issued to you while an overdue item is out.
        </Note>
      ) : null}
      {fines.length ? (
        <Panel title="Fines" right={`${naira(fines.reduce((n, x) => n + Number(x.fine ?? 0), 0))} unpaid`}>
          <DTable cols={["Item", "Returned", "Fine|num", "|num"]} rows={fines.map((x) => [
            <Two key="i" a={x.title} b={x.accession} />,
            <span className="sub2 tnum" key="r">{onDay(x.returned_at)}</span>,
            <b className="tnum" key="f">{naira(x.fine)}</b>,
            <span key="p">{x.fine_reference ? <LinkBtn kind="ghost" href="/student/fees">Pay {x.fine_reference}</LinkBtn> :<Btn kind="primary" disabled={busy !== null} onClick={async () => { const r = await act("fine", "POST", `/me/library/loans/${x.id}/fine-reference`, {}, `Library fine reference for ${x.accession}`); if (r) { setSaid(`Pay ${naira(x.fine)} against ${r.reference} on the Fees page`); router.refresh(); } }}>Generate the reference</Btn>}</span>,
          ])} />
        </Panel>
      ) : null}
      {l.reservations.length ? (
        <Panel title="Reservations" right={`${l.reservations.length}`}>
          <DTable cols={["Item", "Reserved", "Position|num"]} rows={l.reservations.map((r) => [
            <Two key="i" a={r.title} b={r.author ?? ""} />,
            <span className="sub2 tnum" key="d">{onDay(r.reserved_at)}</span>,
            r.state === "READY" ? <Pil kind="ok" key="s">Held for you — collect it</Pil> : <Pil kind="info" key="s">{r.ahead ? `${r.ahead} ahead of you` : "Next"}</Pil>,
          ])} />
        </Panel>
      ) : null}
      <Panel title="Search the catalogue">
        <PBody>
          <form className="field" onSubmit={(e) => { e.preventDefault(); queryNav(`/student/library?q=${encodeURIComponent(query)}`); }}>
            <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Title, author, subject or ISBN" aria-label="Search the catalogue" autoComplete="off" />
          </form>
          {q ? (l.catalogue.length ? (
            <DTable cols={["Title", "Copies|mid", "Available|mid", "|num"]} rows={l.catalogue.map((c) => [
              <Two key="t" a={c.title} b={`${c.author ?? ""}${c.year ? ` · ${c.year}` : ""}${c.edition ? ` · ${c.edition}` : ""}`} />,
              <span className="tnum" key="c">{c.copies}</span>,
              <span className={`tnum b600 ${c.available ? "ink-green" : "ink-red"}`} key="a">{c.available}</span>,
              c.available ? <span className="sub2" key="r">On the shelf — borrow it at the desk</span> : <Btn kind="ghost" key="r" disabled={busy !== null} onClick={async () => { const r = await act("reserve", "POST", "/me/library/reservations", { itemId: c.id }, `Reserved ${c.title}`); if (r) setSaid(`Reserved — ${c.waiting} waiting ahead of you`); }}>Join the waiting list</Btn>,
            ])} />
          ) : <div className="sub2">Nothing in the catalogue matches “{q}”.</div>) : <div className="sub2">{l.standing.clear ? "Nothing stands against you at the Library." : "Items on loan or a fine unpaid stand against you; clear them before a transcript or certificate is released."}</div>}
        </PBody>
      </Panel>
    </>
  );
}
