"use client";

/** Direct Entry screening for a programme: the DE applicants and the subject gate's verdict (V200),
 *  with inline capture of each candidate's prior-qualification subjects. Separate from the UTME merit
 *  list — DE carries no CAPS subjects, so it is checked against what an officer reads off the award.
 *  Screening-only: this reports, it does not gate the offer decision.
 *  V773: a whole list's qualifications uploaded at once from CAPS's grade windows (DeUpload), a degree or
 *  diploma recorded as its discipline and class, and a candidate on JAMB's list who has not registered
 *  found by REG NO. to be corrected. */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, RoleLine, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { DE_BASIS_LABEL, isClassKind, type DeBasis } from "@/lib/de-candidates";
import { DeUpload, type DeLookup } from "./DeUpload";

export interface ProgrammeOption { code: string; name: string; facultyName: string; archived: boolean }
export interface DeRow {
  app_id: string; jamb_reg_no: string; jamb_key: string; surname: string; other_names: string;
  entry_level: number; has_data: boolean; meets_de: boolean; status: string;
}
export interface DeView { session: string; programme: string; counts: { pool: number; met: number; shortfall: number; unverified: number }; rows: DeRow[] }
interface DeSubject { subject: string; grade: string | null }
interface DeAward {
  id: string; basis: string; awarded_year: number | null; institution: string | null; subjects: DeSubject[];
  /** V773: a degree or diploma's discipline and class, the exam/matric number, and whether it was typed here or uploaded */
  discipline?: string | null; award_class?: string | null; exam_no?: string | null; source?: "MANUAL" | "UPLOAD" | string | null;
}
/** the candidate a record is for: a row of the screening list, or one found on JAMB's list by REG NO. */
interface Who { jamb_key: string; jamb_reg_no: string; name: string }

/** the bases an officer may type (V773: a degree, a foreign degree, a University Diploma added); "Not stated" and "Not available"
 *  are what an upload recorded from CAPS, shown and removable, never typed */
const BASES: DeBasis[] = ["A_LEVEL", "IJMB", "JUPEB", "NCE", "ND", "HND", "DEGREE", "DEGREE_FOREIGN", "UNIVERSITY_DIPLOMA"];
const basisLabel = (b: string) => DE_BASIS_LABEL[b as DeBasis] ?? b;
/** each class kind's classes, for the Class field's suggestions */
const CLASS_NAMES: Record<string, string[]> = {
  DEGREE: ["First Class", "2nd Class Upper", "2nd Class Lower", "3rd Class", "Pass"],
  DEGREE_FOREIGN: ["First Class", "2nd Class Upper", "2nd Class Lower", "3rd Class", "Pass"],
  UNIVERSITY_DIPLOMA: ["Distinction", "Credit", "Merit", "Pass"],
  HND: ["Distinction", "Upper Credit", "Lower Credit", "Pass"],
  ND: ["Distinction", "Upper Credit", "Lower Credit", "Pass"],
};
/** the capture form's fields */
interface Form { basis: string; year: string; institution: string; subjects: string; discipline: string; awardClass: string; examNo: string }
const BLANK: Form = { basis: "A_LEVEL", year: "", institution: "", subjects: "", discipline: "", awardClass: "", examNo: "" };
/** the form filled from an award on file; a degree or diploma typed before V773 as one subject row reads its subject as the
 *  discipline and its grade as the class */
function formOf(a: DeAward): Form {
  const legacy = isClassKind(a.basis) ? a.subjects[0] : undefined;
  return {
    basis: a.basis, year: a.awarded_year ? String(a.awarded_year) : "", institution: a.institution ?? "",
    subjects: a.subjects.map((s) => (s.grade ? `${s.subject} = ${s.grade}` : s.subject)).join("\n"),
    discipline: a.discipline ?? legacy?.subject ?? "", awardClass: a.award_class ?? legacy?.grade ?? "", examNo: a.exam_no ?? "",
  };
}
/** what is on file for an award, in a line */
const awardWords = (a: DeAward) => isClassKind(a.basis)
  ? [a.discipline, a.award_class].filter(Boolean).join(" · ") || a.subjects.map((s) => (s.grade ? `${s.subject} ${s.grade}` : s.subject)).join(", ") || "—"
  : a.subjects.map((s) => (s.grade ? `${s.subject} ${s.grade}` : s.subject)).join(", ") || "—";
