"use client";

/** V580: what correcting every waiting level would do to the current session's charges — for the Bursary before the Academic Office
 *  or the Registry corrects them. A run takes the corrections waiting as they stand and reads them behind the screens (about a
 *  minute for 10,000 on the live-shaped copy; the levels raised and undone, nothing changed); the panel shows how far it got, then
 *  the sums for the University, each faculty and each programme, and an Excel of every student. On the Bursar's fee page and on
 *  Student Cohorts → Level corrections.
 *  V584: the students charged nothing after are grouped by programme and corrected level, each group with the lines it could be
 *  stated from (the programme's own at the nearest level, last session's, another programme of the department or faculty) — the
 *  Bursary previews and states them in one step; and each programme says how many have been corrected since, the Registry
 *  correcting one programme at a time from here with its fee effect beside it. */
import { Fragment, useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field, Modal, money } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { COPY_ACTION, copyScope, type CopyAction } from "@/lib/fee-copy";

type Basis = "SPILLOVER" | "REGISTRATION" | "ARITHMETIC";
interface Run {
  id: string; session: string; basis: "LEVEL" | "COHORT"; bases: Basis[]; state: "RUNNING" | "DONE" | "FAILED"; students: number; done: number;
  error: string | null; started_at: string; finished_at: string | null; started_office: string | null; started_by: string | null;
}
interface Sum {
  scope: "UNIVERSITY" | "FACULTY" | "PROGRAMME"; faculty_code: string | null; faculty: string | null; programme_code: string | null; programme: string | null;
  students: number; charged_now: number; charged_after: number; more: number; less: number; same: number; none_after: number; corrected: number;
}
/** V584: where a gap's lines could come from */
interface Source {
  kind: "SAME_PROGRAMME" | "LAST_SESSION" | "SAME_DEPARTMENT" | "SAME_FACULTY"; session: string; programme_code: string; programme: string; level: number; lines: number;
  /** whose lines they are: the programme's own, its faculty's, or the University's (finance.programme_level_lines) */
  tier: "PROGRAMME" | "FACULTY" | "UNIVERSITY";
}
interface Gap {
  programme_code: string; programme: string; faculty_code: string | null; faculty: string | null; department: string | null; level: number;
  students: number; corrected: number; programme_states: boolean; sources: Source[];
}
interface Latest { run: Run | null; waiting: { basis: Basis; students: number }[]; report?: Sum[]; gaps?: Gap[] }
interface Row {
  student_id: string; name: string; number: string | null; faculty: string | null; programme: string | null; basis: Basis;
  current_level: number | null; new_level: number | null; charged_now: number; charged_after: number;
}
interface GapLine {
  item: string; kind: string; amount: number; entry_mode: string | null; fee_group: string | null; semester: number | null; indigene: string | null; ord: number;
  target_amount: number | null; action: CopyAction;
}
interface GapPreview { copy: number; kept: number; lines: GapLine[] }

const URL_ = "/api/bff/api/v1/finance/level-fee-effect";
const WORD: Record<Basis, string> = { SPILLOVER: "spillover", REGISTRATION: "own registration", ARITHMETIC: "sessions counted" };
const TIER: Record<Source["tier"], string> = { PROGRAMME: "its own lines", FACULTY: "the faculty's lines", UNIVERSITY: "the University's lines" };
const fmt = (n: number) => Number(n ?? 0).toLocaleString("en-NG");
const naira = (n: number) => `₦${Number(n ?? 0).toLocaleString("en-NG", { maximumFractionDigits: 2 })}`;
const day = (s: string) => new Date(s).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
const signed = (n: number) => `${n >= 0 ? "+" : "−"}${naira(Math.abs(n))}`;
const gapKey = (g: Gap) => `${g.programme_code}:${g.level}`;
const lines = (n: number) => `${fmt(n)} line${n === 1 ? "" : "s"}`;
const sourceLabel = (s: Source) =>
  s.kind === "SAME_PROGRAMME" ? `${TIER[s.tier]} at ${s.level} Level (${lines(s.lines)})`
    : s.kind === "LAST_SESSION" ? `${TIER[s.tier]} at ${s.level} Level in ${s.session} (${lines(s.lines)})`
      : `${s.programme} at ${s.level} Level (${lines(s.lines)}) — another programme of the ${s.kind === "SAME_DEPARTMENT" ? "department" : "faculty"}`;

