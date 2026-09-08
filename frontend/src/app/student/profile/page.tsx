import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import { Profile } from "../Screens1";

/** s/profile — what the student may change, and what only the Registry may */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const loaded = await loadStudent();
  return (
    <Shell route="s/profile" me={loaded.me}>
      {loaded.student ? <Profile s={loaded.student} change={q.change === "1"} /> : <ProblemNotice problem={loaded.problem} />}
    </Shell>
  );
}
