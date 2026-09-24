"use client";

/** tProjects — research grants: the money the University administers for a sponsor. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, day, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Grant {
  id: string; reference: string; title: string; principal_investigator: string; sponsor: string;
  amount: number; currency: string; starts_on: string | null; ends_on: string | null; state: string; note: string | null;
}

const STATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  PROPOSED: ["warn", "Proposed"], ACTIVE: ["ok", "Active"], COMPLETED: ["info", "Completed"], CLOSED: ["grey", "Closed"], SUSPENDED: ["bad", "Suspended"],
};

export function Projects({ rows, actingOffice }: { rows: Grant[]; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["bursar", "dvc", "super"].includes(actingOffice ?? "");
  const [f, setF] = useState({ title: "", principalInvestigator: "", sponsor: "", amount: "", currency: "NGN", startsOn: "", endsOn: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const active = rows.filter((r) => r.state === "ACTIVE");
  const naira = active.filter((r) => r.currency === "NGN").reduce((n, r) => n + Number(r.amount), 0);

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/research/grants${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind="info" title="Grants are administered, not owned">
        Research grant money is held for a sponsor against a named principal investigator, spent to the award&rsquo;s terms and accounted for separately from the University&rsquo;s own funds.
      </Note>
      {said ? <Note kind="ok" title={said}>On the record.</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}
      <Tiles items={[
        ["Active grants", String(active.length), null, "Currently running"],
        ["Active value (₦)", money(naira), null, "Naira awards"],
        ["Grants", String(rows.length), null, "All"],
        ["Sponsors", String(new Set(rows.map((r) => r.sponsor)).size), null, "Distinct"],
      ]} />
      <Panel title="Research grants">
        {rows.length ? (
          <DTable cols={["Reference", "Title", "PI / Sponsor", "Amount|num", "Window|mid", "State|num"]} rows={rows.map((r) => [
            <span className="tnum" key="r">{r.reference}</span>,
            <span key="t">{r.title}</span>,
            <Two key="p" a={r.principal_investigator} b={r.sponsor} />,
            <b className="tnum" key="a">{r.currency === "NGN" ? money(Number(r.amount)) : `${r.currency} ${Number(r.amount).toLocaleString()}`}</b>,
            <span className="sub2 tnum" key="w">{r.starts_on ? day(r.starts_on) : "—"}{r.ends_on ? ` – ${day(r.ends_on)}` : ""}</span>,
            <span key="s" className="row row--inline row--tight row--right">
              <Pil kind={STATE[r.state]?.[0] ?? "grey"}>{STATE[r.state]?.[1] ?? r.state}</Pil>
              {may && r.state !== "CLOSED" ? <Btn kind="ghost" disabled={busy} onClick={() => { const s = window.prompt("State: PROPOSED, ACTIVE, COMPLETED, CLOSED, SUSPENDED", r.state); if (s && s.trim()) void send(`/${r.id}/state`, { state: s.trim() }, `Set ${r.reference} to ${s.trim()}`); }}>State</Btn> : null}
            </span>,
          ])} texts={rows.map((r) => `${r.reference} ${r.title} ${r.principal_investigator} ${r.sponsor}`)} />
        ) : <PBody><div className="sub2">No grant recorded.</div></PBody>}
      </Panel>
      {may ? (
        <Panel title="Record a grant">
          <PBody>
            <div className="grid grid--2">
              <Field id="g-title" label="Title"><input id="g-title" className="ctl" value={f.title} onChange={(e) => setF({ ...f, title: e.target.value })} /></Field>
              <Field id="g-pi" label="Principal investigator"><input id="g-pi" className="ctl" value={f.principalInvestigator} onChange={(e) => setF({ ...f, principalInvestigator: e.target.value })} /></Field>
            </div>
            <div className="grid grid--3">
              <Field id="g-sponsor" label="Sponsor"><input id="g-sponsor" className="ctl" value={f.sponsor} onChange={(e) => setF({ ...f, sponsor: e.target.value })} placeholder="TETFund, NRF, …" /></Field>
              <Field id="g-amount" label="Amount"><input id="g-amount" className="ctl tnum" inputMode="decimal" value={f.amount} onChange={(e) => setF({ ...f, amount: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
              <Field id="g-cur" label="Currency"><input id="g-cur" className="ctl tnum" value={f.currency} onChange={(e) => setF({ ...f, currency: e.target.value.toUpperCase() })} /></Field>
            </div>
            <div className="grid grid--2">
              <Field id="g-start" label="Starts on" hint="Optional"><input id="g-start" className="ctl" type="date" value={f.startsOn} onChange={(e) => setF({ ...f, startsOn: e.target.value })} /></Field>
              <Field id="g-end" label="Ends on" hint="Optional"><input id="g-end" className="ctl" type="date" value={f.endsOn} onChange={(e) => setF({ ...f, endsOn: e.target.value })} /></Field>
            </div>
            <div><Btn kind="primary" disabled={busy || !f.title.trim() || !f.principalInvestigator.trim() || !f.sponsor.trim() || !(Number(f.amount) >= 0)} onClick={async () => { const j = await send("", { title: f.title.trim(), principalInvestigator: f.principalInvestigator.trim(), sponsor: f.sponsor.trim(), amount: Number(f.amount), currency: f.currency || "NGN", startsOn: f.startsOn || null, endsOn: f.endsOn || null }, `Record grant ${f.title.trim()}`); if (j) { setSaid(`Grant ${j.reference} recorded`); setF({ title: "", principalInvestigator: "", sponsor: "", amount: "", currency: "NGN", startsOn: "", endsOn: "" }); } }}>Record the grant</Btn></div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
