import { LinkBtn, Note } from "@/components/proto/ui";
import { cardTitle, countsLine, nextStep, num, plural, showSummerCard, type MySummerCard } from "@/lib/summer";

/** V735, V779: the Summer Semester on the dashboard — for a student it is for (eligible, with a Summer set and not closed) and for one
 *  who has anything selected, decided or registered in it: the step to take next, where their selections stand, the printed
 *  confirmation, and the page. It reads the slim answer of GET /me/summer/card (the summary, the period, the eligibility and the fee):
 *  never the pool or the results. A course found not outstanding or rejected is counted here and its reason is on the page. */
export function SummerCard({ d }: { d: MySummerCard | null }) {
  if (!d || !showSummerCard(d)) return null;
  const s = d.summary;
  const decided = (s?.notOutstanding ?? 0) + (s?.rejected ?? 0);
  const session = d.period?.session ?? d.session;
  return (
    <Note kind={num(s?.due) > 0 ? "bad" : "info"} title={cardTitle(d)}
          action={
            <span className="row row--tight">
              {s && s.selected > 0 && session ? <a className="btn btn--ghost btn--sm" href={`/student/summer/confirmation/pdf?session=${encodeURIComponent(session)}`} target="_blank" rel="noopener">{s.registered > 0 ? "Print confirmation" : "Print selection summary"}</a> : null}
              <LinkBtn kind="ghost" href="/student/summer">Open</LinkBtn>
            </span>
          }>
      {nextStep(d)}
      {s && (s.selected > 0 || decided > 0) ? <span className="blk sub2 tnum">{countsLine(s)}</span> : null}
      {decided > 0 ? <span className="blk sub2">{plural(decided, "selection")} found not outstanding or rejected: see the reasons on the page.</span> : null}
    </Note>
  );
}
