"use client";

/** lCirculation — proto/part10.html: circulation today, the overdue, the fines, and what stands against a patron. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import type { LibraryDeskData, Loan } from "@/lib/library";
import { Btn, Note, Panel, PBody, Pil, RoleLine, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, day, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export function Circulation({ d, patron, q, actingOffice }: { d: LibraryDeskData; patron: string; q: string; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["library", "services", "admin", "super"].includes(actingOffice ?? "");
  const librarian = actingOffice === "library" || actingOffice === "super";
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const [accession, setAccession] = useState("");
  const [who, setWho] = useState(patron);
  const [query, setQuery] = useState(q);
  const [item, setItem] = useState({ title: "", author: "", edition: "", year: "", isbn: "", subject: "", kind: "BOOK", accessions: "", location: "" });
  const [setting, setSetting] = useState({ loanDays: String(d.setting.loan_days), finePerDay: String(d.setting.fine_per_day), maxLoans: String(d.setting.max_loans), maxRenewals: String(d.setting.max_renewals) });
  const t = d.tiles;

  async function send(path: string, method: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(path, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      router.refresh();
      return j;
    } finally {
      setBusy(false);
    }
  }
  const go = () => { const p = new URLSearchParams(); if (who) p.set("patron", who); if (query) p.set("q", query); router.push(`/library/circulation?${p}`); };
  const loanRow = (x: Loan) => [
    <Two key="p" a={x.patron} b={x.number ?? x.staff_number ?? ""} />,
    <Two key="i" a={x.title} b={x.accession} />,
    <span className="tnum" key="d">{day(x.due_on)}</span>,
  ];

  return (
    <>
      <RoleLine allowed={["library", "services"]} actingOffice={actingOffice} canAct={may}
        action="Issuing, returning and reserving loans" />
      <Tiles items={[
        ["Copies in stock", t.stock.toLocaleString(), null, "On the shelf list"],
        ["On loan", t.on_loan.toLocaleString(), null, t.stock ? `${Math.round((100 * t.on_loan) / t.stock)}% of stock` : "—"],
        ["Overdue", t.overdue.toLocaleString(), t.overdue ? "var(--red-ink)" : null, `Fines posted at ${money(Number(d.setting.fine_per_day))} a day on return`],
        ["Fines unpaid", money(Number(t.fines_unpaid)), Number(t.fines_unpaid) ? "var(--red-ink)" : null, `${t.waiting} on waiting lists`],
      ]} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record, in your name.</Note> : null}

      <div className="grid grid--2">
        <Panel title="Issue, return, renew" right={`${d.setting.loan_days} days · ${d.setting.max_loans} items · ${d.setting.max_renewals} renewal${d.setting.max_renewals === 1 ? "" : "s"}`}>
          <PBody>
            <div className="grid grid--2">
              <Field id="ci-acc" label="Accession number"><input id="ci-acc" className="ctl tnum" value={accession} onChange={(e) => setAccession(e.target.value)} placeholder="CSC/004182" autoComplete="off" /></Field>
              <Field id="ci-who" label="Patron" hint="Matriculation, admission or staff number"><input id="ci-who" className="ctl tnum" value={who} onChange={(e) => setWho(e.target.value)} autoComplete="off" /></Field>
            </div>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
              <Btn kind="primary" disabled={!may || busy || !accession.trim() || !who.trim()} onClick={async () => { const j = await send("/api/bff/api/v1/library/loans", "POST", { accession, patron: who }, `Issued ${accession} to ${who}`); if (j) { setSaid(`${accession.toUpperCase()} issued to ${j.patron}`); setAccession(""); } }}>Issue</Btn>
              <Btn kind="go" disabled={!may || busy || !accession.trim()} onClick={async () => { const j = await send("/api/bff/api/v1/library/returns", "POST", { accession }, `Returned ${accession}`); if (j) { setSaid(Number(j.fine) > 0 ? `Returned ${j.days_overdue} days late — fine ${money(Number(j.fine))} posted` : "Returned on time"); setAccession(""); } }}>Return</Btn>
              <Btn kind="ghost" disabled={busy} onClick={go}>Look the patron up</Btn>
            </div>
            {d.patron === null && patron ? <Note kind="bad" title={`Nobody carries the number ${patron}`}>The matriculation, admission or staff number, as issued.</Note> : null}
            {d.patron ? (
              <>
                <Note kind={d.patronStanding?.clear ? "ok" : "bad"} title={`${d.patron.name} · ${d.patron.number} · ${d.patron.programme}`}>
                  {d.patronStanding ? `${d.patronStanding.on_loan} on loan, ${d.patronStanding.overdue} overdue, ${money(Number(d.patronStanding.fines_unpaid))} in fines unpaid. ${d.patronStanding.clear ? "Nothing stands against this patron: the Library clears." : "Something stands against this patron: the clearance desk holds, naming it."}` : "A member of staff; loans are listed under the staff number."}
                </Note>
                {d.patronLoans?.length ? (
                  <DTable cols={["Item", "Due", "Status", "|num"]} rows={d.patronLoans.map((x) => [
                    <Two key="i" a={x.title} b={x.accession} />,
                    <span className="tnum" key="d">{day(x.due_on)}</span>,
                    x.returned_at ? (x.fine && !x.fine_settled_at && !x.fine_waived_at ? <Pil kind="bad" key="s">Fine {money(Number(x.fine))} unpaid</Pil> : <Pil kind="ok" key="s">Returned</Pil>) : x.days_overdue ? <Pil kind="bad" key="s">{x.days_overdue} days overdue</Pil> : <Pil kind="info" key="s">On loan</Pil>,
                    <span key="a">{!x.returned_at && may ? <Btn kind="ghost" disabled={busy} onClick={async () => { const j = await send(`/api/bff/api/v1/library/loans/${x.id}/renew`, "POST", {}, `Renewed ${x.accession}`); if (j) setSaid(`Renewed to ${day(String(j.dueOn))}`); }}>Renew</Btn> : null}{x.returned_at && x.fine && !x.fine_settled_at && !x.fine_waived_at && librarian ? <Btn kind="ghost" disabled={busy} onClick={async () => { const why = window.prompt("Why is the fine waived? It goes on the record."); if (why && await send(`/api/bff/api/v1/library/loans/${x.id}/waive`, "POST", { why }, `Fine waived on ${x.accession}`)) setSaid("Fine waived"); }}>Waive</Btn> : null}</span>,
                  ])} />
                ) : null}
              </>
            ) : null}
          </PBody>
        </Panel>
        <Panel title="Circulation today" right={`${d.today.length}`}>
          {d.today.length ? (
            <DTable cols={["Patron", "Item", "Due", "Action|num"]} rows={d.today.map((x) => [...loanRow(x), x.returned_at ? <Pil kind="ok" key="a">Returned{x.fine ? ` · fine ${money(Number(x.fine))}` : ""}</Pil> : x.renewals ? <Pil kind="ok" key="a">Renewed</Pil> : <Pil kind="ok" key="a">Issued</Pil>])} />
          ) : <PBody><div className="sub2">Nothing issued or returned today.</div></PBody>}
        </Panel>
      </div>

      <Panel title="Overdue" right={`${d.overdue.length} · fines posted automatically on return`}>
        {d.overdue.length ? (
          <DTable cols={["Patron", "Item", "Due", "Days|mid", "Fine so far|num"]} rows={d.overdue.map((x) => [...loanRow(x), <b className="tnum" key="n" style={{ color: "var(--red-ink)" }}>{x.days_overdue}</b>, <span className="tnum" key="f">{money(x.days_overdue * Number(d.setting.fine_per_day))}</span>])} texts={d.overdue.map((x) => `${x.patron} ${x.number} ${x.title}`)} />
        ) : <PBody><div className="sub2">Nothing overdue.</div></PBody>}
      </Panel>

      <Panel title="Fines unpaid" right="Settled against a payment reference, or waived by the Librarian with the reason">
        {d.fines.length ? (
          <DTable cols={["Patron", "Item", "Returned", "Fine|num", "|num"]} rows={d.fines.map((x) => [
            <Two key="p" a={x.patron} b={x.number ?? ""} />, <Two key="i" a={x.title} b={x.accession} />,
            <span className="sub2 tnum" key="r">{day(x.returned_at)}</span>, <b className="tnum" key="f">{money(Number(x.fine))}</b>,
            <span key="a">{x.fine_reference ? <span className="sub2 tnum">{x.fine_reference}</span> : <span className="sub2">No reference yet</span>} {librarian ? <Btn kind="ghost" disabled={busy} onClick={async () => { const why = window.prompt("Why is the fine waived? It goes on the record."); if (why && await send(`/api/bff/api/v1/library/loans/${x.id}/waive`, "POST", { why }, `Fine waived on ${x.accession}`)) setSaid("Fine waived"); }}>Waive</Btn> : null}</span>,
          ])} texts={d.fines.map((x) => `${x.patron} ${x.number} ${x.title}`)} />
        ) : <PBody><div className="sub2">No fine unpaid.</div></PBody>}
      </Panel>

      <div className="grid grid--2">
        <Panel title="Catalogue" right="Search, and add">
          <PBody>
            <form className="field" onSubmit={(e) => { e.preventDefault(); go(); }}><input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Title, author, subject or ISBN" aria-label="Search the catalogue" autoComplete="off" /></form>
            {q ? (d.catalogue.length ? <DTable cols={["Title", "Copies|mid", "Available|mid", "Waiting|mid"]} rows={d.catalogue.map((c) => [<Two key="t" a={c.title} b={`${c.author ?? ""}${c.year ? ` · ${c.year}` : ""}`} />, <span className="tnum" key="c">{c.copies}</span>, <span className="tnum" key="a">{c.available}</span>, <span className="tnum" key="w">{c.waiting}</span>])} /> : <div className="sub2">Nothing matches “{q}”.</div>) : null}
            {may ? (
              <>
                <div className="grid grid--2">
                  <Field id="it-title" label="Title"><input id="it-title" className="ctl" value={item.title} onChange={(e) => setItem({ ...item, title: e.target.value })} /></Field>
                  <Field id="it-author" label="Author"><input id="it-author" className="ctl" value={item.author} onChange={(e) => setItem({ ...item, author: e.target.value })} /></Field>
                  <Field id="it-ed" label="Edition"><input id="it-ed" className="ctl" value={item.edition} onChange={(e) => setItem({ ...item, edition: e.target.value })} /></Field>
                  <Field id="it-year" label="Year"><input id="it-year" className="ctl tnum" value={item.year} onChange={(e) => setItem({ ...item, year: e.target.value })} /></Field>
                  <Field id="it-isbn" label="ISBN"><input id="it-isbn" className="ctl tnum" value={item.isbn} onChange={(e) => setItem({ ...item, isbn: e.target.value })} /></Field>
                  <Field id="it-subj" label="Subject"><input id="it-subj" className="ctl" value={item.subject} onChange={(e) => setItem({ ...item, subject: e.target.value })} /></Field>
                  <Field id="it-kind" label="Kind"><select id="it-kind" className="ctl" value={item.kind} onChange={(e) => setItem({ ...item, kind: e.target.value })}>{["BOOK", "JOURNAL", "THESIS", "AUDIOVISUAL", "REFERENCE"].map((k) => <option key={k} value={k}>{k.charAt(0) + k.slice(1).toLowerCase()}</option>)}</select></Field>
                  <Field id="it-loc" label="Shelf"><input id="it-loc" className="ctl" value={item.location} onChange={(e) => setItem({ ...item, location: e.target.value })} /></Field>
                </div>
                <Field id="it-acc" label="Accession numbers of the copies" hint="Comma-separated, DEPT/000000 form"><input id="it-acc" className="ctl tnum" value={item.accessions} onChange={(e) => setItem({ ...item, accessions: e.target.value })} placeholder="CSC/004182, CSC/004183" /></Field>
                <div><Btn kind="ghost" disabled={busy || !item.title.trim()} onClick={async () => { const j = await send("/api/bff/api/v1/library/items", "PUT", { ...item, year: item.year ? Number(item.year) : null, accessions: item.accessions.split(",").map((s) => s.trim()).filter(Boolean) }, `Catalogued ${item.title}`); if (j) { setSaid(`${item.title} catalogued with ${j.copies} cop${Number(j.copies) === 1 ? "y" : "ies"}`); setItem({ ...item, title: "", accessions: "" }); } }}>Add to the catalogue</Btn></div>
              </>
            ) : null}
          </PBody>
        </Panel>
        <Panel title="The rule in force" right="Loan period, fine, limits">
          <PBody>
            <div className="grid grid--2">
              <Field id="ls-days" label="Loan days"><input id="ls-days" className="ctl tnum" value={setting.loanDays} onChange={(e) => setSetting({ ...setting, loanDays: e.target.value })} disabled={!librarian} /></Field>
              <Field id="ls-fine" label="Fine per day"><input id="ls-fine" className="ctl tnum" value={setting.finePerDay} onChange={(e) => setSetting({ ...setting, finePerDay: e.target.value })} disabled={!librarian} /></Field>
              <Field id="ls-max" label="Items at once"><input id="ls-max" className="ctl tnum" value={setting.maxLoans} onChange={(e) => setSetting({ ...setting, maxLoans: e.target.value })} disabled={!librarian} /></Field>
              <Field id="ls-ren" label="Renewals"><input id="ls-ren" className="ctl tnum" value={setting.maxRenewals} onChange={(e) => setSetting({ ...setting, maxRenewals: e.target.value })} disabled={!librarian} /></Field>
            </div>
            <div><Btn kind="ghost" disabled={!librarian || busy} onClick={async () => { if (await send("/api/bff/api/v1/library/setting", "PUT", { loanDays: Number(setting.loanDays), finePerDay: Number(setting.finePerDay), maxLoans: Number(setting.maxLoans), maxRenewals: Number(setting.maxRenewals) }, "Library rule restated")) setSaid("The rule is restated"); }}>Restate the rule</Btn></div>
            <div className="sub2">A fine is computed from the days overdue at the rate in force when the item is returned; it is settled against a payment reference the student generates, or waived by the Librarian with the reason on the record.</div>
          </PBody>
        </Panel>
      </div>
    </>
  );
}
