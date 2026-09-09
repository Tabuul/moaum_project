import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";
import { Support, type ServiceRequest } from "./Support";

export const dynamic = "force-dynamic";

/** s/support — ask an office for help */
export default async function Page() {
  const loaded = await loadStudent();
  const r = loaded.student ? await api<ServiceRequest[]>("/api/v1/me/requests") : null;
  return (
    <Shell route="s/support" me={loaded.me}>
      {loaded.student && r && r.ok ? <Support requests={r.data} /> : <ProblemNotice problem={r && !r.ok ? r.problem : loaded.student ? { status: 500, title: "Unreadable" } : loaded.problem} />}
    </Shell>
  );
}
