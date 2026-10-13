"use client";

/**
 * V423 — the students behind the Biodata compliance figures: who, their numbers, where they study, how to reach them,
 * what is missing and when the record last changed — filtered, searched (name, matriculation, JAMB, admission or
 * application number) and paged on the server; the view as it stands exports to Excel or PDF.
 */
import { useState } from "react";
import { usePathname, useSearchParams } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, LinkBtn, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { Ceiling, ScopeStructure } from "@/components/proto/ScopeBar";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import type { Problem } from "@/lib/api";
import type { ComplianceList, ComplianceRow, Requirement } from "@/lib/biodata-gate";
import { ComplianceFilterBar, filterQuery, type ComplianceFilters } from "../ComplianceFilterBar";

const SIZE = 50;
const dayOnly = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

export function BiodataStudents({ list, filters, extra, page, requirements, structure, sessions, ceiling }: {
  list: ComplianceList; filters: ComplianceFilters; extra: { status: string; missing: string; q: string }; page: number;
  requirements: Requirement[]; structure: ScopeStructure; sessions: string[]; ceiling: Ceiling;
}) {
  const queryNav = useQueryNav();
  const pathname = usePathname();
  const params = useSearchParams();
  const [busy, setBusy] = useState<string | null>(null);
  const pages = Math.max(1, Math.ceil(list.total / SIZE));

  function go(patch: Record<string, string>) {
    const p = new URLSearchParams(params.toString());
    for (const [k, v] of Object.entries(patch)) { if (v) p.set(k, v); else p.delete(k); }
    if (!("page" in patch)) p.delete("page");
    queryNav(`${pathname}?${p.toString()}`);
  }

  const status = (r: ComplianceRow) => r.excepted ? <Pil kind="info">Exception</Pil> : <Pil kind={r.complete ? "ok" : "bad"}>{r.complete ? "Up to date" : "Incomplete"}</Pil>;
  const words = [extra.status === "COMPLETE" ? "Complete" : extra.status === "INCOMPLETE" ? "Incomplete" : "All students",
    extra.missing ? `missing ${requirements.find((r) => r.item === extra.missing)?.label ?? extra.missing}` : null,
    extra.q ? `search “${extra.q}”` : null].filter(Boolean).join(" · ");

  async function exportAll(kind: "xlsx" | "pdf") {
    setBusy(kind);
    try {
      const q = filterQuery(filters, { ...extra, page: "0", size: "5000" });
      const r = await fetch(`/api/bff/api/v1/biodata-compliance/students?${q}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      const rows = (j as ComplianceList).rows;
      const serial = docSerial("BIO");
      const head = ["S/N", "Student", "Matric number", "JAMB number", "Faculty", "Department", "Programme", "Level", "Phone", "Email", "Missing", "Last updated", "Status"];
      const body = rows.map((x, i) => [i + 1, x.name, x.matric_no ?? "", x.jamb_reg_no ?? "", x.faculty ?? "", x.department ?? "", x.programme ?? "", x.level ?? "",
        x.phone ?? "", x.email ?? "", x.missing ?? "", dayOnly(x.last_updated), x.complete ? "Up to date" : x.excepted ? "Exception" : "Incomplete"]);
      const title = "Student biodata compliance";
      if (kind === "xlsx") downloadBlob(await brandedXlsx(title, head, body, { sheetName: "Biodata compliance", serial, sub: words }), `biodata-compliance-${serial}.xlsx`);
      else brandedPrint(title, words, head, body, serial);
      notify(`${rows.length.toLocaleString()} student${rows.length === 1 ? "" : "s"} exported${list.total > rows.length ? ` (the first ${rows.length.toLocaleString()} of ${list.total.toLocaleString()})` : ""}`);
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <PageHead description={`${list.total.toLocaleString()} student${list.total === 1 ? "" : "s"} · ${words}`}
        actions={<>
          <LinkBtn href={`/ict/biodata?${filterQuery(filters)}`}>Biodata compliance</LinkBtn>
          <Btn kind="ghost" disabled={busy !== null || !list.total} onClick={() => void exportAll("xlsx")}>{busy === "xlsx" ? "Exporting…" : "Excel"}</Btn>
          <Btn kind="ghost" disabled={busy !== null || !list.total} onClick={() => void exportAll("pdf")}>PDF</Btn>
        </>} />

      <ComplianceFilterBar filters={filters} structure={structure} sessions={sessions} ceiling={ceiling}>
        <div className="scope__f"><Field id="bs-status" label="Biodata status">
          <select id="bs-status" className="ctl" value={extra.status} onChange={(e) => go({ status: e.target.value })}>
            <option value="">All</option><option value="INCOMPLETE">Incomplete</option><option value="COMPLETE">Complete</option>
          </select>
        </Field></div>
        <div className="scope__f"><Field id="bs-missing" label="Missing">
          <select id="bs-missing" className="ctl" value={extra.missing} onChange={(e) => go({ missing: e.target.value })}>
            <option value="">Any item</option>{requirements.map((r) => <option key={r.item} value={r.item}>{r.label}</option>)}
          </select>
        </Field></div>
        <div className="scope__f"><Field id="bs-q" label="Search">
          <input id="bs-q" className="ctl" defaultValue={extra.q} placeholder="Name, matric, JAMB, admission or application number"
            onKeyDown={(e) => { if (e.key === "Enter") go({ q: (e.target as HTMLInputElement).value.trim() }); }}
            onBlur={(e) => { if (e.target.value.trim() !== extra.q) go({ q: e.target.value.trim() }); }} />
        </Field></div>
      </ComplianceFilterBar>

      <Panel title="Students" right={<span className="sub2">Page {page + 1} of {pages}</span>}>
        {list.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Student", "Matric / JAMB number", "Programme", "Level|num", "Phone / email", "Missing fields", "Last updated", "Status|mid", "|num"]}
            rows={list.rows.map((x, i) => [
              <span key="sn" className="tnum sub2">{page * SIZE + i + 1}</span>,
              <span key="n" className="b600">{x.name}{x.migrated ? <div className="sub2">From the old portal</div> : null}</span>,
              <span key="m" className="tnum">{x.matric_no ?? "—"}<div className="sub2">{x.jamb_reg_no ?? "No JAMB number"}</div></span>,
              <span key="p">{x.programme ?? "—"}<div className="sub2">{[x.department, x.faculty].filter(Boolean).join(" · ") || "—"}</div></span>,
              <span key="l" className="tnum">{x.level ?? "—"}</span>,
              <span key="c" className="sub2"><span className="tnum">{x.phone ?? "No phone"}</span><div style={{ overflowWrap: "anywhere" }}>{x.email ?? "No e-mail"}</div></span>,
              <span key="mi" className="sub2" style={{ display: "block", minWidth: 220 }}>{x.missing || "—"}<div className="tnum">{x.completed} of {x.required} given</div></span>,
              <span key="u" className="sub2 tnum">{dayOnly(x.last_updated)}</span>,
              <span key="s">{status(x)}</span>,
              <LinkBtn key="v" size="sm" href={`/students/${x.id}`}>View biodata</LinkBtn>,
            ])} />
        ) : <PBody><div className="sub2">No student matches this view.</div></PBody>}
        {pages > 1 ? (
          <div className="tfoot">
            <div className="tfoot__n">Showing <b className="tnum">{page * SIZE + 1}&ndash;{Math.min(list.total, (page + 1) * SIZE)}</b> of <b className="tnum">{list.total.toLocaleString()}</b></div>
            <div className="pg">
              <button className="pg__b" disabled={page === 0} onClick={() => go({ page: String(page - 1) })} aria-label="Previous page">&larr;</button>
              <button className="pg__b is-on">{page + 1}</button>
              <button className="pg__b" disabled={page >= pages - 1} onClick={() => go({ page: String(page + 1) })} aria-label="Next page">&rarr;</button>
            </div>
          </div>
        ) : null}
      </Panel>
    </>
  );
}
