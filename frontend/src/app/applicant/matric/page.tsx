import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { loadApplication } from "../load";
import { Matric } from "../Screens3";

export const dynamic = "force-dynamic";

/** a/matric — the applicant's own application, as the database says it is */
export default async function Page() {
  const loaded = await loadApplication();
  return (
    <Shell route="a/matric" me={loaded.me}>
      {loaded.app ? <Matric a={loaded.app} /> : <ProblemNotice problem={loaded.problem} />}
    </Shell>
  );
}
