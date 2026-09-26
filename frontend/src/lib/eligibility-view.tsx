"use client";

/** The explanation of one eligibility verdict, as every screen shows it (V266): the requirement, what the candidate holds,
 *  the result of each check, grouped — O'Level, UTME, score, the programme — with the verdict on top. */
import { Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { GROUPS, KIND_WORD, VERDICT, mark, parseChecks, type Check, type CheckStatus, type ResultRow } from "@/lib/eligibility";

export function VerdictPil({ v }: { v: string | null | undefined }) {
  if (!v) return <Pil kind="grey">NOT EVALUATED</Pil>;
  const w = VERDICT[v as keyof typeof VERDICT];
  return <Pil kind={w?.[1] ?? "grey"}>{w?.[0] ?? v}</Pil>;
}
export function Mark({ s }: { s: CheckStatus }) {
  const colour = s === "MET" ? "var(--green-ink)" : s === "NOT_MET" ? "var(--red-ink)" : s === "UNVERIFIED" ? "var(--amber-ink)" : "var(--faint)";
  return <span className="tnum b600" style={{ color: colour }}>{mark(s)}</span>;
}

/** the side-by-side comparison: Requirement | Programme requirement | Candidate | Result, per group */
export function CheckTables({ row, compact }: { row: ResultRow | null | undefined; compact?: boolean }) {
  const checks = parseChecks(row);
  if (!checks.length) return <div className="sub2">No checks were recorded.</div>;
  return (
    <div className="stack">
      {GROUPS.map(([title, kinds]) => {
        const rows = checks.filter((c) => kinds.includes(c.kind));
        if (!rows.length) return null;
        return (
          <div key={title}>
            <div className="eyebrow mb-1">{title}</div>
            <DTable pageSize={0} cols={compact ? ["Requirement", "Candidate", "|mid"] : ["Requirement", "Programme requirement", "Candidate", "Result|mid"]} rows={rows.map((c: Check) => compact
              ? [<span key="l"><b>{c.label}</b><div className="sub2">{c.requirement}</div></span>, <span key="c" className="sub2">{c.candidate}</span>, <Mark key="m" s={c.status} />]
              : [<span key="l"><b>{c.label}</b>{c.kind !== "OLEVEL_REQUIRED" && c.kind !== "UTME_COMBINATION" && c.kind !== "OLEVEL_COMPULSORY" ? <div className="sub2">{KIND_WORD[c.kind] ?? c.kind}</div> : null}</span>, <span key="r">{c.requirement}</span>, <span key="c">{c.candidate}</span>,
                 <span key="m"><Mark s={c.status} /> <span className="sub2">{c.status === "MET" ? "Satisfied" : c.status === "NOT_MET" ? "Not satisfied" : c.status === "UNVERIFIED" ? "Cannot be verified" : "Information"}</span></span>])} />
          </div>
        );
      })}
    </div>
  );
}

/** the reasons list: ✕ per failed requirement, ✓ per met one, as the brief shows */
export function ReasonList({ row }: { row: ResultRow | null | undefined }) {
  const checks = parseChecks(row).filter((c) => c.status !== "INFO");
  if (!checks.length) return null;
  const failed = checks.filter((c) => c.status !== "MET");
  const met = checks.filter((c) => c.status === "MET");
  return (
    <ul className="plain" style={{ display: "grid", gap: 4 }}>
      {failed.map((c, i) => <li key={`f${i}`} className="row row--tight" style={{ gap: 8, alignItems: "baseline" }}><Mark s={c.status} /><span><b>{c.label}</b> — {c.requirement}<div className="sub2">Candidate: {c.candidate}</div></span></li>)}
      {met.map((c, i) => <li key={`m${i}`} className="row row--tight sub2" style={{ gap: 8, alignItems: "baseline" }}><Mark s="MET" /><span>{c.label} — {c.candidate}</span></li>)}
    </ul>
  );
}
