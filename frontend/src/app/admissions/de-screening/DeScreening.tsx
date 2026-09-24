"use client";

/** Direct Entry screening for a programme: the DE applicants and the subject gate's verdict (V200),
 *  with inline capture of each candidate's prior-qualification subjects. Separate from the UTME merit
 *  list — DE carries no CAPS subjects, so it is checked against what an officer reads off the award.
 *  Screening-only: this reports, it does not gate the offer decision. */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, RoleLine, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface ProgrammeOption { code: string; name: string; facultyName: string; archived: boolean }
export interface DeRow {
  app_id: string; jamb_reg_no: string; jamb_key: string; surname: string; other_names: string;
  entry_level: number; has_data: boolean; meets_de: boolean; status: string;
}
export interface DeView { session: string; programme: string; counts: { pool: number; met: number; shortfall: number; unverified: number }; rows: DeRow[] }
interface DeSubject { subject: string; grade: string | null }
interface DeAward { id: string; basis: string; awarded_year: number | null; institution: string | null; subjects: DeSubject[] }

const BASES = ["A_LEVEL", "IJMB", "JUPEB", "NCE", "ND", "HND"] as const;
const basisLabel = (b: string) => (b === "A_LEVEL" ? "’A’ Level" : b);
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
    <div className="field" style={{ flexGrow: 1, minWidth: 300, position: "relative" }}>
      <label htmlFor="de-prog">Programme</label>
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
        <ul id="de-prog-list" role="listbox" style={{ position: "absolute", zIndex: 30, top: "100%", left: 0, right: 0, margin: "2px 0 0", padding: 0, listStyle: "none", maxHeight: 300, overflowY: "auto", background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 8, boxShadow: "0 6px 20px rgba(0,0,0,.12)" }}>
          {matches.length ? matches.map((p, i) => (
            <li key={p.code} role="option" aria-selected={i === hi}
              onMouseDown={(e) => { e.preventDefault(); onPick(p.code); setOpen(false); }}
              onMouseEnter={() => setHi(i)}
              style={{ padding: "8px 10px", cursor: "pointer", borderTop: i ? "1px solid var(--line-2)" : undefined, background: i === hi ? "var(--line-2)" : "transparent" }}>
              <div>{p.name}</div>
              <div className="sub2 tnum">{p.code} · {p.facultyName}</div>
            </li>
          )) : <li className="sub2" style={{ padding: "8px 10px" }}>No programme matches &ldquo;{q}&rdquo;.</li>}
        </ul>
      ) : null}
    </div>
  );
}

