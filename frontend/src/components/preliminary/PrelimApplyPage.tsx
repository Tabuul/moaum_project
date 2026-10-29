import { ApplicationClosed } from "@/components/ApplicationClosed";
import { ProblemNotice } from "@/components/ProblemNotice";
import { prelimPage } from "@/lib/preliminary";
import { PrelimRegister } from "@/app/preliminary-science/apply/PrelimRegister";
import { prelimApplyData } from "./PrelimProgrammePage";

/** A preliminary or proficiency application's first step (V446, V701), started online with no JAMB number. While the Director of ICT
 *  has the route's window closed, scheduled or expired, the closure message instead of the form; the API refuses again whatever
 *  this page shows. */
export async function PrelimApplyPage({ slug }: { slug: string }) {
  const r = await prelimApplyData(slug);
  if (!r.ok) return <div style={{ padding: "var(--s-5)" }}><ProblemNotice problem={r.problem} /></div>;
  const w = r.data.window;
  const path = `${prelimPage(r.data.route)}/apply`;
  if (w.state !== "OPEN") {
    return <ApplicationClosed title={`The ${r.data.name} application`} eyebrow={r.data.programmeTypeCode === "PROFICIENCY_CERTIFICATE" ? "Proficiency certificate" : "Preliminary / Remedial"}
      window={{ type: w.type, label: `${r.data.name} application`, session: r.data.session, status: w.state, open: false,
                opensAt: w.opensAt, closesAt: w.closesAt, message: w.message, applicationPath: path, applicationUrl: path }} />;
  }
  return <PrelimRegister p={r.data} />;
}
