import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import type { GstView } from "@/lib/student-portal";
import { GstScreen } from "./GstScreen";

/** s/gst — GST & EPS (V314): the fee, whether it is paid, the reference to pay it against, and the GST and EPS courses.
 *  The gateway returns the payer here with ?paid=<reference>: the reference is verified with the gateway at once, as on Fees & payments. */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/gst" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const paid = typeof q.paid === "string" && /^[A-Z0-9-]{6,60}$/i.test(q.paid) ? q.paid.toUpperCase() : null;
  if (paid) {
    await api("/api/v1/payments/verify", { method: "POST", body: { reference: paid }, reason: `Verify payment ${paid}` });
  }
  let session = typeof q.session === "string" && /^\d{4}\/\d{4}$/.test(q.session) ? q.session : loaded.student.session;
  let gst = await api<GstView>(`/api/v1/me/gst?session=${encodeURIComponent(session)}`);
  // returned from the gateway for another session's GST fee: show that session
  const theirs = paid && gst.ok ? gst.data.references.find((r) => r.reference === paid) : null;
  if (theirs && theirs.session !== session) {
    session = theirs.session;
    gst = await api<GstView>(`/api/v1/me/gst?session=${encodeURIComponent(session)}`);
  }
  return (
    <Shell route="s/gst" me={loaded.me} sub={`${session} session`}>
      {gst.ok ? <GstScreen s={loaded.student} gst={gst.data} paid={paid} /> : <ProblemNotice problem={gst.problem} />}
    </Shell>
  );
}
