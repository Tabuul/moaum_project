import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import type { StudentHostelFull } from "@/lib/hostel";
import { loadStudent } from "../load";
import { Hostel } from "./Hostel";

export const dynamic = "force-dynamic";

/** s/hostel — the application, the allocation, the rules, check-in, the room, transfer, checkout, clearance, history (V030 + V261) */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" && /^\d{4}\/\d{4}$/.test(p.session) ? p.session : "";
  const loaded = await loadStudent();
  const h = loaded.student ? await api<StudentHostelFull>(`/api/v1/me/hostel/full${session ? `?session=${encodeURIComponent(session)}` : ""}`) : null;
  return (
    <Shell route="s/hostel" me={loaded.me}>
      {loaded.student && h && h.ok ? <Hostel h={h.data} /> : <ProblemNotice problem={h && !h.ok ? h.problem : loaded.student ? { status: 500, title: "Unreadable" } : loaded.problem} />}
    </Shell>
  );
}
