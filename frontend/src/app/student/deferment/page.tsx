import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";
import type { MyDeferments } from "@/lib/deferments";
import { Deferment } from "./Deferment";

export const dynamic = "force-dynamic";

/** s/deferment — the student's deferment: the request, its review, the period in force, the return */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/deferment" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const mine = await api<MyDeferments>("/api/v1/me/deferments");
  return (
    <Shell route="s/deferment" me={loaded.me}>
      {mine.ok ? <Deferment s={loaded.student} data={mine.data} /> : <ProblemNotice problem={mine.problem} />}
    </Shell>
  );
}
