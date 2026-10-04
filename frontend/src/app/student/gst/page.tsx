import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import type { GstView } from "@/lib/student-portal";
import { GstScreen } from "./GstScreen";

/** s/gst — GST & EPS (V314): the fee, whether it is paid, the reference to pay it against, and the GST and EPS courses */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/gst" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const session = typeof q.session === "string" && /^\d{4}\/\d{4}$/.test(q.session) ? q.session : loaded.student.session;
  const gst = await api<GstView>(`/api/v1/me/gst?session=${encodeURIComponent(session)}`);
  return (
    <Shell route="s/gst" me={loaded.me} sub={`${session} session`}>
      {gst.ok ? <GstScreen s={loaded.student} gst={gst.data} /> : <ProblemNotice problem={gst.problem} />}
    </Shell>
  );
}
