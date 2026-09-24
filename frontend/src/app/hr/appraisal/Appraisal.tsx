"use client";

/** tAppraisal — appraisal and promotion eligibility. Years on grade are computed from the
 *  record (the last promotion, or the appointment), so the committee sees the same figure
 *  every candidate sees; the APER grade and publications are captured beside it. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface PromotionRow {
  person_id: string; name: string; staff_no: string; grade: string; step: number; category: string;
  on_grade_since: string; years_on_grade: number; aper_grade: string | null; publications: number | null;
  self_score: number | null; supervisor_score: number | null; appraisal_state: string; eligible_years: boolean;
}

export function Appraisal({ cycle, rows, actingOffice }: { cycle: string; rows: PromotionRow[]; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["hrm", "registrar", "dean", "hod", "super"].includes(actingOffice ?? "");
  const [r, setR] = useState({ number: "", aperGrade: "", publications: "", selfScore: "", supervisorScore: "", note: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const eligible = rows.filter((x) => x.eligible_years).length;
  const appraised = rows.filter((x) => x.aper_grade).length;

  async function save() {
    setBusy(true);
    setErr(null);
    try {
      const res = await fetch("/api/bff/api/v1/hr/appraisal", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Record appraisal for ${r.number}`) }, body: JSON.stringify({ number: r.number.trim(), cycle, aperGrade: r.aperGrade || null, publications: r.publications ? Number(r.publications) : null, selfScore: r.selfScore ? Number(r.selfScore) : null, supervisorScore: r.supervisorScore ? Number(r.supervisorScore) : null, note: r.note || null, state: "MODERATED" }) });
      const j = await res.json().catch(() => null);
      if (!res.ok) { setErr(j ?? { status: res.status, title: res.statusText }); notifyProblem(j ?? { status: res.status, title: res.statusText }); return; }
      setSaid(`Appraisal recorded for ${r.number.trim()}`);
      notify(`Appraisal recorded for ${r.number.trim()}`);
      setR({ number: "", aperGrade: "", publications: "", selfScore: "", supervisorScore: "", note: "" });
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind="info" title="Promotion eligibility is computed, not argued">
        Years on the current grade are derived from the last promotion the record holds, or from the appointment — the committee sees the same figure every candidate sees. The APER grade and publications are recorded beside it; the minimum three years on grade is checked from the record.
      </Note>
      {said ? <Note kind="ok" title={said}>On the record.</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}
      <Tiles items={[
        ["On the establishment", String(rows.length), null, `Cycle ${cycle}`],
        ["Meet the years rule", String(eligible), eligible ? "var(--green-ink)" : null, "≥ 3 years on grade"],
        ["Appraised this cycle", String(appraised), null, `${rows.length - appraised} outstanding`],
        ["Academic", String(rows.filter((x) => x.category === "ACADEMIC").length), null, "Teaching staff"],
      ]} />
      <Panel title="Promotion candidates" right={`APER cycle ${cycle}`}>
        {rows.length ? (
          <DTable cols={["Staff", "Grade|mid", "Years on grade|num", "APER|mid", "Pubs|num", "Eligibility|num"]} rows={rows.map((x) => [
            <Two key="s" a={x.name} b={x.staff_no} />,
            <span className="sub2" key="g">{x.grade} · {x.step}<div className="sub2">{x.category === "ACADEMIC" ? "Academic" : "Non-academic"}</div></span>,
            <span className="tnum" key="y">{Number(x.years_on_grade).toFixed(1)}</span>,
            x.aper_grade ? <Pil kind={["A", "B"].includes(x.aper_grade) ? "ok" : "info"} key="a">{x.aper_grade}</Pil> : <span className="sub2" key="a">—</span>,
            <span className="tnum sub2" key="p">{x.publications ?? "—"}</span>,
            x.eligible_years ? <Pil kind="ok" key="e">Meets the years rule</Pil> : <Pil kind="bad" key="e">Short {(3 - Number(x.years_on_grade)).toFixed(1)} yrs</Pil>,
          ])} texts={rows.map((x) => `${x.name} ${x.staff_no} ${x.grade}`)} />
        ) : <PBody><div className="sub2">No active staff on the establishment.</div></PBody>}
      </Panel>
      {may ? (
        <Panel title="Record an appraisal" right="APER grade, publications and the two scores">
          <PBody>
            <div className="grid grid--3">
              <Field id="ap-num" label="Staff number"><input id="ap-num" className="ctl tnum" value={r.number} onChange={(e) => setR({ ...r, number: e.target.value })} placeholder="MOAUM/STAFF/001" /></Field>
              <Field id="ap-grade" label="APER grade"><select id="ap-grade" className="ctl" value={r.aperGrade} onChange={(e) => setR({ ...r, aperGrade: e.target.value })}><option value="">—</option>{["A", "B", "C", "D", "E"].map((g) => <option key={g} value={g}>{g}</option>)}</select></Field>
              <Field id="ap-pub" label="Publications" hint="Accredited outlets"><input id="ap-pub" className="ctl tnum" inputMode="numeric" value={r.publications} onChange={(e) => setR({ ...r, publications: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
            </div>
            <div className="grid grid--3">
              <Field id="ap-self" label="Self score" hint="0–100"><input id="ap-self" className="ctl tnum" inputMode="numeric" value={r.selfScore} onChange={(e) => setR({ ...r, selfScore: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
              <Field id="ap-sup" label="Supervisor score" hint="0–100"><input id="ap-sup" className="ctl tnum" inputMode="numeric" value={r.supervisorScore} onChange={(e) => setR({ ...r, supervisorScore: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
              <Field id="ap-note" label="Note" hint="Optional"><input id="ap-note" className="ctl" value={r.note} onChange={(e) => setR({ ...r, note: e.target.value })} /></Field>
            </div>
            <div><Btn kind="primary" disabled={busy || !r.number.trim()} onClick={() => void save()}>Record the appraisal</Btn></div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
