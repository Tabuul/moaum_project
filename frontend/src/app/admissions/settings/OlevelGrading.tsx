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
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Grading {
  session: string;
  stated: boolean;
  subjectsCounted: number;
  bonusOneSitting: number;
  bonusTwoSittings: number;
  points: Record<string, number>;
}

const GRADES = ["A1", "B2", "B3", "C4", "C5", "C6", "D7", "E8", "F9"];

export function OlevelGrading({ session, may }: { session: string; may: boolean }) {
  const router = useRouter();
  const [grading, setGrading] = useState<Grading | null>(null);
  const [edits, setEdits] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const path = `/api/bff/api/v1/admissions/sessions/${session}/olevel-grading`;

  useEffect(() => {
    let live = true;
    (async () => {
      const r = await fetch(path, { cache: "no-store" });
      const body = await r.json().catch(() => null);
      if (!live) return;
      if (r.ok) setGrading(body as Grading);
      else setProblem(body && typeof body === "object" && "status" in body ? (body as Problem) : { status: r.status, title: r.statusText });
    })();
    return () => { live = false; };
  }, [path]);

  const val = (key: string, current: number) => (key in edits ? edits[key] : String(current));
  const n = (key: string, current: number) => {
    const v = parseInt(val(key, current), 10);
    return Number.isFinite(v) ? v : current;
  };
  const dirty = Object.keys(edits).length > 0;

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
              {dirty ? <Btn kind="ghost" disabled={busy} onClick={() => setEdits({})}>Discard</Btn> : null}
              {!may ? <span className="sub2">The grading is stated by the Academic Office or the Registrar.</span> : null}
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
