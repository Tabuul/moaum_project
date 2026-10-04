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
import { SearchSelect, type Opt } from "@/components/proto/SearchSelect";
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

/** a first password the officer can read out: twelve characters, none of the look-alikes (0/O, 1/l/I) */
function firstPassword(): string {
  const abc = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
  const bytes = new Uint32Array(12);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => abc[b % abc.length]).join("");
}

/** the University's ladder (/api/v1/ref/structure) and its courses (/api/v1/ref/courses): what a bounded grant chooses from */
export interface StructureLite {
  colleges: { code: string; name: string }[];
  faculties: { code: string; name: string; collegeCode?: string | null; departments: { code: string; name: string; facultyCode?: string | null; programmes: { code: string; name: string; category?: string | null; archived?: boolean }[] }[] }[];
}
export interface CourseLite { code: string; title: string; deptCode?: string | null; deptName?: string | null; level?: number | null }
/** the scopes that name one thing — chosen from the register, never typed */
const NEEDS_ID = new Set(["college", "faculty", "department", "programme", "course", "level"]);
const SCOPE_HINT: Record<string, string> = {
  institution: "The whole University: nothing to choose.", platform: "The platform itself: nothing to choose.", unit: "Name the unit, e.g. Library, Security, Health Centre.",
  college: "Choose the College.", faculty: "Choose the faculty.", department: "Choose the department.", programme: "Choose the programme.", course: "Choose the course.", level: "Choose the level.",
};
const BOUND: Record<string, string> = { institution: "The University", college: "The College", faculty: "Faculty", department: "Department", programme: "Programme", course: "Own courses", unit: "Unit", platform: "The platform", level: "Level (MBBS Coordinator: 200 to 600)" };