export function LevelFeeEffectRun({ mayStart, mayStateFees = false, mayCorrect = false }: { mayStart: boolean; mayStateFees?: boolean; mayCorrect?: boolean }) {
  const [data, setData] = useState<Latest | null>(null);
  const [withArithmetic, setWithArithmetic] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [open, setOpen] = useState<Set<string>>(new Set());
  const [tick, setTick] = useState(0);
  // V584: the source chosen for each gap, the gap being previewed, the programme being corrected
  const [chosen, setChosen] = useState<Record<string, number>>({});
  const [stating, setStating] = useState<{ gap: Gap; source: Source; preview: GapPreview } | null>(null);
  const [correcting, setCorrecting] = useState<{ p: Sum; reason: string; progress: string | null } | null>(null);

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
      "Owe more", "Owe less", "The same", "No fee line after", "Corrected since"],
      data.report.map((s) => [s.scope === "UNIVERSITY" ? "The University" : s.faculty ?? s.faculty_code ?? "", s.scope === "PROGRAMME" ? s.programme ?? s.programme_code ?? "" : "",
        Number(s.students), Number(s.charged_now), Number(s.charged_after), Number(s.charged_after) - Number(s.charged_now), Number(s.more), Number(s.less), Number(s.same),
        Number(s.none_after), Number(s.corrected)]),
      { sheetName: "By programme", serial: docSerial("LFE"), sub: `${run.session}, worked out ${day(run.finished_at ?? run.started_at)}` }), `level-fee-effect-by-programme-${run.session.replace("/", "-")}.xlsx`);
  }

  /** V584: what stating a gap from the source chosen would copy */
  async function previewGap(gap: Gap, source: Source) {
    if (!run) return;
    setBusy(`gap:${gapKey(gap)}`);
    try {
      const q = new URLSearchParams({ fromSession: source.session, fromProgramme: source.programme_code, fromLevel: String(source.level),
        session: run.session, programme: gap.programme_code, level: String(gap.level) });
      const r = await fetch(`${URL_}/gap-lines?${q.toString()}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: "The lines could not be read just now." }); return; }
      setStating({ gap, source, preview: j as GapPreview });
    } finally { setBusy(null); }
  }

  async function stateGap() {
    if (!stating || !run) return;
    const { gap, source } = stating;
    setBusy("state");
    try {
      const r = await fetch(`${URL_}/gap-lines`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${gap.programme} at ${gap.level} Level stated for ${run.session} from ${source.programme} at ${source.level} Level (${source.session})`) },
        body: JSON.stringify({ fromSession: source.session, fromProgramme: source.programme_code, fromLevel: source.level, session: run.session, programme: gap.programme_code, level: gap.level }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify(`${fmt(Number(j?.copy ?? 0))} fee line${Number(j?.copy) === 1 ? "" : "s"} stated for ${gap.programme} at ${gap.level} Level — work the fee effect out again to see it`);
      setStating(null);
    } finally { setBusy(null); }
  }

  /** V584: one programme's waiting corrections made, on the run's bases, in batches of 500 as on Level corrections */
  async function correct() {
    if (!correcting || !run) return;
    const reason = correcting.reason.trim();
    if (reason.length < 10) { notifyProblem({ status: 400, title: "Say why the levels are being corrected — it is kept on each student's history." }); return; }
    const p = correcting.p;
    const batch = docSerial("LVL");
    setBusy("correct");
    let done = 0;
    try {
      for (let round = 0; round < 200; round++) {
        const r = await fetch("/api/bff/api/v1/cohorts/levels/apply", {
          method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Levels corrected to the cohort engine's (${p.programme}): ${reason}`) },
          body: JSON.stringify({ prog: p.programme_code, bases: run.bases, reason, batch, limit: 500, dryRun: false }),
        });
        const j = (await r.json().catch(() => null)) as { corrected?: number; remaining?: number } | null;
        if (!r.ok) { notifyProblem((j ?? { status: r.status, title: r.statusText }) as Parameters<typeof notifyProblem>[0]); break; }
        done += Number(j?.corrected ?? 0);
        const left = Number(j?.remaining ?? 0);
        setCorrecting((c) => (c ? { ...c, progress: `${fmt(done)} corrected${left ? `, ${fmt(left)} to go` : ""}` } : c));
        if (!left || !Number(j?.corrected ?? 0)) break;
      }
      notify(`${fmt(done)} student${done === 1 ? "" : "s"} of ${p.programme} brought to their level`);
      setCorrecting(null);
      setTick((n) => n + 1);
    } finally { setBusy(null); }
  }

  const total = data.report?.find((s) => s.scope === "UNIVERSITY");
  const faculties = (data.report ?? []).filter((s) => s.scope === "FACULTY");
  const programmes = (f: string | null) => (data.report ?? []).filter((s) => s.scope === "PROGRAMME" && s.faculty_code === f);
  const gaps = data.gaps ?? [];
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
              <div className="sub2">
                Worked out {day(run.finished_at ?? run.started_at)}{run.started_by ? ` for ${run.started_by}` : ""}. The charges are as they stood then: work it out
                again after levels are corrected or lines stated. {fmt(total.corrected)} of the {fmt(total.students)} have been corrected since.
              </div>
              <table className="tbl">
                <thead><tr><th>Faculty and programme</th><th className="num">Students</th><th className="num">Now</th><th className="num">After</th><th className="num">Difference</th>
                  <th className="num">No line after</th><th className="num">Corrected</th>{mayCorrect ? <th /> : null}</tr></thead>
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
                        <td className="num tnum">{fmt(f.corrected)}</td>
                        {mayCorrect ? <td /> : null}
                      </tr>
                      {shown ? programmes(f.faculty_code).map((p) => (
                        <tr key={`${key}:${p.programme_code}`}>
                          <td style={{ paddingLeft: 28 }}>{p.programme ?? p.programme_code}</td>
                          <td className="num tnum">{fmt(p.students)}</td><td className="num tnum">{naira(p.charged_now)}</td><td className="num tnum">{naira(p.charged_after)}</td>
                          <td className="num tnum">{signed(p.charged_after - p.charged_now)}</td>
                          <td className="num tnum" style={p.none_after ? { color: "var(--red-ink)" } : undefined}>{fmt(p.none_after)}</td>
                          <td className="num tnum">{fmt(p.corrected)}</td>
                          {mayCorrect ? (
                            <td className="num">{p.corrected < p.students
                              ? <Btn kind="ghost" size="sm" onClick={() => setCorrecting({ p, reason: "", progress: null })}>Correct</Btn>
                              : <span className="sub2">Done</span>}</td>
                          ) : null}
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
              {gaps.length ? (
                <div className="stack" style={{ gap: 6 }}>
                  <b>Fee lines missing at the corrected level</b>
                  <div className="sub2">
                    These students would be charged nothing for {run.session} at their corrected level. State the lines from those shown (the amounts can be
                    adjusted on the charges above afterwards), or upload the approved structure that names them.
                  </div>
                  <table className="tbl">
                    <thead><tr><th>Programme</th><th className="num">Level</th><th className="num">Students</th><th>State from</th><th /></tr></thead>
                    <tbody>{gaps.map((g) => {
                      const k = gapKey(g);
                      const pick = g.sources[chosen[k] ?? 0];
                      return (
                        <tr key={k}>
                          <td>{g.programme}<div className="sub2">{g.department ?? g.faculty ?? ""}{g.programme_states ? ` · no line at ${g.level} Level` : ` · states no line for ${run.session}`}</div></td>
                          <td className="num tnum">{g.level}</td>
                          <td className="num tnum">{fmt(g.students)}{g.corrected ? <div className="sub2">{fmt(g.corrected)} corrected</div> : null}</td>
                          <td>{g.sources.length
                            ? <select className="ctl" aria-label={`The lines to state ${g.programme} at ${g.level} Level from`} value={chosen[k] ?? 0}
                                onChange={(e) => setChosen((c) => ({ ...c, [k]: Number(e.target.value) }))}>
                                {g.sources.map((s, i) => <option key={`${s.programme_code}:${s.level}:${s.session}`} value={i}>{sourceLabel(s)}</option>)}
                              </select>
                            : <span className="sub2">Nothing to copy from: no line applies to it at {g.level} Level this session or before, and no other programme of the faculty states one. State them on the charges above, or upload the structure.</span>}</td>
                          <td className="num">{pick
                            ? <Btn kind="ghost" size="sm" busy={busy === `gap:${k}`} onClick={() => void previewGap(g, pick)}>See the lines</Btn> : null}</td>
                        </tr>
                      );
                    })}</tbody>
                  </table>
                </div>
              ) : null}
            </>
          ) : null}
          {startButton}
          {!mayStart && !run ? <div className="sub2">The Bursary, the Academic Office or the Registry works it out.</div> : null}
        </div>
      </PBody>
      {stating && run ? (
        <Modal wide title={`${stating.gap.programme} at ${stating.gap.level} Level for ${run.session}`}
          sub={`From ${stating.source.kind === "SAME_DEPARTMENT" || stating.source.kind === "SAME_FACULTY" ? "" : `${stating.source.programme}: `}${sourceLabel(stating.source)}${stating.source.kind === "SAME_PROGRAMME" ? `, ${stating.source.session}` : ""} · ${fmt(stating.preview.copy)} to state, ${fmt(stating.preview.kept)} already stated`}
          onClose={() => { if (!busy) setStating(null); }}
          foot={<><Btn kind="ghost" disabled={!!busy} onClick={() => setStating(null)}>Cancel</Btn>
            {mayStateFees
              ? <Btn kind="primary" disabled={!!busy || !stating.preview.copy} busy={busy === "state"} busyLabel="Stating…" onClick={() => void stateGap()}>
                  {`State ${fmt(stating.preview.copy)} line${stating.preview.copy === 1 ? "" : "s"}`}</Btn>
              : <span className="sub2">The Bursary or the Students Account Officer states fee lines.</span>}</>}>
          <div className="sub2">
            Each line is stated for {stating.gap.programme} at {stating.gap.level} Level with the amount shown; a line already stated for the same students is kept.
            Check the amounts against the approved structure — they can be changed on the charges afterwards.
          </div>
          <DTable pageSize={12} cols={["Item", "Applies to", "Amount|num", `Stated now|num`, ""]} rows={stating.preview.lines.map((l) => [
            <strong key="i">{l.item}</strong>,
            <span key="a" className="sub2">{copyScope({ ...l, level: stating.gap.level, programme_code: stating.gap.programme_code, faculty_code: null, spillover: false })}</span>,
            <span key="m" className="tnum">{money(Number(l.amount))}</span>,
            <span key="t" className="tnum sub2">{l.target_amount != null ? money(Number(l.target_amount)) : "—"}</span>,
            <Pil key="p" kind={COPY_ACTION[l.action][1]}>{COPY_ACTION[l.action][0]}</Pil>,
          ])} />
        </Modal>
      ) : null}
      {correcting && run ? (
        <Modal title={`Correct the levels of ${correcting.p.programme}`} sub={`${fmt(correcting.p.students - correcting.p.corrected)} waiting on the run's bases (${run.bases.map((b) => WORD[b]).join(", ")})`}
          onClose={() => { if (!busy) setCorrecting(null); }}
          foot={<><Btn kind="ghost" disabled={!!busy} onClick={() => setCorrecting(null)}>Cancel</Btn>
            <Btn kind="primary" busy={busy === "correct"} busyLabel={correcting.progress ?? "Correcting…"} disabled={correcting.reason.trim().length < 10} onClick={() => void correct()}>Correct the levels</Btn></>}>
          <Note kind={correcting.p.none_after ? "bad" : "info"} title={`Fees for ${run.session}: ${naira(correcting.p.charged_now)} now, ${naira(correcting.p.charged_after)} after`}>
            {fmt(correcting.p.less)} would owe less, {fmt(correcting.p.more)} more and {fmt(correcting.p.same)} the same
            {correcting.p.none_after ? <>; <b>{fmt(correcting.p.none_after)}</b> would have no fee line at their new level — state it first (below the table), or they owe nothing</> : null}.
            {" "}Each record goes to the level the cohort engine computes and none is lowered; the changes go on each student&rsquo;s history with your reason.
          </Note>
          <Field id="lfe-reason" label="Reason" required>
            <textarea id="lfe-reason" className="ctl" rows={3} maxLength={2000} value={correcting.reason}
              onChange={(e) => setCorrecting((c) => (c ? { ...c, reason: e.target.value } : c))}
              placeholder="e.g. Students migrated from the old portal at 100 Level; their level is the programme's final level as spillover students" />
          </Field>
          {correcting.progress ? <div className="sub2 tnum">{correcting.progress}</div> : null}
        </Modal>
      ) : null}
    </Panel>
  );
}