const STATUS: Record<string, { kind: "ok" | "bad" | "warn" | "grey"; label: string }> = {
  MET: { kind: "ok", label: "Meets DE subjects" },
  SHORT: { kind: "bad", label: "Short of subjects" },
  UNVERIFIED: { kind: "warn", label: "No subjects captured" },
  NO_RULE: { kind: "grey", label: "No DE rule set" },
};

/** Type-to-search over the programmes — name, faculty or code. */
function ProgrammePicker({ programmes, chosen, onPick }: { programmes: ProgrammeOption[]; chosen: ProgrammeOption | undefined; onPick: (code: string) => void }) {
  const live = programmes.filter((p) => !p.archived);
  const [q, setQ] = useState("");
  const [open, setOpen] = useState(false);
  const [hi, setHi] = useState(0);
  const term = q.trim().toLowerCase();
  const matches = (term ? live.filter((p) => `${p.name} ${p.facultyName} ${p.code}`.toLowerCase().includes(term)) : live).slice(0, 60);
  const label = chosen ? `${chosen.name} · ${chosen.facultyName}` : "";
  return (
    <div className="grow" style={{ minWidth: 300, position: "relative" }}><Field id="de-prog" label="Programme">
      <input
        id="de-prog" className="ctl" autoComplete="off" role="combobox" aria-controls="de-prog-list" aria-expanded={open} aria-autocomplete="list"
        value={open ? q : label}
        placeholder="Type to search — name, faculty or code"
        onFocus={() => { setQ(""); setOpen(true); setHi(0); }}
        onChange={(e) => { setQ(e.target.value); setOpen(true); setHi(0); }}
        onBlur={() => window.setTimeout(() => setOpen(false), 150)}
        onKeyDown={(e) => {
          if (!open) return;
          if (e.key === "ArrowDown") { e.preventDefault(); setHi((h) => Math.min(h + 1, matches.length - 1)); }
          else if (e.key === "ArrowUp") { e.preventDefault(); setHi((h) => Math.max(h - 1, 0)); }
          else if (e.key === "Enter") { e.preventDefault(); const m = matches[hi]; if (m) { onPick(m.code); setOpen(false); (e.target as HTMLInputElement).blur(); } }
          else if (e.key === "Escape") { setOpen(false); }
        }}
      />
      {open ? (
        <ul id="de-prog-list" role="listbox" style={{ position: "absolute", zIndex: 30, top: "100%", left: 0, right: 0, margin: "2px 0 0", padding: 0, listStyle: "none", maxHeight: 300, overflowY: "auto", background: "var(--surface)", border: "1px solid var(--line)", borderRadius: "var(--r-md)", boxShadow: "var(--sh-2)" }}>
          {matches.length ? matches.map((p, i) => (
            <li key={p.code} role="option" aria-selected={i === hi}
              onMouseDown={(e) => { e.preventDefault(); onPick(p.code); setOpen(false); }}
              onMouseEnter={() => setHi(i)}
              style={{ padding: "var(--s-2) var(--s-3)", cursor: "pointer", borderTop: i ? "1px solid var(--line-2)" : undefined, background: i === hi ? "var(--line-2)" : "transparent" }}>
              <div>{p.name}</div>
              <div className="sub2 tnum">{p.code} · {p.facultyName}</div>
            </li>
          )) : <li className="sub2" style={{ padding: "var(--s-2) var(--s-3)" }}>No programme matches &ldquo;{q}&rdquo;.</li>}
        </ul>
      ) : null}
    </Field></div>
  );
}

