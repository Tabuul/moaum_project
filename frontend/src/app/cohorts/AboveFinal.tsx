"use client";

/** V601: records whose level is above the programme's final level — 500 or 600 on a four-year programme, mostly from the old
 *  portal — listed with the level the cohort engine computes and the latest registration, and brought to the final level (never
 *  below it) by the Academic Office or the Registry: every one found, or the ones chosen, counted first, on a reason, a batch at a
 *  time, each change on the student's cohort history. A student registered above the final level this session is left for review
 *  unless included in so many words; the registration keeps its level. */
import { useCallback, useEffect, useState } from "react";
import { FeeEffect } from "./FeeEffect";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { StudentOpen } from "@/components/StudentModal";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { spilloverWord } from "@/lib/student-query";

interface AboveRow {
  id: string; surname: string; other_names: string; matric_no: string | null; programme_code: string; programme: string; department: string; faculty: string;
  current_level: number; final_level: number; computed_level: number | null; spillover_state: string | null;
  last_registration_session: string | null; last_registration_level: number | null; registered_above_now: boolean;
}
interface AbovePage {
  counts: { total: number; registered_now: number }; byShape: { current_level: number; final_level: number; n: number }[];
  total: number; page: number; size: number; rows: AboveRow[];
}
interface Counted { selected: number; corrected: number; registered_now: number; remaining: number }
const fmt = (v: number) => Number(v).toLocaleString("en-GB");

