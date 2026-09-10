import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { QuestionBank, type Course, type Question, type BlueprintRow } from "./QuestionBank";

export const dynamic = "force-dynamic";

/** t/cbtbank — the CBT question bank: authoring and blueprints per course. */
export default async function QuestionBankPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const course = typeof p.course === "string" ? p.course : null;
  const [me, courses, questions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Course[]>("/api/v1/cbt/courses"),
    course ? api<{ rows: Question[]; blueprint: BlueprintRow[] }>(`/api/v1/cbt/questions?course=${encodeURIComponent(course)}`) : Promise.resolve(null),
  ]);
  return (
    <Shell route="t/cbtbank" me={me.ok ? me.data : null}>
      {courses.ok ? (
        <QuestionBank
          courses={courses.data}
          course={course}
          questions={questions && questions.ok ? questions.data.rows : []}
          blueprint={questions && questions.ok ? questions.data.blueprint : []}
          actingOffice={me.ok ? me.data.activeOffice : null}
        />
      ) : <ProblemNotice problem={courses.problem} />}
    </Shell>
  );
}
