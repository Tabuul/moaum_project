"use client";

/** tClearance — proto/part18.html: independent sign-offs, not a form that travels. */
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import type { ClearanceListing, ClearancePosition } from "@/lib/credentials";
import { csv, download } from "@/lib/results";
import { ScopeBar, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, Note, Panel, PBody, Pil, RoleLine, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Bar, Gate, Gates, Modal, Field, TwoCol, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

/** the clearance units each office owns; Student Services covers three, and the
 *  Registry/Academic can act for any (anyUnit below). Kept in step with
 *  clearance.unit.office_code in the database. */
const MY_UNITS: Record<string, string[]> = {
  bursar: ["BURSARY"], hod: ["DEPARTMENT"], dean: ["FACULTY"], library: ["LIBRARY"],
  services: ["HEALTH", "HOSTEL", "WORKS"],
};

export function ClearanceScreen({ scope, structure, sessions, listing, chosen, position, actingOffice }: {
  scope: Scope;
  structure: ScopeStructure;
  sessions: string[];
  listing: ClearanceListing;
  chosen: string | null;
  position: ClearancePosition[];
  actingOffice: string | null;
}) {
  const router = useRouter();
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [hold, setHold] = useState<string | null>(null);
  const [item, setItem] = useState("");
  const anyUnit = ["registrar", "dregistrar", "academic"].includes(actingOffice ?? "");
  // the units this office may sign: every unit for the Registry/Academic, else the office's own
  const myUnits = anyUnit ? listing.units.map((u) => u.code) : (MY_UNITS[actingOffice ?? ""] ?? []);
  const canSign = myUnits.length > 0;
  const [unit, setUnit] = useState<string>(myUnits[0] ?? "BURSARY");

  async function post(path: string, body: unknown, reason: string): Promise<boolean> {
    setProblem(null);
    const r = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
    if (r.status === 202) {
      const j = await r.json();
      setSaid(`${j.note} (${j.wouldNotify} would have been notified.)`);
      return true;
    }
    if (!r.ok) {
      setProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText });
      return false;
    }
    return true;
  }

  const t = listing.totals;
  const me = listing.candidates.find((c) => c.id === chosen) ?? null;
  const shortUnit = (u: string) => u.slice(0, 4);

  async function clearSelected() {
    setBusy(true);
    try {
      for (const id of selected) {
        if (!(await post(`/api/bff/api/v1/clearance/students/${id}/${unit}/clear`, { purpose: listing.purpose }, `${unit} clearance signed`))) break;
      }
      if (selected.size) notify(`${unit} clearance signed for ${selected.size} student${selected.size === 1 ? "" : "s"}`);
      setSelected(new Set());
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <RoleLine allowed={["registrar", "dregistrar", "academic"]} actingOffice={actingOffice} canAct={anyUnit}
        action="Clearing students through the units" />
      <ScopeBar scope={scope} structure={structure} sessions={sessions} what="candidates" count={listing.candidates.length} of={listing.total} />
      <Note kind="info" title="Clearance is a set of independent sign-offs, not a form that travels">
        Each unit clears against its own record, in any order, and none of them holds a piece of paper for the student to carry. The candidate is cleared when the last unit signs, and the certificate is released by that fact rather than by anyone assembling the evidence.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="info" title="Nothing was sent">{said}</Note> : null}
      <Tiles items={[
        ["Candidates for clearance", t.candidates.toLocaleString(), null, `${listing.purpose === "CONVOCATION" ? "Graduating" : listing.purpose.toLowerCase()}, ${scope.session}`],
        ["Fully cleared", t.fullyCleared.toLocaleString(), "var(--green-ink)", t.candidates ? `${Math.round((100 * t.fullyCleared) / t.candidates)}%` : "—"],
        ["Outstanding at one unit", t.outstandingAtOne.toLocaleString(), "var(--chrome)", "Usually the Bursary"],
        ["Outstanding at two or more", t.outstandingAtTwoOrMore.toLocaleString(), "var(--red-ink)", "Each unit named below"],
      ]} />

      <Panel title="Where candidates are held" right="By unit · a candidate can be held by more than one">
        <DTable
          cols={["Unit", "Clears against", "Holding|mid", "Typical reason", "Progress|num"]}
          rows={listing.units.map((u) => [
            <Two key="u" a={u.label} b={u.clearsAgainst} />, <span className="sub2" key="h">{u.holdsFor}</span>,
            <span className="tnum" key="n">{u.holding}</span>, <span className="sub2" key="r">{u.typicalReason}</span>,
            <Bar key="p" pct={u.progress} colour={u.progress >= 90 ? "var(--green)" : "var(--chrome)"} />,
          ])}
        />
      </Panel>

      <Panel title="Candidates" right={`${listing.candidates.length} in scope`}>
        <DTable
          cols={["", "Matriculation number", "Name", ...listing.units.map((u) => `${shortUnit(u.label)}|mid`), "Status|num"]}
          rows={listing.candidates.map((c) => [
            <input type="checkbox" className="chk" key="x" checked={selected.has(c.id)} onChange={(e) => { const n = new Set(selected); if (e.target.checked) n.add(c.id); else n.delete(c.id); setSelected(n); }} aria-label={`Select ${c.surname}`} />,
            <a key="m" href={`/clearance?${new URLSearchParams({ student: c.id }).toString()}`} className="tnum">{c.number}</a>,
            <Two key="n" a={`${c.surname}, ${c.otherNames}`} b={c.programmeName} />,
            ...c.states.map((s, i) => (s === "CLEARED" ? <span key={i} style={{ color: "var(--green-ink)", fontWeight: 700 }}>✓</span> : <span key={i} style={{ color: "var(--red-ink)", fontWeight: 700 }}>✗</span>)),
            c.cleared ? <Pil kind="ok" key="s">Cleared</Pil> : <Pil kind="bad" key="s">Held</Pil>,
          ])}
          texts={listing.candidates.map((c) => `${c.number} ${c.surname} ${c.otherNames} ${c.programmeName}`)}
        />
        {!listing.candidates.length ? <PBody><div className="sub2">Nobody is on the register in this scope yet. Candidates arrive here from the student register.</div></PBody> : null}
      </Panel>

      <TwoCol>
        <Panel title={me ? `${me.surname}, ${me.otherNames}` : "No candidate chosen"} right={me ? `${me.number} · held by ${position.filter((p) => p.state !== "CLEARED").length} unit${position.filter((p) => p.state !== "CLEARED").length === 1 ? "" : "s"}` : "Pick a row"}>
          <PBody>
            <Gates>
              {position.map((p, i) => (
                <Gate key={p.unit} state={p.state === "CLEARED" ? "done" : "todo"} last={i === position.length - 1}
                  title={`${p.label} — ${p.state === "CLEARED" ? "cleared" : "not cleared"}`}
                  sub={p.state === "CLEARED" ? `${p.officer ?? "Signed"} · ${day(p.decidedAt)}${p.note ? ` · ${p.note}` : ""}` : p.item ? `${p.item}${p.decidedAt ? ` · raised ${day(p.decidedAt)}` : ""}` : "Nothing signed yet; the unit has not cleared against its record"} />
              ))}
              {!position.length ? <Gate state="todo" title="No candidate chosen" sub="Choose a matriculation number in the table." last /> : null}
            </Gates>
            {me && canSign ? (
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 10, alignItems: "center" }}>
                {myUnits.length > 1
                  ? <select className="ws__select" value={unit} onChange={(e) => setUnit(e.target.value)}>{listing.units.filter((u) => myUnits.includes(u.code)).map((u) => <option key={u.code} value={u.code}>{u.label}</option>)}</select>
                  : <span className="sub2">{listing.units.find((u) => u.code === unit)?.label}</span>}
                <Btn kind="go" disabled={busy} onClick={async () => { setBusy(true); if (await post(`/api/bff/api/v1/clearance/students/${me.id}/${unit}/clear`, { purpose: listing.purpose }, `${unit} clearance signed for ${me.number}`)) { notify(`${unit} clearance signed for ${me.number}`); router.refresh(); } setBusy(false); }}>Clear</Btn>
                <Btn kind="urgent" onClick={() => { setHold(me.id); setItem(""); }}>Hold</Btn>
              </div>
            ) : null}
          </PBody>
        </Panel>
        <Panel title="What clearance releases">
          <PBody>
            <Gates>
              <Gate state={me?.cleared ? "done" : "todo"} title="Name on the graduation list" sub="Senate approves the list; an uncleared candidate is not on it." />
              <Gate state={me?.cleared ? "done" : "todo"} title="Statement of result" sub="Released to the candidate on full clearance." />
              <Gate state={me?.cleared ? "done" : "todo"} title="Certificate" sub="Printed only against a cleared, Senate-approved record." />
              <Gate state={me?.cleared ? "done" : "todo"} title="Transcript to a third party" sub="Blocked while any unit holds the candidate." />
              <Gate state={me?.cleared ? "done" : "todo"} title="Convocation" sub="Gown and seat allocated on clearance." last />
            </Gates>
            <div className="sub2" style={{ marginTop: 10 }}>Each of these checks clearance at the moment it is attempted, inside the transaction. None of them reads a report that a clerk ran last week.</div>
          </PBody>
        </Panel>
      </TwoCol>

      <div style={{ display: "flex", gap: 9, flexWrap: "wrap" }}>
        <Btn kind="primary" disabled={busy || !selected.size || !canSign} onClick={() => void clearSelected()}>Clear the selected candidates</Btn>
        <Btn kind="ghost" onClick={() => download(`held-${listing.purpose.toLowerCase()}.csv`, csv([["Matriculation number", "Name", "Programme", ...listing.units.map((u) => u.label)], ...listing.candidates.filter((c) => !c.cleared).map((c) => [c.number, `${c.surname}, ${c.otherNames}`, c.programmeName, ...c.states])]))}>Export the held list</Btn>
        <Btn kind="ghost" disabled={busy} onClick={() => void post("/api/bff/api/v1/clearance/notify-held", { students: listing.candidates.filter((c) => !c.cleared).map((c) => c.id) }, "Held candidates notified")}>Notify held candidates</Btn>
      </div>

      {hold ? (
        <Modal title="Hold this candidate" sub="Name the item outstanding" onClose={() => setHold(null)}
          foot={<><Btn kind="ghost" onClick={() => setHold(null)}>Cancel</Btn><span style={{ flexGrow: 1 }} /><Btn kind="urgent" disabled={!item.trim() || busy} onClick={async () => { setBusy(true); if (await post(`/api/bff/api/v1/clearance/students/${hold}/${unit}/hold`, { purpose: listing.purpose, item }, `${unit} hold: ${item}`)) { notify(`${unit} hold placed`); setHold(null); router.refresh(); } setBusy(false); }}>Hold</Btn></>}>
          <Field id="hold-item" label="What is outstanding" hint="The candidate sees this on their own portal, with the unit, the officer and the date.">
            <input id="hold-item" className="ctl" value={item} onChange={(e) => setItem(e.target.value)} autoComplete="off" />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}
