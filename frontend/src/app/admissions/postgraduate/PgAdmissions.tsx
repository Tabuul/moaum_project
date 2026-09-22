"use client";

/** The postgraduate admissions desks (V202): the department's committee recommends a submitted
 *  application, the School of Postgraduate Studies offers or refuses, the applicant accepts, and the
 *  School admits — which puts the student on the register. Separate from the JAMB/CAPS flow. */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, RoleLine, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface PgRow {
  id: string; application_no: string; state: string; entry_level: number; programme_code: string;
  programme_name: string; pg_award: string | null; pg_research: boolean;
  surname: string; other_names: string; email: string; phone: string | null; state_of_origin: string | null;
  prior_institution: string | null; prior_award: string | null; prior_class: string | null; prior_cgpa: number | null;
  fee_confirmed_at: string | null; submitted_at: string | null; dept_decided_at: string | null;
  spgs_decided_at: string | null; accepted_at: string | null; admitted_at: string | null; student_id: string | null;
}
export interface PgView { session: string; counts: { total: number; submitted: number; recommended: number; offered: number; accepted: number; admitted: number }; rows: PgRow[] }
interface Referee { id: string; name: string; email: string | null; institution: string | null; position: string | null; reference_text: string | null }
interface DocMeta { id: string; kind: string; filename: string; content_type: string; uploaded_at: string }
interface PriorQual { kind: string; institution: string | null; award: string | null; field: string | null; class_of_degree: string | null; cgpa: number | null; year: number | null }
interface Detail { found: boolean; application?: PgRow & { sex: string | null; date_of_birth: string | null; lga: string | null; prior_year: number | null; proposal_title: string | null; proposal_text: string | null; dept_note: string | null; spgs_note: string | null }; referees?: Referee[]; priorDegrees?: PriorQual[]; documents?: DocMeta[] }
const QUAL_LABEL: Record<string, string> = {
  FIRST: "First degree", MASTERS: "Master’s degree", PGD: "Postgraduate Diploma", HND: "Higher National Diploma",
  ND: "National Diploma", NCE: "Nigeria Certificate in Education", PHD: "Doctorate (PhD)", OTHER: "Other qualification",
};

