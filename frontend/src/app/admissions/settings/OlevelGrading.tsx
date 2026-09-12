"use client";

/**
 * The O'Level grading — the Academic Office's rule for what a grade is
 * worth, how many subjects count, and the bonus for one or two sittings
 * (V020). Stated per session and recorded against the office; read under
 * the defaults the Office first gave until it is stated.
 */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, IcoBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Grading {
  session: string;
  stated: boolean;
  subjectsCounted: number;
  bonusOneSitting: number;
  bonusTwoSittings: number;
  points: Record<string, number>;
  /** the programmes screened by the post-UTME examination alone, to which this grading does not apply (V022) */
  examProgrammes: string[];
}

interface ProgrammeLine { code: string; name: string; facultyName?: string; archived: boolean }

const GRADES = ["A1", "B2", "B3", "C4", "C5", "C6", "D7", "E8", "F9"];

export function OlevelGrading({ session, may }: { session: string; may: boolean }) {
  const router = useRouter();
  const [grading, setGrading] = useState<Grading | null>(null);
  const [edits, setEdits] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [programmes, setProgrammes] = useState<ProgrammeLine[]>([]);
  const [exam, setExam] = useState<string[] | null>(null);
  const [pick, setPick] = useState("");
  const path = `/api/bff/api/v1/admissions/sessions/${session}/olevel-grading`;

  useEffect(() => {
    let live = true;
    (async () => {
      const [r, p] = await Promise.all([fetch(path, { cache: "no-store" }), fetch("/api/bff/api/v1/admissions/programmes", { cache: "no-store" })]);
      const body = await r.json().catch(() => null);
      const list = await p.json().catch(() => null);
      if (!live) return;
      if (r.ok) setGrading(body as Grading);
      else setProblem(body && typeof body === "object" && "status" in body ? (body as Problem) : { status: r.status, title: r.statusText });
      if (p.ok && Array.isArray(list)) setProgrammes((list as ProgrammeLine[]).filter((x) => !x.archived));
    })();
    return () => { live = false; };
  }, [path]);
  const examCodes = exam ?? grading?.examProgrammes ?? [];
  const examDirty = exam !== null && JSON.stringify([...exam].sort()) !== JSON.stringify([...(grading?.examProgrammes ?? [])].sort());

  const val = (key: string, current: number) => (key in edits ? edits[key] : String(current));
  const n = (key: string, current: number) => {
    const v = parseInt(val(key, current), 10);
    return Number.isFinite(v) ? v : current;
  };
  const dirty = Object.keys(edits).length > 0 || examDirty;

  async function save() {
    if (!grading) return;
    setBusy(true);
    setProblem(null);
    try {
      const body = {
        subjectsCounted: n("counted", grading.subjectsCounted),
        bonusOneSitting: n("one", grading.bonusOneSitting),
        bonusTwoSittings: n("two", grading.bonusTwoSittings),
        points: Object.fromEntries(GRADES.map((g) => [g, n(`p-${g}`, grading.points[g] ?? 0)])),
        examProgrammes: examCodes,
      };
      const r = await fetch(path, {
        method: "PUT",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`O'Level grading stated for ${session}`) },
        body: JSON.stringify(body),
      });
      const json = await r.json().catch(() => null);
      if (r.ok) {
        setGrading(json as Grading);
        setEdits({});
        setExam(null);
        router.refresh();
      } else {
        setProblem(json && typeof json === "object" && "status" in json ? (json as Problem) : { status: r.status, title: r.statusText });
      }
    } finally {
      setBusy(false);
    }
  }

  const input = (key: string, current: number, width = 64) => (
    <input className="tnum ws__in" style={{ width }} value={val(key, current)} disabled={!may} inputMode="numeric"
      onChange={(e) => setEdits({ ...edits, [key]: e.target.value })} aria-label={key} />
  );

  return (
    <Panel
      title="O’Level grading for the screening score"
      right={grading ? (grading.stated ? <Pil kind="ok">Stated for {session}</Pil> : <Pil kind="info">Defaults · not yet stated for {session}</Pil>) : "reading…"}
    >
      <PBody>
        <div className="sub2" style={{ marginBottom: 10 }}>
          JAMB uploads each candidate&rsquo;s O&rsquo;Level results, one or two sittings of WAEC, NECO or NABTEB. The screening prices each grade,
          counts the subjects most relevant to the programme &mdash; the better grade in a subject sat twice &mdash; and adds a bonus for how many
          sittings it took. <b>These numbers are the Academic Office&rsquo;s to state</b>, per session, and are recorded against it. The score is
          computed under them and shown to the Academic Office only; the applicant sees the results as JAMB sent them, never the score.
        </div>
        {problem ? <ProblemNotice problem={problem} /> : null}
        {grading ? (
          <>
            <DTable
              cols={["Grade", "Points|mid", "", "Rule", "Value|mid"]}
              rows={GRADES.map((g, i) => {
                const rule = i === 0 ? ["Subjects counted", input("counted", grading.subjectsCounted)]
                  : i === 1 ? ["Bonus · one sitting", input("one", grading.bonusOneSitting)]
                  : i === 2 ? ["Bonus · two sittings combined", input("two", grading.bonusTwoSittings)]
                  : ["", null];
                return [
                  <b key="g" className="tnum">{g}</b>,
                  <span key="p">{input(`p-${g}`, grading.points[g] ?? 0)}</span>,
                  <span key="x" />,
                  <span key="r" className={rule[0] ? "" : "sub2"}>{rule[0]}</span>,
                  <span key="v">{rule[1]}</span>,
                ];
              })}
            />
            <div style={{ display: "flex", alignItems: "center", gap: 9, marginTop: 10, flexWrap: "wrap" }}>
              <Btn kind="primary" disabled={!may || !dirty || busy} onClick={() => void save()}>{busy ? "Saving…" : `State the grading for ${session}`}</Btn>
              {dirty ? <Btn kind="ghost" disabled={busy} onClick={() => { setEdits({}); setExam(null); }}>Discard</Btn> : null}
              {!may ? <span className="sub2">The grading is stated by the Academic Office or the Registrar.</span> : null}
            </div>
            <div style={{ marginTop: 14 }}>
              <div className="eyebrow">Programmes screened by the post-UTME examination</div>
              <div className="sub2" style={{ margin: "4px 0 8px" }}>
                The departments named here sit the examination. Their candidates are scored on the examination alone, and the O&rsquo;Level grading above is not applied to them. Every other programme is screened on its O&rsquo;Level results.
              </div>
              <DTable cols={["Programme", "Faculty", "|num"]} rows={examCodes.map((code) => {
                const p = programmes.find((x) => x.code === code);
                return [
                  <strong key="p">{p ? p.name : code}</strong>,
                  <span className="sub2" key="f">{p?.facultyName ?? ""}</span>,
                  <IcoBtn key="x" icon="trash" label={`Remove ${p ? p.name : code} from examination screening`} danger disabled={!may} onClick={() => setExam(examCodes.filter((c) => c !== code))} />,
                ];
              })} />
              {!examCodes.length ? <div className="sub2" style={{ marginBottom: 8 }}>No programme is screened by examination this session; every programme is screened on its O&rsquo;Level results.</div> : null}
              <div style={{ display: "flex", gap: 9, flexWrap: "wrap", alignItems: "center" }}>
                <select className="ws__select" style={{ maxWidth: 460 }} value={pick} disabled={!may} onChange={(e) => setPick(e.target.value)} aria-label="Programme to add">
                  <option value="">Add a programme that sits the examination…</option>
                  {programmes.filter((p) => !examCodes.includes(p.code)).map((p) => <option key={p.code} value={p.code}>{p.code} · {p.name}{p.facultyName ? ` · ${p.facultyName}` : ""}</option>)}
                </select>
                <Btn kind="ghost" disabled={!may || !pick} onClick={() => { setExam([...examCodes, pick]); setPick(""); }}>Add</Btn>
                {examDirty ? <span className="sub2">Press <b>State the grading</b> to record the change.</span> : null}
              </div>
            </div>
            <Note kind="info" title="Worked example under these numbers">
              Two sittings, best grades A1, B2, B3, B3 and C4 in the five relevant subjects:{" "}
              <b className="tnum">{[n("p-A1", grading.points.A1 ?? 0), n("p-B2", grading.points.B2 ?? 0), n("p-B3", grading.points.B3 ?? 0), n("p-B3", grading.points.B3 ?? 0), n("p-C4", grading.points.C4 ?? 0)].reduce((a, b) => a + b, 0)}</b> points
              and the two-sitting bonus of <b className="tnum">{n("two", grading.bonusTwoSittings)}</b>. The same grades in one sitting earn the one-sitting bonus of <b className="tnum">{n("one", grading.bonusOneSitting)}</b> instead.
            </Note>
          </>
        ) : null}
      </PBody>
    </Panel>
  );
}
