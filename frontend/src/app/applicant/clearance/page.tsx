import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { loadApplication } from "../load";
import { Clearance } from "../Screens3";
import { Screening } from "../Screening";

export const dynamic = "force-dynamic";

/** a/clearance — the applicant's own application, as the database says it is */
export default async function Page() {
  const loaded = await loadApplication();
  return (
    <Shell route="a/clearance" me={loaded.me}>
      {loaded.app ? <Screening fallback={<Clearance a={loaded.app} />} /> : <ProblemNotice problem={loaded.problem} />}
    </Shell>
  );
}
