import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { CheckInCard, type CheckIn } from "@/components/cbt/CheckInCard";

export const dynamic = "force-dynamic";

/** t/invigilate — the page a CBT slip's QR opens (V375): the invigilator, signed in on their phone, sees the candidate the slip names
 *  and checks them in. The API reads the slip's signed code and decides who may see and check whom. */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const t = typeof p.t === "string" ? p.t : "";
  const [me, found] = await Promise.all([api<Me>("/api/v1/iam/me"), t ? api<CheckIn>(`/api/v1/cbt/check-in?t=${encodeURIComponent(t)}`) : Promise.resolve(null)]);
  return (
    <Shell route="t/invigilate" me={me.ok ? me.data : null}>
      {!found ? <ProblemNotice problem={{ status: 400, title: "No slip was scanned", detail: "Scan the QR on the candidate's CBT slip with your phone's camera, or find them on the sitting's board." }} />
        : found.ok ? <CheckInCard initial={found.data} /> : <ProblemNotice problem={found.problem} />}
    </Shell>
  );
}
