import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LinkBtn } from "@/components/proto/ui";
import { InvigilatorBoard, type Board } from "@/components/cbt/InvigilatorBoard";

export const dynamic = "force-dynamic";

/** t/invigilate — one sitting's board (V374): for its invigilators, the office running the examination, and the offices that read
 *  examinations (read only). The API judges who may see and mark it. */
export default async function Page({ params }: { params: Promise<{ sitting: string }> }) {
  const { sitting } = await params;
  const [me, board] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Board>(`/api/v1/cbt/sittings/${encodeURIComponent(sitting)}/board`)]);
  return (
    <Shell route="t/invigilate" me={me.ok ? me.data : null}>
      <div className="mb-3"><LinkBtn href="/cbt/invigilate" kind="ghost">← My sittings</LinkBtn></div>
      {board.ok ? <InvigilatorBoard initial={board.data} /> : <ProblemNotice problem={board.problem} />}
    </Shell>
  );
}
