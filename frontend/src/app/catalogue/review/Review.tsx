"use client";

/** V445: the ownership review of the course pool. One place to see every course, who owns it, who offers it, what the review flags —
 *  and to say the word on each (correct, incorrect owner, requires review), correct an owner one by one or in bulk with a reason,
 *  and take the report away. A flag never changes an owner; a person does, on the trail. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, day } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { ISSUE, KINDS, LEVELS, REVIEW, STATE, courseSemName, type CourseList, type CourseListRow, type Directory, type DuplicatePair, type ReviewStatus, type ReviewSummary } from "@/lib/catalogue";

export type ReviewFilters = Record<"q" | "fac" | "dept" | "prog" | "level" | "semester" | "kind" | "state" | "session" | "review" | "issue" | "sort" | "dir" | "size", string>;

const CENTRAL = ["academic", "registrar", "dregistrar", "admin", "super"];
const REVIEWERS = [...CENTRAL, "hod", "dean"];

export function Review({ list, directory, summary, sessions, filters, page, duplicates, actingOffice, generatedBy }: {
  list: CourseList; directory: Directory | null; summary: ReviewSummary | null; sessions: string[]; filters: ReviewFilters; page: number;
  duplicates: DuplicatePair[]; actingOffice: string | null; generatedBy: string | null;
}) {
  const go = useQueryNav();
  const router = useRouter();
  const central = CENTRAL.includes(actingOffice ?? "");
  const mayReview = REVIEWERS.includes(actingOffice ?? "");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [marking, setMarking] = useState<{ row: CourseListRow; status: ReviewStatus; note: string } | null>(null);
  const [owning, setOwning] = useState<{ row: CourseListRow; dept: string; why: string } | null>(null);
  const [bulk, setBulk] = useState<{ dept: string; why: string; preview: BulkPreview | null } | null>(null);

  function nav(patch: Partial<ReviewFilters & { page: string }>) {
    const next: Record<string, string> = { ...filters, page: "1", ...patch };
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(next)) if (v && !(k === "sort" && v === "dept") && !(k === "dir" && v === "asc") && !(k === "size" && v === "50") && !(k === "page" && v === "1")) qs.set(k, v);
    go(`/catalogue/review${qs.toString() ? "?" + qs.toString() : ""}`);
  }
  const filtered = Object.entries(filters).some(([k, v]) => v && !["sort", "dir", "size"].includes(k));
  const depts = (directory?.departments ?? []).filter((d) => !filters.fac || d.faculty_code === filters.fac);
  const progs = (directory?.programmes ?? []).filter((p) => (!filters.dept || p.dept_code === filters.dept) && (!filters.fac || p.faculty_code === filters.fac));
  const deptName = (code: string | null | undefined) => (directory?.departments ?? []).find((d) => d.code === code)?.name ?? code ?? "";
  const offeringDepts = (r: CourseListRow) => [...new Set(r.programmes.map((p) => p.deptName ?? p.dept ?? "").filter(Boolean))];

  async function send(method: "POST", path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = j ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return null; }
      return (j ?? {}) as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  async function mark() {
    if (!marking) return;
    const j = await send("POST", `/courses/${encodeURIComponent(marking.row.code)}/review`, { status: marking.status, note: marking.note }, `${marking.row.code} marked ${REVIEW[marking.status][1].toLowerCase()}`);
    if (j) { notify(`${marking.row.code}: ${REVIEW[marking.status][1]}`); setMarking(null); router.refresh(); }
  }

  async function changeOwner() {
    if (!owning) return;
    const j = await send("POST", `/courses/${encodeURIComponent(owning.row.code)}/owner`, { department: owning.dept, programme: null, reason: owning.why.trim() }, `${owning.row.code} moved to ${owning.dept}`);
    if (j) { notify(`${owning.row.code} now belongs to ${deptName(owning.dept)}`); setOwning(null); router.refresh(); }
  }

  async function bulkPreview(dept: string) {
    const j = await send("POST", "/courses/bulk-owner", { codes: [...selected], department: dept, dryRun: true }, "Bulk owner change previewed");
    if (j) setBulk((b) => (b ? { ...b, dept, preview: j as unknown as BulkPreview } : b));
  }

  async function bulkApply() {
    if (!bulk || !bulk.preview) return;
    const j = await send("POST", "/courses/bulk-owner", { codes: [...selected], department: bulk.dept, reason: bulk.why.trim(), dryRun: false }, `${selected.size} courses moved to ${bulk.dept}`);
    if (j) { notify(`${(j.moved as unknown[] | undefined)?.length ?? selected.size} course(s) now belong to ${deptName(bulk.dept)}`); setBulk(null); setSelected(new Set()); router.refresh(); }
  }

  /** the report: the filtered set, up to 2,000 rows, with S/N from 1 */
  async function exportRows(): Promise<(string | number)[][]> {
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(filters)) if (v && k !== "size") qs.set(k, v);
    qs.set("size", "2000");
    const r = await fetch(`/api/bff/api/v1/catalogue/courses/list?${qs.toString()}`, { cache: "no-store" });
    const j = (await r.json().catch(() => null)) as CourseList | null;
    const rows = r.ok && j ? j.rows : list.rows;
    return rows.map((x, i) => [i + 1, x.code, x.title, x.units, x.faculty_name ?? "", x.dept_name ?? x.dept_code ?? "", offeringDepts(x).join("; "),
      x.programmes.map((p) => p.name).join("; "), x.level, courseSemName(x.semester, x.both_semesters), x.last_session ?? "", STATE[x.state]?.[1] ?? x.state,
      REVIEW[x.review_status ?? "NOT_REVIEWED"][1], (x.issues ?? []).map((k) => ISSUE[k] ?? k).join("; "), x.updated_at ? day(x.updated_at) : ""]);
  }
  const HEAD = ["S/N", "Course Code", "Course Title", "Units", "Course Owner Faculty", "Course Owner Department", "Offering Departments", "Programmes", "Level", "Semester", "Session", "Status", "Review Status", "Issues", "Last Updated"];
  const meta = (): [string, string][] => [["Filters", filtered ? Object.entries(filters).filter(([k, v]) => v && !["sort", "dir", "size"].includes(k)).map(([k, v]) => `${k}=${v}`).join(", ") : "none"], ["Courses", String(list.total)]];

  const tile = (label: string, value: number | undefined, patch: Partial<ReviewFilters>, sub: string) =>
    [<button key={label} type="button" className="lnk" style={{ font: "inherit", padding: 0, background: "none", border: 0, cursor: "pointer", color: "inherit" }} onClick={() => nav(patch)}>{label}</button>, String(value ?? "—"), sub] as [React.ReactNode, React.ReactNode, string];
  const allOnPage = list.rows.length > 0 && list.rows.every((r) => selected.has(r.code));

  return (
    <>
      <PageHead title="Course ownership review" description="Every course, who owns it, who offers it, and what the review flags; the owner corrected by a person, with a reason, on the trail."
        actions={<><LinkBtn href="/catalogue/all">All courses</LinkBtn><LinkBtn href="/catalogue/structure">Programme structure</LinkBtn><LinkBtn href="/catalogue/upload">Course upload</LinkBtn></>} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {summary ? (
        <Tiles items={[
          tile("Total courses", summary.total, { state: "", review: "", issue: "" }, `${summary.departments} departments hold courses`),
          tile("Active", summary.live, { state: "LIVE" }, "Live on the catalogue"),
          tile("Inactive", summary.ended, { state: "ENDED" }, "Ended"),
          tile("Not reviewed", summary.not_reviewed, { review: "NOT_REVIEWED" }, "Awaiting the review's word"),
          tile("Marked incorrect", summary.incorrect_owner, { review: "INCORRECT_OWNER" }, "Owner to correct"),
          tile("Requiring review", summary.requires_review, { review: "REQUIRES_REVIEW" }, "Flagged by a person"),
          tile("With issues", summary.with_issues, { issue: "ANY" }, `${summary.code_names_other} code names another · ${summary.not_in_structure} in no structure`),
          tile("Possible duplicates", summary.possible_duplicates, { issue: "POSSIBLE_DUPLICATE" }, `${duplicates.length} title pairs below`),
        ]} />
      ) : null}

      <form className="filterbar" onSubmit={(e) => { e.preventDefault(); const f = new FormData(e.currentTarget); nav({ q: String(f.get("q") ?? "") }); }}>
        <div className="row">
          <Field id="cr-q" label="Search" style={{ flex: "2 1 220px" }}><input id="cr-q" name="q" className="ctl" type="search" defaultValue={filters.q} placeholder="Code, title, description, department, faculty, programme, 100 level, first semester" /></Field>
          {!list.scope.dept ? <>
            {!list.scope.fac ? <Field id="cr-fac" label="Faculty" style={{ flex: "1 1 170px" }}><SearchSelect id="cr-fac" value={filters.fac} onChange={(v) => nav({ fac: v, dept: "", prog: "" })} allLabel="Any faculty" options={(directory?.faculties ?? []).map((f) => ({ value: f.code, label: f.name }))} /></Field> : null}
            <Field id="cr-dept" label="Department (owns or offers)" style={{ flex: "1 1 190px" }}><SearchSelect id="cr-dept" value={filters.dept} onChange={(v) => nav({ dept: v, prog: "" })} allLabel="Any department" options={depts.map((d) => ({ value: d.code, label: d.name }))} /></Field>
          </> : null}
          <Field id="cr-prog" label="Programme offering" style={{ flex: "1 1 200px" }}><SearchSelect id="cr-prog" value={filters.prog} onChange={(v) => nav({ prog: v })} allLabel="Any programme" options={progs.map((p) => ({ value: p.code, label: p.name }))} /></Field>
          <Field id="cr-level" label="Level" style={{ flex: "0 1 90px" }}><select id="cr-level" className="ctl" value={filters.level} onChange={(e) => nav({ level: e.target.value })}><option value="">Any</option>{LEVELS.map((l) => <option key={l} value={String(l)}>{l}</option>)}</select></Field>
          <Field id="cr-sem" label="Semester" style={{ flex: "0 1 100px" }}><select id="cr-sem" className="ctl" value={filters.semester} onChange={(e) => nav({ semester: e.target.value })}><option value="">Any</option><option value="1">First</option><option value="2">Second</option><option value="3">Third</option></select></Field>
          <Field id="cr-kind" label="Course type" style={{ flex: "0 1 110px" }}><select id="cr-kind" className="ctl" value={filters.kind} onChange={(e) => nav({ kind: e.target.value })}><option value="">Any</option>{KINDS.map((k) => <option key={k} value={k}>{k}</option>)}</select></Field>
          <Field id="cr-state" label="Status" style={{ flex: "0 1 120px" }}><select id="cr-state" className="ctl" value={filters.state} onChange={(e) => nav({ state: e.target.value })}><option value="">Any</option>{Object.entries(STATE).map(([k, v]) => <option key={k} value={k}>{v[1]}</option>)}</select></Field>
          <Field id="cr-session" label="Offered in session" style={{ flex: "0 1 130px" }}><select id="cr-session" className="ctl" value={filters.session} onChange={(e) => nav({ session: e.target.value })}><option value="">Any</option>{sessions.map((s) => <option key={s} value={s}>{s}</option>)}</select></Field>
          <Field id="cr-review" label="Review status" style={{ flex: "0 1 150px" }}><select id="cr-review" className="ctl" value={filters.review} onChange={(e) => nav({ review: e.target.value })}><option value="">Any</option>{(Object.keys(REVIEW) as ReviewStatus[]).map((k) => <option key={k} value={k}>{REVIEW[k][1]}</option>)}</select></Field>
          <Field id="cr-issue" label="Issue" style={{ flex: "0 1 200px" }}><select id="cr-issue" className="ctl" value={filters.issue} onChange={(e) => nav({ issue: e.target.value })}><option value="">Any</option><option value="ANY">Any issue</option>{Object.entries(ISSUE).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
          <div className="row row--tight" style={{ alignSelf: "flex-end" }}>
            <Btn kind="primary" type="submit">Search</Btn>
            {filtered ? <Btn kind="ghost" onClick={() => go("/catalogue/review")}>Clear</Btn> : null}
          </div>
        </div>
      </form>

      <Panel title="Courses" right={<span className="row row--inline row--tight">
        <span className="sub2">{list.total.toLocaleString()} course{list.total === 1 ? "" : "s"} · page {list.page}</span>
        <Btn kind="ghost" size="sm" onClick={async () => downloadBlob(await brandedXlsx("Course Ownership Report", HEAD, await exportRows(), { sheetName: "Ownership", serial: docSerial("CRSOWN"), meta: meta() }), "course-ownership-report.xlsx")}>Excel</Btn>
        <Btn kind="ghost" size="sm" onClick={async () => brandedPrint("Course Ownership Report", "Every course, its owner, who offers it, the review's word", HEAD, await exportRows(), docSerial("CRSOWN"), { meta: meta(), generatedBy: generatedBy ?? undefined })}>PDF</Btn>
      </span>}>
        {central ? (
          <div className="row row--inline row--tight" style={{ padding: "8px 12px", borderBottom: "1px solid var(--line)" }}>
            <Btn kind="ghost" size="sm" onClick={() => { const n = new Set(selected); for (const r of list.rows) { if (allOnPage) n.delete(r.code); else n.add(r.code); } setSelected(n); }}>{allOnPage ? "Unselect this page" : "Select this page"}</Btn>
            {selected.size ? <>
              <span className="b600">{selected.size} selected</span>
              <Btn kind="secondary" size="sm" disabled={busy} onClick={() => setBulk({ dept: "", why: "", preview: null })}>Change owner department…</Btn>
              <Btn kind="ghost" size="sm" onClick={() => setSelected(new Set())}>Clear selection</Btn>
            </> : <span className="sub2">Pick courses to change their owner in one act.</span>}
          </div>
        ) : null}
        {list.rows.length ? (
          <DTable cols={[central ? "Pick" : "", "Course", "Units|num", "Owner department", "Offering departments", "Programmes", "Level|mid", "Status", "Review", "Issues", "Updated|mid", "Action|num"]}
            rows={list.rows.map((r) => [
              central ? <input key="s" type="checkbox" aria-label={`Select ${r.code}`} checked={selected.has(r.code)} onChange={(e) => { const n = new Set(selected); if (e.target.checked) n.add(r.code); else n.delete(r.code); setSelected(n); }} /> : "",
              <span key="c"><Link className="lnk tnum b600" href={`/catalogue/course?code=${encodeURIComponent(r.code)}`}>{r.code}</Link><div className="sub2">{r.title}</div></span>,
              <span className="tnum" key="u">{r.units}</span>,
              <span key="o"><b>{r.dept_name ?? r.dept_code ?? "—"}</b><div className="sub2">{r.faculty_name ?? ""}</div></span>,
              <span className="sub2" key="od">{offeringDepts(r).join(", ") || "—"}</span>,
              <span className="sub2" key="p">{r.programmes.length ? `${r.programmes.length} programme${r.programmes.length === 1 ? "" : "s"}` : "none"}</span>,
              <span className="tnum" key="l">{r.level} · {courseSemName(r.semester, r.both_semesters).replace("First and second", "1 & 2")}</span>,
              <Pil key="st" kind={STATE[r.state]?.[0] ?? "grey"}>{STATE[r.state]?.[1] ?? r.state}</Pil>,
              <span key="rv"><Pil kind={REVIEW[r.review_status ?? "NOT_REVIEWED"][0]}>{REVIEW[r.review_status ?? "NOT_REVIEWED"][1]}</Pil>{r.review_note ? <div className="sub2" title={r.review_note}>{r.review_note.length > 40 ? r.review_note.slice(0, 37) + "…" : r.review_note}</div> : null}</span>,
              <span key="is" className="row row--tight" style={{ flexWrap: "wrap" }}>{(r.issues ?? []).map((k) => <Pil key={k} kind={k === "POSSIBLE_DUPLICATE" || k === "MOVED_BY_RULE" ? "warn" : "bad"} title={ISSUE[k] ?? k}>{(ISSUE[k] ?? k).split(" (")[0].split(" —")[0]}</Pil>)}{(r.issues ?? []).length ? null : <span className="sub2">—</span>}</span>,
              <span className="tnum sub2" key="up">{r.updated_at ? day(r.updated_at) : "—"}</span>,
              <span key="a" className="row row--inline row--tight row--right">
                {mayReview ? <Btn kind="ghost" size="sm" onClick={() => setMarking({ row: r, status: (r.review_status ?? "NOT_REVIEWED") === "NOT_REVIEWED" ? "CORRECT" : r.review_status!, note: r.review_note ?? "" })}>Mark</Btn> : null}
                {central && !r.ended_on ? <Btn kind="ghost" size="sm" onClick={() => setOwning({ row: r, dept: r.dept_code ?? "", why: "" })}>Change owner</Btn> : null}
                <LinkBtn size="sm" href={`/catalogue/course?code=${encodeURIComponent(r.code)}`}>Details</LinkBtn>
              </span>,
            ])} texts={list.rows.map((r) => `${r.code} ${r.title} ${r.dept_name ?? ""} ${(r.issues ?? []).join(" ")}`)} />
        ) : <PBody><div className="sub2">No course matches.</div></PBody>}
        <div className="row row--inline row--tight" style={{ padding: "8px 12px" }}>
          <Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => nav({ page: String(page - 1) })}>Previous</Btn>
          <Btn kind="ghost" size="sm" disabled={list.page * list.size >= list.total} onClick={() => nav({ page: String(page + 1) })}>Next</Btn>
          <select className="ctl" value={filters.size || "50"} onChange={(e) => nav({ size: e.target.value })} aria-label="Rows a page">{["25", "50", "100", "500", "2000"].map((s) => <option key={s} value={s}>{s} a page</option>)}</select>
          <span className="sub2">Sort:</span>
          {[["dept", "Department"], ["code", "Code"], ["title", "Title"], ["review", "Review"], ["updated", "Updated"]].map(([k, l]) => <Btn key={k} kind={filters.sort === k || (!filters.sort && k === "dept") ? "secondary" : "ghost"} size="sm" onClick={() => nav({ sort: k, dir: filters.sort === k && filters.dir !== "desc" ? "desc" : "asc" })}>{l}</Btn>)}
        </div>
      </Panel>

      {duplicates.length ? (
        <Panel title="Possible duplicates by title" right="The same title at the same level and semester under two codes — investigate; a confirmed pair is merged on All courses">
          <DTable cols={["Keep", "Also", "Owners", "Differences"]} rows={duplicates.map((d) => [
            <span key="k"><Link className="lnk tnum b600" href={`/catalogue/course?code=${encodeURIComponent(d.keep_code)}`}>{d.keep_code}</Link><div className="sub2">{d.keep_title}</div></span>,
            <span key="m"><Link className="lnk tnum b600" href={`/catalogue/course?code=${encodeURIComponent(d.merge_code)}`}>{d.merge_code}</Link><div className="sub2">{d.merge_title}</div></span>,
            <span className="sub2" key="o">{deptName(d.keep_dept)} · {deptName(d.merge_dept)}</span>,
            <span className="sub2" key="d">{d.differences.length ? d.differences.join(", ").toLowerCase() : "none"}</span>,
          ])} texts={duplicates.map((d) => `${d.keep_code} ${d.merge_code} ${d.keep_title}`)} />
        </Panel>
      ) : null}

      {marking ? (
        <Modal title={`The review's word on ${marking.row.code}`} sub={`${marking.row.title} · owned by ${marking.row.dept_name ?? marking.row.dept_code ?? "—"}`} onClose={() => setMarking(null)}
          foot={<><Btn kind="primary" disabled={busy || (["INCORRECT_OWNER", "REQUIRES_REVIEW"].includes(marking.status) && marking.note.trim().length < 3)} onClick={() => void mark()}>{busy ? "Saving…" : "Save"}</Btn><Btn kind="ghost" onClick={() => setMarking(null)}>Cancel</Btn></>}>
          <Field id="rv-status" label="Status"><select id="rv-status" className="ctl" value={marking.status} onChange={(e) => setMarking({ ...marking, status: e.target.value as ReviewStatus })}>{(Object.keys(REVIEW) as ReviewStatus[]).map((k) => <option key={k} value={k}>{REVIEW[k][1]}</option>)}</select></Field>
          <Field id="rv-note" label="Note" hint={["INCORRECT_OWNER", "REQUIRES_REVIEW"].includes(marking.status) ? "Required: what is wrong, or what must be looked at" : "Optional"}><textarea id="rv-note" className="ctl" rows={2} maxLength={1000} value={marking.note} onChange={(e) => setMarking({ ...marking, note: e.target.value })} /></Field>
          {(marking.row.issues ?? []).length ? <div className="sub2">Flagged: {(marking.row.issues ?? []).map((k) => ISSUE[k] ?? k).join("; ")}.</div> : null}
        </Modal>
      ) : null}

      {owning ? (
        <Modal title={`Change the owner of ${owning.row.code}`} sub="Every offering, registration and result stays on the course; the change goes on the owner trail" onClose={() => setOwning(null)}
          foot={<><Btn kind="primary" disabled={busy || !owning.dept || owning.dept === owning.row.dept_code || owning.why.trim().length < 3} onClick={() => void changeOwner()}>{busy ? "Moving…" : "Change owner"}</Btn><Btn kind="ghost" onClick={() => setOwning(null)}>Cancel</Btn></>}>
          <div className="mb-2"><b>Old owner:</b> {owning.row.dept_name ?? owning.row.dept_code ?? "—"}{owning.dept && owning.dept !== owning.row.dept_code ? <> · <b>New owner:</b> {deptName(owning.dept)} ({(directory?.departments ?? []).find((d) => d.code === owning.dept)?.faculty_code ?? ""})</> : null}</div>
          <Field id="ow-dept" label="New owner department"><SearchSelect id="ow-dept" value={owning.dept} placeholder="Search a department…" options={(directory?.departments ?? []).map((d) => ({ value: d.code, label: d.name }))} onChange={(v) => setOwning({ ...owning, dept: v })} /></Field>
          <Field id="ow-why" label="Reason" hint="Kept on the owner history"><textarea id="ow-why" className="ctl" rows={2} maxLength={2000} value={owning.why} onChange={(e) => setOwning({ ...owning, why: e.target.value })} placeholder="Course was uploaded under the wrong department." /></Field>
          <div className="sub2">Historical registrations, results and allocations are not changed by a change of owner.</div>
        </Modal>
      ) : null}

      {bulk ? (
        <Modal title={`Change the owner of ${selected.size} course${selected.size === 1 ? "" : "s"}`} sub="One act, one reason; all move or none" onClose={() => setBulk(null)}
          foot={<>
            {bulk.preview ? <Btn kind="urgent" disabled={busy || bulk.why.trim().length < 5} onClick={() => void bulkApply()}>{busy ? "Moving…" : `Move ${selected.size} to ${deptName(bulk.dept)}`}</Btn>
              : <Btn kind="primary" disabled={busy || !bulk.dept} onClick={() => void bulkPreview(bulk.dept)}>{busy ? "Checking…" : "Preview"}</Btn>}
            <Btn kind="ghost" onClick={() => setBulk(null)}>Cancel</Btn>
          </>}>
          <Field id="bk-dept" label="New owner department"><SearchSelect id="bk-dept" value={bulk.dept} placeholder="Search a department…" options={(directory?.departments ?? []).map((d) => ({ value: d.code, label: d.name }))} onChange={(v) => setBulk({ ...bulk, dept: v, preview: null })} /></Field>
          {bulk.preview ? (
            <div className="mb-2">
              <div><b>Number of courses:</b> {bulk.preview.courses}</div>
              <div><b>Current departments:</b> {Object.entries(bulk.preview.byDepartment).map(([d, n]) => `${d}: ${n}`).join(" · ")}</div>
              <div><b>New owner:</b> {bulk.preview.target.name} ({bulk.preview.target.faculty ?? bulk.preview.target.code})</div>
              <div className="sub2">These courses carry {bulk.preview.impact.registrations.toLocaleString()} registrations, {bulk.preview.impact.scoreSheets.toLocaleString()} score sheets and {bulk.preview.impact.allocations.toLocaleString()} allocations; none is changed by the move.{bulk.preview.alreadyOwned ? ` ${bulk.preview.alreadyOwned} already belong to the new owner.` : ""}</div>
            </div>
          ) : null}
          <Field id="bk-why" label="Reason" hint="Kept on every course's owner history"><textarea id="bk-why" className="ctl" rows={2} maxLength={400} value={bulk.why} onChange={(e) => setBulk({ ...bulk, why: e.target.value })} placeholder="Correction of incorrect department assignments from the initial bulk upload." /></Field>
        </Modal>
      ) : null}
    </>
  );
}

interface BulkPreview {
  courses: number; byDepartment: Record<string, number>; target: { code: string; name: string; faculty: string | null };
  impact: { registrations: number; scoreSheets: number; allocations: number }; alreadyOwned: number; dryRun: boolean;
}
