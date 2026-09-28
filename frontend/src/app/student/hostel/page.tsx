import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import type { StudentHostelFull, StudentRooms } from "@/lib/hostel";
import { loadStudent } from "../load";
import { Hostel } from "./Hostel";

export const dynamic = "force-dynamic";

/** s/hostel — the application, the allocation, the rules, check-in, the room, transfer, checkout, clearance, history (V030 + V261) */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" && /^\d{4}\/\d{4}$/.test(p.session) ? p.session : "";
  const loaded = await loadStudent();
  const h = loaded.student ? await api<StudentHostelFull>(`/api/v1/me/hostel/full${session ? `?session=${encodeURIComponent(session)}` : ""}`) : null;
  // V290: the eligibility checklist and the rooms open to this student, for the session the view landed on
  const rooms = h && h.ok ? await api<StudentRooms>(`/api/v1/me/hostel/rooms?session=${encodeURIComponent(h.data.session)}`) : null;
  if (h && h.ok) h.data.rooms = rooms && rooms.ok ? rooms.data : null;
  return (
    <Shell route="s/hostel" me={loaded.me}>
      {loaded.student && h && h.ok ? <Hostel h={h.data} /> : <ProblemNotice problem={h && !h.ok ? h.problem : loaded.student ? { status: 500, title: "Unreadable" } : loaded.problem} />}
    </Shell>
  );
}
