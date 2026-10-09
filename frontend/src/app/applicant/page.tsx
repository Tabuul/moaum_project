import { redirect } from "next/navigation";
import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { loadApplication } from "./load";
import { Dashboard } from "./Screens1";

export const dynamic = "force-dynamic";

/** a/dashboard — the applicant's own application, as the database says it is */
export default async function Page() {
  const loaded = await loadApplication();
  /* V379: a CCE applicant's home is the CCE application */
  if (loaded.app?.route === "CCE") redirect("/applicant/cce");
  return (
    <Shell route="a/dashboard" me={loaded.me}>
      {loaded.app ? <Dashboard a={loaded.app} /> : <ProblemNotice problem={loaded.problem} />}
    </Shell>
  );
}
