import { redirect } from "next/navigation";
import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { loadApplication } from "../load";
import { PrelimApplicantForm } from "./PrelimApplicantForm";

export const dynamic = "force-dynamic";

/** a/preliminary — the Preliminary Science application (V446): the fee, the details, the O'Level and its eligibility, the target
 *  programme, the documents and the submission; then the Office's review and the published outcome */
export default async function Page() {
  const loaded = await loadApplication();
  if (loaded.app && loaded.app.route !== "PRELIMINARY_SCIENCE") redirect("/applicant");
  return (
    <Shell route="a/preliminary" me={loaded.me}>
      {loaded.app ? <PrelimApplicantForm /> : <ProblemNotice problem={loaded.problem} />}
    </Shell>
  );
}
