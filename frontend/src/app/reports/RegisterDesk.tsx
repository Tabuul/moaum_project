"use client";

/** The register desk: filter controls, a search box and a Search button, the matching rows with
 *  their count, and the ways out — a formatted Excel workbook of everything that matched (fetched
 *  page by page from the API) and the branded, printable return. The filters are plain query
 *  parameters, so a filtered register has a URL that can be bookmarked or sent. */
import { useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { Btn, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { buildXlsx, loadCrest } from "@/lib/xlsx";
import { staffSheetRow, studentSheetRow, type FilterSpec, type Opt, type StaffRow, type StudentRow } from "@/lib/registers";

type Options = Record<string, unknown>;

/** the options a control lists — narrowed by the faculty / department already chosen, so a department
 *  list under "Science" shows only Science's departments */
function optionsFor(spec: FilterSpec, options: Options, values: Record<string, string>): [string, string][] {
  if (spec.options === "sex") return [["F", "Female"], ["M", "Male"]];
  const raw = options[spec.options];
  if (!Array.isArray(raw)) return [];
  if (spec.options === "levels") return (raw as number[]).map((l) => [String(l), `${l} level`]);
  if (spec.options === "sessions") return (raw as { name: string }[]).map((s) => [s.name, s.name]);
  if (spec.options === "statuses" || spec.options === "entryModes" || spec.options === "categories" || spec.options === "ranks") {
    return (raw as string[]).map((s) => [s, s.split("_").map((w) => w.charAt(0) + w.slice(1).toLowerCase()).join(" ")]);
  }
  let list = raw as Opt[];
  if (spec.options === "departments" && values.faculty) list = list.filter((o) => o.faculty_code === values.faculty);
  if (spec.options === "programmes") {
    if (values.department) list = list.filter((o) => o.department_code === values.department);
    else if (values.faculty) list = list.filter((o) => o.faculty_code === values.faculty);
  }
  return list.map((o) => [o.code, o.name]);
}

export function RegisterDesk({ kind, title, filters, options, initial, total, page, size, cols, rows, texts, headers, tiles }: {
  kind: "students" | "staff";
  title: string;
  filters: FilterSpec[];
  options: Options;
  initial: Record<string, string>;
  total: number; page: number; size: number;
  cols: string[]; rows: ReactNode[][]; texts: string[];
  headers: string[];
  tiles?: [ReactNode, ReactNode, string | null | undefined, ReactNode?][];
}) {
  const router = useRouter();
  /* the Excel row for an API row — chosen here, not passed in: a server page cannot hand a function to a client component */
  const sheetRow = (r: StudentRow | StaffRow) => (kind === "students" ? studentSheetRow(r as StudentRow) : staffSheetRow(r as StaffRow));
  const [v, setV] = useState<Record<string, string>>(initial);
  const [exporting, setExporting] = useState(false);
  const set = (k: string, val: string) => setV((s) => {
    const n = { ...s, [k]: val };
    // a change of faculty or department clears what hangs off it
    if (k === "faculty") { n.department = ""; n.programme = ""; }
    if (k === "department") n.programme = "";
    return n;
  });

  const query = (extra?: Record<string, string>) => {
    const u = new URLSearchParams();
    for (const [k, val] of Object.entries({ ...v, ...(extra ?? {}) })) if (val && val.trim()) u.set(k, val.trim());
    return u.toString();
  };
  /* the same page with new search params is liable to be served from the client router cache; refresh after the push */
  const nav = (url: string) => { router.push(url); router.refresh(); };
  const search = () => nav(`/reports/${kind}${query() ? `?${query()}` : ""}`);
  const clear = () => { setV({}); nav(`/reports/${kind}`); };
  const pages = Math.max(1, Math.ceil(total / size));
  const goPage = (n: number) => nav(`/reports/${kind}?${query({ page: String(n) })}`);

  async function exportAll() {
    setExporting(true);
    try {
      // every matched row, 500 a page, until the count the API states is reached — never a silent cap
      const all: (string | number | null)[][] = [];
      let expected = total;
      let short = false;
      for (let p = 1; all.length < expected; p++) {
        const u = new URLSearchParams(query()); u.set("page", String(p)); u.set("size", "500"); u.set("options", "false");
        const r = await fetch(`/api/bff/api/v1/reports/registers/${kind}?${u.toString()}`, { cache: "no-store" });
        if (!r.ok) { short = true; break; }
        const j = (await r.json()) as { rows: (StudentRow | StaffRow)[]; total: number };
        expected = Number(j.total);
        all.push(...j.rows.map(sheetRow));
        if (j.rows.length === 0) break;
      }
      if (short) { window.alert(`The export stopped after ${all.length.toLocaleString()} of ${expected.toLocaleString()} rows — the portal did not answer. Try again.`); if (!all.length) return; }
      const logo = await loadCrest();
      const date = "Generated " + new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });
      const filterLine = Object.entries(v).filter(([, val]) => val && val.trim()).map(([k, val]) => `${k}: ${val}`).join(" · ");
      const blob = buildXlsx(headers, all, kind === "students" ? "Students" : "Staff", {
        school: "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI",
        title: `${title}${filterLine ? ` — ${filterLine}` : ""} (${all.length.toLocaleString()} rows)`,
        date, logo: logo ?? undefined,
      });
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = `${kind}-register-${new Date().toISOString().slice(0, 10)}.xlsx`;
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    } finally {
      setExporting(false);
    }
  }

  const active = Object.entries(v).filter(([, val]) => val && val.trim()).length;

  return (
    <>
      <Panel title="Filter the register" right={active ? `${active} filter${active === 1 ? "" : "s"} set` : "Every row until you narrow it"}>
        <PBody>
          <form onSubmit={(e) => { e.preventDefault(); search(); }}>
            <div className="grid grid--4" style={{ gap: 10 }}>
              {filters.map((f) => (
                <div className="field" key={f.key} style={f.wide ? { gridColumn: "span 2" } : undefined}>
                  <label htmlFor={`rf-${f.key}`}>{f.label}</label>
                  <select id={`rf-${f.key}`} className="ctl" value={v[f.key] ?? ""} onChange={(e) => set(f.key, e.target.value)}>
                    <option value="">All</option>
                    {optionsFor(f, options, v).map(([code, name]) => <option key={code} value={code}>{name}</option>)}
                  </select>
                </div>
              ))}
              <div className="field" style={{ gridColumn: "span 2" }}>
                <label htmlFor="rf-q">Search</label>
                <input id="rf-q" className="ctl" value={v.q ?? ""} onChange={(e) => set("q", e.target.value)}
                  placeholder={kind === "students" ? "Name, matric, admission or JAMB number" : "Name, staff number or email"} autoComplete="off" />
              </div>
            </div>
            <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap", marginTop: 12 }}>
              <button type="submit" className="btn btn--primary">Search</button>
              <Btn kind="ghost" onClick={clear}>Clear filters</Btn>
              <span style={{ flexGrow: 1 }} />
              <Btn kind="ghost" onClick={() => void exportAll()} disabled={exporting || !total}>{exporting ? "Preparing…" : `Download Excel (${total.toLocaleString()} rows)`}</Btn>
              <Btn kind="primary" onClick={() => window.open(`/reports/${kind}/view${query() ? `?${query()}` : ""}`, "_blank")} disabled={!total}>Print / Save as PDF</Btn>
            </div>
          </form>
        </PBody>
      </Panel>

      {tiles ? <Tiles items={tiles} /> : null}

      <Panel title={title} right={total ? `${total.toLocaleString()} matched · showing ${(page - 1) * size + 1}–${Math.min(total, page * size)}` : "Nothing matched"}>
        {rows.length ? (
          <>
            <DTable cols={cols} rows={rows} texts={texts} />
            {pages > 1 ? (
              <PBody>
                <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
                  <Btn kind="ghost" disabled={page <= 1} onClick={() => goPage(page - 1)}>← Previous</Btn>
                  <span className="sub2 tnum">Page {page} of {pages}</span>
                  <Btn kind="ghost" disabled={page >= pages} onClick={() => goPage(page + 1)}>Next →</Btn>
                  <span className="sub2">The Excel download and the printable return carry every matched row, not only this page.</span>
                </div>
              </PBody>
            ) : null}
          </>
        ) : <PBody><div className="sub2">No {kind === "students" ? "student" : "member of staff"} on the register matches these filters. Clear one and search again.</div></PBody>}
      </Panel>
    </>
  );
}
