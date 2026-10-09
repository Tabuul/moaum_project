import { redirect } from "next/navigation";
import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { loadApplication } from "../load";
import { CceApplicantForm } from "./CceApplicantForm";

export const dynamic = "force-dynamic";

/** a/cce — the CCE application (V379): the details the CCE list gave and the applicant completes, the O'Level in one sitting or
 *  two, the documents and passport, the programme, the CCE application fee, and the submission; then the Centre's review */
export default async function Page() {
  const loaded = await loadApplication();
  if (loaded.app && loaded.app.route !== "CCE") redirect("/applicant");
  return (
    <Shell route="a/cce" me={loaded.me}>
      {loaded.app ? <CceApplicantForm /> : <ProblemNotice problem={loaded.problem} />}
    </Shell>
  );
}
