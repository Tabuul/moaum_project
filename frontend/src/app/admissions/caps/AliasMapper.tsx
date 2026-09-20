"use client";

/**
 * JAMB course names the alias list does not carry, each with the candidates
 * behind it and a programme to map it to. The suggestion is only a
 * suggestion — the mapping is a person's act, recorded against their office,
 * because it decides what degree those candidates are admitted to.
 */
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Programme } from "@/lib/caps";
import { norm } from "@/lib/caps";
import type { Problem } from "@/lib/api";
import { Btn, Panel } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

/** "B.Sc. STRATEGIC COMMUNICATIONS" → "strategiccommunications": the award prefix is not the name. */
export function bareName(name: string): string {
  return norm(
    name
      .replace(/\b(bachelor of|doctor of|b\.?\s*sc\.?|b\.?\s*a\.?|b\.?\s*ed\.?|b\.?\s*tech\.?|ll\.?\s*b|m\.?\s*a\.?)\b/gi, " ")
      .replace(/\(ed\)/gi, " ")
      .replace(/\(law\)/gi, " "),
  );
}

export function suggest(jambName: string, programmes: Programme[]): Programme | null {
  const want = bareName(jambName);
  if (!want) return null;
  const exact = programmes.find((p) => bareName(p.name) === want);
  if (exact) return exact;
  const contains = programmes.filter((p) => bareName(p.name).includes(want) || want.includes(bareName(p.name)));
  return contains.length === 1 ? contains[0] : null;
}

export function AliasMapper({
  unresolved,
  counts,
  programmes,
}: {
  unresolved: string[];
  counts: Record<string, number>;
  programmes: Programme[];
}) {
  const router = useRouter();
  const [choice, setChoice] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [done, setDone] = useState<Record<string, string>>({});

  async function map(jambName: string) {
    const code = choice[jambName] ?? suggest(jambName, programmes)?.code;
    if (!code) return;
    setBusy(jambName);
    setProblem(null);
    try {
      const response = await fetch(`/api/bff/api/v1/admissions/programmes/${encodeURIComponent(code)}/jamb-alias`, {
        method: "PUT",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`JAMB calls ${code} "${jambName}", mapped from the CAPS download on the intake screen`) },
        body: JSON.stringify({ jambName }),
      });
      const body = await response.json().catch(() => null);
      if (response.ok) {
        setDone({ ...done, [jambName]: (body as Programme).name });
        notify(`${code} mapped to “${jambName}”`);
        router.refresh();
      } else {
        setProblem(body && typeof body === "object" && "status" in body ? (body as Problem) : { status: response.status, title: response.statusText });
      }
    } finally {
      setBusy(null);
    }
  }

  return (
    <Panel title="JAMB course names the alias list does not carry" right={`${unresolved.length} name${unresolved.length === 1 ? "" : "s"} · map each to the programme it means`}>
      <DTable
        cols={["JAMB calls it", "Candidates|num", "The University calls it", "|num"]}
        rows={unresolved.map((name) => {
          const guess = suggest(name, programmes);
          const selected = choice[name] ?? guess?.code ?? "";
          return [
            <strong key="n">{name}</strong>,
            <span className="tnum" key="c">{counts[name] ?? 0}</span>,
            done[name] ? (
              <span key="s">
                <strong>{done[name]}</strong> <span className="sub2">mapped</span>
              </span>
            ) : (
              <select
                key="s"
                className="ws__select"
                style={{ maxWidth: 420 }}
                value={selected}
                onChange={(e) => setChoice({ ...choice, [name]: e.target.value })}
                aria-label={`The programme JAMB means by ${name}`}
              >
                <option value="">Choose the programme…</option>
                {programmes.map((p) => (
                  <option key={p.code} value={p.code}>
                    {p.code} · {p.name}
                    {p.jambName && norm(p.jambName) !== norm(p.name) ? ` (JAMB: ${p.jambName})` : ""}
                  </option>
                ))}
              </select>
            ),
            done[name] ? (
              <span key="b" />
            ) : (
              <Btn kind={guess ? "primary" : "urgent"} key="b" disabled={!selected || busy !== null} onClick={() => void map(name)}>
                {busy === name ? "Mapping…" : "Map"}
              </Btn>
            ),
          ];
        })}
      />
      {problem ? (
        <div className="card__body">
          <ProblemNotice problem={problem} />
        </div>
      ) : null}
      <div className="card__body">
        <div className="sub2">
          A suggestion is offered where the University&rsquo;s own name matches once the award prefix is set aside; it
          is still your act, recorded against your office, because it decides what degree these candidates are
          admitted to. Once mapped, the file is read again here without re-uploading.
        </div>
      </div>
    </Panel>
  );
}