export function AboveFinal({ fac, dept, canApply }: { fac: string; dept: string; canApply: boolean }) {
  const [q, setQ] = useState("");
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);
  const [data, setData] = useState<AbovePage | null>(null);
  const [failed, setFailed] = useState<string | null>(null);
  const [chosen, setChosen] = useState<Set<string>>(new Set());
  const [apply, setApply] = useState<{ mode: "found" | "chosen"; reason: string; withRegistered: boolean } | null>(null);
  const [counted, setCounted] = useState<Counted | null>(null);
  const [progress, setProgress] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [tick, setTick] = useState(0);

  const query = useCallback((p: number, size: number) => {
    const qs = new URLSearchParams();
    if (fac) qs.set("fac", fac);
    if (dept) qs.set("dept", dept);
    if (search) qs.set("q", search);
    qs.set("page", String(p));
    qs.set("size", String(size));
    return `/api/bff/api/v1/cohorts/levels/above-final?${qs.toString()}`;
  }, [fac, dept, search]);

  useEffect(() => {
    let live = true;
    (async () => {
      try {
        const r = await fetch(query(page, 50), { cache: "no-store" });
        const j = await r.json().catch(() => null);
        if (!live) return;
        if (!r.ok) { setFailed((j as { title?: string } | null)?.title ?? "The list could not be read."); return; }
        setFailed(null);
        setData(j as AbovePage);
      } catch { if (live) setFailed("The connection to the portal dropped."); }
    })();
    return () => { live = false; };
  }, [query, page, tick]);

  const pages = data ? Math.max(1, Math.ceil(data.total / data.size)) : 1;

  /** what is brought down: every one found (the faculty, department and search on the screen, read again by the server), or the ones chosen */
  function body(mode: "found" | "chosen", withRegistered: boolean) {
    return mode === "chosen" ? { studentIds: [...chosen], includeRegistered: withRegistered }
      : { fac: fac || null, dept: dept || null, q: search || null, includeRegistered: withRegistered };
  }
  async function count(mode: "found" | "chosen", withRegistered: boolean) {
    setCounted(null);
    const r = await fetch("/api/bff/api/v1/cohorts/levels/above-final/apply", {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ...body(mode, withRegistered), limit: 500, dryRun: true }),
    });
    const j = await r.json().catch(() => null);
    if (r.ok) setCounted(j as Counted); else notifyProblem((j ?? { status: r.status, title: r.statusText }) as Parameters<typeof notifyProblem>[0]);
  }
  function open(mode: "found" | "chosen") {
    setApply({ mode, reason: "", withRegistered: false });
    void count(mode, false);
  }

  async function run() {
    if (!apply) return;
    const reason = apply.reason.trim();
    if (!reason) { notifyProblem({ status: 400, title: "Say why the levels are being brought to the final level — it is kept on each student's history." }); return; }
    const batch = docSerial("LVF");
    setBusy(true);
    let done = 0;
    try {
      for (let round = 0; round < 400; round++) {
        const r = await fetch("/api/bff/api/v1/cohorts/levels/above-final/apply", {
          method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Levels brought to the programme's final level: ${reason}`) },
          body: JSON.stringify({ ...body(apply.mode, apply.withRegistered), reason, batch, limit: 500, dryRun: false }),
        });
        const j = (await r.json().catch(() => null)) as { corrected?: number; remaining?: number } | null;
        if (!r.ok) { notifyProblem((j ?? { status: r.status, title: r.statusText }) as Parameters<typeof notifyProblem>[0]); break; }
        done += Number(j?.corrected ?? 0);
        const left = Number(j?.remaining ?? 0);
        setProgress(`${fmt(done)} brought to the final level${left ? `, ${fmt(left)} to go` : ""}`);
        if (!left || !Number(j?.corrected ?? 0)) break;
      }
      notify(`${fmt(done)} record${done === 1 ? "" : "s"} brought to the programme's final level`);
      setApply(null); setChosen(new Set()); setPage(1); setTick((t) => t + 1);
    } finally { setBusy(false); setProgress(null); }
  }

  async function download() {
    if (!data?.total) return;
    const rows: AboveRow[] = [];
    for (let p = 1; (p - 1) * 500 < data.total && p <= 100; p++) {
      const r = await fetch(query(p, 500), { cache: "no-store" });
      if (!r.ok) { notifyProblem({ status: r.status, title: "The list could not be read." }); return; }
      const j = (await r.json()) as AbovePage;
      rows.push(...j.rows);
      if (j.rows.length < 500) break;
    }
    const blob = await brandedXlsx("Records above the final level — Student Cohorts",
      ["Student", "Matric No.", "Programme", "Department", "Faculty", "Level on record", "Final level", "Level computed", "Spillover", "Latest registration", "Registered above the final level this session"],
      rows.map((r) => [`${r.surname}, ${r.other_names}`, r.matric_no ?? "", r.programme, r.department, r.faculty, r.current_level, r.final_level, r.computed_level ?? "",
        spilloverWord(r.spillover_state)?.long ?? "", r.last_registration_session ? `${r.last_registration_session} at ${r.last_registration_level}` : "",
        r.registered_above_now ? "Yes" : ""]),
      { sheetName: "Above the final level", serial: docSerial("LVF"), sub: [search ? `"${search}"` : null].filter(Boolean).join(" · ") });
    downloadBlob(blob, "levels-above-final.xlsx");
  }

  const registeredNow = Number(data?.counts.registered_now ?? 0);
  return (
    <>
      <Panel title={`Records above the programme's final level${data ? ` (${fmt(data.counts.total)})` : ""}`} right={<span className="row row--inline row--tight">
        {canApply ? <Btn kind="primary" size="sm" disabled={busy || !data?.total} onClick={() => open("found")}>Bring every one found to the final level ({fmt(data?.total ?? 0)})</Btn> : null}
        {canApply && chosen.size ? <Btn kind="secondary" size="sm" disabled={busy} onClick={() => open("chosen")}>Bring the {fmt(chosen.size)} chosen</Btn> : null}
        <Btn kind="ghost" size="sm" disabled={!data?.total} onClick={() => void download()}>Excel</Btn>
      </span>}>
        <PBody>
          <div className="sub2">
            A level above the programme&rsquo;s last one — 500 or 600 on a four-year programme — is not a level the programme has. The record goes to the
            final level (never below it); a student past the programme&rsquo;s length is in spillover there.
            {registeredNow ? <> {fmt(registeredNow)} {registeredNow === 1 ? "holds" : "hold"} a registration above the final level this session: they are left for review unless you include them, and the registration keeps its level.</> : null}
          </div>
          <form className="row mt-1" onSubmit={(e) => { e.preventDefault(); setPage(1); setChosen(new Set()); setSearch(q.trim()); }}>
            <Field id="af-q" label="Search" style={{ flex: "2 1 260px" }}>
              <input id="af-q" className="ctl" type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Name or matriculation number" />
            </Field>
            <div style={{ alignSelf: "flex-end" }}><Btn kind="primary" type="submit">Search</Btn></div>
          </form>
        </PBody>
        {data && data.byShape.length ? (
          <PBody>
            <div className="row row--tight" style={{ gap: 6, flexWrap: "wrap", alignItems: "center" }} aria-label="Levels on record against the final level">
              <span className="sub2">On record → final level:</span>
              {data.byShape.map((x) => <Pil key={`${x.current_level}-${x.final_level}`} kind="warn">{x.current_level} → {x.final_level} · {fmt(x.n)}</Pil>)}
            </div>
          </PBody>
        ) : null}
        {failed ? <PBody><Note kind="bad" title="The list could not be read">{failed}</Note></PBody> : null}
        {data && data.rows.length ? (
          <DTable pageSize={0} cols={[...(canApply ? ["|mid"] : []), "S/N|num", "Student", "Programme", "On record|mid", "Final level|mid", "Computed|mid", "Spillover|mid", "Latest registration|mid", "|num"]}
            rows={data.rows.map((r, i) => [
              ...(canApply ? [<input key="c" type="checkbox" aria-label={`Choose ${r.surname}, ${r.other_names}`} checked={chosen.has(r.id)}
                onChange={(e) => setChosen((prev) => { const n = new Set(prev); if (e.target.checked) n.add(r.id); else n.delete(r.id); return n; })} />] : []),
              <span key="sn" className="tnum sub2">{(data.page - 1) * data.size + i + 1}</span>,
              <span key="n"><strong>{r.surname}, {r.other_names}</strong><div className="sub2 tnum">{r.matric_no ?? "—"}</div></span>,
              <span key="p">{r.programme}<div className="sub2">{r.department} · {r.faculty}</div></span>,
              <span key="o" className="tnum ink-red">{r.current_level}</span>,
              <b key="f" className="tnum">{r.final_level}</b>,
              <span key="cl" className="tnum">{r.computed_level ?? <span className="sub2">—</span>}</span>,
              <span key="sp">{spilloverWord(r.spillover_state)?.short ?? <span className="sub2">—</span>}</span>,
              <span key="lr" className="tnum">{r.last_registration_session ? <>{r.last_registration_level}<div className="sub2">{r.last_registration_session}</div></> : <span className="sub2">none</span>}
                {r.registered_above_now ? <div><Pil kind="bad" title="A registration above the final level stands this session">Registered above, this session</Pil></div> : null}</span>,
              <StudentOpen key="o2" id={r.id} label="Record" kind="ghost" />,
            ])} />
        ) : data && !failed ? <PBody><Note kind="ok" title="No record above its final level">Every record in study is at or below its programme&rsquo;s final level{search ? " for this search" : ""}.</Note></PBody> : null}
        {data && pages > 1 ? (
          <PBody><div className="row row--between">
            <Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</Btn>
            <span className="sub2 tnum">Page {page} of {pages} · {fmt(data.total)} in all</span>
            <Btn kind="ghost" size="sm" disabled={page >= pages} onClick={() => setPage(page + 1)}>Next</Btn>
          </div></PBody>
        ) : null}
      </Panel>

      {apply ? (
        <Modal title={apply.mode === "found" ? `Bring every one found to the final level (${fmt(data?.total ?? 0)})` : `Bring the ${fmt(chosen.size)} chosen to the final level`}
          sub="Each record goes to its programme's final level; none goes below it" onClose={() => { if (!busy) setApply(null); }}
          foot={<><Btn kind="ghost" disabled={busy} onClick={() => setApply(null)}>Cancel</Btn>
            <Btn kind="primary" disabled={!counted || !(counted.selected - (apply.withRegistered ? 0 : counted.registered_now))} onClick={() => run()}>
              {busy ? progress ?? "Bringing them down…" : counted ? `Bring ${fmt(counted.selected - (apply.withRegistered ? 0 : counted.registered_now))} to the final level` : "Counting…"}</Btn></>}>
          <Note kind="info" title={apply.mode === "chosen" ? "The records you chose" : [search ? `"${search}"` : null, fac || dept ? "within the faculty or department chosen" : null].filter(Boolean).join(" · ") || "Every one found"}>
            {counted ? <>Found {fmt(counted.selected)} above the final level{counted.registered_now ? `; ${fmt(counted.registered_now)} ${counted.registered_now === 1 ? "holds" : "hold"} a registration above it this session` : ""}.
              {" "}{fmt(counted.selected - (apply.withRegistered ? 0 : counted.registered_now))} will be brought to the final level.</> : "Counting…"}
            {" "}The changes run in batches of 500; each goes on the student&rsquo;s cohort history in your name. The level the cohort engine computes, where it is lower, is a separate correction.
          </Note>
          {counted?.registered_now ? (
            <label className="row row--inline row--tight mt-1" style={{ alignItems: "center", gap: 6 }}>
              <input type="checkbox" className="chk" checked={apply.withRegistered} disabled={busy}
                onChange={(e) => setApply({ ...apply, withRegistered: e.target.checked })} />
              <span>Include the {fmt(counted.registered_now)} registered above the final level this session — checked one by one; their registration keeps its level, and Course Registration support puts it right</span>
            </label>
          ) : null}
          {/* what the first batch does to the students' fees, read before anything is changed */}
          <FeeEffect label="See what the first 500 would be charged" change="fall" request={() => fetch("/api/bff/api/v1/cohorts/levels/above-final/fee-effect", {
            method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ...body(apply.mode, apply.withRegistered), limit: 500 }),
          })} />
          <Field id="af-reason" label="Reason" required>
            <textarea id="af-reason" className="ctl" rows={3} maxLength={2000} value={apply.reason} onChange={(e) => setApply({ ...apply, reason: e.target.value })}
              placeholder="e.g. Migrated from the old portal at 600 Level; the programme runs four years, so the record is at 400 Level" />
          </Field>
          {progress ? <div className="sub2 tnum">{progress}</div> : null}
        </Modal>
      ) : null}
    </>
  );
}
