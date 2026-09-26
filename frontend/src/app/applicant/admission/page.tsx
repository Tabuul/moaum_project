import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { loadApplication } from "../load";
import { AdmissionPage } from "../Admission";

export const dynamic = "force-dynamic";

/** a/admission — the applicant's admission: congratulations, the details, the next step, the tracker */
export default async function Page() {
  const loaded = await loadApplication();
  return (
    <Shell route="a/admission" me={loaded.me}>
      {loaded.app ? <AdmissionPage /> : <ProblemNotice problem={loaded.problem} />}
    </Shell>
  );
}
