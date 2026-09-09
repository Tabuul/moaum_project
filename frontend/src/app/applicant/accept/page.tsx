import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadApplication } from "../load";
import { Accept } from "../Screens3";

export const dynamic = "force-dynamic";

/** a/accept — the applicant's own application, as the database says it is */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  // on return from the gateway, verify with the gateway and confirm at once — no Bursary step, no wait for a webhook
  if (typeof q.paid === "string" && q.paid) {
    await api("/api/v1/payments/verify", { method: "POST", body: { reference: q.paid }, reason: `Verify payment ${q.paid}` });
  }
  const loaded = await loadApplication();
  return (
    <Shell route="a/accept" me={loaded.me}>
      {loaded.app ? <Accept a={loaded.app} /> : <ProblemNotice problem={loaded.problem} />}
    </Shell>
  );
}
