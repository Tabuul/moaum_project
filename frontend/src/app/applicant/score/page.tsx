import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { loadApplication } from "../load";
import { Score } from "../Screens2";

export const dynamic = "force-dynamic";

/** a/score — the applicant's own application, as the database says it is */
export default async function Page() {
  const loaded = await loadApplication();
  return (
    <Shell route="a/score" me={loaded.me}>
      {loaded.app ? <Score a={loaded.app} /> : <ProblemNotice problem={loaded.problem} />}
    </Shell>
  );
}
