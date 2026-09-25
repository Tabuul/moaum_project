"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, PageHead, Panel, PBody } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ExaminerPil, dayOf, type ExaminerRow } from "@/lib/examiners";

export function Profile({ e }: { e: ExaminerRow }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [f, setF] = useState({ phone: e.phone ?? "", department: e.department ?? "", rank: e.rank ?? "", specialization: e.specialization ?? "", qualification: e.qualification ?? "", professional: e.professional ?? "", experienceYears: e.experience_years == null ? "" : String(e.experience_years), country: e.country ?? "", region: e.region ?? "", orcid: e.orcid ?? "" });
  async function save(ev: React.FormEvent) {
    ev.preventDefault();
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/examiners/me/profile", { method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Examiner profile updated") }, body: JSON.stringify({ ...f, experienceYears: f.experienceYears ? Number(f.experienceYears) : null }) });
      if (!r.ok) { const p = (await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return; }
      notify("Profile saved"); router.refresh();
    } finally { setBusy(false); }
  }
  return (
    <>
      <PageHead eyebrow="External Examiner" title={e.name} description={`${e.institution} · examiner since ${dayOf(e.activated_at ?? e.created_at)}`} actions={<ExaminerPil status={e.status} />} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Panel title="On the University's record" right="Set by the Academic Office; write to them for a change">
        <PBody><KvGrid cls="grid--3" pairs={[["Name", e.name], ["Email (your username)", e.email], ["Institution", e.institution], ["Status", <ExaminerPil key="s" status={e.status} />], ["Projects assigned", String(Number(e.assigned))], ["Submitted", String(Number(e.submitted))]]} /></PBody>
      </Panel>
      <form onSubmit={(ev) => void save(ev)}>
        <Panel title="Keep current" right="What you may edit yourself">
          <PBody>
            <div className="grid grid--3">
              <Field id="pf-phone" label="Phone"><input id="pf-phone" className="ctl" value={f.phone} onChange={(ev) => setF({ ...f, phone: ev.target.value })} /></Field>
              <Field id="pf-dept" label="Department"><input id="pf-dept" className="ctl" value={f.department} onChange={(ev) => setF({ ...f, department: ev.target.value })} /></Field>
              <Field id="pf-rank" label="Position or rank"><input id="pf-rank" className="ctl" value={f.rank} onChange={(ev) => setF({ ...f, rank: ev.target.value })} /></Field>
              <Field id="pf-spec" label="Area of specialisation"><input id="pf-spec" className="ctl" value={f.specialization} onChange={(ev) => setF({ ...f, specialization: ev.target.value })} /></Field>
              <Field id="pf-qual" label="Highest qualification"><input id="pf-qual" className="ctl" value={f.qualification} onChange={(ev) => setF({ ...f, qualification: ev.target.value })} /></Field>
              <Field id="pf-prof" label="Professional qualifications"><input id="pf-prof" className="ctl" value={f.professional} onChange={(ev) => setF({ ...f, professional: ev.target.value })} /></Field>
              <Field id="pf-years" label="Years of academic experience"><input id="pf-years" className="ctl tnum" inputMode="numeric" value={f.experienceYears} onChange={(ev) => setF({ ...f, experienceYears: ev.target.value.replace(/[^0-9]/g, "") })} /></Field>
              <Field id="pf-country" label="Country"><input id="pf-country" className="ctl" value={f.country} onChange={(ev) => setF({ ...f, country: ev.target.value })} /></Field>
              <Field id="pf-region" label="State or region"><input id="pf-region" className="ctl" value={f.region} onChange={(ev) => setF({ ...f, region: ev.target.value })} /></Field>
              <Field id="pf-orcid" label="ORCID or professional identifier"><input id="pf-orcid" className="ctl tnum" value={f.orcid} onChange={(ev) => setF({ ...f, orcid: ev.target.value })} placeholder="0000-0000-0000-0000" /></Field>
            </div>
            <div className="mt-3"><Btn kind="primary" type="submit" disabled={busy}>{busy ? "Saving…" : "Save Profile"}</Btn></div>
          </PBody>
        </Panel>
      </form>
    </>
  );
}
