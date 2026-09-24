import { api } from "@/lib/api";
import { ReportDoc } from "@/components/proto/ReportDoc";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { ReportColumn } from "@/lib/report";
import { FileReturn, type Dispatch } from "./FileReturn";

export const dynamic = "force-dynamic";

interface Snapshot {
  id: string; report: string; title: string; subtitle: string | null; period: string; parameters: string; due_on: string | null;
  headers: string; rows: string; totals: string | null; row_count: number; note: string | null;
  taken_at: string; taken_office: string | null; taken_by_name: string | null; verification_code: string;
  filed_to: string | null; filed_at: string | null; filed_note: string | null; filed_by_name: string | null;
}

/** a kept copy of a return (V229), printed exactly as it was taken, with its verification code and filing */
export default async function SnapshotPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [r, sent] = await Promise.all([
    api<Snapshot>(`/api/v1/reports/snapshots/${encodeURIComponent(id)}`),
    api<Dispatch[]>(`/api/v1/reports/snapshots/${encodeURIComponent(id)}/dispatches`),
  ]);
  if (!r.ok) return <div style={{ padding: "var(--s-6)" }}><ProblemNotice problem={r.problem} /></div>;
  const s = r.data;
  const headers = JSON.parse(s.headers) as string[];
  const rows = JSON.parse(s.rows) as (string | number | null)[][];
  const columns: ReportColumn[] = headers.map((h, i) => ({
    key: `c${i}`, label: h, align: rows.some((row) => typeof row[i] === "number") ? "right" : "left",
  }));
  const shown = rows.map((row) => Object.fromEntries(row.map((v, i) => [`c${i}`, v])));
  return (
    <ReportDoc
      title={s.title}
      subtitle={s.subtitle ?? `Kept copy · ${s.period}`}
      session={s.period}
      columns={columns}
      rows={shown}
      note={<>{s.note ? <div>{s.note}</div> : null}<div className={s.note ? "mt-2" : undefined}>{s.row_count.toLocaleString()} row{s.row_count === 1 ? "" : "s"} as kept{s.due_on ? ` · answers the return due ${s.due_on}` : ""}{s.filed_note ? ` · ${s.filed_note}` : ""}.</div></>}
      issuedFor={s.taken_office ?? undefined}
      kept={{ code: s.verification_code, takenAt: s.taken_at, office: s.taken_office, by: s.taken_by_name, filedTo: s.filed_to, filedAt: s.filed_at }}
      toolbar={<FileReturn id={s.id} title={`${s.title} · ${s.period}`} headers={headers} rows={rows} filedTo={s.filed_to} dispatches={sent.ok ? sent.data : []} />}
    />
  );
}
