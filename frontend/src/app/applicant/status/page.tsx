import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { loadApplication } from "../load";
import { Status } from "../Screens2";

export const dynamic = "force-dynamic";

/** a/status — the applicant's own application, as the database says it is */
export default async function Page() {
  const loaded = await loadApplication();
  return (
    <Shell route="a/status" me={loaded.me}>
      {loaded.app ? <Status a={loaded.app} /> : <ProblemNotice problem={loaded.problem} />}
    </Shell>
  );
}
