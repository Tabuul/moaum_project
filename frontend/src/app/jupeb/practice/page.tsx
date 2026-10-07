import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebPractice } from "./JupebPractice";

export const dynamic = "force-dynamic";

/** /jupeb/practice — practice tests: the question banks the JUPEB Office keeps and the students' timed practice (V347); the API decides who reads and who writes */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const canWrite = office === "jupeb" || office === "super";
  return (
    <Shell route="jupeb/practice" me={me.ok ? me.data : null}>
      <JupebPractice canWrite={canWrite} />
    </Shell>
  );
}
