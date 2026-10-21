"use client";

/** V593: the records may also be found by the level they should be at (every student who should be at 400 Level) and by spillover
 *  position (SP1, SP2, beyond the limit, or within the programme's length), every one found counted first — how many the corrections
 *  would raise and how many are left for review — and corrected in batches, each batch read again from the engine when applied.
 *
 *  V475: the records whose level is below the level the cohort engine computes — most of them spillover students who came over
 *  from the old portal at 100 Level — each with the basis of the correction: SPILLOVER (past the programme's length, so at its final
 *  level — certain), REGISTRATION (the student's own latest registration is at that level) or ARITHMETIC (the count of sessions
 *  alone — for review, applied only when chosen). The Academic Office or the Registry raises them in one act, a batch at a time,
 *  on a reason; no level is lowered and each change goes on the student's cohort history. */
import { useCallback, useEffect, useState } from "react";
import { FeeEffect } from "./FeeEffect";
import { LevelFeeEffectRun } from "./LevelFeeEffectRun";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { StudentOpen } from "@/components/StudentModal";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { spilloverWord } from "@/lib/student-query";

type Basis = "SPILLOVER" | "REGISTRATION" | "ARITHMETIC";
interface LevelRow {
  id: string; surname: string; other_names: string; matric_no: string | null; programme_code: string; programme: string; department: string; faculty: string;
  current_level: number; proposed_level: number; basis: Basis; spillover_state: string | null; spillover_years: number | null; expected_completion: string | null;
  effective_cohort: string | null; last_registration_session: string | null; last_registration_level: number | null;
}
interface LevelPage {
  counts: { basis: Basis; n: number }[]; total: number; page: number; size: number; rows: LevelRow[];
  /** V593: where the corrections would take the students, and their spillover position, under the other filters */
  byLevel?: { level: number; n: number }[]; bySpillover?: { spillover: string; n: number }[];
}
interface Counted { selected: number; spillover: number; registration: number; arithmetic: number; remaining: number }
type Spill = "" | "SPILLOVER_YEAR_1" | "SPILLOVER_YEAR_2" | "SPILLOVER_LIMIT_REACHED" | "NONE";
const SPILL: Record<Exclude<Spill, "">, string> = {
  SPILLOVER_YEAR_1: "SP1 — first spillover year", SPILLOVER_YEAR_2: "SP2 — second spillover year",
  SPILLOVER_LIMIT_REACHED: "Beyond the spillover limit", NONE: "Within the programme's length",
};

const BASIS: Record<Basis, [string, string, "warn" | "info" | "grey"]> = {
  SPILLOVER: ["Spillover", "Past the programme's length, so at its final level", "info"],
  REGISTRATION: ["Own registration", "The student's latest registration is at this level, or was one level below last session", "info"],
  ARITHMETIC: ["Sessions counted only", "Only the count of sessions says so — check before applying", "warn"],
};
const fmt = (v: number) => Number(v).toLocaleString("en-GB");

