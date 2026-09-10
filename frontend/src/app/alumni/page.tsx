import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Alumni, type AlumniData } from "./Alumni";

export const dynamic = "force-dynamic";

/** t/alumni — the alumni register, read from the graduands Senate approved. */
export default async function AlumniPage() {
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<AlumniData>("/api/v1/alumni")]);
  return (
    <Shell route="t/alumni" me={me.ok ? me.data : null}>
      {data.ok ? <Alumni d={data.data} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
