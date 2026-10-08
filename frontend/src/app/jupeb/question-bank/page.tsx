import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { QuestionBank, type Course, type Question, type BlueprintRow } from "@/app/exams/question-bank/QuestionBank";

export const dynamic = "force-dynamic";

/** /jupeb/question-bank — the JUPEB subjects' CBT question banks (V365), named JUPEB:<subject code>, frozen by version as every bank is */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const course = typeof p.course === "string" ? p.course : null;
  const [me, courses, questions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Course[]>("/api/v1/cbt/courses?office=JUPEB"),
    course ? api<{ rows: Question[]; blueprint: BlueprintRow[] }>(`/api/v1/cbt/questions?course=${encodeURIComponent(course)}${typeof p.q === "string" && p.q ? `&q=${encodeURIComponent(p.q)}` : ""}${typeof p.status === "string" && p.status ? `&status=${encodeURIComponent(p.status)}` : ""}`) : Promise.resolve(null),
  ]);
  return (
    <Shell route="jupeb/bank" me={me.ok ? me.data : null}>
      {courses.ok ? (
        <QuestionBank courses={courses.data} course={course} questions={questions && questions.ok ? questions.data.rows : []} blueprint={questions && questions.ok ? questions.data.blueprint : []} actingOffice={me.ok ? me.data.activeOffice : null} base="/jupeb/question-bank" search={typeof p.q === "string" ? p.q : ""} status={typeof p.status === "string" ? p.status : ""} />
      ) : <ProblemNotice problem={courses.problem} />}
    </Shell>
  );
}