export function LevelCorrections({ fac, dept, canApply, canStateFees = false }: { fac: string; dept: string; canApply: boolean; canStateFees?: boolean }) {
  const [basis, setBasis] = useState<"" | Basis>("");
  const [lvl, setLvl] = useState("");
  const [cur, setCur] = useState("");   // V598: the level on record
  const [spill, setSpill] = useState<Spill>("");
  const [counted, setCounted] = useState<Counted | null>(null);
  const [q, setQ] = useState("");
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);
  const [data, setData] = useState<LevelPage | null>(null);
  const [failed, setFailed] = useState<string | null>(null);
  const [chosen, setChosen] = useState<Set<string>>(new Set());
  const [apply, setApply] = useState<{ mode: "safe" | "chosen" | "found"; reason: string; withCounted?: boolean } | null>(null);
  const [progress, setProgress] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [tick, setTick] = useState(0);

  const query = useCallback((p: number, size: number) => {
    const qs = new URLSearchParams();
    if (fac) qs.set("fac", fac);
    if (dept) qs.set("dept", dept);
    if (basis) qs.set("basis", basis);
    if (search) qs.set("q", search);
    if (lvl) qs.set("level", lvl);
    if (cur) qs.set("current", cur);
    if (spill) qs.set("spillover", spill);
    qs.set("page", String(p));
    qs.set("size", String(size));
    return `/api/bff/api/v1/cohorts/levels?${qs.toString()}`;
  }, [fac, dept, basis, search, lvl, spill, cur]);

  // the page is read after it paints, and again after a correction (tick)
  useEffect(() => {
    let live = true;
    (async () => {
      try {
        const r = await fetch(query(page, 50), { cache: "no-store" });
        const j = await r.json().catch(() => null);
        if (!live) return;
        if (!r.ok) { setFailed((j as { title?: string } | null)?.title ?? "The list could not be read."); return; }
        setFailed(null);
        setData(j as LevelPage);
      } catch { if (live) setFailed("The connection to the portal dropped."); }
    })();
    return () => { live = false; };
  }, [query, page, tick]);

  const count = (b: Basis) => Number(data?.counts.find((c) => c.basis === b)?.n ?? 0);
  const safe = count("SPILLOVER") + count("REGISTRATION");
  const pages = data ? Math.max(1, Math.ceil(data.total / data.size)) : 1;
  // V593: a filter beyond the faculty or department narrows "every one" to the ones found
  const filtered = Boolean(lvl || spill || search || basis || cur);

  /** V593: what "every one found" is — the filters on the screen, read again by the server when it applies */
  function foundBody(withCounted: boolean) {
    const bases = basis ? [basis] : withCounted ? ["SPILLOVER", "REGISTRATION", "ARITHMETIC"] : ["SPILLOVER", "REGISTRATION"];
    return { bases, fac: fac || null, dept: dept || null, toLevel: lvl ? Number(lvl) : null, spillover: spill || null, q: search || null, fromLevel: cur ? Number(cur) : null };
  }
  async function count2(withCounted: boolean) {
    setCounted(null);
    const r = await fetch("/api/bff/api/v1/cohorts/levels/apply", {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ...foundBody(withCounted), limit: 500, dryRun: true }),
    });
    const j = await r.json().catch(() => null);
    if (r.ok) setCounted(j as Counted); else notifyProblem((j ?? { status: r.status, title: r.statusText }) as Parameters<typeof notifyProblem>[0]);
  }

  async function run() {
    if (!apply) return;
    const reason = apply.reason.trim();
    if (!reason) { notifyProblem({ status: 400, title: "Say why the levels are being corrected — it is kept on each student's history." }); return; }
    const body = apply.mode === "safe"
      ? { bases: ["SPILLOVER", "REGISTRATION"], fac: fac || null, dept: dept || null }
      : apply.mode === "found" ? foundBody(Boolean(apply.withCounted))
      : { studentIds: [...chosen], bases: ["SPILLOVER", "REGISTRATION", "ARITHMETIC"] };
    const batch = docSerial("LVL");
    setBusy(true);
    let done = 0;
    try {
      for (let round = 0; round < 400; round++) {
        const r = await fetch("/api/bff/api/v1/cohorts/levels/apply", {
          method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Levels corrected to the cohort engine's: ${reason}`) },
          body: JSON.stringify({ ...body, reason, batch, limit: 500, dryRun: false }),
        });
        const j = (await r.json().catch(() => null)) as { corrected?: number; remaining?: number; title?: string } | null;
        if (!r.ok) { notifyProblem((j ?? { status: r.status, title: r.statusText }) as Parameters<typeof notifyProblem>[0]); break; }
        done += Number(j?.corrected ?? 0);
        const left = Number(j?.remaining ?? 0);
        setProgress(`${fmt(done)} corrected${left ? `, ${fmt(left)} to go` : ""}`);
        if (!left || !Number(j?.corrected ?? 0)) break;
      }
      notify(`${fmt(done)} student${done === 1 ? "" : "s"} brought to their level`);
      setApply(null); setChosen(new Set()); setPage(1); setTick((t) => t + 1);
    } finally { setBusy(false); setProgress(null); }
  }

  async function download() {
    if (!data?.total) return;
    const rows: LevelRow[] = [];
    for (let p = 1; (p - 1) * 500 < data.total && p <= 100; p++) {
      const r = await fetch(query(p, 500), { cache: "no-store" });
      if (!r.ok) { notifyProblem({ status: r.status, title: "The list could not be read." }); return; }
      const j = (await r.json()) as LevelPage;
      rows.push(...j.rows);
      if (j.rows.length < 500) break;
    }
    const blob = await brandedXlsx("Level corrections — Student Cohorts",
      ["Student", "Matric No.", "Programme", "Department", "Faculty", "Level on record", "Level computed", "Basis", "Spillover", "Effective cohort", "Expected completion", "Latest registration"],
      rows.map((r) => [`${r.surname}, ${r.other_names}`, r.matric_no ?? "", r.programme, r.department, r.faculty, r.current_level, r.proposed_level, BASIS[r.basis][0],
        spilloverWord(r.spillover_state)?.long ?? "", r.effective_cohort ?? "", r.expected_completion ?? "",
        r.last_registration_session ? `${r.last_registration_session} at ${r.last_registration_level}` : ""]),
      { sheetName: "Level corrections", serial: docSerial("LVL"), sub: [basis ? BASIS[basis][0] : "Every basis", cur ? `at ${cur} Level` : null, lvl ? `should be at ${lvl} Level` : null, spill ? SPILL[spill] : null, search ? `"${search}"` : null].filter(Boolean).join(" · ") });
    downloadBlob(blob, "level-corrections.xlsx");
  }

  return (
    <>
      <Note kind="info" title="Records whose level is below where the cohort engine places the student">
        A student past the programme&rsquo;s length is in spillover — SP1, then SP2, each a session of both semesters, up to the limit set under Policy (approved
        deferments push the expected completion on) — and stands at the programme&rsquo;s final level. Many such students came over from the old portal at 100 Level.
        Raise them here; no level is ever lowered, and each change goes on the student&rsquo;s history with your reason.
      </Note>
      <Tiles items={[
        ["Spillover", fmt(count("SPILLOVER")), count("SPILLOVER") ? "var(--amber-ink)" : null, BASIS.SPILLOVER[1]],
        ["Own registration", fmt(count("REGISTRATION")), null, BASIS.REGISTRATION[1]],
        ["Sessions counted only", fmt(count("ARITHMETIC")), count("ARITHMETIC") ? "var(--red-ink)" : null, "For review — applied only when chosen"],
        ["In all", fmt(count("SPILLOVER") + count("REGISTRATION") + count("ARITHMETIC")), null, fac || dept ? "Within the faculty or department chosen above" : "Within your scope"],
      ]} />
      <Panel title="Level corrections" right={<span className="row row--inline row--tight">
        {canApply && !filtered ? <Btn kind="primary" size="sm" disabled={busy || !safe} onClick={() => setApply({ mode: "safe", reason: "" })}>Correct the {fmt(safe)} spillover and own-registration records</Btn> : null}
        {canApply && filtered ? <Btn kind="primary" size="sm" disabled={busy || !data?.total} onClick={() => { setApply({ mode: "found", reason: "", withCounted: basis === "ARITHMETIC" }); void count2(basis === "ARITHMETIC"); }}>Correct every one found ({fmt(data?.total ?? 0)})</Btn> : null}
        {canApply && chosen.size ? <Btn kind="secondary" size="sm" disabled={busy} onClick={() => setApply({ mode: "chosen", reason: "" })}>Correct the {fmt(chosen.size)} chosen</Btn> : null}
        <Btn kind="ghost" size="sm" disabled={!data?.total} onClick={() => void download()}>Excel</Btn>
      </span>}>
        <PBody>
          <form className="row" onSubmit={(e) => { e.preventDefault(); setPage(1); setSearch(q.trim()); }}>
            <Field id="lv-basis" label="Basis" style={{ flex: "1 1 200px" }}>
              <select id="lv-basis" className="ctl" value={basis} onChange={(e) => { setBasis(e.target.value as "" | Basis); setPage(1); }}>
                <option value="">Every basis</option>
                {(Object.keys(BASIS) as Basis[]).map((b) => <option key={b} value={b}>{BASIS[b][0]}</option>)}
              </select>
            </Field>
            <Field id="lv-cur" label="Level on record" style={{ flex: "1 1 160px" }}>
              <select id="lv-cur" className="ctl" value={cur} onChange={(e) => { setCur(e.target.value); setPage(1); setChosen(new Set()); }}>
                <option value="">Any level</option>
                {[100, 200, 300, 400, 500].map((l) => <option key={l} value={String(l)}>{l} Level</option>)}
              </select>
            </Field>
            <Field id="lv-level" label="Should be at" style={{ flex: "1 1 160px" }}>
              <select id="lv-level" className="ctl" value={lvl} onChange={(e) => { setLvl(e.target.value); setPage(1); setChosen(new Set()); }}>
                <option value="">Any level</option>
                {[100, 200, 300, 400, 500, 600].map((l) => <option key={l} value={String(l)}>{l} Level</option>)}
              </select>
            </Field>
            <Field id="lv-spill" label="Spillover" style={{ flex: "1 1 220px" }}>
              <select id="lv-spill" className="ctl" value={spill} onChange={(e) => { setSpill(e.target.value as Spill); setPage(1); setChosen(new Set()); }}>
                <option value="">Any position</option>
                {(Object.keys(SPILL) as Exclude<Spill, "">[]).map((k) => <option key={k} value={k}>{SPILL[k]}</option>)}
              </select>
            </Field>
            <Field id="lv-q" label="Search" style={{ flex: "2 1 260px" }}>
              <input id="lv-q" className="ctl" type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Name or matriculation number" />
            </Field>
            <div style={{ alignSelf: "flex-end" }}><Btn kind="primary" type="submit">Search</Btn></div>
          </form>
        </PBody>
        {data && (data.byLevel?.length || data.bySpillover?.length) ? (
          <PBody>
            <div className="row row--tight" style={{ gap: 6, flexWrap: "wrap", alignItems: "center" }}>
              <span className="sub2">Should be at:</span>
              {(data.byLevel ?? []).map((x) => (
                <button key={x.level} type="button" className={`btn btn--sm ${lvl === String(x.level) ? "btn--secondary" : "btn--ghost"}`} aria-pressed={lvl === String(x.level)}
                  onClick={() => { setLvl(lvl === String(x.level) ? "" : String(x.level)); setPage(1); setChosen(new Set()); }}>{x.level} Level · {fmt(x.n)}</button>
              ))}
              <span className="sub2" style={{ marginLeft: 8 }}>Spillover:</span>
              {(data.bySpillover ?? []).map((x) => (
                <button key={x.spillover} type="button" className={`btn btn--sm ${spill === x.spillover ? "btn--secondary" : "btn--ghost"}`} aria-pressed={spill === x.spillover}
                  onClick={() => { setSpill(spill === x.spillover ? "" : (x.spillover as Spill)); setPage(1); setChosen(new Set()); }}>
                  {x.spillover === "NONE" ? "Within the length" : spilloverWord(x.spillover)?.short ?? x.spillover} · {fmt(x.n)}</button>
              ))}
            </div>
          </PBody>
        ) : null}
        {failed ? <PBody><Note kind="bad" title="The list could not be read">{failed}</Note></PBody> : null}
        {canApply && data && data.rows.length ? (
          <PBody>
            <label className="row row--inline row--tight" style={{ alignItems: "center", gap: 6 }}>
              <input type="checkbox" className="chk" checked={data.rows.every((r) => chosen.has(r.id))}
                onChange={(e) => setChosen((prev) => { const n = new Set(prev); for (const r of data.rows) { if (e.target.checked) n.add(r.id); else n.delete(r.id); } return n; })} />
              <span>Choose all {fmt(data.rows.length)} on this page</span>
              {chosen.size ? <span className="sub2">· {fmt(chosen.size)} chosen</span> : null}
            </label>
          </PBody>
        ) : null}
        {data && data.rows.length ? (
          <DTable pageSize={0} cols={[...(canApply ? ["|mid"] : []), "S/N|num", "Student", "Programme", "On record|mid", "Should be|mid", "Basis", "Spillover|mid", "Latest registration|mid", "|num"]}
            rows={data.rows.map((r, i) => [
              ...(canApply ? [<input key="c" type="checkbox" aria-label={`Choose ${r.surname}, ${r.other_names}`} checked={chosen.has(r.id)}
                onChange={(e) => setChosen((prev) => { const n = new Set(prev); if (e.target.checked) n.add(r.id); else n.delete(r.id); return n; })} />] : []),
              <span key="sn" className="tnum sub2">{(data.page - 1) * data.size + i + 1}</span>,
              <span key="n"><strong>{r.surname}, {r.other_names}</strong><div className="sub2 tnum">{r.matric_no ?? "—"}</div></span>,
              <span key="p">{r.programme}<div className="sub2">{r.department} · {r.faculty}</div></span>,
              <span key="o" className="tnum ink-red">{r.current_level}</span>,
              <b key="s" className="tnum">{r.proposed_level}</b>,
              <Pil key="b" kind={BASIS[r.basis][2]} title={BASIS[r.basis][1]}>{BASIS[r.basis][0]}</Pil>,
              <span key="sp">{spilloverWord(r.spillover_state)?.long ?? <span className="sub2">—</span>}<div className="sub2">{r.effective_cohort ?? ""}{r.expected_completion ? ` · due ${r.expected_completion}` : ""}</div></span>,
              <span key="lr" className="tnum">{r.last_registration_session ? <>{r.last_registration_level}<div className="sub2">{r.last_registration_session}</div></> : <span className="sub2">none</span>}</span>,
              <StudentOpen key="o2" id={r.id} label="Record" kind="ghost" />,
            ])} />
        ) : data && !failed ? <PBody><Note kind="ok" title="Nothing to correct">Every record in study is at or above the level the cohort engine computes{basis || search ? " for this search" : ""}.</Note></PBody> : null}
        {data && pages > 1 ? (
          <PBody><div className="row row--between">
            <Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</Btn>
            <span className="sub2 tnum">Page {page} of {pages} · {fmt(data.total)} in all</span>
            <Btn kind="ghost" size="sm" disabled={page >= pages} onClick={() => setPage(page + 1)}>Next</Btn>
          </div></PBody>
        ) : null}
      </Panel>
      {/* V580: what correcting every one waiting would do to the current session's charges, worked out behind the screens */}
      <LevelFeeEffectRun mayStart={canApply} mayCorrect={canApply} mayStateFees={canStateFees} />

      {apply ? (
        <Modal title={apply.mode === "safe" ? `Correct ${fmt(safe)} records` : apply.mode === "found" ? `Correct every one found (${fmt(data?.total ?? 0)})` : `Correct the ${fmt(chosen.size)} chosen records`}
          sub="Each record goes to the level shown; none is lowered" onClose={() => { if (!busy) setApply(null); }}
          foot={<><Btn kind="ghost" disabled={busy} onClick={() => setApply(null)}>Cancel</Btn><Btn kind="primary" disabled={apply.mode === "found" && !counted?.selected} onClick={() => run()}>{busy ? progress ?? "Correcting…" : apply.mode === "found" && counted ? `Correct ${fmt(counted.selected)} levels` : "Correct the levels"}</Btn></>}>
          {apply.mode === "found" ? (
            <>
              <Note kind="info" title={[cur ? `At ${cur} Level` : null, lvl ? `Should be at ${lvl} Level` : null, spill ? SPILL[spill] : null, basis ? BASIS[basis][0] : null, search ? `"${search}"` : null, fac || dept ? "within the faculty or department chosen" : null].filter(Boolean).join(" · ") || "Every one found"}>
                {counted ? <>Found {fmt(counted.selected)}: {fmt(counted.spillover)} past the programme&rsquo;s length, {fmt(counted.registration)} by their own registration
                  {counted.arithmetic ? `, ${fmt(counted.arithmetic)} by the count of sessions alone` : ""}. {fmt(counted.selected)} will be corrected.</> : "Counting…"}
                {" "}Each batch is read again from the cohort engine when it is applied: a record changed since, or no longer below its level, is left alone. No level is lowered.
              </Note>
              {!basis ? (
                <label className="row row--inline row--tight mt-1" style={{ alignItems: "center", gap: 6 }}>
                  <input type="checkbox" className="chk" checked={Boolean(apply.withCounted)} disabled={busy}
                    onChange={(e) => { setApply({ ...apply, withCounted: e.target.checked }); void count2(e.target.checked); }} />
                  <span>Include the records only the count of sessions supports — checked one by one; a repeated year or a gap reads the same</span>
                </label>
              ) : null}
              {!apply.withCounted && !basis && data ? (() => { const left = Number(data.counts.find((c) => c.basis === "ARITHMETIC")?.n ?? 0); return left ? <div className="sub2 mt-1">{fmt(left)} found only by the count of sessions are left for review.</div> : null; })() : null}
            </>
          ) : null}
          {apply.mode !== "found" ? <Note kind="info" title={apply.mode === "safe" ? "Spillover and own-registration records only" : "The records you chose"}>
            {apply.mode === "safe"
              ? <>The {fmt(count("SPILLOVER"))} spillover records go to their programme&rsquo;s final level and the {fmt(count("REGISTRATION"))} others to the level of their own latest registration{fac || dept ? ", within the faculty or department chosen" : ""}. Records whose level only the count of sessions supports are left for you to choose.</>
              : <>Chosen records may include ones whose level only the count of sessions supports — a repeated year or a gap reads the same. Check each before going on.</>}
            {" "}The changes run in batches of 500; each goes on the student&rsquo;s cohort history in your name.
          </Note> : null}
          {/* V576: what the first batch does to the students' fees, read before anything is changed */}
          <FeeEffect label="See what the first 500 would be charged" request={() => fetch("/api/bff/api/v1/cohorts/levels/fee-effect", {
            method: "POST", headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ ...(apply.mode === "safe" ? { bases: ["SPILLOVER", "REGISTRATION"], fac: fac || null, dept: dept || null }
              : apply.mode === "found" ? foundBody(Boolean(apply.withCounted))
              : { studentIds: [...chosen], bases: ["SPILLOVER", "REGISTRATION", "ARITHMETIC"] }), limit: 500 }),
          })} />
          <Field id="lv-reason" label="Reason" required>
            <textarea id="lv-reason" className="ctl" rows={3} maxLength={2000} value={apply.reason} onChange={(e) => setApply({ ...apply, reason: e.target.value })}
              placeholder="e.g. Students migrated from the old portal at 100 Level; their level is the programme's final level as spillover students" />
          </Field>
          {progress ? <div className="sub2 tnum">{progress}</div> : null}
        </Modal>
      ) : null}
    </>
  );
}
