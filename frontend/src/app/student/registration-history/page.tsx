import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";
import { RegistrationHistory, type RegHistory } from "./RegistrationHistory";

export const dynamic = "force-dynamic";

/** s/reghistory — the student's course registration history, session by session */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/reghistory" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const d = await api<RegHistory>("/api/v1/me/registration-history");
  return (
    <Shell route="s/reghistory" me={loaded.me}>
      {d.ok ? <RegistrationHistory d={d.data} /> : <ProblemNotice problem={d.problem} />}
    </Shell>
  );
}