export function People({ q, persons, grants, offices, actingOffice, open, structure = null, courses = [] }: {
  structure?: StructureLite | null; courses?: CourseLite[];
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
  /* what a bounded grant chooses from, by its scope: codes from the register with their names, searchable */
  const facs = structure?.faculties ?? [];
  const SCOPE_OPTIONS: Record<string, Opt[]> = {
    college: (structure?.colleges ?? []).map((c) => ({ value: c.code, label: `${c.name} · ${c.code}` })),
    faculty: facs.map((x) => ({ value: x.code, label: `${x.name} · ${x.code}` })),
    department: facs.flatMap((x) => x.departments.map((d) => ({ value: d.code, label: `${d.name} · ${d.code} — ${x.name}` }))),
    programme: facs.flatMap((x) => x.departments.flatMap((d) => d.programmes.filter((p) => !p.archived).map((p) => ({ value: p.code, label: `${p.name} · ${p.code} — ${d.name}` })))),
    course: courses.map((c) => ({ value: c.code, label: `${c.code} — ${c.title}${c.deptName ? ` (${c.deptName})` : ""}` })),
    level: [200, 300, 400, 500, 600].map((l) => ({ value: String(l), label: `${l} Level` })),
  };
  const scopeLabel = (kind: string, id: string | null) => {
    if (!id) return BOUND[kind] ?? kind;
    const hit = SCOPE_OPTIONS[kind]?.find((o) => o.value === id);
    return `${BOUND[kind] ?? kind}: ${hit ? hit.label.split(" — ")[0] : id}`;
  };
  const canCredential = ["registrar", "dregistrar", "ict", "admin", "super"].includes(actingOffice ?? "");
  // a dashboard shortcut can ask this console to open straight into a task (?new=person|grant),
  // decided once as the initial state rather than in an effect that would set state on mount
  const openGrant = open === "grant" && canGrant && persons.length > 0;
  const openPerson = open === "person" && canCredential;
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [modal, setModal] = useState<"person" | "grant" | "credential" | "end" | "contact" | "edit" | null>(openGrant ? "grant" : openPerson ? "person" : null);
  // nobody is chosen for a grant until the officer chooses them (the dashboard's shortcut used to grant to the first name on the register)
  const [target, setTarget] = useState<PersonRow | GrantRow | null>(null);
  const [pick, setPick] = useState("");
  const [f, setF] = useState({ staffNumber: "", surname: "", givenNames: "", email: "", phone: "", office: openGrant ? (offices[0]?.code ?? "") : "", scopeKind: openGrant ? (offices[0]?.scope_kind ?? "institution") : "institution", scopeId: "", instrument: "", validFrom: "", validTo: "", username: "", password: "", reason: "", on: "" });
  const [search, setSearch] = useState(q);
  const [shown, setShown] = useState(false);
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

  // a grant carries its office; anything else chosen is a person (never tell them apart by a field that may be null, and left out)
  const grant = target && "officeCode" in target ? (target as GrantRow) : null;
  const person = target && !("officeCode" in target) ? (target as PersonRow) : null;
  const labelOf = (x: PersonRow) => `${x.surname}, ${x.givenNames}${x.staffNumber ? ` · ${x.staffNumber}` : ""}`;
  // the grant form's person: chosen from the list, or typed as a staff number or username
  const choose = (v: string) => {
    setPick(v);
    const t = v.trim().toLowerCase();
    setTarget(persons.find((x) => labelOf(x) === v) ?? persons.find((x) => !!t && ((x.staffNumber ?? "").toLowerCase() === t || (x.username ?? "").toLowerCase() === t)) ?? null);
  };

  /* the fields a grant is made of — the office, what it is bounded to, the dates, the instrument — shared by the new-grant
     and the amendment modals (V319) */
  const grantFields = (
          <div className="grid grid--3 rfgrid">
            <Field id="gr-o" label="Office"><select id="gr-o" className="ctl" value={f.office} onChange={(e) => { const o = offices.find((x) => x.code === e.target.value); setF({ ...f, office: e.target.value, scopeKind: o?.scope_kind ?? f.scopeKind, scopeId: "" }); }}>{offices.map((o) => <option key={o.code} value={o.code}>{o.label}</option>)}</select></Field>
            <Field id="gr-k" label="Bounded to"><select id="gr-k" className="ctl" value={f.scopeKind} onChange={(e) => setF({ ...f, scopeKind: e.target.value, scopeId: "" })}>{Object.entries(BOUND).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
            <Field id="gr-id" label="Which one" required={NEEDS_ID.has(f.scopeKind)} hint={SCOPE_HINT[f.scopeKind] ?? "Chosen from the register, never typed."}>
              {NEEDS_ID.has(f.scopeKind) ? (
                SCOPE_OPTIONS[f.scopeKind]?.length
                  ? <SearchSelect id="gr-id" value={f.scopeId} onChange={(v) => setF({ ...f, scopeId: v })} options={SCOPE_OPTIONS[f.scopeKind]} placeholder={`Type to search the ${f.scopeKind === "level" ? "levels" : f.scopeKind + "s"}…`} />
                  : <input id="gr-id" className="ctl" value="" disabled placeholder="The register has nothing to choose from" />
              ) : f.scopeKind === "unit" ? (
                <input id="gr-id" className="ctl" value={f.scopeId} onChange={(e) => setF({ ...f, scopeId: e.target.value })} autoComplete="off" placeholder="Library, Security, Health Centre…" />
              ) : (
                <input id="gr-id" className="ctl" value="" disabled placeholder="Not needed for this scope" />
              )}
            </Field>
            <Field id="gr-f" label="From"><input id="gr-f" className="ctl" type="date" value={f.validFrom} onChange={(e) => setF({ ...f, validFrom: e.target.value })} /></Field>
            <Field id="gr-t" label="To" hint="An acting grant must carry one."><input id="gr-t" className="ctl" type="date" value={f.validTo} onChange={(e) => setF({ ...f, validTo: e.target.value })} /></Field>
            <Field id="gr-i" label="Authority for the grant" full hint="The Directorate of ICT operates this console; it does not decide who holds an office."><input id="gr-i" className="ctl" value={f.instrument} placeholder="Registrar, memo REG/2026/318" onChange={(e) => setF({ ...f, instrument: e.target.value })} autoComplete="off" /></Field>
          </div>
  );

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
              <Btn kind="ghost" disabled={!canCredential} onClick={() => { setTarget(p); setShown(false); setF({ ...f, username: p.username ?? p.staffNumber?.toLowerCase() ?? "", password: "" }); setModal("credential"); }}>{p.username ? "Reset password" : "Create account"}</Btn>{" "}
              <Btn kind="ghost" disabled={!canCredential} onClick={() => { setTarget(p); setF({ ...f, email: p.email ?? "", phone: p.phone ?? "" }); setModal("contact"); }}>Contact</Btn>{" "}
              <Btn kind="ghost" disabled={!canGrant} onClick={() => { setTarget(p); setPick(labelOf(p)); setF({ ...f, office: offices[0]?.code ?? "", scopeKind: offices[0]?.scope_kind ?? "institution", scopeId: "", instrument: "", validFrom: "", validTo: "" }); setModal("grant"); }}>Grant an office</Btn>
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
            <span className="sub2" key="b">{scopeLabel(g.scopeKind, g.scopeId)}</span>,
            <span className="sub2" key="g">{g.grantedByName ?? g.instrument}</span>,
            <span className="tnum" key="f">{day(g.validFrom)}</span>,
            g.validTo ? <span className="tnum ink-red" key="t">{day(g.validTo)}</span> : <span className="sub2" key="t">—</span>,
            <span key="a">
              <Btn kind="ghost" disabled={!canGrant} onClick={() => { setTarget(g); setF({ ...f, office: g.officeCode, scopeKind: g.scopeKind, scopeId: g.scopeId ?? "", instrument: g.instrument, validFrom: g.validFrom, validTo: g.validTo ?? "", reason: "" }); setModal("edit"); }}>Edit</Btn>{" "}
              <Btn kind="ghost" disabled={!canGrant} onClick={() => { setTarget(g); setF({ ...f, reason: "", on: "" }); setModal("end"); }}>End</Btn>
            </span>,
          ])}
          texts={grants.map((g) => `${g.surname} ${g.givenNames} ${g.label} ${g.instrument}`)}
        />
        <div className="rfbar">
          <Btn kind="primary" disabled={!canGrant || !persons.length} onClick={() => { setTarget(null); setPick(""); setF({ ...f, office: offices[0]?.code ?? "", scopeKind: offices[0]?.scope_kind ?? "institution", scopeId: "", instrument: "", validFrom: "", validTo: "" }); setModal("grant"); }}>+ Grant an office</Btn>
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

      {modal === "grant" && !grant ? (
        <Modal title={person ? `Grant an office to ${person.surname}, ${person.givenNames}` : "Grant an office"} sub="Bounded, dated, on an instrument" wide onClose={() => setModal(null)}
          foot={<><Btn kind="ghost" onClick={() => setModal(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy || !person || !f.office || !f.instrument.trim() || (NEEDS_ID.has(f.scopeKind) && !f.scopeId)} onClick={() => { if (person) void send("POST", `/api/bff/api/v1/iam/persons/${person.id}/office-assignments`, { officeCode: f.office, scopeKind: f.scopeKind, scopeId: f.scopeId || null, instrument: f.instrument, validFrom: f.validFrom || null, validTo: f.validTo || null }, `${f.office} granted to ${person.surname} under ${f.instrument}`); }}>Grant</Btn></>}>
          <Note kind="bad" title="A role is granted by the Registrar, recorded here, and reviewed">Every grant carries the authority that made it, a start date and an end date, because acting appointments are the normal case and an acting appointment that never ends is how a person keeps a power they no longer hold.</Note>
          <Field id="gr-who" label="Person" hint={person ? `${person.username ? `Signs in as ${person.username}` : "No account yet: create one too, or the office cannot be used"} · ${person.liveOffices} office${person.liveOffices === 1 ? "" : "s"} held now` : "Type a name or a staff number and choose from the list"}>
            <input id="gr-who" className="ctl" list="gr-people" value={pick} onChange={(e) => choose(e.target.value)} placeholder="Surname, or staff number" autoComplete="off" />
            <datalist id="gr-people">{persons.filter((x) => !x.endedOn).map((x) => <option key={x.id} value={labelOf(x)} />)}</datalist>
          </Field>
          {grantFields}
          <Note kind="bad" title="Two offices in one approval chain is allowed; approving twice in it is not">A Dean who taught the course may hold both offices. BR-006 blocks the second approval by the same person, at the database — so the chain waits for somebody else.</Note>
        </Modal>
      ) : null}

      {modal === "edit" && grant ? (
        <Modal title={`Amend ${grant.label} for ${grant.surname}, ${grant.givenNames}`} sub="The grant is corrected in place; the old values and your reason stay in the audit trail" wide onClose={() => setModal(null)}
          foot={<><Btn kind="ghost" onClick={() => setModal(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy || !f.office || !f.instrument.trim() || !f.reason.trim() || (NEEDS_ID.has(f.scopeKind) && !f.scopeId)} onClick={() => void send("PUT", `/api/bff/api/v1/iam/persons/${grant.personId}/office-assignments/${grant.id}`, { officeCode: f.office, scopeKind: f.scopeKind, scopeId: f.scopeId || null, instrument: f.instrument, validFrom: f.validFrom || null, validTo: f.validTo || null, reason: f.reason }, `${offices.find((o) => o.code === f.office)?.label ?? f.office} for ${grant.surname} amended: ${f.reason}`)}>Save the amendment</Btn></>}>
          <Note kind="info" title="A mistake on a grant is corrected here, not ended and made again">
            Change the office, what it is bounded to, the instrument or the dates. The person stays: a grant to the wrong person is <b>ended</b> and a new one made. An ended grant is never amended. Every amendment keeps the values it replaced and your reason in the audit trail.
          </Note>
          {grantFields}
          <Field id="am-why" label="Why the grant is amended" required hint="As it will read in the audit trail, beside the old and the new values">
            <input id="am-why" className="ctl" value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} autoComplete="off" placeholder="e.g. granted over the department in error; the letter names the programme" />
          </Field>
        </Modal>
      ) : null}

      {modal === "credential" && person ? (
        <Modal title={`${person.username ? "Reset the password of" : "Create the account of"} ${person.surname}, ${person.givenNames}`} sub="They change it at their first sign-in" onClose={() => setModal(null)}
          foot={<><Btn kind="ghost" onClick={() => setModal(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy || f.username.length < 3 || f.password.length < 10} onClick={() => void send("PUT", `/api/bff/api/v1/iam/persons/${person.id}/credential`, { username: f.username, password: f.password }, person.username ? "Password reset by the Registry" : "Account created by the Registry")}>{person.username ? "Reset" : "Create"}</Btn></>}>
          <div className="grid grid--2 rfgrid">
            <Field id="cr-u" label="Username" hint="The staff number or an email address"><input id="cr-u" className="ctl" value={f.username} onChange={(e) => setF({ ...f, username: e.target.value })} autoComplete="off" /></Field>
            <Field id="cr-p" label="First password" hint="At least ten characters, not containing the username; told to the person, who changes it at first sign-in">
              <span className="row row--inline row--tight">
                <input id="cr-p" className="ctl" type={shown ? "text" : "password"} value={f.password} onChange={(e) => setF({ ...f, password: e.target.value })} autoComplete="new-password" />
                <Btn kind="ghost" size="sm" onClick={() => { setF({ ...f, password: firstPassword() }); setShown(true); }}>Generate</Btn>
                <Btn kind="ghost" size="sm" onClick={() => setShown(!shown)}>{shown ? "Hide" : "Show"}</Btn>
              </span>
            </Field>
          </div>
          {person.liveOffices === 0 ? <Note kind="info" title="Grant an office as well">An account signs a person in to the offices they hold. With none, they reach nothing: grant the office of their unit (Bursary, Registry, Library, Security, Support Services…) with Grant an office.</Note> : null}
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
