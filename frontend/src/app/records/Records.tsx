"use client";

/**
 * Records & queries — proto/part21.html tRecords: one scope, eight views,
 * and the tabs that move between them. The scope is in the URL, so a link
 * says what it is a list of; the view is too.
 */
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { RECORD_VIEWS } from "@/lib/student";
import type { RecordsResult, RefCourse } from "@/lib/student";
import type { Scope } from "@/lib/scope";
import { Note } from "@/components/proto/ui";
import { ScopeBar, type ScopeStructure } from "@/components/proto/ScopeBar";
import { RecordBody } from "./RecordViews";


export function Records({
  view,
  scope,
  result,
  structure,
  sessions,
  courses,
}: {
  view: string;
  scope: Scope;
  result: RecordsResult;
  structure: ScopeStructure;
  sessions: string[];
  courses: RefCourse[];
}) {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();

  function show(next: string) {
    const q = new URLSearchParams(params.toString());
    if (next === "students") q.delete("view");
    else q.set("view", next);
    router.push(`${pathname}?${q.toString()}`);
  }

  return (
    <>
      <Note kind="info" title="One scope, every query">
        Set the faculty, department, programme, level, course and semester once. It holds as you move between students,
        registration, fees, results, examinations, assignment, clearance and attendance &mdash; and it is carried into
        whatever you export, so a spreadsheet that reaches somebody else says what it is a list of.
      </Note>

      <div className="rectabs">
        {RECORD_VIEWS.map((v) => (
          <button className={`rectab${view === v[0] ? " is-on" : ""}`} key={v[0]} onClick={() => show(v[0])}>
            <span className="t">{v[1]}</span>
            <span className="s">{v[2]}</span>
          </button>
        ))}
      </div>

      <ScopeBar
        scope={scope}
        structure={structure}
        sessions={sessions}
        courses={courses}
        withCourse
        what={view === "students" ? "students" : "records"}
        count={result.rows.length}
        of={result.total}
      />

      <RecordBody view={view} result={result} scope={scope} />
    </>
  );
}
