"use client";

/** V580: what correcting every waiting level would do to the current session's charges — for the Bursary before the Academic Office
 *  or the Registry corrects them. A run takes the corrections waiting as they stand and reads them behind the screens (about a
 *  minute for 10,000 on the live-shaped copy; the levels raised and undone, nothing changed); the panel shows how far it got, then
 *  the sums for the University, each faculty and each programme, and an Excel of every student. On the Bursar's fee page and on
 *  Student Cohorts → Level corrections. */
import { Fragment, useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { notifyProblem } from "@/components/proto/Toast";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

type Basis = "SPILLOVER" | "REGISTRATION" | "ARITHMETIC";
interface Run {
  id: string; session: string; basis: "LEVEL" | "COHORT"; bases: Basis[]; state: "RUNNING" | "DONE" | "FAILED"; students: number; done: number;
  error: string | null; started_at: string; finished_at: string | null; started_office: string | null; started_by: string | null;
}
interface Sum {
  scope: "UNIVERSITY" | "FACULTY" | "PROGRAMME"; faculty_code: string | null; faculty: string | null; programme_code: string | null; programme: string | null;
  students: number; charged_now: number; charged_after: number; more: number; less: number; same: number; none_after: number;
}
interface Latest { run: Run | null; waiting: { basis: Basis; students: number }[]; report?: Sum[] }
interface Row {
  student_id: string; name: string; number: string | null; faculty: string | null; programme: string | null; basis: Basis;
  current_level: number | null; new_level: number | null; charged_now: number; charged_after: number;
}

const URL_ = "/api/bff/api/v1/finance/level-fee-effect";
const WORD: Record<Basis, string> = { SPILLOVER: "spillover", REGISTRATION: "own registration", ARITHMETIC: "sessions counted" };
const fmt = (n: number) => Number(n ?? 0).toLocaleString("en-NG");
const naira = (n: number) => `₦${Number(n ?? 0).toLocaleString("en-NG", { maximumFractionDigits: 2 })}`;
const day = (s: string) => new Date(s).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
const signed = (n: number) => `${n >= 0 ? "+" : "−"}${naira(Math.abs(n))}`;

export function LevelFeeEffectRun({ mayStart }: { mayStart: boolean }) {
  const [data, setData] = useState<Latest | null>(null);
  const [withArithmetic, setWithArithmetic] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [open, setOpen] = useState<Set<string>>(new Set());
  const [tick, setTick] = useState(0);

  useEffect(() => {
    let alive = true;
    void fetch(URL_, { cache: "no-store" }).then(async (r) => { if (alive && r.ok) setData((await r.json()) as Latest); });
    return () => { alive = false; };
  }, [tick]);
  // while a run is being read, how far it got every three seconds
  const running = data?.run?.state === "RUNNING";
  useEffect(() => {
    if (!running) return;
    const t = setInterval(() => setTick((n) => n + 1), 3000);
    return () => clearInterval(t);
  }, [running]);

  if (!data) return null;
  const run = data.run;
  const waiting = (b: Basis) => Number(data.waiting.find((w) => w.basis === b)?.students ?? 0);
  const all = data.waiting.reduce((n, w) => n + Number(w.students), 0);

  async function start() {
    setBusy("start");
    try {
      const bases: Basis[] = withArithmetic ? ["SPILLOVER", "REGISTRATION", "ARITHMETIC"] : ["SPILLOVER", "REGISTRATION"];
      const r = await fetch(URL_, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("The fee effect of the waiting level corrections worked out") },
        body: JSON.stringify({ bases }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: "The fee effect could not be started just now." }); return; }
      setTick((n) => n + 1);
    } finally { setBusy(null); }
  }

  async function excelStudents() {
    if (!run) return;
    const r = await fetch(`${URL_}/${run.id}/rows`, { cache: "no-store" });
    if (!r.ok) { notifyProblem({ status: r.status, title: "The students could not be read." }); return; }
    const rows = (await r.json()) as Row[];
    downloadBlob(await brandedXlsx("Level corrections — fee effect", ["Student", "Number", "Faculty", "Programme", "Basis", "Level on record", "Corrected level",
      `Charged ${run.session} now`, `Charged ${run.session} after`, "Difference"],
      rows.map((x) => [x.name, x.number ?? "", x.faculty ?? "", x.programme ?? "", WORD[x.basis] ?? x.basis, x.current_level ?? "", x.new_level ?? "",
        Number(x.charged_now), Number(x.charged_after), Number(x.charged_after) - Number(x.charged_now)]),
      { sheetName: "Students", serial: docSerial("LFE"), sub: `${run.session}, worked out ${day(run.finished_at ?? run.started_at)}` }), `level-fee-effect-${run.session.replace("/", "-")}.xlsx`);
  }

  async function excelSums() {
    if (!run || !data?.report) return;
    downloadBlob(await brandedXlsx("Level corrections — fee effect by programme", ["Faculty", "Programme", "Students", "Charged now", "Charged after", "Difference",
      "Owe more", "Owe less", "The same", "No fee line after"],
      data.report.map((s) => [s.scope === "UNIVERSITY" ? "The University" : s.faculty ?? s.faculty_code ?? "", s.scope === "PROGRAMME" ? s.programme ?? s.programme_code ?? "" : "",
        Number(s.students), Number(s.charged_now), Number(s.charged_after), Number(s.charged_after) - Number(s.charged_now), Number(s.more), Number(s.less), Number(s.same), Number(s.none_after)]),
      { sheetName: "By programme", serial: docSerial("LFE"), sub: `${run.session}, worked out ${day(run.finished_at ?? run.started_at)}` }), `level-fee-effect-by-programme-${run.session.replace("/", "-")}.xlsx`);
  }

  const total = data.report?.find((s) => s.scope === "UNIVERSITY");
  const faculties = (data.report ?? []).filter((s) => s.scope === "FACULTY");
  const programmes = (f: string | null) => (data.report ?? []).filter((s) => s.scope === "PROGRAMME" && s.faculty_code === f);
  const startButton = mayStart ? (
    <div className="row" style={{ gap: 12, flexWrap: "wrap", alignItems: "center" }}>
      <Btn kind={run ? "ghost" : "primary"} busy={busy === "start"} busyLabel="Starting…" disabled={running || !all} onClick={() => void start()}>
        {run ? "Work it out again" : "Work out the fee effect"}
      </Btn>
      {waiting("ARITHMETIC") ? (
        <label className="sub2 row" style={{ gap: 6 }}>
          <input type="checkbox" checked={withArithmetic} onChange={(e) => setWithArithmetic(e.target.checked)} />
          Also the {fmt(waiting("ARITHMETIC"))} records only the count of sessions supports
        </label>
      ) : null}
    </div>
  ) : null;

  return (
    <Panel title="What correcting every waiting level does to the fees"
      right={run ? <Pil kind={run.state === "DONE" ? "ok" : run.state === "FAILED" ? "bad" : "info"}>{run.state === "DONE" ? run.session : run.state === "FAILED" ? "Stopped" : "Working out"}</Pil> : null}>
      <PBody>
        <div className="stack">
          <div className="sub2">
            {all ? <>{fmt(all)} level correction{all === 1 ? "" : "s"} wait: {fmt(waiting("SPILLOVER"))} spillover, {fmt(waiting("REGISTRATION"))} by their own registration
              {waiting("ARITHMETIC") ? <>, {fmt(waiting("ARITHMETIC"))} by the sessions counted</> : null}.</> : "No level correction waits."}
            {" "}Each is read as if the level were corrected — the charges for the current session now and after — and nothing is changed.
          </div>
          {run?.state === "RUNNING" ? (
            <div className="stack" style={{ gap: 4 }}>
              <div className="sub2 tnum">{fmt(run.done)} of {fmt(run.students)} read… (started {day(run.started_at)}{run.started_by ? ` by ${run.started_by}` : ""})</div>
              <div style={{ height: 8, borderRadius: 4, background: "var(--sunk, #eef1f4)", overflow: "hidden" }} role="progressbar" aria-valuemin={0} aria-valuemax={run.students} aria-valuenow={run.done}>
                <div style={{ height: "100%", width: `${run.students ? Math.round((100 * run.done) / run.students) : 100}%`, background: "var(--sky, #2f7fbf)" }} />
              </div>
            </div>
          ) : null}
          {run?.state === "FAILED" ? <Note kind="bad" title="The last working-out stopped">{run.error ?? "It did not finish."} Start it again.</Note> : null}
          {run?.state === "DONE" && total ? (
            <>
              <Tiles cls="grid--4" items={[
                ["Students read", fmt(total.students), null, `${run.bases.map((b) => WORD[b]).join(", ")}; charged ${run.basis === "COHORT" ? "by the cohort" : "by the level"}`],
                [`Charged ${run.session} now`, naira(total.charged_now), null, "as their levels stand"],
                [`Charged ${run.session} after`, naira(total.charged_after), null, `${signed(total.charged_after - total.charged_now)}: ${fmt(total.more)} owe more, ${fmt(total.less)} less`],
                ["No fee line after", fmt(total.none_after), total.none_after ? "var(--red-ink)" : null, total.none_after ? "state the line at their new level first" : "every one is charged a line"],
              ]} />
              <div className="sub2">Worked out {day(run.finished_at ?? run.started_at)}{run.started_by ? ` for ${run.started_by}` : ""}. Levels corrected since are not in these figures: work it out again.</div>
              <table className="tbl">
                <thead><tr><th>Faculty and programme</th><th className="num">Students</th><th className="num">Now</th><th className="num">After</th><th className="num">Difference</th><th className="num">No line after</th></tr></thead>
                <tbody>{faculties.map((f) => {
                  const key = f.faculty_code ?? "";
                  const shown = open.has(key);
                  return (
                    <Fragment key={key}>
                      <tr>
                        <td><button type="button" className="lnk" aria-expanded={shown} aria-label={`${f.faculty ?? f.faculty_code}: ${shown ? "hide" : "show"} its programmes`}
                          onClick={() => setOpen((o) => { const n = new Set(o); if (n.has(key)) n.delete(key); else n.add(key); return n; })}>
                          {shown ? "▾" : "▸"} <b>{f.faculty ?? f.faculty_code}</b></button></td>
                        <td className="num tnum">{fmt(f.students)}</td><td className="num tnum">{naira(f.charged_now)}</td><td className="num tnum">{naira(f.charged_after)}</td>
                        <td className="num tnum">{signed(f.charged_after - f.charged_now)}</td>
                        <td className="num tnum" style={f.none_after ? { color: "var(--red-ink)" } : undefined}>{fmt(f.none_after)}</td>
                      </tr>
                      {shown ? programmes(f.faculty_code).map((p) => (
                        <tr key={`${key}:${p.programme_code}`}>
                          <td style={{ paddingLeft: 28 }}>{p.programme ?? p.programme_code}</td>
                          <td className="num tnum">{fmt(p.students)}</td><td className="num tnum">{naira(p.charged_now)}</td><td className="num tnum">{naira(p.charged_after)}</td>
                          <td className="num tnum">{signed(p.charged_after - p.charged_now)}</td>
                          <td className="num tnum" style={p.none_after ? { color: "var(--red-ink)" } : undefined}>{fmt(p.none_after)}</td>
                        </tr>
                      )) : null}
                    </Fragment>
                  );
                })}</tbody>
              </table>
              <div className="row" style={{ gap: 8, flexWrap: "wrap" }}>
                <Btn kind="ghost" busyLabel="Preparing Excel..." onClick={excelSums}>Excel by faculty and programme</Btn>
                <Btn kind="ghost" busyLabel="Preparing Excel..." onClick={excelStudents}>Excel of every student</Btn>
              </div>
            </>
          ) : null}
          {startButton}
          {!mayStart && !run ? <div className="sub2">The Bursary, the Academic Office or the Registry works it out.</div> : null}
        </div>
      </PBody>
    </Panel>
  );
}
