"use client";

/**
 * V700: the uploads of marks (assessment.result_uploads) — each score sheet's upload by its lecturer or desk, and each load of the
 * old portal's past results (its marks written in one go by one person). What the portal holds of them: the records written and,
 * for past results, those that replaced an earlier mark; a preview's invalid rows were never written, so none is counted here.
 */
import { useState } from "react";
import { useJson } from "@/lib/use-json";
import { ScopeBar, type Ceiling, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import { roleLabel } from "@/lib/offices";
import { monitorQuery, stageWord } from "@/lib/result-monitor";

interface Row { kind: "SCORE_SHEET" | "PAST_RESULTS"; uploadedAt: string; office: string | null; session: string; semester: number; courseCode: string | null;
  sheetId: string | null; records: number; replaced: number | null; sheets: number; students: number | null; reason: string | null; stage: string | null; uploadedBy: string | null }
interface Answer { session: string | null; semester: number | null; total: number; records: number; page: number; size: number; rows: Row[] }

const SIZE = 50;
const KIND_WORD = { SCORE_SHEET: "Score sheet upload", PAST_RESULTS: "Past results (old portal)" } as const;
const HEADERS = ["Uploaded", "Kind", "Uploaded By", "Office", "Session", "Semester", "Course", "Records", "Replaced", "Sheets", "Students", "Stage", "Reason"];
const when = (s: string) => new Date(s).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });

export function Uploads({ scope, structure, sessions, ceiling }: { scope: Scope; structure: ScopeStructure; sessions: string[]; ceiling: Ceiling }) {
  const [kind, setKind] = useState<"" | Row["kind"]>("");
  const viewKey = `${scope.session}|${scope.sem}|${kind}`;
  const [pager, setPager] = useState<{ key: string; page: number }>({ key: "", page: 1 });
  const page = pager.key === viewKey ? pager.page : 1;
  const setPage = (n: number) => setPager({ key: viewKey, page: n });
  const [exporting, setExporting] = useState(false);
  const { data, failed, loading } = useJson<Answer>(`/api/bff/api/v1/results/monitor/uploads${monitorQuery({ session: scope.session, sem: scope.sem, kind, page, size: SIZE })}`);

  const cells = (r: Row) => [when(r.uploadedAt), KIND_WORD[r.kind], r.uploadedBy ?? "—", r.office ? roleLabel(r.office) : "—", r.session, r.semester, r.courseCode ?? "—",
    r.records, r.replaced ?? "—", r.sheets, r.students ?? "—", r.stage ? stageWord(r.stage) : "—", r.reason ?? ""];

  async function exportAs(as: "xlsx" | "pdf") {
    setExporting(true);
    notify("Export processing…", "ok", 2500);
    const win = as === "pdf" ? window.open("", "_blank") : null;
    try {
      const r = await fetch(`/api/bff/api/v1/results/monitor/uploads${monitorQuery({ session: scope.session, sem: scope.sem, kind, page: 1, size: 5000 })}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) throw j ?? { status: r.status, title: "The export could not read the uploads" };
      const rows = (j.rows as Row[]).map((x) => cells(x).map((c) => (typeof c === "number" ? c : String(c))));
      const meta: [string, string][] = [["Session", scope.session || "Every session"], ["Semester", scope.sem || "Every semester"], ["Kind", kind ? KIND_WORD[kind] : "Every upload"]];
      const serial = docSerial("RUP");
      if (as === "xlsx") downloadBlob(await brandedXlsx("Result upload history", HEADERS, rows, { serial, meta, sheetName: "Uploads" }), "Result upload history.xlsx");
      else brandedPrint("Result upload history", meta.map(([k, v]) => `${k}: ${v}`).join(" · "), HEADERS, rows, serial, { meta, orientation: "landscape", window: win });
      notify(`Export completed — ${rows.length.toLocaleString()} upload${rows.length === 1 ? "" : "s"}.`);
    } catch (e) {
      win?.close();
      notifyProblem(e as Problem, "The export did not complete");
    } finally { setExporting(false); }
  }

  return (
    <>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} hide={["fac", "dept", "prog", "level"]} what="uploads"
        count={data?.rows.length ?? 0} of={data?.total ?? 0} onExport={data?.total ? () => void exportAs("xlsx") : undefined} />
      {failed ? <Note kind="bad" title="Unable to load the uploads">{failed}</Note> : null}
      <Panel title="Result upload history" right={<span className="row row--inline">
        {loading ? <span className="sub2">Loading the uploads…</span> : <span className="sub2">{data ? `${data.total.toLocaleString()} uploads · ${data.records.toLocaleString()} records written` : ""}</span>}
        <Btn kind="ghost" disabled={exporting || !data?.total} busy={exporting} onClick={() => void exportAs("xlsx")}>Excel</Btn>
        <Btn kind="ghost" disabled={exporting || !data?.total} busy={exporting} onClick={() => void exportAs("pdf")}>PDF</Btn>
      </span>}>
        <PBody>
          <p className="sub2">Every upload that wrote marks. An upload&rsquo;s preview is checked before anything is written, so the rows it refused never reached the record and are not counted here.</p>
          <div className="row" style={{ gap: 6, margin: "8px 0" }}>
            <Btn kind={kind === "" ? "primary" : "ghost"} onClick={() => setKind("")}>Every upload</Btn>
            <Btn kind={kind === "SCORE_SHEET" ? "primary" : "ghost"} onClick={() => setKind("SCORE_SHEET")}>Score sheet uploads</Btn>
            <Btn kind={kind === "PAST_RESULTS" ? "primary" : "ghost"} onClick={() => setKind("PAST_RESULTS")}>Past results (old portal)</Btn>
          </div>
          {data ? (
            <DTable pageSize={0} cols={["S/N|num", "Uploaded", "Kind", "By", "Session", "Sem|num", "Course", "Records|num", "Replaced|num", "Sheets|num", "Stage", "Reason"]}
              rows={data.rows.map((r, i) => [(data.page - 1) * data.size + i + 1, when(r.uploadedAt),
                <Pil key="k" kind={r.kind === "PAST_RESULTS" ? "info" : "grey"}>{KIND_WORD[r.kind]}</Pil>,
                `${r.uploadedBy ?? "—"}${r.office ? ` (${roleLabel(r.office)})` : ""}`, r.session, r.semester, r.courseCode ?? "—", r.records.toLocaleString(),
                r.replaced ?? "—", r.sheets, r.stage ? stageWord(r.stage) : "—", r.reason ?? ""])} />
          ) : null}
          {data && !data.rows.length && !loading ? <Note kind="info" title="No upload in this period">Choose another session or semester above.</Note> : null}
          {data ? (
            <div className="row" style={{ marginTop: 8 }}>
              <span className="grow" />
              <Btn kind="ghost" disabled={data.page <= 1 || loading} onClick={() => setPage(data.page - 1)}>Previous</Btn>
              <Btn kind="ghost" disabled={data.page * data.size >= data.total || loading} onClick={() => setPage(data.page + 1)}>Next</Btn>
            </div>
          ) : null}
        </PBody>
      </Panel>
    </>
  );
}
