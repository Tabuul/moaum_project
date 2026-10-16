import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Withheld } from "@/lib/exam-cards-withheld";
import { ExamCardsWithheld } from "./ExamCardsWithheld";

export const dynamic = "force-dynamic";

/** t/examcards — Examination cards withheld (V505): every approved registration whose card the card's own rule refuses, and
 *  why, by faculty and department, with a reminder to those students */
export default async function ExamCardsWithheldPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const str = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const session = /^\d{4}\/\d{4}$/.test(str("session")) ? str("session") : "";
  const semester = /^[123]$/.test(str("semester")) ? Number(str("semester")) : null;
  const code = /^EXAM_CARD_[A-Z_]{2,30}$/.test(str("code")) ? str("code") : "";
  const faculty = /^[A-Z0-9]{1,10}$/.test(str("faculty")) ? str("faculty") : "";
  const q = str("q").slice(0, 60);
  const page = /^\d{1,4}$/.test(str("page")) ? Number(str("page")) : 0;
  const refresh = str("refresh") === "1";
  const qs = new URLSearchParams({ page: String(page), size: "50" });
  if (session) qs.set("session", session);
  if (semester) qs.set("semester", String(semester));
  if (code) qs.set("code", code);
  if (faculty) qs.set("faculty", faculty);
  if (q) qs.set("q", q);
  if (refresh) qs.set("refresh", "true");
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Withheld>(`/api/v1/registration/exam-cards/withheld?${qs.toString()}`)]);
  return (
    <Shell route="t/examcards" me={me.ok ? me.data : null} sub={list.ok ? `${list.data.session}${list.data.semester ? ` · semester ${list.data.semester}` : ""}` : undefined}>
      {!list.ok ? <ProblemNotice problem={list.problem} />
        : <ExamCardsWithheld key={`${list.data.session}|${semester ?? ""}|${code}|${faculty}|${q}|${page}`} w={list.data} code={code} faculty={faculty} q={q}
            mayRemind={me.ok && ["records", "bursar", "registrar", "dregistrar", "academic", "super"].includes(me.data.activeOffice ?? "")} />}
    </Shell>
  );
}