/** The capture form for one candidate's Direct Entry award, prefilled from what is on file. */
function CaptureForm({ session, row, mayEdit, onDone }: { session: string; row: Who; mayEdit: boolean; onDone: () => void }) {
  const [loaded, setLoaded] = useState<DeAward[] | null>(null);
  const [form, setForm] = useState<Form>(BLANK);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const { basis, year, institution, subjects, discipline, awardClass, examNo } = form;
  const set = (patch: Partial<Form>) => setForm({ ...form, ...patch });

  // load what is on file when the row is opened, and prefill from the first award an officer may type
  useEffect(() => {
    let live = true;
    (async () => {
      try {
        const r = await fetch(`/api/bff/api/v1/admissions/de-awards?session=${encodeURIComponent(session)}&jambKey=${encodeURIComponent(row.jamb_key)}`);
        const j = (await r.json().catch(() => [])) as DeAward[];
        const arr = Array.isArray(j) ? j : [];
        if (!live) return;
        setLoaded(arr);
        const a = arr.find((x) => BASES.includes(x.basis as DeBasis));
        if (a) setForm(formOf(a));
      } catch {
        if (live) setLoaded([]);
      }
    })();
    return () => { live = false; };
  }, [session, row.jamb_key]);

  const onFile = (loaded ?? []).find((a) => a.basis === basis);
  const classKind = isClassKind(basis);
  /** a basis chosen: what is on file under it, if anything, fills the form */
  function choose(b: string) {
    const a = (loaded ?? []).find((x) => x.basis === b);
    setForm(a ? formOf(a) : { ...form, basis: b });
  }

  function parseSubjects(): DeSubject[] {
    return subjects.split(/\n/).map((line) => line.trim()).filter(Boolean).map((line) => {
      const m = line.split(/\s*[=:,]\s*/);
      const subject = (m[0] ?? "").trim();
      const grade = m.length > 1 && m[1].trim() ? m[1].trim() : null;
      return { subject, grade };
    }).filter((s) => s.subject);
  }

  async function save() {
    const subs = classKind ? [] : parseSubjects();
    // as the server's DE_AWARD_EMPTY: a degree or diploma needs its discipline or its class; an A'Level or NCE at least one subject
    const empty = classKind ? !discipline.trim() && !awardClass.trim() : !subs.length;
    if (empty) {
      const refusal = { status: 400, title: classKind ? "Enter the discipline or the class" : "Enter at least one subject" };
      setProblem(refusal); notifyProblem(refusal);
      return;
    }
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/admissions/de-awards", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Direct Entry qualification recorded for ${row.name} (${row.jamb_reg_no})`) },
        body: JSON.stringify({
          session, jambKey: row.jamb_key, basis, awardedYear: year.trim() ? Number(year.trim()) : null, institution: institution.trim() || null, subjects: subs,
          discipline: classKind ? discipline.trim() || null : null, awardClass: classKind ? awardClass.trim() || null : null, examNo: examNo.trim() || null,
        }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      notify(`Direct Entry qualification saved for ${row.name}`);
      onDone();
    } finally {
      setBusy(false);
    }
  }

  async function remove(a: DeAward) {
    if (!window.confirm(`Remove the ${basisLabel(a.basis)} record for ${row.name}?`)) return;
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/admissions/de-awards/${a.id}`, {
        method: "DELETE",
        headers: { "X-Reason": reasonHeader(`Direct Entry ${basisLabel(a.basis)} record removed for ${row.jamb_reg_no}`) },
      });
      if (!r.ok) { const j = await r.json().catch(() => null); setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      notify(`Record removed for ${row.name}`);
      onDone();
    } finally {
      setBusy(false);
    }
  }

  if (loaded === null) return <PBody><div className="sub2">Loading what is on file…</div></PBody>;

  return (
    <PBody>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {loaded.length ? (
        <div className="mb-3">
          <DTable noPrint cols={["On file", "Qualification", "Year · exam no.|mid", "Source|mid", "|num"]} rows={loaded.map((a) => [
            <strong key="b">{basisLabel(a.basis)}</strong>,
            <span className="sub2" key="w">{awardWords(a)}</span>,
            <span className="sub2 tnum" key="y">{[a.awarded_year, a.exam_no].filter(Boolean).join(" · ") || "—"}</span>,
            a.source === "UPLOAD" ? <Pil kind="info" key="s">Uploaded</Pil> : <Pil kind="grey" key="s">Typed</Pil>,
            mayEdit ? <Btn kind="ghost" key="r" disabled={busy} onClick={() => void remove(a)}>Remove</Btn> : <span key="r" />,
          ])} />
        </div>
      ) : null}
      <div className="grid grid--2 rfgrid">
        <Field id="de-basis" label="Qualification (basis)">
          <select id="de-basis" className="ctl" value={basis} disabled={!mayEdit} onChange={(e) => choose(e.target.value)}>
            {BASES.map((b) => <option key={b} value={b}>{basisLabel(b)}</option>)}
          </select>
        </Field>
        <Field id="de-year" label="Year awarded" hint="Optional">
          <input id="de-year" className="ctl tnum" inputMode="numeric" value={year} disabled={!mayEdit} onChange={(e) => set({ year: e.target.value })} placeholder="2024" autoComplete="off" />
        </Field>
        <Field id="de-inst" label="Awarding body / institution" hint="Optional">
          <input id="de-inst" className="ctl" value={institution} disabled={!mayEdit} onChange={(e) => set({ institution: e.target.value })} placeholder="e.g. IJMB, Ahmadu Bello University" autoComplete="off" />
        </Field>
        <Field id="de-exam" label="Exam / matric no." hint="Optional">
          <input id="de-exam" className="ctl tnum" value={examNo} disabled={!mayEdit} onChange={(e) => set({ examNo: e.target.value })} autoComplete="off" />
        </Field>
        {classKind ? (
          <>
            <Field id="de-disc" label="Discipline" hint="As the certificate names it (e.g. Biochemistry, Pharmaceutical Technology)">
              <input id="de-disc" className="ctl" value={discipline} disabled={!mayEdit} onChange={(e) => set({ discipline: e.target.value })} autoComplete="off" />
            </Field>
            <Field id="de-class" label="Class" hint="Choose or type the class awarded">
              <input id="de-class" className="ctl" list="de-class-names" value={awardClass} disabled={!mayEdit} onChange={(e) => set({ awardClass: e.target.value })} autoComplete="off" />
              <datalist id="de-class-names">{(CLASS_NAMES[basis] ?? []).map((c) => <option key={c} value={c} />)}</datalist>
            </Field>
          </>
        ) : (
          <Field id="de-subs" label="Subjects offered" hint="One per line · add the grade after “=”, “:” or “,” (e.g. Physics = A) · the gate reads the subjects" full>
            <textarea id="de-subs" className="ctl" rows={4} value={subjects} disabled={!mayEdit} onChange={(e) => set({ subjects: e.target.value })} placeholder={"Physics = A\nChemistry = B\nBiology = C"} />
          </Field>
        )}
      </div>
      {mayEdit ? (
        <div className="row">
          <Btn kind="primary" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : onFile ? "Update the record" : "Save the record"}</Btn>
          <span className="grow" />
          <span className="sub2">{classKind ? "A degree or diploma is read by its discipline and class." : "Recorded subjects are checked against the programme’s DE requirement."}</span>
        </div>
      ) : <div className="sub2">You can view what is on file; recording is the Admissions Office&rsquo;s.</div>}
    </PBody>
  );
}

export function DeScreening({ session, programme, programmes, view, problem, actingOffice }: {
  session: string; programme: string; programmes: ProgrammeOption[]; view: DeView | null; problem: Problem | null; actingOffice: string | null;
}) {
  const router = useRouter();
  const pick = (code: string) => router.push(`/admissions/de-screening?session=${encodeURIComponent(session)}${code ? `&programme=${encodeURIComponent(code)}` : ""}`);
  const chosen = programmes.find((p) => p.code === programme);
  const mayEdit = ["academic", "registrar"].includes(actingOffice ?? "");
  const [openRow, setOpenRow] = useState<string | null>(null);
  // V773: a candidate on JAMB's live Direct Entry list found by REG NO. — registered or not, whatever programme is chosen
  const [found, setFound] = useState<DeLookup | null>(null);

  return (
    <>
      <RoleLine allowed={["academic", "registrar"]} actingOffice={actingOffice}
        action="Recording Direct Entry subjects" />
      <Note kind="info" title="Direct Entry is screened on its own, not on UTME subjects">
        Checked against the programme&rsquo;s <b>Direct Entry subject set</b> from the certificate subjects recorded below. It reports; it does not gate the Board&rsquo;s decision.
      </Note>

      <DeUpload session={session} programme={programme} mayUpload={mayEdit} onFound={(c) => { setOpenRow(null); setFound(c); }} onRecorded={() => router.refresh()} />

      {found ? (
        <Panel title={`Direct Entry record — ${found.name ?? found.regNo}`} right={<span className="row row--inline">
          <span className="tnum sub2">{found.regNo}{found.programme ? ` · ${found.programme}` : ""}</span>
          {found.registered ? <Pil kind="ok">Registered</Pil> : <Pil kind="grey">Not registered on the portal</Pil>}
          <Btn kind="ghost" onClick={() => setFound(null)}>Close</Btn>
        </span>}>
          <CaptureForm key={found.jambKey} session={session} row={{ jamb_key: found.jambKey, jamb_reg_no: found.regNo, name: found.name ?? found.regNo }} mayEdit={mayEdit}
            onDone={() => { setFound(null); router.refresh(); }} />
        </Panel>
      ) : null}

      <Panel title="Choose a programme" right={`${session}`}>
        <div className="card__body row row--end">
          <ProgrammePicker programmes={programmes} chosen={chosen} onPick={pick} />
          {chosen ? <Btn kind="ghost" onClick={() => pick("")}>Clear</Btn> : null}
        </div>
      </Panel>

      {problem ? <ProblemNotice problem={problem} /> : null}

      {view ? (
        <>
          <Tiles items={[
            ["DE applicants", String(view.counts.pool), null, chosen ? chosen.name : programme],
            ["Meets subjects", String(view.counts.met), Number(view.counts.met) ? "var(--green-ink)" : null, "Offered the required set"],
            ["Short of subjects", String(view.counts.shortfall), Number(view.counts.shortfall) ? "var(--red-ink)" : null, "Captured, but the set is not met"],
            ["Not yet captured", String(view.counts.unverified), Number(view.counts.unverified) ? "var(--chrome)" : null, "No subjects on file to check"],
          ]} />
          <Panel title="Direct Entry applicants" right={`${view.counts.pool} in the pool`}>
            {view.rows.length ? (
              <DTable
                cols={["Candidate", "JAMB|mid", "Level|mid", "Subjects|mid", "Status|mid", "|num"]}
                rows={view.rows.map((r) => {
                  const st = STATUS[r.status] ?? { kind: "grey" as const, label: r.status };
                  return [
                    <Two key="n" a={`${r.surname}, ${r.other_names}`} b={r.jamb_reg_no} />,
                    <span className="tnum" key="j">{r.jamb_reg_no}</span>,
                    <span className="tnum" key="l">{r.entry_level}</span>,
                    r.has_data ? <Pil kind="ok" key="d">On file</Pil> : <Pil kind="grey" key="d">None</Pil>,
                    <Pil kind={st.kind} key="s">{st.label}</Pil>,
                    <Btn kind="ghost" key="a" onClick={() => { setFound(null); setOpenRow(openRow === r.app_id ? null : r.app_id); }}>{openRow === r.app_id ? "Close" : r.has_data ? "Edit subjects" : "Enter subjects"}</Btn>,
                  ];
                })}
                texts={view.rows.map((r) => `${r.surname} ${r.other_names} ${r.jamb_reg_no} ${r.status}`)}
              />
            ) : <PBody><div className="sub2">No Direct Entry applicant for this programme yet.</div></PBody>}
          </Panel>

          {openRow ? (() => {
            const r = view.rows.find((x) => x.app_id === openRow);
            if (!r) return null;
            return (
              <Panel title={`Direct Entry record — ${r.surname}, ${r.other_names}`} right={<span className="tnum sub2">{r.jamb_reg_no}</span>}>
                <CaptureForm key={r.jamb_key} session={session} row={{ jamb_key: r.jamb_key, jamb_reg_no: r.jamb_reg_no, name: `${r.surname}, ${r.other_names}` }} mayEdit={mayEdit}
                  onDone={() => { setOpenRow(null); router.refresh(); }} />
              </Panel>
            );
          })() : null}
        </>
      ) : (
        <Note kind="info" title="Choose a programme to screen its Direct Entry applicants" />
      )}
    </>
  );
}
