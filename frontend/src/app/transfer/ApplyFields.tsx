"use client";

/** V766: the particulars of an inter-university transfer application, as the public form asks them (/transfer/apply) and as the
 *  applicant's portal edits them or fills them again for a later window: about you, your present university, what you apply for and
 *  why. Which fields may change is the state's (lib/transfer-application editableFields); a field closed is shown, not hidden. */
import type { ReactNode } from "react";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { programmeGroups, type ApiField, type ApplyField, type ApplyForm, type PublicProgramme, type PublicUniversity } from "@/lib/transfer-application";

const OTHER_LEVELS = [100, 200, 300, 400, 500, 600, 700];
const NOT_LISTED = "__NOT_LISTED__";

export function Section({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="eyebrow" style={{ borderBottom: "1px solid var(--line-2)", paddingBottom: "var(--s-1)", marginTop: "var(--s-3)" }}>
      {title}{children}
    </div>
  );
}

export function ApplyFields({ f, set, programmes, universities, session, errors, shown, editable = null, contact = true, prefix = "ta", fixedProgramme, universityLabel }: {
  f: ApplyForm;
  set: (patch: Partial<ApplyForm>) => void;
  programmes: PublicProgramme[];
  universities: PublicUniversity[];
  session: string | null;
  errors: Partial<Record<ApplyField, string>>;
  /** errors are shown once the person has tried to send the form */
  shown: boolean;
  /** the fields the state lets change (null: every one) */
  editable?: ApiField[] | null;
  /** the e-mail and phone are asked (not when applying again from the account, which keeps its own) */
  contact?: boolean;
  /** the controls' id prefix (the page focuses `${prefix}-${field}`) */
  prefix?: string;
  /** the programme and level applied for, in words, where they can no longer change */
  fixedProgramme?: string | null;
  /** the present university's name where the list given does not hold it */
  universityLabel?: string | null;
}) {
  const can = (k: ApiField) => editable === null || editable.includes(k);
  const err = (k: ApplyField) => (shown ? errors[k] : undefined);
  const id = (k: string) => `${prefix}-${k}`;
  const text = (k: "surname" | "otherNames" | "email" | "phone" | "jambRegNo" | "otherMatricNo" | "otherProgramme" | "otherEntrySession" | "otherCgpa" | "universityNamed") =>
    (e: { target: { value: string } }) => set({ [k]: e.target.value } as Partial<ApplyForm>);
  const prog = programmes.find((p) => p.code === f.programme) ?? null;
  const groups = programmeGroups(programmes);
  const chooseProgramme = can("programme") && programmes.length > 0;

  return (
    <>
      <Section title="About you" />
      <div className="grid grid--2">
        <Field id={id("surname")} label="Surname" required error={err("surname")}>
          <input id={id("surname")} className="ctl" value={f.surname} onChange={text("surname")} disabled={!can("surname")} autoComplete="family-name" maxLength={60} />
        </Field>
        <Field id={id("otherNames")} label="Other names" required error={err("otherNames")}>
          <input id={id("otherNames")} className="ctl" value={f.otherNames} onChange={text("otherNames")} disabled={!can("otherNames")} autoComplete="given-name" maxLength={120} />
        </Field>
        <Field id={id("sex")} label="Sex" required error={err("sex")}>
          <select id={id("sex")} className="ctl" value={f.sex} disabled={!can("sex")} onChange={(e) => set({ sex: e.target.value as ApplyForm["sex"] })}>
            <option value="">—</option><option value="F">Female</option><option value="M">Male</option>
          </select>
        </Field>
        <Field id={id("dateOfBirth")} label="Date of birth" required error={err("dateOfBirth")}>
          <input id={id("dateOfBirth")} type="date" className="ctl" value={f.dateOfBirth} disabled={!can("dateOfBirth")} onChange={(e) => set({ dateOfBirth: e.target.value })} />
        </Field>
        {contact ? (
          <>
            <Field id={id("email")} label="E-mail" required error={err("email")} hint="You sign in with it, and the University writes to you there">
              <input id={id("email")} type="email" className="ctl" value={f.email} onChange={text("email")} disabled={!can("email")} autoComplete="email" maxLength={200} />
            </Field>
            <Field id={id("phone")} label="Phone" required error={err("phone")} hint="A Nigerian number, for text messages">
              <input id={id("phone")} className="ctl tnum" inputMode="tel" placeholder="08012345678" value={f.phone} onChange={text("phone")} disabled={!can("phone")} autoComplete="tel" maxLength={20} />
            </Field>
          </>
        ) : null}
        <Field id={id("jambRegNo")} label="JAMB registration number" required error={err("jambRegNo")} hint="From the JAMB admission into your present university">
          <input id={id("jambRegNo")} className="ctl tnum" value={f.jambRegNo} onChange={(e) => set({ jambRegNo: e.target.value.toUpperCase() })} disabled={!can("jambRegNo")}
            placeholder="12345678901AB" maxLength={20} autoCapitalize="characters" spellCheck={false} />
        </Field>
      </div>

      <Section title="Your present university" />
      <div className="grid grid--2">
        <Field id={id("universityCode")} label="University" required error={err("universityCode")} style={{ gridColumn: "1 / -1" }}>
          <SearchSelect id={id("universityCode")} value={f.notListed ? NOT_LISTED : f.universityCode} disabled={!can("universityCode")} placeholder="Choose your university…"
            valueLabel={universityLabel ?? undefined}
            onChange={(v) => set(v === NOT_LISTED ? { notListed: true, universityCode: "" } : { notListed: false, universityCode: v })}
            options={[...universities.map((u) => ({ value: u.code, label: u.name, sub: u.country ?? undefined })), { value: NOT_LISTED, label: "My university is not on the list" }]} />
        </Field>
        {f.notListed ? (
          <Field id={id("universityNamed")} label="The university's full name" required error={err("universityNamed")} style={{ gridColumn: "1 / -1" }} hint="The Registry adds it to the list">
            <input id={id("universityNamed")} className="ctl" value={f.universityNamed} onChange={text("universityNamed")} disabled={!can("universityNamed")} maxLength={200} />
          </Field>
        ) : null}
        <Field id={id("otherMatricNo")} label="Your matriculation number there" required error={err("otherMatricNo")}>
          <input id={id("otherMatricNo")} className="ctl tnum" value={f.otherMatricNo} onChange={(e) => set({ otherMatricNo: e.target.value.toUpperCase() })} disabled={!can("otherMatricNo")} maxLength={40} />
        </Field>
        <Field id={id("otherProgramme")} label="The programme you study there" required error={err("otherProgramme")}>
          <input id={id("otherProgramme")} className="ctl" value={f.otherProgramme} onChange={text("otherProgramme")} disabled={!can("otherProgramme")} maxLength={200} placeholder="B.Sc. Biochemistry" />
        </Field>
        <Field id={id("otherLevel")} label="The level you have reached there" required error={err("otherLevel")}>
          <select id={id("otherLevel")} className="ctl" value={f.otherLevel} disabled={!can("otherLevel")} onChange={(e) => set({ otherLevel: e.target.value })}>
            <option value="">—</option>
            {OTHER_LEVELS.map((l) => <option key={l} value={l}>{l} Level</option>)}
          </select>
        </Field>
        <Field id={id("otherEntrySession")} label="The session you entered there" required error={err("otherEntrySession")}>
          <input id={id("otherEntrySession")} className="ctl tnum" value={f.otherEntrySession} onChange={text("otherEntrySession")} disabled={!can("otherEntrySession")} placeholder="2023/2024" maxLength={9} />
        </Field>
        <Field id={id("otherCgpa")} label="Your CGPA there" required error={err("otherCgpa") ?? err("otherCgpaScale")}>
          <div className="row row--inline row--tight">
            <input id={id("otherCgpa")} className="ctl tnum" inputMode="decimal" value={f.otherCgpa} onChange={text("otherCgpa")} disabled={!can("otherCgpa")} placeholder="3.45" maxLength={4} style={{ maxWidth: 110 }} />
            <select id={id("otherCgpaScale")} className="ctl" aria-label="The scale" value={f.otherCgpaScale} disabled={!can("otherCgpaScale")}
              onChange={(e) => set({ otherCgpaScale: e.target.value as ApplyForm["otherCgpaScale"] })} style={{ maxWidth: 170 }}>
              <option value="">on a scale of…</option><option value="5">of 5 points</option><option value="4">of 4 points</option>
            </select>
          </div>
        </Field>
      </div>

      <Section title="What you apply for" />
      {chooseProgramme ? (
        <div className="grid grid--2">
          <Field id={id("programme")} label="Programme" required error={err("programme")} hint="Only the programmes taking transfer students are listed">
            <select id={id("programme")} className="ctl" value={f.programme} onChange={(e) => {
              const next = programmes.find((p) => p.code === e.target.value);
              set({ programme: e.target.value, level: next && next.levels.length === 1 ? String(next.levels[0]) : next?.levels.includes(Number(f.level)) ? f.level : "" });
            }}>
              <option value="">— Choose a programme —</option>
              {groups.map((g) => (
                <optgroup key={g.label} label={g.label}>
                  {g.programmes.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}
                </optgroup>
              ))}
            </select>
          </Field>
          <Field id={id("level")} label="Level" required error={err("level")} hint={session ? `For the ${session} session` : undefined}>
            <select id={id("level")} className="ctl" value={f.level} disabled={!prog} onChange={(e) => set({ level: e.target.value })}>
              <option value="">{prog ? "— Choose a level —" : "Choose a programme first"}</option>
              {(prog?.levels ?? []).map((l) => <option key={l} value={l}>{l} Level</option>)}
            </select>
          </Field>
        </div>
      ) : (
        <div className="sub2">{fixedProgramme ?? "—"}{session ? ` · ${session}` : ""}. The programme and level are not changed now: the window has closed, or the application is past its draft.</div>
      )}

      <Section title="Your reason for transferring" />
      <Field id={id("reason")} label="Why you wish to transfer to this University" required error={err("reason")}
        hint={`${f.reason.trim().length.toLocaleString()} of 2,000 characters; at least 20`}>
        <textarea id={id("reason")} className="ctl" rows={4} maxLength={2000} value={f.reason} disabled={!can("reason")} onChange={(e) => set({ reason: e.target.value })} />
      </Field>
    </>
  );
}
