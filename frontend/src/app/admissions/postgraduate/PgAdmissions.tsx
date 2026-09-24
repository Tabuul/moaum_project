"use client";

/** The postgraduate admissions desks (V202): the department's committee recommends a submitted
 *  application, the School of Postgraduate Studies offers or refuses, the applicant accepts, and the
 *  School admits — which puts the student on the register. Separate from the JAMB/CAPS flow. */
import { useEffect, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, RoleLine, Tiles, Two } from "@/components/proto/ui";
import { Modal } from "@/components/proto/blocks";
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
export interface PgView { session: string; counts: { total: number; submitted: number; recommended: number; faculty: number; offered: number; accepted: number; admitted: number }; rows: PgRow[] }
interface Referee { id: string; name: string; email: string | null; phone: string | null; institution: string | null; position: string | null; reference_text: string | null; submitted_at: string | null; relationship: string | null; known_duration: string | null; attestation: string | null; recommendation: string | null; verdict: string | null }
const VERDICT_LABEL: Record<string, string> = { RECOMMEND: "Recommended", RECOMMEND_WITH_RESERVATION: "Recommended with reservation", DO_NOT_RECOMMEND: "Not recommended" };
interface DocMeta { id: string; kind: string; filename: string; content_type: string; uploaded_at: string }
interface PriorQual { kind: string; institution: string | null; award: string | null; field: string | null; class_of_degree: string | null; cgpa: number | null; year: number | null }
interface Detail { found: boolean; application?: PgRow & { sex: string | null; date_of_birth: string | null; lga: string | null; prior_year: number | null; proposal_title: string | null; proposal_text: string | null; dept_note: string | null; fac_note: string | null; fac_decided_at: string | null; spgs_note: string | null }; referees?: Referee[]; priorDegrees?: PriorQual[]; documents?: DocMeta[] }
const QUAL_LABEL: Record<string, string> = {
  FIRST: "First degree", MASTERS: "Master’s degree", PGD: "Postgraduate Diploma", HND: "Higher National Diploma",
  ND: "National Diploma", NCE: "Nigeria Certificate in Education", PHD: "Doctorate (PhD)", OTHER: "Other qualification",
};

const STATE: Record<string, { kind: "ok" | "bad" | "warn" | "info" | "grey"; label: string }> = {
  DRAFT: { kind: "grey", label: "Draft" },
  SUBMITTED: { kind: "info", label: "Submitted" },
  DEPT_RECOMMENDED: { kind: "info", label: "Dept recommended" },
  DEPT_DECLINED: { kind: "grey", label: "Dept declined" },
  FAC_RECOMMENDED: { kind: "info", label: "Faculty recommended" },
  FAC_DECLINED: { kind: "grey", label: "Faculty declined" },
  OFFERED: { kind: "ok", label: "Offered" },
  NOT_OFFERED: { kind: "grey", label: "Not offered" },
  ACCEPTED: { kind: "ok", label: "Accepted" },
  ADMITTED: { kind: "ok", label: "Admitted" },
};
const isDept = (o: string | null) => ["hod", "academic", "super"].includes(o ?? "");
const isFaculty = (o: string | null) => ["dean", "academic", "super"].includes(o ?? "");
const isSpgs = (o: string | null) => ["pgschool", "pgsecretary", "super"].includes(o ?? "");
const mayAdmit = (o: string | null) => ["pgschool", "pgsecretary", "registrar", "super"].includes(o ?? "");
const fmtDate = (v: string | null | undefined) => { if (!v) return "—"; const d = new Date(v); return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" }); };
const sexLabel = (v: string | null | undefined) => (v === "F" ? "Female" : v === "M" ? "Male" : "—");

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div>
      <div className="eyebrow ink-chrome" style={{ borderBottom: "2px solid var(--line-2)", paddingBottom: 5, marginBottom: "var(--s-2)" }}>{title}</div>
      {children}
    </div>
  );
}
function Kv({ k, v }: { k: string; v: string }) {
  return (
    <div className="row row--base" style={{ gap: "var(--s-4)", padding: "6px 0", borderBottom: "1px solid var(--line-2)" }}>
      <span className="sub2" style={{ minWidth: 150, textTransform: "uppercase", letterSpacing: ".04em", fontSize: "var(--t-xs)" }}>{k}</span>
      <span className="b600" style={{ fontSize: "var(--t-base)" }}>{v}</span>
    </div>
  );
}

