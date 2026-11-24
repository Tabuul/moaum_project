import type { Problem } from "@/lib/api";
import { Note } from "@/components/proto/ui";
import { humanTitle, problemRemedy } from "@/lib/problem-title";
import { LISTED_PROBLEMS, listedProblem } from "@/lib/problem-list";
import Link from "next/link";

/**
 * Every refusal is shown with its remedy and the office responsible
 * (NFR-USA-005), in the prototype's own notice. "422" is never what a
 * person sees.
 */
export function ProblemNotice({ problem }: { problem: Problem }) {
  // V681: a refusal naming many programmes at once is listed, one a line
  const listed = problem.code && LISTED_PROBLEMS.has(problem.code) ? listedProblem(problem.detail) : null;
  const remedy = problemRemedy(problem);
  return (
    <Note kind="bad" title={humanTitle(problem.title, undefined, problem.code)}>
      {listed ? (
        <>
          {listed.lead}:
          <ul className="mt-1 mb-1" style={{ paddingLeft: "1.2em", listStyle: "disc" }}>
            {listed.items.map((it, i) => <li key={i}>{it}</li>)}
          </ul>
          {listed.tail ? <>{listed.tail[0].toUpperCase() + listed.tail.slice(1)}.</> : null}
        </>
      ) : problem.detail}
      {remedy && (
        <>
          {" "}
          <b>What to do:</b> {remedy.message} <span className="sub2">&mdash; {remedy.office}</span>
        </>
      )}
      {problem.code === "BIODATA_COMPLETION_REQUIRED" ? <>{" "}<Link className="lnk b600" href="/student/biodata">Complete your biodata</Link></> : null}
      {problem.violations && problem.violations.length > 0 && (
        <>
          {" "}
          {problem.violations.map((v, i) => (
            <span key={i}>
              <code>{v.field}</code> {v.message}
              {i < problem.violations!.length - 1 ? "; " : ""}
            </span>
          ))}
        </>
      )}
    </Note>
  );
}
