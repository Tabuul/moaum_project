import { LinkBtn, Panel } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

/** V737: a preliminary programme's figures for its own session, as its desk counts them (GET /api/v1/admissions/preliminary/overview) */
export interface PrelimOverview {
  route: string; name: string; session: string;
  stats: { total?: number; submitted?: number; underReview?: number; admitted?: number; accepted?: number; paid?: number; feeHeld?: number; migrated?: number };
}

const n = (v: number | undefined) => (v ?? 0).toLocaleString("en-GB");

/** The preliminary programmes on the General Admissions dashboard (V737): one row a programme, each opening its desk. They are
 *  counted here and on their desks, never among the UTME offers. */
export function PrelimProgrammes({ rows }: { rows: PrelimOverview[] }) {
  if (!rows.length) return null;
  return (
    <Panel title="Preliminary programmes" right="Each in its own session · opens the programme's desk">
      <DTable pageSize={0}
        cols={["Programme", "Session|mid", "Applications|num", "Submitted|num", "Under review|num", "Admitted|num", "Paid|num", "Fee held|num", "From the old portal|num", "|num"]}
        rows={rows.map((r) => [
          <b key="p">{r.name}</b>, r.session, n(r.stats.total), n(r.stats.submitted), n(r.stats.underReview), n(r.stats.admitted), n(r.stats.paid), n(r.stats.feeHeld),
          n(r.stats.migrated), <LinkBtn key="o" href={`/preliminary?route=${encodeURIComponent(r.route)}`}>Open</LinkBtn>,
        ])} />
    </Panel>
  );
}