function DetailPanel({ id, office, onChanged }: { id: string; office: string | null; onChanged: () => void }) {
  const [d, setD] = useState<Detail | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [note, setNote] = useState("");
  /* a document opened in a modal viewer on this page, rather than in a new tab */
  const [viewing, setViewing] = useState<{ url: string; title: string; image: boolean } | null>(null);

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
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      notify(label);
      setD(j && (j as Detail).found ? (j as Detail) : d);
      onChanged();
    } finally { setBusy(null); }
  }

  if (!d) return <PBody><div className="sub2">Loading the application…</div></PBody>;
  if (!d.found || !d.application) return <PBody><div className="sub2">This application could not be read.</div></PBody>;
  const a = d.application;
  const st = a.state;
  const docUrl = (docId: string) => `/api/bff/api/v1/pg/applications/${id}/documents/${docId}`;
  const passport = (d.documents ?? []).find((x) => x.kind === "PASSPORT") ?? null;
  const otherDocs = (d.documents ?? []).filter((x) => x.kind !== "PASSPORT");
  const quals: PriorQual[] = (d.priorDegrees ?? []).length
    ? (d.priorDegrees ?? [])
    : [{ kind: "FIRST", institution: a.prior_institution, award: a.prior_award, field: null, class_of_degree: a.prior_class, cgpa: a.prior_cgpa, year: a.prior_year } as PriorQual];
  return (
    <PBody style={{ gap: "var(--s-5)" }}>
      {problem ? <ProblemNotice problem={problem} /> : null}

      {/* identity, with the passport shown as a photograph */}
      <div className="row row--top" style={{ gap: "var(--s-5)" }}>
        {passport ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={docUrl(passport.id)} alt="Passport photograph" style={{ width: 108, height: 132, objectFit: "cover", borderRadius: "var(--r-md)", border: "1px solid var(--line-2)" }} />
        ) : (
          <div className="sub2" style={{ width: 108, height: 132, borderRadius: "var(--r-md)", border: "1px dashed var(--line-2)", display: "grid", placeItems: "center", textAlign: "center", padding: "var(--s-2)" }}>No passport uploaded</div>
        )}
        <div style={{ minWidth: 0 }}>
          <div className="b700 t-lg">{a.surname}, {a.other_names}</div>
          <div className="sub2 mt-1">{a.application_no} · {a.programme_name}{a.pg_award ? ` (${a.pg_award})` : ""}</div>
          <div className="sub2">{a.email}{a.phone ? ` · ${a.phone}` : ""}</div>
        </div>
      </div>

      <Section title="Bio-data">
        <Kv k="Surname" v={a.surname} />
        <Kv k="Other names" v={a.other_names} />
        <Kv k="Sex" v={sexLabel(a.sex)} />
        <Kv k="Date of birth" v={fmtDate(a.date_of_birth)} />
        <Kv k="State of origin" v={a.state_of_origin ?? "—"} />
        <Kv k="LGA" v={a.lga ?? "—"} />
        <Kv k="Email" v={a.email} />
        <Kv k="Phone" v={a.phone ?? "—"} />
      </Section>

      <Section title="Institutions attended">
        <div className="stack">
          {quals.map((q, i) => (
            <div key={i} style={{ border: "1px solid var(--line-2)", borderRadius: "var(--r-md)", padding: "var(--s-2) var(--s-3)" }}>
              <div className="b600" style={{ fontSize: "var(--t-base)" }}>
                {QUAL_LABEL[q.kind] ?? q.kind}{q.award ? ` — ${q.award}` : ""}{q.field ? ` (${q.field})` : ""}
              </div>
              <div className="sub2 mt-1">
                {[q.institution, q.class_of_degree, q.cgpa != null ? `CGPA ${q.cgpa}` : null, q.year != null ? String(q.year) : null].filter(Boolean).join(" · ") || "—"}
              </div>
            </div>
          ))}
        </div>
      </Section>

      {a.pg_research ? (
        <Section title="Research proposal">
          <div className="b600">{a.proposal_title || "—"}</div>
          {a.proposal_text ? <div className="sub2 mt-1" style={{ lineHeight: 1.5 }}>{a.proposal_text}</div> : null}
        </Section>
      ) : null}

      <Section title="Referees">
        {(d.referees ?? []).length ? (d.referees ?? []).map((r) => (
          <div key={r.id} className="mb-2" style={{ paddingBottom: "var(--s-2)", borderBottom: "1px solid var(--line-2)" }}>
            <div className="sub2"><b>{r.name}</b>{r.position ? ` · ${r.position}` : ""}{r.institution ? ` · ${r.institution}` : ""}</div>
            <div className="sub2">{r.email ? `${r.email}` : ""}{r.phone ? ` · ${r.phone}` : ""}</div>
            {r.submitted_at ? (
              <div className="mt-2" style={{ paddingLeft: "var(--s-2)", borderLeft: "3px solid var(--green-ink)" }}>
                <div className="sub2 ink-green b600">
                  Reference received{r.verdict ? ` · ${VERDICT_LABEL[r.verdict] ?? r.verdict}` : ""}
                </div>
                {r.relationship ? <div className="sub2"><b>Relationship:</b> {r.relationship}{r.known_duration ? ` · known ${r.known_duration}` : ""}</div> : null}
                {r.attestation ? <div className="sub2 mt-1" style={{ whiteSpace: "pre-wrap" }}><b>Attestation:</b> {r.attestation}</div> : null}
                {r.recommendation ? <div className="sub2 mt-1" style={{ whiteSpace: "pre-wrap" }}><b>Recommendation:</b> {r.recommendation}</div> : null}
              </div>
            ) : <div className="sub2 ink-chrome">Reference not yet submitted{r.email ? " — a request was emailed" : " (no email on record)"}.</div>}
          </div>
        )) : <div className="sub2">None named.</div>}
      </Section>

      <Section title="Documents">
        {otherDocs.length || passport ? (
          <div className="stack">
            <div className="row mb-1">
              <Btn kind="primary" onClick={() => setViewing({ url: `/api/bff/api/v1/pg/applications/${id}/documents.pdf`, title: "All documents — one PDF", image: false })}>View all as one PDF</Btn>
              <a href={`/api/bff/api/v1/pg/applications/${id}/documents.pdf`} download className="btn btn--ghost btn--sm">Download</a>
            </div>
            {passport ? (
              <div className="sub2 row">
                <span>passport — {passport.filename}</span>
                <Btn kind="ghost" onClick={() => setViewing({ url: docUrl(passport.id), title: `Passport — ${passport.filename}`, image: true })}>View</Btn>
              </div>
            ) : null}
            {otherDocs.map((x) => (
              <div key={x.id} className="sub2 row">
                <span>{x.kind.replace(/_/g, " ").toLowerCase()} — {x.filename}</span>
                <Btn kind="ghost" onClick={() => setViewing({ url: docUrl(x.id), title: `${x.kind.replace(/_/g, " ").toLowerCase()} — ${x.filename}`, image: false })}>View PDF</Btn>
              </div>
            ))}
          </div>
        ) : <div className="sub2">No documents uploaded yet.</div>}
      </Section>

      {viewing ? (
        <Modal title={viewing.title} sub="Opens here; close to return to the application" wide onClose={() => setViewing(null)}
          foot={<><a href={viewing.url} download className="btn btn--ghost btn--sm">Download</a><span className="grow" /><Btn kind="primary" onClick={() => setViewing(null)}>Close</Btn></>}>
          {viewing.image ? (
            <div style={{ display: "flex", justifyContent: "center" }}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={viewing.url} alt={viewing.title} style={{ maxWidth: "100%", maxHeight: "70vh", borderRadius: "var(--r-md)", border: "1px solid var(--line-2)" }} />
            </div>
          ) : (
            <iframe src={viewing.url} title={viewing.title} style={{ width: "100%", height: "72vh", border: "1px solid var(--line-2)", borderRadius: "var(--r-md)", background: "var(--surface)" }} />
          )}
        </Modal>
      ) : null}

      {a.dept_note ? <Note kind="info" title="Department note">{a.dept_note}</Note> : null}
      {a.fac_note ? <Note kind="info" title="Faculty note">{a.fac_note}</Note> : null}
      {a.spgs_note ? <Note kind="info" title="School note">{a.spgs_note}</Note> : null}

      {(isDept(office) && st === "SUBMITTED") || (isFaculty(office) && st === "DEPT_RECOMMENDED") || (isSpgs(office) && st === "FAC_RECOMMENDED") ? (
        <div>
          <textarea className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} placeholder="A note for the decision (optional)" />
        </div>
      ) : null}

      <div className="row">
        {isDept(office) && st === "SUBMITTED" ? (
          <>
            <Btn kind="primary" disabled={busy !== null} onClick={() => void act("dept-decision", `Department recommended ${a.surname}, ${a.other_names} for ${a.programme_name}`, { recommend: true, note })}>Department: recommend</Btn>
            <Btn kind="ghost" disabled={busy !== null} onClick={() => void act("dept-decision", `Department declined ${a.surname}, ${a.other_names}`, { recommend: false, note })}>Decline</Btn>
          </>
        ) : null}
        {isFaculty(office) && st === "DEPT_RECOMMENDED" ? (
          <>
            <Btn kind="primary" disabled={busy !== null} onClick={() => void act("faculty-decision", `Faculty recommended ${a.surname}, ${a.other_names} for ${a.programme_name}`, { recommend: true, note })}>Faculty: recommend</Btn>
            <Btn kind="ghost" disabled={busy !== null} onClick={() => void act("faculty-decision", `Faculty declined ${a.surname}, ${a.other_names}`, { recommend: false, note })}>Decline</Btn>
          </>
        ) : null}
        {isSpgs(office) && st === "FAC_RECOMMENDED" ? (
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
        {st === "ADMITTED" ? <span className="sub2 ink-green" style={{ alignSelf: "center" }}>Admitted &mdash; on the register, awaiting matriculation on fees and registration.</span> : null}
        {busy ? <span className="sub2" style={{ alignSelf: "center" }}>Working…</span> : null}
      </div>
    </PBody>
  );
}

