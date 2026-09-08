import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import type { StudentHostel } from "@/lib/hostel";
import { loadStudent } from "../load";
import { Hostel } from "./Hostel";

export const dynamic = "force-dynamic";

/** s/hostel — the application, the draw, the hold, the fee, the room */
export default async function Page() {
  const loaded = await loadStudent();
  const h = loaded.student ? await api<StudentHostel>("/api/v1/me/hostel") : null;
  return (
    <Shell route="s/hostel" me={loaded.me}>
      {loaded.student && h && h.ok ? <Hostel h={h.data} /> : <ProblemNotice problem={h && !h.ok ? h.problem : loaded.student ? { status: 500, title: "Unreadable" } : loaded.problem} />}
    </Shell>
  );
}
