import { api } from "@/lib/api";
import { ApplicationClosed } from "@/components/ApplicationClosed";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { PrelimPublic } from "@/lib/preliminary";
import { PrelimRegister } from "./PrelimRegister";

export const dynamic = "force-dynamic";

/** The Preliminary Science application's first step (V446), started online with no JAMB number. While the Director of ICT has the
 *  window closed, scheduled or expired, the closure message instead of the form; the API refuses again whatever this page shows. */
export default async function PrelimApplyPage() {
  const r = await api<PrelimPublic>("/api/v1/public/preliminary-science", { anonymous: true });
  if (!r.ok) return <div style={{ padding: "var(--s-5)" }}><ProblemNotice problem={r.problem} /></div>;
  const w = r.data.window;
  if (w.state !== "OPEN") {
    return <ApplicationClosed title="The Preliminary Science application" eyebrow="Preliminary / Remedial"
      window={{ type: "PRELIMINARY_SCIENCE_APPLICATION", label: "Preliminary Science application", session: r.data.session, status: w.state, open: false,
                opensAt: w.opensAt, closesAt: w.closesAt, message: w.message, applicationPath: "/preliminary-science/apply", applicationUrl: "/preliminary-science/apply" }} />;
  }
  return <PrelimRegister p={r.data} />;
}
