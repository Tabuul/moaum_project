"use client";

/** tRecruit — recruitment: the office opens a vacancy, records applications, scores them
 *  against the advertised criteria, shortlists, interviews and offers. The shortlist is
 *  scored, not argued. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Vacancy {
  id: string; title: string; department: string; requirements: string; grade: string | null; category: string | null;
  opened_on: string; closes_on: string | null; state: string; note: string | null; applications: number; shortlisted: number;
}
interface App {
  id: string; name: string; email: string | null; phone: string | null; qualification: string | null;
  publications: number | null; teaching_years: number | null; score: number | null; recommendation: string | null; state: string; applied_at: string;
}
export interface Applicants { vacancy: { id: string; title: string; department: string; requirements: string; grade: string | null; state: string }; rows: App[] }

const VSTATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  OPEN: ["ok", "Open"], SHORTLISTING: ["info", "Shortlisting"], INTERVIEW: ["info", "Interview"], OFFER: ["info", "Offer"], CLOSED: ["grey", "Closed"], CANCELLED: ["grey", "Cancelled"],
};
const ASTATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  APPLIED: ["grey", "Applied"], SHORTLISTED: ["ok", "Shortlisted"], RESERVE: ["info", "Reserve"], REJECTED: ["bad", "Rejected"], INVITED: ["info", "Invited"], OFFERED: ["ok", "Offered"], DECLINED: ["grey", "Declined"], APPOINTED: ["ok", "Appointed"],
};

export function Recruitment({ rows, applicants, actingOffice }: { rows: Vacancy[]; applicants: Applicants | null; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["hrm", "registrar", "super"].includes(actingOffice ?? "");
  const [v, setV] = useState({ title: "", department: "", requirements: "", grade: "", category: "", closesOn: "" });
  const [ap, setAp] = useState({ name: "", email: "", phone: "", qualification: "", publications: "", teachingYears: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/hr${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  if (applicants) {
    const a = applicants;
    return (
      <>
        {said ? <Note kind="ok" title={said}>On the record.</Note> : null}
        {err ? <ProblemNotice problem={err} /> : null}
        <div style={{ marginBottom: 10 }}><Link href="/hr/recruitment" className="btn btn--ghost btn--sm">← All vacancies</Link></div>
        <Panel title={a.vacancy.title} right={`${a.vacancy.department} · ${a.vacancy.grade ?? ""}`}>
          <PBody><div className="sub2"><b>Advertised criteria:</b> {a.vacancy.requirements}</div></PBody>
          {a.rows.length ? (
            <DTable cols={["Candidate", "Qualification", "Pubs|num", "Teaching|num", "Score|num", "Stage", "Action|num"]} rows={a.rows.map((r) => [
              <span key="n">{r.name}<div className="sub2">{[r.email, r.phone].filter(Boolean).join(" · ")}</div></span>,
              <span className="sub2" key="q">{r.qualification ?? "—"}</span>,
              <span className="tnum sub2" key="p">{r.publications ?? "—"}</span>,
              <span className="tnum sub2" key="t">{r.teaching_years ?? "—"}</span>,
              <b className="tnum" key="sc">{r.score ?? "—"}</b>,
              <span key="st"><Pil kind={ASTATE[r.state]?.[0] ?? "grey"}>{ASTATE[r.state]?.[1] ?? r.state}</Pil>{r.recommendation ? <div className="sub2">{r.recommendation}</div> : null}</span>,
              <span key="ac" style={{ display: "inline-flex", gap: 6, flexWrap: "wrap", justifyContent: "flex-end" }}>
                {may ? <Btn kind="ghost" disabled={busy} onClick={() => { const s = window.prompt("Score (0–100)", r.score != null ? String(r.score) : ""); if (s === null) return; const rec = window.prompt("Recommendation (e.g. Invite, Reserve)") ?? ""; void send(`/applicants/${r.id}/assess`, { score: s ? Number(s) : null, recommendation: rec || null }, `Score ${r.name}`).then((j) => { if (j) setSaid(`${r.name} scored`); }); }}>Score</Btn> : null}
                {may ? <Btn kind="go" disabled={busy} onClick={() => void send(`/applicants/${r.id}/assess`, { state: "SHORTLISTED" }, `Shortlist ${r.name}`).then((j) => { if (j) setSaid(`${r.name} shortlisted`); })}>Shortlist</Btn> : null}
              </span>,
            ])} texts={a.rows.map((r) => `${r.name} ${r.qualification ?? ""} ${r.state}`)} />
          ) : <PBody><div className="sub2">No application recorded for this post yet.</div></PBody>}
        </Panel>
        {may ? (
          <Panel title="Record an application" right="As received on paper or by e-mail">
            <PBody>
              <div className="grid grid--2">
                <Field id="ap-name" label="Candidate name"><input id="ap-name" className="ctl" value={ap.name} onChange={(e) => setAp({ ...ap, name: e.target.value })} /></Field>
                <Field id="ap-qual" label="Qualification"><input id="ap-qual" className="ctl" value={ap.qualification} onChange={(e) => setAp({ ...ap, qualification: e.target.value })} placeholder="Ph.D Computer Science, 2023" /></Field>
              </div>
              <div className="grid grid--2">
                <Field id="ap-email" label="E-mail" hint="Optional"><input id="ap-email" className="ctl" value={ap.email} onChange={(e) => setAp({ ...ap, email: e.target.value })} /></Field>
                <Field id="ap-phone" label="Phone" hint="Optional"><input id="ap-phone" className="ctl tnum" value={ap.phone} onChange={(e) => setAp({ ...ap, phone: e.target.value })} /></Field>
              </div>
              <div className="grid grid--2">
                <Field id="ap-pub" label="Publications" hint="Optional"><input id="ap-pub" className="ctl tnum" inputMode="numeric" value={ap.publications} onChange={(e) => setAp({ ...ap, publications: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
                <Field id="ap-ty" label="Teaching years" hint="Optional"><input id="ap-ty" className="ctl tnum" inputMode="decimal" value={ap.teachingYears} onChange={(e) => setAp({ ...ap, teachingYears: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
              </div>
              <div><Btn kind="primary" disabled={busy || !ap.name.trim()} onClick={async () => { const j = await send(`/vacancies/${a.vacancy.id}/applicants`, { name: ap.name.trim(), email: ap.email || null, phone: ap.phone || null, qualification: ap.qualification || null, publications: ap.publications ? Number(ap.publications) : null, teachingYears: ap.teachingYears ? Number(ap.teachingYears) : null }, `Record applicant ${ap.name.trim()}`); if (j) { setSaid("Application recorded"); setAp({ name: "", email: "", phone: "", qualification: "", publications: "", teachingYears: "" }); } }}>Record the application</Btn></div>
            </PBody>
          </Panel>
        ) : null}
      </>
    );
  }

  const open = rows.filter((r) => ["OPEN", "SHORTLISTING", "INTERVIEW", "OFFER"].includes(r.state)).length;
  return (
    <>
      {said ? <Note kind="ok" title={said}>On the record.</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}
      <Tiles items={[
        ["Open vacancies", String(open), open ? "var(--chrome)" : null, "Advertised and live"],
        ["Applications", String(rows.reduce((n, r) => n + Number(r.applications), 0)), null, "Across all posts"],
        ["Shortlisted", String(rows.reduce((n, r) => n + Number(r.shortlisted), 0)), null, "Meeting the criteria"],
        ["Posts", String(rows.length), null, "All"],
      ]} />
      <Panel title="Vacancies" right={may ? undefined : "You are reading these posts"}>
        {rows.length ? (
          <DTable cols={["Post", "Department", "Applications|num", "State", "Action|num"]} rows={rows.map((r) => [
            <Two key="p" a={r.title} b={[r.grade, r.category === "ACADEMIC" ? "Academic" : r.category === "NON_ACADEMIC" ? "Non-academic" : null].filter(Boolean).join(" · ")} />,
            <span className="sub2" key="d">{r.department}</span>,
            <span className="tnum" key="a">{r.applications}<span className="sub2"> · {r.shortlisted} shortlisted</span></span>,
            <span key="s"><Pil kind={VSTATE[r.state]?.[0] ?? "grey"}>{VSTATE[r.state]?.[1] ?? r.state}</Pil>{r.closes_on ? <div className="sub2 tnum">closes {day(r.closes_on)}</div> : null}</span>,
            <span key="ac" style={{ display: "inline-flex", gap: 6, flexWrap: "wrap", justifyContent: "flex-end" }}>
              <Link href={`/hr/recruitment?vacancy=${r.id}`} className="btn btn--primary btn--sm">Open</Link>
              {may && r.state !== "CLOSED" && r.state !== "CANCELLED" ? <Btn kind="ghost" disabled={busy} onClick={() => { const s = window.prompt("Set state: OPEN, SHORTLISTING, INTERVIEW, OFFER, CLOSED, CANCELLED", r.state); if (s && s.trim()) void send(`/vacancies/${r.id}/state`, { state: s.trim() }, `Set ${r.title} to ${s.trim()}`); }}>State</Btn> : null}
            </span>,
          ])} texts={rows.map((r) => `${r.title} ${r.department} ${r.state}`)} />
        ) : <PBody><div className="sub2">No vacancy advertised.</div></PBody>}
      </Panel>
      {may ? (
        <Panel title="Advertise a vacancy" right="The criteria here are what applications are scored against">
          <PBody>
            <div className="grid grid--2">
              <Field id="v-title" label="Post"><input id="v-title" className="ctl" value={v.title} onChange={(e) => setV({ ...v, title: e.target.value })} placeholder="Lecturer II — Computer Science" /></Field>
              <Field id="v-dept" label="Department"><input id="v-dept" className="ctl" value={v.department} onChange={(e) => setV({ ...v, department: e.target.value })} /></Field>
            </div>
            <Field id="v-req" label="Advertised criteria"><textarea id="v-req" className="ctl" rows={2} value={v.requirements} onChange={(e) => setV({ ...v, requirements: e.target.value })} placeholder="Ph.D required · CONUASS 03 · publications in accredited outlets" /></Field>
            <div className="grid grid--3">
              <Field id="v-grade" label="Grade" hint="Optional"><input id="v-grade" className="ctl tnum" value={v.grade} onChange={(e) => setV({ ...v, grade: e.target.value })} placeholder="CONUASS 3" /></Field>
              <Field id="v-cat" label="Category"><select id="v-cat" className="ctl" value={v.category} onChange={(e) => setV({ ...v, category: e.target.value })}><option value="">—</option><option value="ACADEMIC">Academic</option><option value="NON_ACADEMIC">Non-academic</option></select></Field>
              <Field id="v-closes" label="Closes on" hint="Optional"><input id="v-closes" className="ctl" type="date" value={v.closesOn} onChange={(e) => setV({ ...v, closesOn: e.target.value })} /></Field>
            </div>
            <div><Btn kind="primary" disabled={busy || !v.title.trim() || !v.department.trim() || !v.requirements.trim()} onClick={async () => { const j = await send("/vacancies", { title: v.title.trim(), department: v.department.trim(), requirements: v.requirements.trim(), grade: v.grade || null, category: v.category || null, closesOn: v.closesOn || null }, `Advertise ${v.title.trim()}`); if (j) { setSaid("Vacancy advertised"); setV({ title: "", department: "", requirements: "", grade: "", category: "", closesOn: "" }); } }}>Advertise the post</Btn></div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