const STATE: Record<string, { kind: "ok" | "bad" | "warn" | "info" | "grey"; label: string }> = {
  DRAFT: { kind: "grey", label: "Draft" },
  SUBMITTED: { kind: "info", label: "Submitted" },
  DEPT_RECOMMENDED: { kind: "info", label: "Dept recommended" },
  DEPT_DECLINED: { kind: "grey", label: "Dept declined" },
  OFFERED: { kind: "ok", label: "Offered" },
  NOT_OFFERED: { kind: "grey", label: "Not offered" },
  ACCEPTED: { kind: "ok", label: "Accepted" },
  ADMITTED: { kind: "ok", label: "Admitted" },
};
const isDept = (o: string | null) => ["hod", "dean", "academic", "super"].includes(o ?? "");
const isSpgs = (o: string | null) => ["pgschool", "pgsecretary", "super"].includes(o ?? "");
const mayAdmit = (o: string | null) => ["pgschool", "pgsecretary", "registrar", "super"].includes(o ?? "");
const fmtDate = (v: string | null | undefined) => { if (!v) return "—"; const d = new Date(v); return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" }); };
const sexLabel = (v: string | null | undefined) => (v === "F" ? "Female" : v === "M" ? "Male" : "—");

function DetailPanel({ id, office, onChanged }: { id: string; office: string | null; onChanged: () => void }) {
  const [d, setD] = useState<Detail | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [note, setNote] = useState("");

  useEffect(() => {
    let live = true;
    (async () => {
      try {
        const r = await fetch(`/api/bff/api/v1/pg/applications/${id}`);
        const j = (await r.json().catch(() => null)) as Detail | null;
        if (live) setD(j && j.found ? j : { found: false });
      } catch { if (live) setD({ found: false }); }
    })();
    return () => { live = false; };
  }, [id]);

  async function act(path: string, label: string, body?: unknown) {
    setBusy(path); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/pg/applications/${id}/${path}`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(label) },
        body: JSON.stringify(body ?? {}),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      notify(label);
      setD(j && (j as Detail).found ? (j as Detail) : d);
      onChanged();
    } finally { setBusy(null); }
  }

  if (!d) return <PBody><div className="sub2">Loading the application…</div></PBody>;
  if (!d.found || !d.application) return <PBody><div className="sub2">This application could not be read.</div></PBody>;
  const a = d.application;
  const st = a.state;
  return (
    <div className="card__body" style={{ display: "grid", gap: 14 }}>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: "10px 24px" }}>
        {([["Sex", sexLabel(a.sex)], ["Date of birth", fmtDate(a.date_of_birth)],
           ["State of origin", a.state_of_origin ?? "—"], ["LGA", a.lga ?? "—"],
           ["Contact", `${a.email}${a.phone ? ` · ${a.phone}` : ""}`]] as [string, string][]).map(([k, v]) => (
          <div key={k}><div className="sub2" style={{ textTransform: "uppercase", letterSpacing: ".04em", fontSize: 10.5 }}>{k}</div><div style={{ fontWeight: 600, fontSize: 13.5 }}>{v}</div></div>
        ))}
      </div>

      <div>
        <div className="sub2" style={{ textTransform: "uppercase", letterSpacing: ".04em", fontSize: 10.5, marginBottom: 6 }}>Qualifications</div>
        {(() => {
          const list = (d.priorDegrees ?? []).length
            ? (d.priorDegrees ?? [])
            : [{ kind: "FIRST", institution: a.prior_institution, award: a.prior_award, field: null, class_of_degree: a.prior_class, cgpa: a.prior_cgpa, year: a.prior_year } as PriorQual];
          return (
            <div style={{ display: "grid", gap: 8 }}>
              {list.map((q, i) => (
                <div key={i} style={{ border: "1px solid var(--line-2)", borderRadius: 8, padding: "8px 12px" }}>
                  <div style={{ fontWeight: 600, fontSize: 13.5 }}>
                    {QUAL_LABEL[q.kind] ?? q.kind}{q.award ? ` — ${q.award}` : ""}{q.field ? ` (${q.field})` : ""}
                  </div>
                  <div className="sub2" style={{ marginTop: 2 }}>
                    {[q.institution, q.class_of_degree, q.cgpa != null ? `CGPA ${q.cgpa}` : null, q.year != null ? String(q.year) : null].filter(Boolean).join(" · ") || "—"}
                  </div>
                </div>
              ))}
            </div>
          );
        })()}
      </div>

      {a.pg_research ? (
        <div>
          <div className="sub2" style={{ textTransform: "uppercase", letterSpacing: ".04em", fontSize: 10.5, marginBottom: 4 }}>Research proposal</div>
          <div style={{ fontWeight: 600 }}>{a.proposal_title || "—"}</div>
          {a.proposal_text ? <div className="sub2" style={{ marginTop: 4, lineHeight: 1.5 }}>{a.proposal_text}</div> : null}
        </div>
      ) : null}

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))", gap: 14 }}>
        <div>
          <div className="sub2" style={{ textTransform: "uppercase", letterSpacing: ".04em", fontSize: 10.5, marginBottom: 6 }}>Referees</div>
          {(d.referees ?? []).length ? (d.referees ?? []).map((r) => (
            <div key={r.id} className="sub2" style={{ marginBottom: 4 }}><b>{r.name}</b>{r.position ? ` · ${r.position}` : ""}{r.institution ? ` · ${r.institution}` : ""}</div>
          )) : <div className="sub2">None named.</div>}
        </div>
        <div>
          <div className="sub2" style={{ textTransform: "uppercase", letterSpacing: ".04em", fontSize: 10.5, marginBottom: 6 }}>Documents</div>
          {(d.documents ?? []).length ? (d.documents ?? []).map((x) => (
            <div key={x.id} className="sub2" style={{ marginBottom: 6, display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
              <span>{x.kind.replace("_", " ").toLowerCase()} — {x.filename}</span>
              <a href={`/api/bff/api/v1/pg/applications/${id}/documents/${x.id}`} target="_blank" rel="noopener" className="btn btn--ghost btn--sm">View PDF</a>
            </div>
          )) : <div className="sub2">None uploaded &mdash; the applicant scans their O&rsquo;/A&rsquo;Level and birth certificate into one PDF on their dashboard.</div>}
        </div>
      </div>

      {a.dept_note ? <Note kind="info" title="Department note">{a.dept_note}</Note> : null}
      {a.spgs_note ? <Note kind="info" title="School note">{a.spgs_note}</Note> : null}

      {(isDept(office) && st === "SUBMITTED") || (isSpgs(office) && ["DEPT_RECOMMENDED", "SUBMITTED"].includes(st)) ? (
        <div>
          <textarea className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} placeholder="A note for the decision (optional)" />
        </div>
      ) : null}

      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
        {isDept(office) && st === "SUBMITTED" ? (
          <>
            <Btn kind="primary" disabled={busy !== null} onClick={() => void act("dept-decision", `Recommended ${a.surname}, ${a.other_names} for ${a.programme_name}`, { recommend: true, note })}>Recommend</Btn>
            <Btn kind="ghost" disabled={busy !== null} onClick={() => void act("dept-decision", `Declined ${a.surname}, ${a.other_names}`, { recommend: false, note })}>Decline</Btn>
          </>
        ) : null}
        {isSpgs(office) && ["DEPT_RECOMMENDED", "SUBMITTED"].includes(st) ? (
          <>
            <Btn kind="primary" disabled={busy !== null} onClick={() => void act("spgs-decision", `Offered ${a.surname}, ${a.other_names} a place on ${a.programme_name}`, { offer: true, note })}>Offer a place</Btn>
            <Btn kind="ghost" disabled={busy !== null} onClick={() => void act("spgs-decision", `Refused ${a.surname}, ${a.other_names}`, { offer: false, note })}>Refuse</Btn>
          </>
        ) : null}
        {isSpgs(office) && st === "OFFERED" ? (
          <Btn kind="primary" disabled={busy !== null} onClick={() => void act("accept", `Recorded acceptance for ${a.surname}, ${a.other_names}`)}>Record acceptance</Btn>
        ) : null}
        {mayAdmit(office) && st === "ACCEPTED" ? (
          <Btn kind="primary" disabled={busy !== null} onClick={() => void act("admit", `Admitted ${a.surname}, ${a.other_names} onto the register`)}>Admit onto the register</Btn>
        ) : null}
        {st === "ADMITTED" ? <span className="sub2" style={{ alignSelf: "center", color: "var(--green-ink)" }}>Admitted &mdash; on the register, awaiting matriculation on fees and registration.</span> : null}
        {busy ? <span className="sub2" style={{ alignSelf: "center" }}>Working…</span> : null}
      </div>
    </div>
  );
}

export function PgAdmissions({ session, view, problem, actingOffice }: {
  session: string; view: PgView | null; problem: Problem | null; actingOffice: string | null;
}) {
  const router = useRouter();
  const [open, setOpen] = useState<string | null>(null);
  const c = view?.counts;
  return (
    <>
      <RoleLine allowed={["pgschool", "pgsecretary", "hod", "dean", "academic", "registrar"]} actingOffice={actingOffice}
        action="Deciding postgraduate admissions" />
      <Note kind="info" title="Postgraduate admission is decided on the record, not on a UTME score">
        A postgraduate applicant applies on a first degree — no JAMB, no UTME aggregate. The department&rsquo;s committee recommends a submitted application, the <b>School of Postgraduate Studies</b> offers or refuses, the applicant accepts, and the School admits, which puts the student on the register to be matriculated on fees and registration.
      </Note>

      {problem ? <ProblemNotice problem={problem} /> : null}

      {view ? (
        <>
          <Tiles items={[
            ["Applications", String(c?.total ?? 0), null, session],
            ["Submitted", String(c?.submitted ?? 0), Number(c?.submitted) ? "var(--chrome)" : null, "Awaiting the department"],
            ["Recommended", String(c?.recommended ?? 0), Number(c?.recommended) ? "var(--chrome)" : null, "Awaiting the School"],
            ["Offered", String(c?.offered ?? 0), Number(c?.offered) ? "var(--green-ink)" : null, "Awaiting acceptance"],
            ["Admitted", String(c?.admitted ?? 0), Number(c?.admitted) ? "var(--green-ink)" : null, "On the register"],
          ]} />

          <Panel title="Postgraduate applications" right={`${view.rows.length} application${view.rows.length === 1 ? "" : "s"}`}>
            {view.rows.length ? (
              <DTable
                cols={["Applicant", "Programme", "Level|mid", "First degree", "Stage|mid", "|num"]}
                rows={view.rows.map((r) => {
                  const st = STATE[r.state] ?? { kind: "grey" as const, label: r.state };
                  return [
                    <Two key="n" a={`${r.surname}, ${r.other_names}`} b={r.application_no} />,
                    <span key="p"><span>{r.programme_name}</span><div className="sub2">{r.pg_award ?? ""}{r.pg_research ? " · research" : ""}</div></span>,
                    <span className="tnum" key="l">{r.entry_level}</span>,
                    <span className="sub2" key="d">{r.prior_award ?? "—"}{r.prior_class ? ` · ${r.prior_class}` : ""}</span>,
                    <Pil kind={st.kind} key="s">{st.label}</Pil>,
                    <Btn kind="ghost" key="a" onClick={() => setOpen(open === r.id ? null : r.id)}>{open === r.id ? "Close" : "Details"}</Btn>,
                  ];
                })}
                texts={view.rows.map((r) => `${r.surname} ${r.other_names} ${r.application_no} ${r.programme_name} ${r.state}`)}
              />
            ) : <PBody><div className="sub2">No postgraduate application has been submitted for {session} yet.</div></PBody>}
          </Panel>

          {open ? (() => {
            const r = view.rows.find((x) => x.id === open);
            if (!r) return null;
            return (
              <Panel title={`${r.surname}, ${r.other_names}`} right={<span className="tnum sub2">{r.application_no} · {r.programme_name}</span>}>
                <DetailPanel id={r.id} office={actingOffice} onChanged={() => router.refresh()} />
              </Panel>
            );
          })() : null}
        </>
      ) : (
        <Note kind="bad" title="The postgraduate applications could not be read">The desk reads the postgraduate admissions register; it did not answer.</Note>
      )}
    </>
  );
}
