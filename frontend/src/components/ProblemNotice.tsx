import type { Problem } from "@/lib/api";

/**
 * Every refusal is shown with its remedy and the office responsible
 * (NFR-USA-005). The API puts both in the problem; this is where a person
 * reads them, so "422" is never what they see.
 */
export function ProblemNotice({ problem }: { problem: Problem }) {
  return (
    <div role="alert" className="rounded border border-red-line bg-red-bg px-4 py-3 text-sm">
      <p className="font-semibold text-red-ink">
        {problem.title ?? "The request was refused"}{" "}
        <span className="font-normal text-faint tnum">· {problem.status}</span>
        {problem.code && <span className="ml-2 font-mono text-xs text-faint">{problem.code}</span>}
      </p>
      {problem.detail && <p className="mt-1 text-ink">{problem.detail}</p>}
      {problem.remedy && (
        <p className="mt-2 text-ink">
          <span className="font-semibold">What to do:</span> {problem.remedy.message}{" "}
          <span className="text-faint">— {problem.remedy.office}</span>
        </p>
      )}
      {problem.violations && problem.violations.length > 0 && (
        <ul className="mt-2 list-disc pl-5 text-ink">
          {problem.violations.map((v, i) => (
            <li key={i}>
              <span className="font-mono text-xs">{v.field}</span> — {v.message}
            </li>
          ))}
        </ul>
      )}
      {problem.correlationId && (
        <p className="mt-2 text-xs text-faint">
          Quote <span className="font-mono">{problem.correlationId}</span> when reporting this.
        </p>
      )}
    </div>
  );
}
