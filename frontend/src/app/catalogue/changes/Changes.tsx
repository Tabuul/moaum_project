"use client";
/** Every change of a course's code and title (V713), newest first: the course as it reads now, what changed from what to what,
 *  why, on which ticket, by whom and when. The trail is never altered; the report is the filtered trail, up to 2,000 rows. */
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, LinkBtn, PageHead, Panel, PBody } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { CHANGE_SOURCE, type CourseChangeList, type CourseChangeRow } from "@/lib/course-correction";

export type ChangeFilters = Record<"q" | "field" | "source" | "from" | "to", string>;

const at = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" });

/** the reason as one line: the reason chosen and its remarks, or the request's own words */
function why(r: CourseChangeRow): string {
  const chosen = [r.reason_words, r.remarks].filter(Boolean).join(" — ");
  const past = r.source === "CORRECTION" && r.field === "TITLE" && r.past_classes === false ? " (classes already registered or examined keep their title)" : "";
  return (chosen || r.reason || "") + past;
}

export function Changes({ list, filters, page, generatedBy }: { list: CourseChangeList; filters: ChangeFilters; page: number; generatedBy: string | null }) {
  const go = useQueryNav();
  function nav(patch: Partial<ChangeFilters & { page: string }>) {
    const next: Record<string, string> = { ...filters, page: "1", ...patch };
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(next)) if (v && !(k === "page" && v === "1")) qs.set(k, v);
    go(`/catalogue/changes${qs.toString() ? "?" + qs.toString() : ""}`);
  }
  const filtered = Object.values(filters).some(Boolean);

  async function exportRows(): Promise<(string | number)[][]> {
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(filters)) if (v) qs.set(k, v);
    qs.set("size", "2000");
    const r = await fetch(`/api/bff/api/v1/catalogue/course-changes?${qs.toString()}`, { cache: "no-store" });
    const j = (await r.json().catch(() => null)) as CourseChangeList | null;
    const rows = r.ok && j ? j.rows : list.rows;
    return rows.map((x, i) => [i + 1, x.course_id, x.current_shown ?? "", x.current_title ?? "", x.dept_name ?? x.dept_code ?? "", x.field === "CODE" ? "Code" : "Title",
      x.old_value, x.new_value, why(x), x.ticket ?? "", CHANGE_SOURCE[x.source] ?? x.source, x.changed_by ?? "", x.changed_office ?? "", at(x.changed_at)]);
  }
  const HEAD = ["S/N", "Course ID", "Current Code", "Current Title", "Department", "Field", "Previous Value", "New Value", "Reason", "Ticket", "How", "Changed By", "Office", "Change Date"];
  const meta = (): [string, string][] => [["Filters", filtered ? Object.entries(filters).filter(([, v]) => v).map(([k, v]) => `${k}=${v}`).join(", ") : "none"], ["Changes", String(list.total)]];

  return (
    <>
      <PageHead title="Course code and title changes" description="Every change of a course's code or title — the same course before and after — with why, on which ticket, by whom and when. Kept as written; never altered."
        actions={<><LinkBtn href="/catalogue/all">All courses</LinkBtn></>} />
      <form className="filterbar" onSubmit={(e) => { e.preventDefault(); const f = new FormData(e.currentTarget); nav({ q: String(f.get("q") ?? ""), from: String(f.get("from") ?? ""), to: String(f.get("to") ?? "") }); }}>
        <div className="row">
          <Field id="ch-q" label="Search" style={{ flex: "2 1 260px" }}><input id="ch-q" name="q" className="ctl" type="search" defaultValue={filters.q} placeholder="Code (old or new), title, Course ID, ticket, department, remarks" /></Field>
          <Field id="ch-field" label="Field" style={{ flex: "0 1 120px" }}><select id="ch-field" className="ctl" value={filters.field} onChange={(e) => nav({ field: e.target.value })}><option value="">Code or title</option><option value="CODE">Code</option><option value="TITLE">Title</option></select></Field>
          <Field id="ch-source" label="How" style={{ flex: "0 1 200px" }}><select id="ch-source" className="ctl" value={filters.source} onChange={(e) => nav({ source: e.target.value })}><option value="">Any</option>{Object.entries(CHANGE_SOURCE).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
          <Field id="ch-from" label="From" style={{ flex: "0 1 150px" }}><input id="ch-from" name="from" className="ctl" type="date" defaultValue={filters.from} /></Field>
          <Field id="ch-to" label="To" style={{ flex: "0 1 150px" }}><input id="ch-to" name="to" className="ctl" type="date" defaultValue={filters.to} /></Field>
          <div className="row row--tight" style={{ alignSelf: "flex-end" }}>
            <Btn kind="primary" type="submit">Search</Btn>
            {filtered ? <Btn kind="ghost" onClick={() => go("/catalogue/changes")}>Clear</Btn> : null}
          </div>
        </div>
      </form>
      <Panel title="Changes" right={<span className="row row--inline row--tight">
        <span className="sub2">{list.total.toLocaleString()} change{list.total === 1 ? "" : "s"} · page {list.page}</span>
        <Btn kind="ghost" size="sm" onClick={async () => downloadBlob(await brandedXlsx("Course Code and Title Changes", HEAD, await exportRows(), { sheetName: "Changes", serial: docSerial("CRSCHG"), meta: meta() }), "course-code-title-changes.xlsx")}>Excel</Btn>
        <Btn kind="ghost" size="sm" onClick={async () => brandedPrint("Course Code and Title Changes", "Every change of a course's code or title, with its reason", HEAD, await exportRows(), docSerial("CRSCHG"), { meta: meta(), generatedBy: generatedBy ?? undefined })}>PDF</Btn>
      </span>}>
        {list.rows.length ? (
          <DTable pageSize={0} noPrint cols={["S/N|num", "When|mid", "Course (now)", "Field|mid", "From", "To", "Reason", "By"]} rows={list.rows.map((x, i) => [
            <span key="n" className="tnum sub2">{(page - 1) * list.size + i + 1}</span>,
            <span key="w" className="tnum sub2">{at(x.changed_at)}</span>,
            <span key="c">{x.current_code ? <Link className="lnk tnum" href={`/catalogue/course?code=${encodeURIComponent(x.current_code)}`}>{x.current_shown}</Link> : <span className="sub2">merged away</span>} {x.current_title ?? ""}
              <div className="sub2 tnum">{x.dept_name ?? x.dept_code ?? ""} · Course ID {x.course_id}</div></span>,
            <span key="f">{x.field === "CODE" ? "Code" : "Title"}</span>,
            <span key="o" className="sub2">{x.old_value}</span>,
            <b key="v">{x.new_value}</b>,
            <span key="r" className="sub2">{why(x)}{x.ticket ? <div>Ticket {x.ticket}</div> : null}<div>{CHANGE_SOURCE[x.source] ?? x.source}</div></span>,
            <span key="b" className="sub2">{x.changed_by ?? "—"}{x.changed_office ? ` (${x.changed_office})` : ""}</span>,
          ])} />
        ) : <PBody><div className="sub2">{filtered ? "No change matches." : "No course's code or title has changed yet."}</div></PBody>}
        {list.total > list.size ? (
          <div className="row row--inline row--tight" style={{ padding: "8px 12px" }}>
            <Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => nav({ page: String(page - 1) })}>Previous</Btn>
            <Btn kind="ghost" size="sm" disabled={list.page * list.size >= list.total} onClick={() => nav({ page: String(page + 1) })}>Next</Btn>
          </div>
        ) : null}
      </Panel>
    </>
  );
}
