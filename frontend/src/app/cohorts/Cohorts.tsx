"use client";
/** Student cohorts (V331): where every student stands, computed from the register — the figures first, then the current,
 *  graduated and spillover lists, the reconciliation review with the Registry's decisions, the data quality report, and the
 *  policy (the spillover limit, each programme's length, the sessions merged). Every list is the server's: filtered within
 *  the office's scope, paged, names A–Z; exports follow the University's standard, S/N first. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { StudentOpen } from "@/components/StudentModal";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { CLASS, CONF, ISSUE, RULE, SPILL, STATUSES, classWord, fullName, issuesOf, statusWord, type CohortList, type CohortRow, type CohortSettings, type CohortStudent, type CohortSummary } from "@/lib/cohorts";

export interface Filters { q: string; fac: string; dept: string; prog: string; cohort: string; entry: string; jamb: string; level: string; duration: string; status: string; grad: string; spill: string; conf: string; issue: string; sex: string; entryMode: string; sort: string; dir: string; size: string }
type Tab = "overview" | "current" | "graduated" | "spillover" | "review" | "all" | "quality" | "settings";
const TAB_TITLE: Record<Tab, string> = { overview: "Overview", current: "Current students", graduated: "Graduated students", spillover: "Spillover students", review: "Reconciliation review", all: "Every student", quality: "Data quality", settings: "Policy and sessions" };
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

export function Cohorts({ tab, summary, list, listProblem, settings, structure, filters, page, canDecide, canSet, generatedBy }: {
  tab: string; summary: CohortSummary; list: CohortList | null; listProblem: { title?: string; detail?: string } | null; settings: CohortSettings | null;
  structure: { code: string; name: string; departments: { code: string; name: string }[] }[]; filters: Filters; page: number; canDecide: boolean; canSet: boolean; generatedBy: string | null;
}) {
  const go = useQueryNav();
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [open, setOpen] = useState<string | null>(null);
  const [applyCount, setApplyCount] = useState<number | null>(null);
  const [merge, setMerge] = useState<{ session: string; into: string; reason: string; minute: string } | null>(null);
  const [length, setLength] = useState<{ code: string; name: string; level: string; years: string; note: string; pg: boolean } | null>(null);
  const [award, setAward] = useState<{ award: string; years: string; note: string } | null>(null);
  const [years, setYears] = useState(String(summary.policy?.max_spillover_years ?? 2));
  const t = summary.totals;
  const n = (v: number | null | undefined) => Number(v ?? 0);
  const isList = ["current", "graduated", "spillover", "review", "all"].includes(tab);

  function nav(patch: Partial<Filters & { tab: string; page: string }>) {
    const next: Record<string, string> = { ...filters, tab, page: "1", ...patch };
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(next)) if (v && !(k === "tab" && v === "overview") && !(k === "sort" && v === "name") && !(k === "dir" && v === "asc") && !(k === "size" && v === "50") && !(k === "page" && v === "1")) qs.set(k, v);
    go(`/cohorts${qs.toString() ? "?" + qs.toString() : ""}`);
  }
  async function call(method: "POST" | "PUT", path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/cohorts${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = (await r.json().catch(() => null)) as Record<string, unknown> | null;
      if (!r.ok) { notifyProblem(j ? (j as unknown as Parameters<typeof notifyProblem>[0]) : { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j;
    } finally { setBusy(false); }
  }

  const departments = (structure.find((f) => f.code === filters.fac)?.departments ?? structure.flatMap((f) => f.departments)).map((d) => ({ value: d.code, label: d.name }));
  const cohorts = summary.byCohort.filter((c) => c.key !== "Not stated").map((c) => ({ value: c.key, label: c.key }));
  const jambYears = Array.from(new Set(summary.byCohort.map((c) => c.jamb_year).filter((y): y is number => y != null))).sort((a, b) => b - a);
  const filtered = Object.entries(filters).some(([k, v]) => v && !["sort", "dir", "size"].includes(k));
  const sortBy = (key: string) => nav({ sort: key, dir: filters.sort === key && filters.dir === "asc" ? "desc" : "asc" });

  const HEAD = ["S/N", "Student", "Matric No.", "JAMB No.", "JAMB year", "Entry session", "Effective cohort", "Current session", "Programme", "Length", "Level", "Expected completion", "Spillover", "Existing status", "Proposed", "Classification", "Reason", "Confidence"];
  const exportRows = (rows: CohortRow[]) => rows.map((r) => [fullName(r), r.matric_no ?? "", r.jamb_reg_no ?? "", r.jamb_year ?? "", r.entry_session ?? "", r.effective_cohort ?? "", r.current_session ?? "", r.programme, r.duration_years ? `${r.duration_years} sessions` : "", r.current_level ?? "", r.expected_completion ?? "", SPILL[r.spillover_state] ?? r.spillover_state, statusWord(r.existing_status), statusWord(r.proposed_status), classWord(r.classification), RULE[r.rule] ?? r.rule, CONF[r.confidence]?.[0] ?? r.confidence]);
  const meta = (): [string, string][] => [["Session", t.current_session ?? "—"], ["View", TAB_TITLE[tab as Tab] ?? tab], ["Filters", filtered ? Object.entries(filters).filter(([k, v]) => v && !["sort", "dir", "size"].includes(k)).map(([k, v]) => `${k} ${v}`).join(", ") : "None"]];

  return (
    <>
      <PageHead title="Student cohorts" description={t.current_session ?? "The current session"}
        actions={<>
          {canSet ? <Btn kind="ghost" disabled={busy} onClick={() => void call("POST", "/refresh", {}, "Every student's position recomputed")}>Recompute</Btn> : null}
          <LinkBtn href="/students">Student Records</LinkBtn>
          <LinkBtn href="/graduation">Graduation</LinkBtn>
        </>} />
      <Tabs label="View" items={[
        { id: "overview", label: "Overview" }, { id: "current", label: "Current", count: n(t.current) }, { id: "graduated", label: "Graduated", count: n(t.graduated) },
        { id: "spillover", label: "Spillover", count: n(t.spillover) + n(t.spillover_limit) }, { id: "review", label: "Review", count: n(t.review) }, { id: "all", label: "All" },
        { id: "quality", label: "Data quality", count: summary.byIssue.reduce((a, b) => a + n(b.n), 0) }, { id: "settings", label: "Policy & sessions" },
      ]} value={tab as Tab} onChange={(v) => nav({ tab: v })} />

      {(isList || tab === "overview") ? (
        <form className="filterbar" onSubmit={(e) => { e.preventDefault(); const f = new FormData(e.currentTarget); nav({ q: String(f.get("q") ?? "") }); }}>
          <div className="row">
            <Field id="co-q" label="Search" style={{ flex: "2 1 240px" }}><input id="co-q" name="q" className="ctl" type="search" defaultValue={filters.q} placeholder="Name, matriculation, admission or JAMB number" /></Field>
            <Field id="co-fac" label="Faculty" style={{ flex: "1 1 170px" }}><SearchSelect id="co-fac" value={filters.fac} onChange={(v) => nav({ fac: v, dept: "", prog: "" })} allLabel="Any faculty" options={structure.map((f) => ({ value: f.code, label: f.name }))} /></Field>
            <Field id="co-dept" label="Department" style={{ flex: "1 1 170px" }}><SearchSelect id="co-dept" value={filters.dept} onChange={(v) => nav({ dept: v, prog: "" })} allLabel="Any department" options={departments} /></Field>
            <Field id="co-cohort" label="Effective cohort" style={{ flex: "1 1 140px" }}><SearchSelect id="co-cohort" value={filters.cohort} onChange={(v) => nav({ cohort: v })} allLabel="Any cohort" options={cohorts} /></Field>
            <Field id="co-jamb" label="JAMB year" style={{ flex: "1 1 110px" }}>
              <select id="co-jamb" className="ctl" value={filters.jamb} onChange={(e) => nav({ jamb: e.target.value })}><option value="">Any</option>{jambYears.map((y) => <option key={y} value={String(y)}>{y}</option>)}</select>
            </Field>
            <Field id="co-level" label="Level" style={{ flex: "1 1 100px" }}>
              <select id="co-level" className="ctl" value={filters.level} onChange={(e) => nav({ level: e.target.value })}><option value="">Any</option>{[100, 200, 300, 400, 500, 600].map((l) => <option key={l} value={String(l)}>{l}</option>)}</select>
            </Field>
            <Field id="co-dur" label="Programme length" style={{ flex: "1 1 120px" }}>
              <select id="co-dur" className="ctl" value={filters.duration} onChange={(e) => nav({ duration: e.target.value })}><option value="">Any</option>{[1, 2, 3, 4, 5, 6].map((y) => <option key={y} value={String(y)}>{y} session{y === 1 ? "" : "s"}</option>)}</select>
            </Field>
            <Field id="co-status" label="Status on record" style={{ flex: "1 1 150px" }}>
              <select id="co-status" className="ctl" value={filters.status} onChange={(e) => nav({ status: e.target.value })}><option value="">Any</option>{STATUSES.map((s) => <option key={s} value={s}>{statusWord(s)}</option>)}</select>
            </Field>
            <Field id="co-spill" label="Spillover" style={{ flex: "1 1 150px" }}>
              <select id="co-spill" className="ctl" value={filters.spill} onChange={(e) => nav({ spill: e.target.value })}><option value="">Any</option>{Object.entries(SPILL).filter(([k]) => k !== "NOT_APPLICABLE").map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select>
            </Field>
            <Field id="co-conf" label="Confidence" style={{ flex: "1 1 120px" }}>
              <select id="co-conf" className="ctl" value={filters.conf} onChange={(e) => nav({ conf: e.target.value })}><option value="">Any</option>{Object.entries(CONF).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}</select>
            </Field>
            <Field id="co-issue" label="Issue" style={{ flex: "1 1 190px" }}><SearchSelect id="co-issue" value={filters.issue} onChange={(v) => nav({ issue: v })} allLabel="Any" options={Object.entries(ISSUE).map(([k, v]) => ({ value: k, label: v }))} /></Field>
            <div className="row row--tight" style={{ alignSelf: "flex-end" }}>
              <Btn kind="primary" type="submit">Search</Btn>
              {filtered ? <Btn kind="ghost" onClick={() => go(`/cohorts${tab === "overview" ? "" : `?tab=${tab}`}`)}>Clear</Btn> : null}
            </div>
          </div>
        </form>
      ) : null}

      {tab === "overview" ? (
        <>
          <Tiles items={[
            ["Current students", String(n(t.current)), "var(--green-ink)", `In study in ${t.current_session ?? "the current session"}`, "/cohorts?tab=current"],
            ["Graduated", String(n(t.graduated)), null, "Awards approved by Senate, or marked so on the record", "/cohorts?tab=graduated"],
            ["Spillover", String(n(t.spillover)), n(t.spillover) ? "var(--amber-ink)" : null, `Beyond the programme's length, within ${summary.policy?.max_spillover_years ?? 2} sessions`, "/cohorts?tab=spillover"],
            ["Spillover limit reached", String(n(t.spillover_limit)), n(t.spillover_limit) ? "var(--red-ink)" : null, "For the Registry's review", "/cohorts?tab=spillover&spill=SPILLOVER_LIMIT_REACHED"],
          ]} />
          <Tiles items={[
            ["Expected to complete", String(n(t.expected_to_complete)), null, "Current students in their final session"],
            ["Graduation eligible", String(n(t.eligible)), null, "Audited with nothing unmet, awaiting Senate", "/cohorts?tab=all&conf=&status=&spill=&jamb=&q=&issue=&classification=GRADUATION_ELIGIBLE"],
            ["Requires review", String(n(t.review)), n(t.review) ? "var(--red-ink)" : null, `${n(t.requires_review)} too thin to judge · ${n(t.proposals_validated)} validated proposals`, "/cohorts?tab=review"],
            ["Historical", String(n(t.historical)), null, `${n(t.deferred)} deferred · ${n(t.withdrawn)} withdrawn · ${n(t.discontinued)} discontinued · graduated`],
          ]} />
          <div className="grid grid--2">
            <Panel title="By effective cohort" right="The cohort that carries the student, JAMB year beside it">
              <DTable pageSize={0} cols={["Cohort", "JAMB year|mid", "Students|mid", "Current|mid", "Graduated|mid", "Spillover|mid"]} rows={summary.byCohort.map((c, i) => [
                <span key={"k" + i}>{c.key === "Not stated" ? <span className="sub2">Not stated</span> : <a className="lnk" href={`/cohorts?tab=all&cohort=${encodeURIComponent(c.key)}`}>{c.key}</a>}</span>,
                <span key={"j" + i} className="tnum">{c.jamb_year ?? "—"}</span>, <span key={"n" + i} className="tnum">{n(c.n)}</span>,
                <span key={"c" + i} className="tnum">{n(c.current)}</span>, <span key={"g" + i} className="tnum">{n(c.graduated)}</span>,
                <span key={"s" + i} className={`tnum${n(c.spillover) ? " ink-amber" : ""}`}>{n(c.spillover)}</span>,
              ])} />
            </Panel>
            <Panel title="By faculty" right="Within your scope">
              <DTable pageSize={0} cols={["Faculty", "Students|mid", "Current|mid", "Graduated|mid", "Spillover|mid", "Review|mid"]} rows={summary.byFaculty.map((f, i) => [
                <span key={"k" + i}>{f.key}</span>, <span key={"n" + i} className="tnum">{n(f.n)}</span>, <span key={"c" + i} className="tnum">{n(f.current)}</span>,
                <span key={"g" + i} className="tnum">{n(f.graduated)}</span>, <span key={"s" + i} className={`tnum${n(f.spillover) ? " ink-amber" : ""}`}>{n(f.spillover)}</span>,
                <span key={"r" + i} className={`tnum${n(f.review) ? " ink-red" : ""}`}>{n(f.review)}</span>,
              ])} />
            </Panel>
          </div>
          <div className="grid grid--2">
            <Panel title="Students in study, by level" right="Current, spillover and eligible">
              <DTable pageSize={0} noPrint cols={["Level", "Students|mid"]} rows={summary.byLevel.map((l, i) => [<span key={"l" + i}>{l.key} Level</span>, <span key={"n" + i} className="tnum">{n(l.n)}</span>])} />
            </Panel>
            <Panel title="Spillover, by year" right={`Limit ${summary.policy?.max_spillover_years ?? 2} sessions`}>
              <DTable pageSize={0} noPrint cols={["State", "Students|mid"]} rows={summary.bySpillover.map((s, i) => [<span key={"s" + i}>{SPILL[s.key] ?? s.key}</span>, <span key={"n" + i} className="tnum">{n(s.n)}</span>])} />
            </Panel>
          </div>
          <div className="sub2">Graduated only on Senate&rsquo;s approval of the award. Computed {when(t.computed_to)}.</div>
        </>
      ) : null}

      {isList ? (
        <Panel title={TAB_TITLE[tab as Tab]} right={<span className="row row--inline row--tight">
          <span className="sub2">{list ? `${list.total} student${list.total === 1 ? "" : "s"}` : ""} · sorted by</span>
          {[["name", "Name"], ["matric", "Matric"], ["cohort", "Cohort"], ["jamb", "JAMB year"], ["level", "Level"], ["expected", "Expected"], ["spillover", "Spillover"], ["classification", "Standing"]].map(([k, l]) => (
            <Btn key={k} kind={filters.sort === k ? "primary" : "ghost"} size="sm" onClick={() => sortBy(k)}>{l}{filters.sort === k ? (filters.dir === "asc" ? " ↑" : " ↓") : ""}</Btn>
          ))}
          {list?.rows.length ? <>
            <Btn kind="ghost" size="sm" onClick={async () => downloadBlob(await brandedXlsx(`${TAB_TITLE[tab as Tab]} — Student Cohorts`, HEAD.slice(1), exportRows(list.rows), { sheetName: "Cohorts", serial: docSerial("COH"), meta: meta() }), `student-cohorts-${tab}.xlsx`)}>Excel</Btn>
            <Btn kind="ghost" size="sm" onClick={() => brandedPrint(`${TAB_TITLE[tab as Tab]} — Student Cohorts`, `Computed from the register for ${t.current_session ?? "the current session"}`, HEAD.slice(1), exportRows(list.rows), docSerial("COH"), { meta: meta(), generatedBy, orientation: "landscape" })}>PDF</Btn>
          </> : null}
        </span>}>
          {listProblem ? <PBody><Note kind="bad" title={listProblem.title ?? "The list could not be read"}>{listProblem.detail}</Note></PBody> : null}
          {tab === "review" && canDecide ? (
            <PBody>
              <div className="row row--base">
                <span className="sub2">Senate-approved awards of students still active can be reconciled in one act (rule R1).</span>
                <span className="grow" />
                <Btn kind="ghost" size="sm" disabled={busy} onClick={async () => { const j = await call("POST", "/apply", { rule: "R1", dryRun: true }, "Counted the approved awards awaiting reconciliation"); if (j) setApplyCount(Number(j.considered ?? 0)); }}>Count approved awards</Btn>
                {applyCount != null ? <Btn kind="primary" size="sm" disabled={busy || !applyCount} onClick={() => { if (window.confirm(`Reconcile ${applyCount} student${applyCount === 1 ? "" : "s"} whose award Senate approved to GRADUATED? Each change goes on the status history in your name.`)) void call("POST", "/apply", { rule: "R1", dryRun: false, batch: docSerial("REC") }, `${applyCount} approved award${applyCount === 1 ? "" : "s"} reconciled`).then(() => setApplyCount(null)); }}>Apply to {applyCount}</Btn> : null}
              </div>
            </PBody>
          ) : null}
          {list?.rows.length ? (
            <DTable pageSize={0} cols={["S/N|num", "Student", "Matric No.", "JAMB year|mid", "Entry → cohort", "Programme", "Level|mid", "Expected|mid", "Spillover|mid", "Status|mid", "Proposed|mid", "Reason", "Confidence|mid", "|num"]} rows={list.rows.map((r, i) => [
              <span key="sn" className="tnum sub2">{(list.page - 1) * list.size + i + 1}</span>,
              <span key="n"><strong>{fullName(r)}</strong><div className="sub2 tnum">{r.jamb_reg_no ?? r.admission_no ?? ""}</div></span>,
              <span key="m" className="tnum">{r.matric_no ?? <span className="sub2">—</span>}</span>,
              <span key="j" className="tnum">{r.jamb_year ?? "—"}</span>,
              <span key="c" className="tnum">{r.entry_session ?? "—"}{r.effective_cohort && r.effective_cohort !== r.entry_session ? <> → <b>{r.effective_cohort}</b><div className="sub2">{r.cohort_source === "MERGED" ? "session merged" : "set by the Registry"}</div></> : null}</span>,
              <span key="p">{r.programme}<div className="sub2">{r.faculty} · {r.duration_years ? `${r.duration_years} sessions` : "length not set"}</div></span>,
              <span key="l" className="tnum">{r.current_level ?? "—"}{r.computed_level != null && r.computed_level !== r.current_level ? <div className="sub2 ink-red">cohort says {r.computed_level}</div> : null}</span>,
              <span key="e" className="tnum">{r.expected_completion ?? "—"}</span>,
              <span key="s">{r.spillover_state === "NOT_APPLICABLE" ? <span className="sub2">—</span> : <Pil kind={r.spillover_state === "NORMAL" ? "grey" : r.spillover_state === "SPILLOVER_LIMIT_REACHED" ? "bad" : "warn"}>{SPILL[r.spillover_state] ?? r.spillover_state}</Pil>}</span>,
              <span key="st"><Pil kind={r.existing_status === "ACTIVE" ? "ok" : r.existing_status === "GRADUATED" ? "info" : "grey"}>{statusWord(r.existing_status)}</Pil></span>,
              <span key="pr"><Pil kind={CLASS[r.classification]?.[1] ?? "grey"}>{classWord(r.classification)}</Pil>{r.proposed_status !== r.existing_status ? <div className="sub2">status → {statusWord(r.proposed_status)}</div> : null}</span>,
              <span key="r" className="sub2">{RULE[r.rule] ?? r.rule}{issuesOf(r.issues).length ? <div>{issuesOf(r.issues).map((x) => ISSUE[x] ?? x).join("; ")}</div> : null}</span>,
              <Pil key="cf" kind={CONF[r.confidence]?.[1] ?? "grey"}>{CONF[r.confidence]?.[0] ?? r.confidence}</Pil>,
              <span key="a" className="row row--inline row--tight row--right"><Btn kind={r.confidence === "REVIEW" ? "primary" : "ghost"} size="sm" onClick={() => setOpen(r.id)}>Review</Btn><StudentOpen id={r.id} label="Record" kind="ghost" /></span>,
            ])} />
          ) : !listProblem ? <PBody><div className="sub2">{tab === "spillover" ? "No student is beyond their programme's length." : tab === "review" ? "Nothing waits for the Registry's decision." : tab === "graduated" ? "No graduate within these filters." : "No student within these filters."}</div></PBody> : null}
          {list ? (
            <PBody><div className="row row--base">
              <span className="sub2">{list.total ? `Showing ${(list.page - 1) * list.size + 1}–${Math.min(list.page * list.size, list.total)} of ${list.total}` : ""}</span>
              <span className="grow" />
              <Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => nav({ page: String(page - 1) })}>Previous</Btn>
              <Btn kind="ghost" size="sm" disabled={list.page * list.size >= list.total} onClick={() => nav({ page: String(page + 1) })}>Next</Btn>
              <select className="ctl" value={filters.size} onChange={(e) => nav({ size: e.target.value })} aria-label="Rows a page">{["25", "50", "100", "500", "2000"].map((s) => <option key={s} value={s}>{s} a page</option>)}</select>
            </div></PBody>
          ) : null}
        </Panel>
      ) : null}

      {tab === "quality" ? (
        <Panel title="Data quality" right="What the reconciliation found on the migrated register">
          {summary.byIssue.length ? (
            <DTable pageSize={0} cols={["Finding", "Students|mid", "|num"]} rows={summary.byIssue.map((x, i) => [
              <span key={"k" + i}><strong>{ISSUE[x.key] ?? x.key}</strong><div className="sub2 tnum">{x.key}</div></span>,
              <span key={"n" + i} className="tnum">{n(x.n)}</span>,
              <LinkBtn key={"o" + i} size="sm" href={`/cohorts?tab=all&issue=${x.key}`}>Open the list</LinkBtn>,
            ])} />
          ) : <PBody><div className="sub2">Nothing to report: every record carries what the reconciliation needs.</div></PBody>}
          <PBody><div className="sub2">Resolve each on the student&rsquo;s record; the position recomputes.</div></PBody>
        </Panel>
      ) : null}

      {tab === "settings" && settings ? (
        <>
          <Panel title="Spillover policy" right={`Set ${when(settings.policy.updated_at)}${settings.policy.updated_by ? ` by ${settings.policy.updated_by}` : ""}`}>
            <PBody>
              <div className="row row--base">
                <Field id="co-years" label="Maximum spillover, in sessions beyond the programme's length" style={{ flex: "0 1 320px" }}>
                  <select id="co-years" className="ctl" value={years} onChange={(e) => setYears(e.target.value)} disabled={!canSet}>{[0, 1, 2, 3, 4, 5, 6].map((y) => <option key={y} value={String(y)}>{y}</option>)}</select>
                </Field>
                {canSet ? <Btn kind="primary" disabled={busy || years === String(settings.policy.max_spillover_years)} onClick={() => void call("PUT", "/settings", { maxSpilloverYears: Number(years) }, `Spillover limit set to ${years} sessions`)}>Save</Btn> : null}
                <span className="sub2">Beyond it a student is flagged for the Registry&rsquo;s review.</span>
              </div>
            </PBody>
          </Panel>
          <Panel title="Academic sessions" right="A cancelled session is merged into the one that carried its students; their entry session stays">
            <DTable pageSize={0} cols={["Session", "State|mid", "Merged into", "Reason", "Entrants|mid", "Cohort size|mid", "|num"]} rows={settings.sessions.map((s) => [
              <span key="n" className="tnum b600">{s.name}</span>,
              <Pil key="s" kind={s.state === "CURRENT" ? "ok" : s.state === "CANCELLED" ? "bad" : s.state === "PLANNED" || s.state === "DRAFT" ? "info" : "grey"}>{s.state.charAt(0) + s.state.slice(1).toLowerCase()}</Pil>,
              <span key="m" className="tnum">{s.merged_into ?? <span className="sub2">—</span>}</span>,
              <span key="r" className="sub2">{s.merged_reason ?? ""}{s.merged_minute ? ` · ${s.merged_minute}` : ""}{s.merged_on ? ` · ${when(s.merged_on)}` : ""}</span>,
              <span key="e" className="tnum">{n(s.entrants)}</span>, <span key="c" className="tnum">{n(s.cohort_size)}</span>,
              <span key="a" className="row row--inline row--tight row--right">
                {canSet && s.state === "CANCELLED" ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { const why = window.prompt(`Undo the merger of ${s.name}? Say why.`); if (why && why.trim()) void call("POST", `/sessions/${s.name}/unmerge`, { reason: why.trim() }, `${s.name} restored as a session of its own`); }}>Undo merger</Btn> : null}
                {canSet && s.state !== "CANCELLED" && s.state !== "CURRENT" ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => setMerge({ session: s.name, into: "", reason: "", minute: "" })}>Cancel and merge</Btn> : null}
              </span>,
            ])} />
          </Panel>
          {settings.awards.length ? (
            <Panel title="Postgraduate awards" right="A postgraduate programme's level does not advance; its length is in sessions, every programme of an award in one act">
              <DTable pageSize={0} noPrint cols={["Award", "Programmes|mid", "Length set|mid", "Active students|mid", "|num"]} rows={settings.awards.map((a) => [
                <span key="a" className="b600">{a.award}</span>, <span key="p" className="tnum">{n(a.programmes)}</span>,
                <span key="c" className={`tnum${n(a.configured) < n(a.programmes) ? " ink-red" : ""}`}>{n(a.configured)} of {n(a.programmes)}{a.min_years ? ` · ${a.min_years === a.max_years ? `${a.min_years}` : `${a.min_years}–${a.max_years}`} sessions` : ""}</span>,
                <span key="s" className="tnum">{n(a.active_students)}</span>,
                canSet ? <Btn key="x" kind="ghost" size="sm" onClick={() => setAward({ award: a.award, years: String(a.min_years ?? ""), note: "" })}>Set the length</Btn> : <span key="x" />,
              ])} />
            </Panel>
          ) : null}
          <Panel title="Programme lengths" right="Undergraduate programmes seeded from the rule in force and confirmed by the Registry; a postgraduate programme's length is set, never guessed">
            <DTable cols={["Programme", "Faculty", "Last level|mid", "Length|mid", "Active students|mid", "Note", "|num"]} rows={settings.programmes.map((p) => [
              <span key="p"><strong>{p.name}</strong><div className="sub2 tnum">{p.code}{p.category ? ` · ${p.category}` : ""}</div></span>,
              <span key="f" className="sub2">{p.faculty ?? ""}{p.department ? ` · ${p.department}` : ""}</span>,
              <span key="l" className="tnum">{p.final_level ?? <span className="sub2">—</span>}</span>,
              <span key="y" className="tnum">{p.duration_years ? `${p.duration_years} sessions` : p.final_level ? `${(p.final_level - 100) / 100 + 1} sessions from 100 Level` : <Pil kind="bad">Not set</Pil>}</span>,
              <span key="n" className="tnum">{n(p.active_students)}</span>,
              <span key="o" className="sub2">{p.final_level_note ?? ""}</span>,
              canSet ? <Btn key="a" kind="ghost" size="sm" onClick={() => setLength({ code: p.code, name: p.name, level: String(p.final_level ?? ""), years: String(p.duration_years ?? ""), note: "", pg: p.category === "POST GRADUATE" || !!p.pg_award })}>Set</Btn> : <span key="a" />,
            ])} texts={settings.programmes.map((p) => `${p.code} ${p.name} ${p.faculty ?? ""} ${p.department ?? ""}`)} />
          </Panel>
        </>
      ) : null}

      {open ? <CohortStudentModal id={open} canDecide={canDecide} onClose={() => setOpen(null)} call={call} busy={busy} /> : null}

      {merge ? (
        <Modal title={`Cancel ${merge.session} and merge it into another session`} sub="Students keep their entry session and matriculation numbers" onClose={() => setMerge(null)}
          foot={<><Btn kind="ghost" onClick={() => setMerge(null)}>Cancel</Btn><Btn kind="urgent" disabled={busy || !merge.into || merge.reason.trim().length < 5} onClick={async () => { if (await call("POST", `/sessions/${merge.session}/merge`, { into: merge.into, reason: merge.reason.trim(), minute: merge.minute.trim() || null }, `${merge.session} cancelled and merged into ${merge.into}`)) setMerge(null); }}>Cancel and Merge</Btn></>}>
          <div className="stack">
            <Field id="mg-into" label="Merged into" required>
              <select id="mg-into" className="ctl" value={merge.into} onChange={(e) => setMerge({ ...merge, into: e.target.value })}>
                <option value="">Choose…</option>
                {settings?.sessions.filter((s) => s.name !== merge.session && s.state !== "CANCELLED").map((s) => <option key={s.name} value={s.name}>{s.name} · {s.state.toLowerCase()}</option>)}
              </select>
            </Field>
            <Field id="mg-reason" label="Reason" required><textarea id="mg-reason" className="ctl" rows={3} value={merge.reason} onChange={(e) => setMerge({ ...merge, reason: e.target.value })} maxLength={2000} placeholder="The Senate decision that cancelled the session" /></Field>
            <Field id="mg-minute" label="Senate minute"><input id="mg-minute" className="ctl" value={merge.minute} onChange={(e) => setMerge({ ...merge, minute: e.target.value })} maxLength={120} /></Field>
          </div>
        </Modal>
      ) : null}
      {length ? (
        <Modal title={`Length of ${length.name}`} sub={length.pg ? "A postgraduate programme runs a number of sessions" : "The last level, or a fixed number of sessions"} onClose={() => setLength(null)}
          foot={<><Btn kind="ghost" onClick={() => setLength(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || (!length.level && !length.years)} onClick={async () => { if (await call("PUT", `/programmes/${encodeURIComponent(length.code)}`, { finalLevel: length.level ? Number(length.level) : null, years: length.years ? Number(length.years) : null, note: length.note.trim() || null }, `${length.name}: ${length.years ? `${length.years} sessions` : `last level ${length.level}`}`)) setLength(null); }}>Save</Btn></>}>
          <div className="stack">
            <Field id="ln-level" label="Last level" hint="For a programme whose level advances each session">
              <select id="ln-level" className="ctl" value={length.level} onChange={(e) => setLength({ ...length, level: e.target.value })}><option value="">No level · the length is in sessions</option>{[300, 400, 500, 600, 700, 800, 900].map((l) => <option key={l} value={String(l)}>{l} Level · {(l - 100) / 100 + 1} sessions from 100 Level</option>)}</select>
            </Field>
            <Field id="ln-years" label="Length in sessions" hint="Set for a postgraduate programme; for a level-based programme only where it differs from the level arithmetic">
              <select id="ln-years" className="ctl" value={length.years} onChange={(e) => setLength({ ...length, years: e.target.value })}><option value="">{length.level ? "From the level" : "Choose…"}</option>{[1, 2, 3, 4, 5, 6, 7, 8].map((y) => <option key={y} value={String(y)}>{y}</option>)}</select>
            </Field>
            <Field id="ln-note" label="Note" hint="The approved programme document or the Senate minute"><input id="ln-note" className="ctl" value={length.note} onChange={(e) => setLength({ ...length, note: e.target.value })} maxLength={300} /></Field>
          </div>
        </Modal>
      ) : null}
      {award ? (
        <Modal title={`Length of every ${award.award} programme`} sub="Every active programme of the award takes this length" onClose={() => setAward(null)}
          foot={<><Btn kind="ghost" onClick={() => setAward(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !award.years} onClick={async () => { if (await call("POST", "/programmes/by-award", { award: award.award, years: Number(award.years), note: award.note.trim() || null }, `${award.award}: ${award.years} sessions`)) setAward(null); }}>Set the Length</Btn></>}>
          <div className="stack">
            <Field id="aw-years" label="Length in sessions" required>
              <select id="aw-years" className="ctl" value={award.years} onChange={(e) => setAward({ ...award, years: e.target.value })}><option value="">Choose…</option>{[1, 2, 3, 4, 5, 6, 7, 8].map((y) => <option key={y} value={String(y)}>{y}</option>)}</select>
            </Field>
            <Field id="aw-note" label="Note" hint="The approved programme document or the Senate minute"><input id="aw-note" className="ctl" value={award.note} onChange={(e) => setAward({ ...award, note: e.target.value })} maxLength={300} /></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}

/** one student's lifecycle, and the Registry's decision on it */
function CohortStudentModal({ id, canDecide, onClose, call, busy }: { id: string; canDecide: boolean; onClose: () => void; call: (m: "POST" | "PUT", p: string, b: unknown, r: string) => Promise<Record<string, unknown> | null>; busy: boolean }) {
  const [s, setS] = useState<CohortStudent | null | undefined>(undefined);
  const [status, setStatus] = useState("");
  const [reason, setReason] = useState("");
  const [cohort, setCohort] = useState("");
  const [why, setWhy] = useState("");
  if (s === undefined) {
    fetch(`/api/bff/api/v1/cohorts/students/${id}`).then(async (r) => { const j = r.ok ? ((await r.json()) as CohortStudent) : null; setS(j); if (j) setStatus(j.existing_status); });
    setS(null);
  }
  const d = s ?? null;
  return (
    <Modal title={d ? fullName(d) : "Loading…"} sub={d ? `${d.matric_no ?? d.admission_no ?? ""} · ${d.programme}` : ""} onClose={onClose} wide
      foot={<Btn kind="ghost" onClick={onClose}>Close</Btn>}>
      {!d ? <div className="sub2">Reading the record…</div> : (
        <div className="stack">
          <Note kind={d.confidence === "REVIEW" ? "bad" : "info"} title={`${classWord(d.classification)} · ${RULE[d.rule] ?? d.rule}`}>
            Status on the record <b>{statusWord(d.existing_status)}</b>{d.proposed_status !== d.existing_status ? <>; proposed <b>{statusWord(d.proposed_status)}</b></> : null}. Confidence {CONF[d.confidence]?.[0] ?? d.confidence}.
            {issuesOf(d.issues).length ? <div className="mt-1">{issuesOf(d.issues).map((x) => ISSUE[x] ?? x).join(" · ")}</div> : null}
          </Note>
          <div className="grid grid--3">
            {([["JAMB year", d.jamb_year], ["Entry session", d.entry_session], ["Effective cohort", `${d.effective_cohort ?? "—"}${d.cohort_source === "MERGED" ? " (session merged)" : d.cohort_source === "OVERRIDE" ? " (set by the Registry)" : ""}`],
              ["Matriculation", d.matric_no], ["Programme length", d.duration_years ? `${d.duration_years} sessions` : "not configured"], ["Current session", d.current_session],
              ["Level on record", d.current_level], ["Level the cohort implies", d.computed_level], ["Expected completion", d.expected_completion],
              ["Deferred sessions", d.deferred_sessions], ["Spillover", SPILL[d.spillover_state] ?? d.spillover_state], ["This session", d.registered_current ? "Registered" : d.enrolled_current ? "Enrolled" : "Not registered"],
              ["Last session on record", d.last_session], ["Graduation record", d.graduation_state ? `${d.graduation_state.toLowerCase()} · ${d.graduation_session}` : "none"], ["Outstanding courses", d.outstanding.length]] as [string, unknown][]).map(([k, v]) => (
              <div key={k} className="kv"><span className="k">{k}</span><span className="v tnum">{v == null || v === "" ? "—" : String(v)}</span></div>
            ))}
          </div>
          <div className="grid grid--2">
            <div className="stack">
              <div className="b600">Status history</div>
              {d.statusHistory.length ? <DTable pageSize={0} noPrint cols={["When|mid", "From → to", "Instrument / reason"]} rows={d.statusHistory.map((h, i) => [<span key={"w" + i} className="tnum sub2">{when(h.effective_on)}</span>, <span key={"s" + i}>{statusWord(h.from_status)} → <b>{statusWord(h.to_status)}</b></span>, <span key={"r" + i} className="sub2">{h.instrument ?? ""}{h.reason ? ` · ${h.reason}` : ""}</span>])} /> : <div className="sub2">No change on record.</div>}
              <div className="b600">Registrations and enrolments</div>
              {d.registrations.length || d.enrolments.length ? <DTable pageSize={0} noPrint cols={["Session", "Semester|mid", "Level|mid", "State"]} rows={[...d.registrations.map((r) => ({ session: r.session, semester: r.semester, level: r.level, state: `Registration ${r.status.toLowerCase()}` })), ...d.enrolments.filter((e) => !d.registrations.some((r) => r.session === e.session)).map((e) => ({ session: e.session, semester: null as number | null, level: e.level, state: "Enrolled" }))].sort((a, b) => a.session.localeCompare(b.session) || Number(a.semester ?? 0) - Number(b.semester ?? 0)).map((r, i) => [<span key={"s" + i} className="tnum">{r.session}</span>, <span key={"m" + i} className="tnum">{r.semester ?? "—"}</span>, <span key={"l" + i} className="tnum">{r.level}</span>, <span key={"t" + i} className="sub2">{r.state}</span>])} /> : <div className="sub2">Nothing on record.</div>}
              {d.deferments.length ? <><div className="b600">Deferments</div><DTable pageSize={0} noPrint cols={["Reference", "Period", "State", "Returns"]} rows={d.deferments.map((x, i) => [<span key={"r" + i} className="tnum">{x.reference}</span>, <span key={"p" + i}>{x.kind.toLowerCase()} · {x.session}{x.semester ? ` semester ${x.semester}` : ""}</span>, <span key={"s" + i} className="sub2">{x.state.toLowerCase()}</span>, <span key={"b" + i} className="tnum">{x.return_session ?? "—"}</span>])} /></> : null}
              {d.programmeChanges.length ? <><div className="b600">Programme changes</div><DTable pageSize={0} noPrint cols={["Session", "From → to", "State"]} rows={d.programmeChanges.map((x, i) => [<span key={"s" + i} className="tnum">{x.session}</span>, <span key={"p" + i}>{x.from_programme} → {x.to_programme}</span>, <span key={"t" + i} className="sub2">{x.state.toLowerCase()}</span>])} /></> : null}
            </div>
            <div className="stack">
              <div className="b600">Graduation record</div>
              {d.graduands.length ? <DTable pageSize={0} noPrint cols={["Session", "CGPA|mid", "Award", "Senate"]} rows={d.graduands.map((g, i) => [<span key={"s" + i} className="tnum">{g.session}</span>, <span key={"c" + i} className="tnum">{g.cgpa ?? "—"}</span>, <span key={"a" + i}>{g.award ?? ""}{g.unmet ? <div className="sub2 ink-red">{g.unmet}</div> : null}</span>, <span key={"m" + i} className="sub2">{g.senate_state.toLowerCase()}{g.senate_minute ? ` · ${g.senate_minute}` : ""}</span>])} /> : <div className="sub2">Not yet on a graduation list.</div>}
              <div className="b600">Outstanding courses</div>
              {d.outstanding.length ? <DTable pageSize={0} noPrint cols={["Course", "Units|mid", "Failed in"]} rows={d.outstanding.map((o, i) => [<span key={"c" + i}><b>{o.course_code}</b> {o.title}</span>, <span key={"u" + i} className="tnum">{o.units}</span>, <span key={"f" + i} className="sub2">{o.failed_in}</span>])} /> : <div className="sub2">None on the published record.</div>}
              <div className="b600">Decisions taken</div>
              {d.decisions.length ? <DTable pageSize={0} noPrint cols={["When|mid", "Decision", "By"]} rows={d.decisions.map((x, i) => [<span key={"w" + i} className="tnum sub2">{when(x.decided_at)}</span>, <span key={"d" + i}>{x.rule === "COHORT" ? `Cohort ${x.previous_cohort ?? "—"} → ${x.effective_cohort ?? "—"}` : `${statusWord(x.previous_status)} → ${statusWord(x.final_status)}`}<div className="sub2">{x.reason}{x.batch_ref ? ` · ${x.batch_ref}` : ""}</div></span>, <span key={"b" + i} className="sub2">{x.officer ?? "—"}{x.actor_office ? ` · ${x.actor_office}` : ""}</span>])} /> : <div className="sub2">None yet.</div>}
            </div>
          </div>
          {canDecide ? (
            <div className="grid grid--2">
              <Panel title="Decide the standing" right="On evidence; recorded in your name">
                <PBody><div className="stack">
                  <Field id="dc-status" label="Status on the record" required>
                    <select id="dc-status" className="ctl" value={status} onChange={(e) => setStatus(e.target.value)}>{STATUSES.map((x) => <option key={x} value={x}>{statusWord(x)}{x === "GRADUATED" ? " (Senate's approval required)" : ""}</option>)}</select>
                  </Field>
                  <Field id="dc-reason" label="Reason" required><textarea id="dc-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={2000} placeholder="The result, the minute, the letter that settles it" /></Field>
                  <div><Btn kind="primary" disabled={busy || reason.trim().length < 5} onClick={async () => { const j = await call("POST", `/students/${id}/decision`, { finalStatus: status, reason: reason.trim() }, `${fullName(d)}: standing decided`); if (j) { setReason(""); setS(undefined); } }}>Record the Decision</Btn></div>
                </div></PBody>
              </Panel>
              <Panel title="Correct the cohort" right={d.override ? `Set by ${d.override.set_by ?? "the Registry"} on ${when(d.override.set_at)}` : "Only where the session rule does not fit"}>
                <PBody><div className="stack">
                  <Field id="oc-cohort" label="Effective cohort" hint="A re-entry or a transfer in; the entry session stays as it is">
                    <select id="oc-cohort" className="ctl" value={cohort} onChange={(e) => setCohort(e.target.value)}><option value="">Choose…</option>{d.sessions.filter((x) => x.state !== "CANCELLED").map((x) => <option key={x.name} value={x.name}>{x.name}</option>)}</select>
                  </Field>
                  <Field id="oc-why" label="Reason" required><input id="oc-why" className="ctl" value={why} onChange={(e) => setWhy(e.target.value)} maxLength={2000} /></Field>
                  <div className="row row--tight">
                    <Btn kind="secondary" disabled={busy || !cohort || why.trim().length < 5} onClick={async () => { const j = await call("POST", `/students/${id}/cohort`, { cohort, reason: why.trim() }, `${fullName(d)}: cohort set to ${cohort}`); if (j) { setWhy(""); setS(undefined); } }}>Set the Cohort</Btn>
                    {d.override ? <Btn kind="ghost" disabled={busy || why.trim().length < 5} onClick={async () => { const j = await call("POST", `/students/${id}/cohort`, { cohort: null, reason: why.trim() }, `${fullName(d)}: cohort correction removed`); if (j) { setWhy(""); setS(undefined); } }}>Remove the Correction</Btn> : null}
                  </div>
                </div></PBody>
              </Panel>
            </div>
          ) : null}
        </div>
      )}
    </Modal>
  );
}
