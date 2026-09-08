import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { loadApplication } from "../load";
import { Accept } from "../Screens3";

export const dynamic = "force-dynamic";

/** a/accept — the applicant's own application, as the database says it is */
export default async function Page() {
  const loaded = await loadApplication();
  return (
    <Shell route="a/accept" me={loaded.me}>
      {loaded.app ? <Accept a={loaded.app} /> : <ProblemNotice problem={loaded.problem} />}
    </Shell>
  );
}
