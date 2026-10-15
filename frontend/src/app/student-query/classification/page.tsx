import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Classification, type Audit, type Review } from "./Classification";

export const dynamic = "force-dynamic";

/** the offices that decide a classification (people.require_classifier); the others read the report */
const DECIDERS = new Set(["academic", "registrar", "dregistrar", "super"]);

/** t/classification — the student classification audit and the learners to be classified (V469) */
export default async function ClassificationPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const q = typeof p.q === "string" ? p.q.slice(0, 80) : "";
  const page = typeof p.page === "string" && /^\d+$/.test(p.page) ? Number(p.page) : 0;
  const [me, audit, review] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Audit>("/api/v1/student/classification/audit"),
    api<Review>(`/api/v1/student/classification/review?page=${page}&size=50${q ? `&q=${encodeURIComponent(q)}` : ""}`),
  ]);
  const office = me.ok ? me.data.activeOffice ?? "" : "";
  return (
    <Shell route="t/classification" me={me.ok ? me.data : null}>
      {!audit.ok ? <ProblemNotice problem={audit.problem} />
        : !review.ok ? <ProblemNotice problem={review.problem} />
        : <Classification audit={audit.data} review={review.data} q={q} decides={DECIDERS.has(office)} />}
    </Shell>
  );
}
