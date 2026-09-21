import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Note } from "@/components/proto/ui";
import { loadStudent } from "../load";
import { Research } from "./Research";

export const dynamic = "force-dynamic";

/** s/research — the postgraduate student's research & thesis (V209); postgraduates only. */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/research" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const isPg = loaded.student.entryMode === "POSTGRADUATE";
  return (
    <Shell route="s/research" me={loaded.me}>
      {isPg ? <Research /> : <Note kind="info" title="Research & thesis is for postgraduate students">This page tracks a postgraduate research degree; it does not apply to your programme.</Note>}
    </Shell>
  );
}
