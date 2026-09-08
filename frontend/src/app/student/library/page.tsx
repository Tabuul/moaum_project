import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import type { StudentLibrary } from "@/lib/library";
import { loadStudent } from "../load";
import { Library } from "./Library";

export const dynamic = "force-dynamic";

/** s/library — loans, fines and the catalogue */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const q = typeof params.q === "string" ? params.q : "";
  const loaded = await loadStudent();
  const l = loaded.student ? await api<StudentLibrary>(`/api/v1/me/library${q ? `?q=${encodeURIComponent(q)}` : ""}`) : null;
  return (
    <Shell route="s/library" me={loaded.me}>
      {loaded.student && l && l.ok ? <Library l={l.data} q={q} /> : <ProblemNotice problem={l && !l.ok ? l.problem : loaded.student ? { status: 500, title: "Unreadable" } : loaded.problem} />}
    </Shell>
  );
}