export function PgAdmissions({ session, sessions = [], view, problem, actingOffice }: {
  session: string; sessions?: { name: string; state: string }[]; view: PgView | null; problem: Problem | null; actingOffice: string | null;
}) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const [open, setOpen] = useState<string | null>(null);
  const c = view?.counts;
  // the session on the desk is always among the options, even if the calendar doesn't list it yet
  const sessionOptions = sessions.some((s) => s.name === session) ? sessions : [{ name: session, state: "" }, ...sessions];
  return (
    <>
      <RoleLine allowed={["pgschool", "pgsecretary", "hod", "dean", "academic", "registrar"]} actingOffice={actingOffice}
        action="Deciding postgraduate admissions" />
      <Note kind="info" title="Postgraduate admission is decided on the record, not on a UTME score">
        A postgraduate applicant applies on a first degree — no JAMB, no UTME aggregate. The <b>department</b> recommends a submitted application, the <b>faculty</b> vets it, then the <b>School of Postgraduate Studies</b> offers or refuses; the applicant accepts, and the School admits, which puts the student on the register to be matriculated on fees and registration.
      </Note>

      <Panel title="Session" right={<span className="sub2">Applications are shown for the session you choose</span>}>
        <PBody>
          <div className="row">
            <label htmlFor="pg-session" className="sub2 b600">Admissions session</label>
            <select id="pg-session" className="ctl" style={{ maxWidth: 260 }} value={session}
              onChange={(e) => queryNav(`/admissions/postgraduate?session=${encodeURIComponent(e.target.value)}`)}>
              {sessionOptions.map((s) => (
                <option key={s.name} value={s.name}>{s.name}{s.state === "CURRENT" ? " · current" : s.state === "PLANNED" ? " · planned" : ""}</option>
              ))}
            </select>
          </div>
        </PBody>
      </Panel>

      {problem ? <ProblemNotice problem={problem} /> : null}

      {view ? (
        <>
          <Tiles items={[
            ["Applications", String(c?.total ?? 0), null, session],
            ["Submitted", String(c?.submitted ?? 0), Number(c?.submitted) ? "var(--chrome)" : null, "Awaiting the department"],
            ["Dept recommended", String(c?.recommended ?? 0), Number(c?.recommended) ? "var(--chrome)" : null, "Awaiting the faculty"],
            ["Faculty recommended", String(c?.faculty ?? 0), Number(c?.faculty) ? "var(--chrome)" : null, "Awaiting the School"],
            ["Offered", String(c?.offered ?? 0), Number(c?.offered) ? "var(--green-ink)" : null, "Awaiting acceptance"],
            ["Admitted", String(c?.admitted ?? 0), Number(c?.admitted) ? "var(--green-ink)" : null, "On the register"],
          ]} cls="grid--3" />

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
