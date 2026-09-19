import { api } from "@/lib/api";
import { ReportDoc } from "@/components/proto/ReportDoc";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { ReportColumn } from "@/lib/report";
import type { TransferRow } from "../Transfers";
import { MemoBar } from "./MemoBar";

export const dynamic = "force-dynamic";

const columns: ReportColumn[] = [
  { key: "sn", label: "S/No", align: "right" },
  { key: "candidate", label: "Name, Matriculation Number, Department & Level" },
  { key: "entry", label: "Mode of Entry, UTME Score & CGPA" },
  { key: "applied", label: "Course Applied for & Reason for Seeking Transfer" },
  { key: "recommendation", label: "Committee’s Recommendations" },
];

/** t/transfers memo — the branded, printable recommended-list and withdrawal memos. */
export default async function TransferMemoPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const type = p.type === "withdrawn" ? "withdrawn" : "recommended";
  const data = await api<{ rows: TransferRow[] }>("/api/v1/transfers");
  if (!data.ok) return <div style={{ padding: 24 }}><ProblemNotice problem={data.problem} /></div>;

  const wanted = type === "recommended" ? ["RECOMMENDED", "APPROVED", "EFFECTED"] : ["NOT_RECOMMENDED", "WITHDRAWN"];
  const cases = data.data.rows.filter((r) => wanted.includes(r.state));
  const session = cases[0]?.session ?? "2026/2027";

  const rows = cases.map((r, i) => ({
    sn: i + 1,
    candidate: `${r.name} · ${r.matric_no ?? ""} · ${r.from_programme} · ${r.from_level} Level`,
    entry: `${r.mode_of_entry}${r.utme_score != null ? ` · UTME ${r.utme_score}` : ""}${r.cgpa != null ? ` · CGPA ${Number(r.cgpa).toFixed(2)}` : ""}`,
    applied: `${r.to_programme} — ${r.reason}`,
    recommendation: type === "recommended"
      ? `Recommended for ${r.recommended_level ?? r.from_level} level${r.state === "APPROVED" ? " (approved)" : r.state === "EFFECTED" ? " (effected)" : ""}`
      : r.state === "WITHDRAWN" ? `Withdrawn${r.withdrawn_why ? ` — ${r.withdrawn_why}` : ""}` : `Not recommended${r.committee_note ? ` — ${r.committee_note}` : ""}`,
  }));

  const title = type === "recommended"
    ? "Recommended List of Inter-Departmental Transfer Candidates"
    : "Non-Recommended / Withdrawn Inter-Departmental Transfer Cases";
  const note = type === "recommended"
    ? "The Special Admissions and Admission Irregularities Committee considered and recommended the cases of inter-departmental transfer of the underlisted students for the approval of Senate. Successful applicants are to pay the non-refundable processing fee set by the Bursary against the reference generated on the portal, print their approval letters, and proceed for registration."
    : "The Special Admissions and Admission Irregularities Committee did not recommend, or has withdrawn, the underlisted cases. The Directorate of ICT is requested to withdraw any affected names from the recommended cases earlier sent, please.";

  return (
    <ReportDoc
      title={title}
      subtitle="Special Admissions and Admission Irregularities Committee"
      session={session}
      columns={columns}
      rows={rows}
      note={note}
      issuedFor="Deputy Vice-Chancellor (Academic) / Chairman, SAIC"
      toolbar={<MemoBar />}
    />
  );
}
