"use client";

/**
 * The register — proto/part5.html staffStudents, with the scope bar of
 * proto/part21 above it: the card that finds a student, and the list the
 * scope selects. The figures are the register's own; when nobody is on it
 * the screen says so rather than showing a row that is not there.
 */
import { useState, type FormEvent } from "react";
import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import type { Register } from "@/lib/student";
import { fullName, statusLabel, statusPill } from "@/lib/student";
import type { Scope } from "@/lib/scope";
import { Note, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ScopeBar, type Ceiling, type ScopeStructure } from "@/components/proto/ScopeBar";

export function Students({
  scope,
  q,
  register,
  structure,
  sessions,
  ceiling,
}: {
  scope: Scope;
  q: string;
  register: Register;
  structure: ScopeStructure;
  sessions: string[];
  ceiling?: Ceiling;
}) {
  const queryNav = useQueryNav();
  const pathname = usePathname();
  const params = useSearchParams();
  const [term, setTerm] = useState(q);

  function find(event?: FormEvent) {
    event?.preventDefault();
    if (term.trim() === q.trim()) return;
    const next = new URLSearchParams(params.toString());
    if (term.trim()) next.set("q", term.trim());
    else next.delete("q");
    queryNav(`${pathname}?${next.toString()}`);
  }

  const rows = register.rows.map((s) => [
    <span className="tnum" key="m">
      {s.matricNo ?? <span className="sub2">{s.admissionNo ?? "—"}</span>}
    </span>,
    fullName(s),
    <span className="sub2" key="p">
      {s.programmeName}
    </span>,
    <span className="tnum" key="l">
      {s.currentLevel}
    </span>,
    <Pil kind={statusPill(s.status)} key="s">
      {statusLabel(s.status)}
    </Pil>,
    <Link className="btn btn--primary btn--sm" href={`/students/${s.id}`} key="o">
      Open
    </Link>,
  ]);

  return (
    <>
      <ScopeBar
        scope={scope}
        structure={structure}
        sessions={sessions}
        what="students"
        count={register.rows.length}
        of={register.total}
        ceiling={ceiling}
      />

      <div className="card">
        <div className="card__head">
          <span className="card__title">Find a student</span>
        </div>
        <div className="card__body">
          <form className="field" onSubmit={find}>
            <input
              value={term}
              onChange={(e) => setTerm(e.target.value)}
              onBlur={() => find()}
              aria-label="Search by matriculation number or name"
              autoComplete="off"
              placeholder="Matriculation number, admission number or name"
            />
          </form>
        </div>
        {register.rows.length === 0 ? (
          <div className="card__body">
            <Note
              kind="info"
              title={q ? `Nothing on the register matches “${q}”` : "Nobody is on the register in this scope"}
            >
              {q
                ? "Check the spelling, or try part of the name rather than all of it. A student is on the register from the moment the Academic Office brings the admitted candidates onto it."
                : "The register fills when the Academic Office brings a session’s admitted candidates onto it, each with an admission number. Until then this list is empty, and it says so rather than showing a name that is not there."}
            </Note>
          </div>
        ) : (
          <DTable
            cols={["Matriculation no.", "Name", "Programme", "Level|mid", "Status", "|num"]}
            rows={rows}
            texts={register.rows.map((s) => `${s.matricNo ?? ""} ${s.admissionNo ?? ""} ${fullName(s)} ${s.programmeName}`)}
            title="Students"
          />
        )}
      </div>
    </>
  );
}
