"use client";

/**
 * Users & roles — proto/part27.html cfgUsers, with the prototype's grant
 * form (part36): the people, the offices they hold under an instrument
 * with a start and an end, and the credential that signs each one in.
 */
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal, Field, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface PersonRow {
  id: string;
  staffNumber: string | null;
  surname: string;
  givenNames: string;
  email: string | null;
  phone: string | null;
  endedOn: string | null;
  username: string | null;
  mustChange: boolean;
  lastSignInAt: string | null;
  lockedUntil: string | null;
  liveOffices: number;
}

export interface GrantRow {
  id: string;
  personId: string;
  surname: string;
  givenNames: string;
  staffNumber: string | null;
  officeCode: string;
  label: string;
  scopeKind: string;
  scopeId: string | null;
  instrument: string;
  grantedByName: string | null;
  validFrom: string;
  validTo: string | null;
}

const BOUND: Record<string, string> = { institution: "The University", college: "The College", faculty: "Faculty", department: "Department", programme: "Programme", course: "Own courses", unit: "Unit", platform: "The platform", level: "Level (MBBS Coordinator: 200 to 600)" };

export function People({ q, persons, grants, offices, actingOffice, open }: {
  q: string;
  persons: PersonRow[];
  grants: GrantRow[];
  offices: { code: string; label: string; scope_kind: string }[];
  actingOffice: string | null;
  open?: string | null;
}) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const canGrant = ["registrar", "dregistrar", "vc", "super", "ict", "admin"].includes(actingOffice ?? "");
  const canCredential = ["registrar", "dregistrar", "ict", "admin", "super"].includes(actingOffice ?? "");
  // a dashboard shortcut can ask this console to open straight into a task (?new=person|grant),
  // decided once as the initial state rather than in an effect that would set state on mount
  const openGrant = open === "grant" && canGrant && persons.length > 0;
  const openPerson = open === "person" && canCredential;
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [modal, setModal] = useState<"person" | "grant" | "credential" | "end" | "contact" | null>(openGrant ? "grant" : openPerson ? "person" : null);
  const [target, setTarget] = useState<PersonRow | GrantRow | null>(openGrant ? persons[0] : null);
  const [f, setF] = useState({ staffNumber: "", surname: "", givenNames: "", email: "", phone: "", office: openGrant ? (offices[0]?.code ?? "") : "", scopeKind: "institution", scopeId: "", instrument: "", validFrom: "", validTo: "", username: "", password: "", reason: "", on: "" });
  const [search, setSearch] = useState(q);
  const [now] = useState(() => Date.now());
  const soon = grants.filter((g) => g.validTo && new Date(g.validTo).getTime() - now < 30 * 86400000).length;
  const two = new Set(grants.map((g) => g.personId).filter((id, i, all) => all.indexOf(id) !== i)).size;

  async function send(method: "POST" | "PUT", path: string, body: unknown, reason: string): Promise<boolean> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(path, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      if (!r.ok) {
        { const p = (await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); }
        return false;
      }
      setModal(null);
      notify(reason);
      router.refresh();
      return true;
    } finally {
      setBusy(false);
    }
  }

  const person = target && "surname" in target && "username" in target ? (target as PersonRow) : null;
  const grant = target && "officeCode" in target ? (target as GrantRow) : null;

  return (
    <>
      <Note kind="bad" title="A role is granted by the Registrar, recorded here, and reviewed">
        The Directorate of ICT operates this console; it does not decide who holds an office. Every grant carries the authority that made it, a start date and an end date, because acting appointments are the normal case in a Nigerian university and an acting appointment that never ends is how a person keeps a power they no longer hold.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Tiles items={[
        ["Accounts", persons.filter((p) => p.username).length.toLocaleString(), null, "People who can sign in"],
        ["Staff accounts", persons.filter((p) => p.liveOffices > 0).length.toLocaleString(), null, "With at least one office"],
        ["Holding two offices", String(two), "var(--chrome)", "A Dean who also teaches"],
        ["Grants expiring in 30 days", String(soon), soon ? "var(--red-ink)" : null, "Acting appointments"],
      ]} />

      <Panel title="People on the register" right={`${persons.length} shown`}>
        <PBody>
          <form className="field" style={{ maxWidth: 420 }} onSubmit={(e) => { e.preventDefault(); queryNav(`/people?q=${encodeURIComponent(search)}`); }}>
            <label htmlFor="pp-q">Find a person</label>
            <input id="pp-q" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Name, staff number or username" autoComplete="off" />
          </form>
        </PBody>
        <DTable
          cols={["Name", "Staff number|mid", "Username", "Offices|mid", "Last sign-in|mid", "State|mid", "Action|num"]}
          rows={persons.map((p) => [
            <strong key="n">{p.surname}, {p.givenNames}</strong>,
            <span className="tnum" key="s">{p.staffNumber ?? "—"}</span>,
            <span className="tnum" key="u">{p.username ?? <span className="sub2">no account</span>}</span>,
            <span className="tnum" key="o">{p.liveOffices}</span>,
            <span className="sub2 tnum" key="l">{p.lastSignInAt ? day(p.lastSignInAt) : "never"}</span>,
            p.endedOn ? <Pil kind="grey" key="st">Ended</Pil> : p.lockedUntil && new Date(p.lockedUntil).getTime() > now ? <Pil kind="bad" key="st">Locked</Pil> : p.mustChange ? <Pil kind="info" key="st">Password to change</Pil> : p.username ? <Pil kind="ok" key="st">Active</Pil> : <Pil kind="grey" key="st">No account</Pil>,
            <span key="a">
              <Btn kind="ghost" disabled={!canCredential} onClick={() => { setTarget(p); setF({ ...f, username: p.username ?? p.staffNumber?.toLowerCase() ?? "", password: "" }); setModal("credential"); }}>{p.username ? "Reset password" : "Create account"}</Btn>{" "}
              <Btn kind="ghost" disabled={!canCredential} onClick={() => { setTarget(p); setF({ ...f, email: p.email ?? "", phone: p.phone ?? "" }); setModal("contact"); }}>Contact</Btn>{" "}
              <Btn kind="ghost" disabled={!canGrant} onClick={() => { setTarget(p); setF({ ...f, office: offices[0]?.code ?? "", scopeKind: "institution", scopeId: "", instrument: "", validFrom: "", validTo: "" }); setModal("grant"); }}>Grant an office</Btn>
            </span>,
          ])}
          texts={persons.map((p) => `${p.surname} ${p.givenNames} ${p.staffNumber ?? ""} ${p.username ?? ""}`)}
        />
        <div className="rfbar">
          <Btn kind="primary" disabled={!canCredential} onClick={() => { setF({ ...f, staffNumber: "", surname: "", givenNames: "" }); setModal("person"); }}>+ New person</Btn>
          <span className="sub2">A person is created once, however many offices they come to hold.</span>
        </div>
      </Panel>

      <Panel title="Staff accounts and the offices they hold" right="Newest grant first">
        <DTable
          cols={["Name", "Staff number|mid", "Office", "Bounded to", "Granted by", "From|mid", "To|mid", "Action|num"]}
          rows={grants.map((g) => [
            <strong key="n">{g.surname}, {g.givenNames}</strong>,
            <span className="tnum" key="s">{g.staffNumber ?? "—"}</span>,
            <span key="o">{g.label}</span>,
            <span className="sub2" key="b">{g.scopeId ? `${BOUND[g.scopeKind] ?? g.scopeKind} ${g.scopeId}` : BOUND[g.scopeKind] ?? g.scopeKind}</span>,
            <span className="sub2" key="g">{g.grantedByName ?? g.instrument}</span>,
            <span className="tnum" key="f">{day(g.validFrom)}</span>,
            g.validTo ? <span className="tnum ink-red" key="t">{day(g.validTo)}</span> : <span className="sub2" key="t">—</span>,
            <Btn kind="ghost" key="a" disabled={!canGrant} onClick={() => { setTarget(g); setF({ ...f, reason: "", on: "" }); setModal("end"); }}>End</Btn>,
          ])}
          texts={grants.map((g) => `${g.surname} ${g.givenNames} ${g.label} ${g.instrument}`)}
        />
        <div className="rfbar">
          <Btn kind="primary" disabled={!canGrant || !persons.length} onClick={() => { setTarget(persons[0]); setF({ ...f, office: offices[0]?.code ?? "", scopeKind: "institution", scopeId: "", instrument: "", validFrom: "", validTo: "" }); setModal("grant"); }}>+ Grant an office</Btn>
          <span className="sub2">Not effective until the instrument is cited.</span>
        </div>
      </Panel>

      {modal === "person" ? (
        <Modal title="New person" sub="Created once, however many offices they hold" onClose={() => setModal(null)}
          foot={<><Btn kind="ghost" onClick={() => setModal(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy || !f.surname || !f.givenNames} onClick={() => void send("POST", "/api/bff/api/v1/iam/persons", { staffNumber: f.staffNumber || null, surname: f.surname, givenNames: f.givenNames, email: f.email || null, phone: f.phone || null }, "Person created")}>Create</Btn></>}>
          <div className="grid grid--2 rfgrid">
            <Field id="np-s" label="Surname"><input id="np-s" className="ctl" value={f.surname} onChange={(e) => setF({ ...f, surname: e.target.value })} autoComplete="off" /></Field>
            <Field id="np-g" label="Given names"><input id="np-g" className="ctl" value={f.givenNames} onChange={(e) => setF({ ...f, givenNames: e.target.value })} autoComplete="off" /></Field>
            <Field id="np-n" label="Staff number" hint="Optional; the number the University issued"><input id="np-n" className="ctl tnum" value={f.staffNumber} placeholder="MOAUM/STF/" onChange={(e) => setF({ ...f, staffNumber: e.target.value })} autoComplete="off" /></Field>
            <Field id="np-e" label="Email" hint="Where a password reset and notices are sent"><input id="np-e" className="ctl tnum" value={f.email} placeholder="name@moaum.edu.ng" onChange={(e) => setF({ ...f, email: e.target.value })} autoComplete="off" /></Field>
            <Field id="np-p" label="Phone" hint="Optional; for SMS notices"><input id="np-p" className="ctl tnum" value={f.phone} placeholder="0803…" onChange={(e) => setF({ ...f, phone: e.target.value })} autoComplete="off" /></Field>
          </div>
        </Modal>
      ) : null}

      {modal === "contact" && person ? (
        <Modal title={`Contact for ${person.surname}, ${person.givenNames}`} sub="Where a password reset and notices are sent" onClose={() => setModal(null)}
          foot={<><Btn kind="ghost" onClick={() => setModal(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy} onClick={() => void send("PUT", `/api/bff/api/v1/iam/persons/${person.id}/contact`, { email: f.email || null, phone: f.phone || null }, "Staff contact set")}>Save</Btn></>}>
          <div className="grid grid--2 rfgrid">
            <Field id="ct-e" label="Email" hint="Where a password reset and notices are sent"><input id="ct-e" className="ctl tnum" value={f.email} placeholder="name@moaum.edu.ng" onChange={(e) => setF({ ...f, email: e.target.value })} autoComplete="off" /></Field>
            <Field id="ct-p" label="Phone" hint="Optional; for SMS notices"><input id="ct-p" className="ctl tnum" value={f.phone} placeholder="0803…" onChange={(e) => setF({ ...f, phone: e.target.value })} autoComplete="off" /></Field>
          </div>
        </Modal>
      ) : null}

      {modal === "grant" && person ? (
        <Modal title={`Grant an office to ${person.surname}, ${person.givenNames}`} sub="Bounded, dated, on an instrument" wide onClose={() => setModal(null)}
          foot={<><Btn kind="ghost" onClick={() => setModal(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy || !f.office || !f.instrument.trim()} onClick={() => void send("POST", `/api/bff/api/v1/iam/persons/${person.id}/office-assignments`, { officeCode: f.office, scopeKind: f.scopeKind, scopeId: f.scopeId || null, instrument: f.instrument, validFrom: f.validFrom || null, validTo: f.validTo || null }, `${f.office} granted under ${f.instrument}`)}>Grant</Btn></>}>
          <Note kind="bad" title="A role is granted by the Registrar, recorded here, and reviewed">Every grant carries the authority that made it, a start date and an end date, because acting appointments are the normal case and an acting appointment that never ends is how a person keeps a power they no longer hold.</Note>
          <div className="grid grid--3 rfgrid">
            <Field id="gr-o" label="Office"><select id="gr-o" className="ctl" value={f.office} onChange={(e) => { const o = offices.find((x) => x.code === e.target.value); setF({ ...f, office: e.target.value, scopeKind: o?.scope_kind ?? f.scopeKind }); }}>{offices.map((o) => <option key={o.code} value={o.code}>{o.label}</option>)}</select></Field>
            <Field id="gr-k" label="Bounded to"><select id="gr-k" className="ctl" value={f.scopeKind} onChange={(e) => setF({ ...f, scopeKind: e.target.value })}>{Object.entries(BOUND).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
            <Field id="gr-id" label="Which one" hint="The faculty, department, programme or course code; blank for the University or the platform"><input id="gr-id" className="ctl tnum" value={f.scopeId} onChange={(e) => setF({ ...f, scopeId: e.target.value })} autoComplete="off" /></Field>
            <Field id="gr-f" label="From"><input id="gr-f" className="ctl" type="date" value={f.validFrom} onChange={(e) => setF({ ...f, validFrom: e.target.value })} /></Field>
            <Field id="gr-t" label="To" hint="An acting grant must carry one."><input id="gr-t" className="ctl" type="date" value={f.validTo} onChange={(e) => setF({ ...f, validTo: e.target.value })} /></Field>
            <Field id="gr-i" label="Authority for the grant" full hint="The Directorate of ICT operates this console; it does not decide who holds an office."><input id="gr-i" className="ctl" value={f.instrument} placeholder="Registrar, memo REG/2026/318" onChange={(e) => setF({ ...f, instrument: e.target.value })} autoComplete="off" /></Field>
          </div>
          <Note kind="bad" title="Two offices in one approval chain is allowed; approving twice in it is not">A Dean who taught the course may hold both offices. BR-006 blocks the second approval by the same person, at the database — so the chain waits for somebody else.</Note>
        </Modal>
      ) : null}

      {modal === "credential" && person ? (
        <Modal title={`${person.username ? "Reset the password of" : "Create the account of"} ${person.surname}, ${person.givenNames}`} sub="They change it at their first sign-in" onClose={() => setModal(null)}
          foot={<><Btn kind="ghost" onClick={() => setModal(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy || f.username.length < 3 || f.password.length < 10} onClick={() => void send("PUT", `/api/bff/api/v1/iam/persons/${person.id}/credential`, { username: f.username, password: f.password }, person.username ? "Password reset by the Registry" : "Account created by the Registry")}>{person.username ? "Reset" : "Create"}</Btn></>}>
          <div className="grid grid--2 rfgrid">
            <Field id="cr-u" label="Username" hint="The staff number or an email address"><input id="cr-u" className="ctl" value={f.username} onChange={(e) => setF({ ...f, username: e.target.value })} autoComplete="off" /></Field>
            <Field id="cr-p" label="First password" hint="At least ten characters; told to the person, never written down here"><input id="cr-p" className="ctl" type="password" value={f.password} onChange={(e) => setF({ ...f, password: e.target.value })} autoComplete="new-password" /></Field>
          </div>
        </Modal>
      ) : null}

      {modal === "end" && grant ? (
        <Modal title={`End ${grant.label} for ${grant.surname}, ${grant.givenNames}`} sub="It stays on the record" onClose={() => setModal(null)}
          foot={<><Btn kind="ghost" onClick={() => setModal(null)}>Cancel</Btn><span className="grow" /><Btn kind="urgent" disabled={busy || !f.reason.trim()} onClick={() => void send("POST", `/api/bff/api/v1/iam/persons/${grant.personId}/office-assignments/${grant.id}/end`, { on: f.on || null, reason: f.reason }, `Office ended: ${f.reason}`)}>End it</Btn></>}>
          <Note kind="bad" title="Ending is not deleting, and the difference is the whole point">Revoking an office takes the permissions away from the date you give and leaves the grant on the record, with who made it and who ended it. Everything the holder approved while they held it stands, because it was validly approved at the time.</Note>
          <div className="grid grid--2 rfgrid">
            <Field id="en-on" label="Ended with effect from" hint="Today, when blank"><input id="en-on" className="ctl" type="date" value={f.on} onChange={(e) => setF({ ...f, on: e.target.value })} /></Field>
            <Field id="en-why" label="Reason, as it will read in the log"><input id="en-why" className="ctl" value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} autoComplete="off" /></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
