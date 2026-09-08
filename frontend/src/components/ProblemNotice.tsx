import type { Problem } from "@/lib/api";
import { Note } from "@/components/proto/ui";

/**
 * Every refusal is shown with its remedy and the office responsible
 * (NFR-USA-005), in the prototype's own notice. "422" is never what a
 * person sees.
 */
export function ProblemNotice({ problem }: { problem: Problem }) {
  return (
    <Note kind="bad" title={problem.title ?? "The request was refused"}>
      {problem.detail}
      {problem.remedy && (
        <>
          {" "}
          <b>What to do:</b> {problem.remedy.message} <span className="sub2">&mdash; {problem.remedy.office}</span>
        </>
      )}
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
      {problem.correlationId && (
        <>
          {" "}
          <span className="sub2">
            Quote <span className="tnum">{problem.correlationId}</span> when reporting this.
          </span>
        </>
      )}
    </Note>
  );
}
