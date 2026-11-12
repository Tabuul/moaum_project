import { LinkBtn, Note } from "@/components/proto/ui";
import { categoryWord, naira, nextStep, num, type MySummer } from "@/lib/summer";

/** V735: the Summer Semester on the dashboard — only for a student it is for: eligible for a Summer set and not closed, or with
 *  something selected, owed or registered in it; the step to take next, and the page */
export function SummerCard({ d }: { d: MySummer | null }) {
  if (!d?.period || (d.period.state === "CLOSED" && !num(d.account?.due))) return null;
  const a = d.account;
  const took = !!a && (num(a.due) > 0 || num(a.paid) > 0);
  if (!d.eligibility?.eligible && !took) return null;
  const registered = a?.coursesPaid ?? 0;
  return (
    <Note kind={num(a?.due) > 0 ? "bad" : "info"} title={`Summer Semester ${d.period.session}${d.eligibility?.eligible ? ` · ${categoryWord(d.eligibility.category)}` : ""}`}
          action={<LinkBtn kind="ghost" href="/student/summer">Open</LinkBtn>}>
      {nextStep(d)}{registered ? ` ${registered} course${registered === 1 ? "" : "s"} registered.` : ""}{num(a?.paid) > 0 ? ` ${naira(a?.paid)} paid.` : ""}
    </Note>
  );
}