/** The capture form for one candidate's Direct Entry award, prefilled from what is on file. */
function CaptureForm({ session, row, mayEdit, onDone }: { session: string; row: DeRow; mayEdit: boolean; onDone: () => void }) {
  const [loaded, setLoaded] = useState<DeAward[] | null>(null);
  const [basis, setBasis] = useState<string>("A_LEVEL");
  const [year, setYear] = useState("");
  const [institution, setInstitution] = useState("");
  const [subjects, setSubjects] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);

  // load what is on file when the row is opened, and prefill from the first award
  useEffect(() => {
    let live = true;
    (async () => {
      try {
        const r = await fetch(`/api/bff/api/v1/admissions/de-awards?session=${encodeURIComponent(session)}&jambKey=${encodeURIComponent(row.jamb_key)}`);
        const j = (await r.json().catch(() => [])) as DeAward[];
        const arr = Array.isArray(j) ? j : [];
        if (!live) return;
        setLoaded(arr);
        const a = arr[0];
        if (a) {
          setBasis(a.basis);
          setYear(a.awarded_year ? String(a.awarded_year) : "");
          setInstitution(a.institution ?? "");
          setSubjects(a.subjects.map((s) => (s.grade ? `${s.subject} = ${s.grade}` : s.subject)).join("\n"));
        }
      } catch {
        if (live) setLoaded([]);
      }
    })();
    return () => { live = false; };
  }, [session, row.jamb_key]);

  const onFile = (loaded ?? []).find((a) => a.basis === basis);

  function parseSubjects(): DeSubject[] {
    return subjects.split(/\n/).map((line) => line.trim()).filter(Boolean).map((line) => {
      const m = line.split(/\s*[=:,]\s*/);
      const subject = (m[0] ?? "").trim();
      const grade = m.length > 1 && m[1].trim() ? m[1].trim() : null;
      return { subject, grade };
    }).filter((s) => s.subject);
  }

  async function save() {
    const subs = parseSubjects();
    if (!subs.length) { setProblem({ status: 400, title: "Enter at least one subject" }); return; }
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/admissions/de-awards", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Direct Entry subjects recorded for ${row.surname}, ${row.other_names} (${row.jamb_reg_no})`) },
        body: JSON.stringify({ session, jambKey: row.jamb_key, basis, awardedYear: year.trim() ? Number(year.trim()) : null, institution: institution.trim() || null, subjects: subs }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      notify(`Direct Entry subjects saved for ${row.surname}, ${row.other_names}`);
      onDone();
    } finally {
      setBusy(false);
    }
  }

  async function remove() {
    if (!onFile) return;
    if (!window.confirm(`Remove the ${basisLabel(basis)} record for ${row.surname}, ${row.other_names}?`)) return;
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/admissions/de-awards/${onFile.id}`, {
        method: "DELETE",
        headers: { "X-Reason": reasonHeader(`Direct Entry ${basisLabel(basis)} record removed for ${row.jamb_reg_no}`) },
      });
      if (!r.ok) { const j = await r.json().catch(() => null); setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      notify(`Record removed for ${row.surname}, ${row.other_names}`);
      onDone();
    } finally {
      setBusy(false);
    }
  }

  if (loaded === null) return <PBody><div className="sub2">Loading what is on file…</div></PBody>;

  return (
    <div className="card__body" style={{ display: "grid", gap: 10 }}>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <div className="grid grid--2 rfgrid">
        <Field id="de-basis" label="Qualification (basis)">
          <select id="de-basis" className="ctl" value={basis} disabled={!mayEdit} onChange={(e) => setBasis(e.target.value)}>
            {BASES.map((b) => <option key={b} value={b}>{basisLabel(b)}</option>)}
          </select>
        </Field>
        <Field id="de-year" label="Year awarded" hint="Optional">
          <input id="de-year" className="ctl tnum" inputMode="numeric" value={year} disabled={!mayEdit} onChange={(e) => setYear(e.target.value)} placeholder="2024" autoComplete="off" />
        </Field>
        <Field id="de-inst" label="Awarding body / institution" hint="Optional" full>
          <input id="de-inst" className="ctl" value={institution} disabled={!mayEdit} onChange={(e) => setInstitution(e.target.value)} placeholder="e.g. IJMB, Ahmadu Bello University" autoComplete="off" />
        </Field>
        <Field id="de-subs" label="Subjects offered" hint="One per line · add the grade after “=”, “:” or “,” (e.g. Physics = A) · the gate reads the subjects" full>
          <textarea id="de-subs" className="ctl" rows={4} value={subjects} disabled={!mayEdit} onChange={(e) => setSubjects(e.target.value)} placeholder={"Physics = A\nChemistry = B\nBiology = C"} />
        </Field>
      </div>
      {mayEdit ? (
        <div className="row">
          <Btn kind="primary" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : onFile ? "Update the record" : "Save the record"}</Btn>
          {onFile ? <Btn kind="ghost" disabled={busy} onClick={() => void remove()}>Remove</Btn> : null}
          <span className="grow" />
          <span className="sub2">Recorded subjects are checked against the programme&rsquo;s DE requirement.</span>
        </div>
      ) : <div className="sub2">You can view what is on file; recording is the Admissions Office&rsquo;s.</div>}
    </div>
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

  return (
    <>
      <RoleLine allowed={["academic", "registrar"]} actingOffice={actingOffice}
        action="Recording Direct Entry subjects" />
      <Note kind="info" title="Direct Entry is screened on its own, not on UTME subjects">
        A Direct Entry candidate offers a prior qualification — an <b>&rsquo;A&rsquo; Level</b> (IJMB, JUPEB), an <b>NCE</b>, an <b>ND</b> or an <b>HND</b> — and carries no UTME aggregate or CAPS subjects. This screen checks each DE applicant against the programme&rsquo;s <b>Direct Entry subject set</b> (set in Admission settings), reading the subjects an officer records off the certificate below. It reports — it does not gate the Board&rsquo;s decision.
      </Note>

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
                    <Btn kind="ghost" key="a" onClick={() => setOpenRow(openRow === r.app_id ? null : r.app_id)}>{openRow === r.app_id ? "Close" : r.has_data ? "Edit subjects" : "Enter subjects"}</Btn>,
                  ];
                })}
                texts={view.rows.map((r) => `${r.surname} ${r.other_names} ${r.jamb_reg_no} ${r.status}`)}
              />
            ) : <PBody><div className="sub2">No Direct Entry applicant has registered for this programme yet. DE candidates appear here once they are on a committed list and have applied.</div></PBody>}
          </Panel>

          {openRow ? (() => {
            const r = view.rows.find((x) => x.app_id === openRow);
            if (!r) return null;
            return (
              <Panel title={`Direct Entry record — ${r.surname}, ${r.other_names}`} right={<span className="tnum sub2">{r.jamb_reg_no}</span>}>
                <CaptureForm session={session} row={r} mayEdit={mayEdit} onDone={() => { setOpenRow(null); router.refresh(); }} />
              </Panel>
            );
          })() : null}
        </>
      ) : (
        <Note kind="info" title="Choose a programme to screen its Direct Entry applicants">Pick a programme above. The list is its Direct Entry applicants, each checked against the programme&rsquo;s DE subject set.</Note>
      )}
    </>
  );
}
