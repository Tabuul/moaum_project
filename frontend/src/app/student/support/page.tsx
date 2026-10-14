import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";
import { Support, type ServiceRequest } from "./Support";

export const dynamic = "force-dynamic";

/** s/support — ask an office for help */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  // V451: a link may name the office and the subject (the fees page's "ask the Bursary")
  const q = await searchParams;
  const loaded = await loadStudent({ gateOpen: true });
  const r = loaded.student ? await api<ServiceRequest[]>("/api/v1/me/requests") : null;
  return (
    <Shell route="s/support" me={loaded.me}>
      {loaded.student && r && r.ok ? <Support requests={r.data} office={typeof q.office === "string" ? q.office : undefined} subject={typeof q.subject === "string" ? q.subject.slice(0, 200) : undefined} /> : <ProblemNotice problem={r && !r.ok ? r.problem : loaded.student ? { status: 500, title: "Unreadable" } : loaded.problem} />}
    </Shell>
  );
}
