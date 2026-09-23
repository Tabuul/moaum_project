"use client";

/**
 * Search — proto/part22.html tSearch, element for element: the box, the
 * kinds, the no-query state with what can be searched for and what was
 * searched recently, the exact-match note, and one panel of hits per kind.
 *
 * The scope bar narrows a list; this finds one record. Payments are not a
 * kind here because the Bursary's ledger is not on the portal yet, and a
 * kind that can find nothing is worse than one that is not offered.
 */
import { useEffect, useState, type FormEvent } from "react";
import { KINDS } from "@/lib/student";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import type { SearchHit, SearchResult } from "@/lib/student";
import { statusLabel, statusPill } from "@/lib/student";
import { rememberSearch, useRecentSearches } from "@/lib/student-recents";
import { Btn, Ico, Note, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { StudentOpen } from "@/components/StudentModal";
import { TwoCol } from "@/components/proto/blocks";


const KIND_LABEL: Record<string, string> = {
  students: "Students",
  staff: "Staff",
  courses: "Courses",
  credentials: "Credentials",
};


function hitRow(hit: SearchHit) {
  const identifier = (
    <span className="tnum" key="i">
      {hit.identifier}
    </span>
  );
  const name = <strong key="n">{hit.name}</strong>;
  const detail = (
    <span className="sub2" key="d">
      {hit.detail}
    </span>
  );
  if (hit.kind === "students") {
    return [
      identifier,
      name,
      detail,
      <Pil kind={statusPill(hit.status)} key="s">
        {statusLabel(hit.status)}
      </Pil>,
      <StudentOpen id={hit.id} label="Details" key="a" />,
    ];
  }
  if (hit.kind === "staff") {
    return [
      identifier,
      name,
      detail,
      <Pil kind="info" key="s">
        Staff
      </Pil>,
      <Btn kind="ghost" disabled title="The staff record is not on the portal yet" key="a">
        Open record
      </Btn>,
    ];
  }
  if (hit.kind === "courses") {
    return [
      identifier,
      name,
      detail,
      <Pil kind={hit.status === "Live" ? "ok" : hit.status === "Ended" ? "grey" : "info"} key="s">
        {hit.status}
      </Pil>,
      <Btn kind="ghost" disabled title="The course screens are not on the portal yet" key="a">
        Open
      </Btn>,
    ];
  }
  return [
    identifier,
    name,
    detail,
    <Pil kind="ok" key="s">
      Valid
    </Pil>,
    <Btn kind="ghost" disabled title="Verification is not on the portal yet" key="a">
      Verify
    </Btn>,
  ];
}

export function Search({ q, kind, result }: { q: string; kind: string; result: SearchResult | null }) {
  const router = useRouter();
  const pathname = usePathname();
  const [term, setTerm] = useState(q);
  const recent = useRecentSearches();

  useEffect(() => {
    rememberSearch(q);
  }, [q]);

  function go(next: string, nextKind = kind) {
    const params = new URLSearchParams();
    if (next.trim()) params.set("q", next.trim());
    if (nextKind !== "all") params.set("kind", nextKind);
    router.push(`${pathname}${params.toString() ? `?${params.toString()}` : ""}`);
  }

  function submit(event: FormEvent) {
    event.preventDefault();
    go(term);
  }

  const hits = result?.hits ?? [];
  const counted = (k: string) =>
    k === kind ? hits.length : kind === "all" ? hits.filter((h) => h.kind === k).length : null;

  const head = (
    <div className="srch">
      <form className="srch__in" onSubmit={submit}>
        <Ico name="user" size={18} stroke="var(--faint)" />
        <input
          id="srch-q"
          value={term}
          onChange={(e) => setTerm(e.target.value)}
          autoComplete="off"
          placeholder="Matriculation number, name, staff number, course code or verification code"
        />
        {q ? (
          <button
            type="button"
            className="srch__x"
            onClick={() => {
              setTerm("");
              go("");
            }}
          >
            Clear
          </button>
        ) : null}
      </form>
      <div className="srch__kinds">
        {KINDS.map((k) => {
          const n = q ? counted(k[0]) : null;
          return (
            <button className={`srch__k${kind === k[0] ? " is-on" : ""}`} key={k[0]} onClick={() => go(term, k[0])}>
              {k[1]}
              {n === null ? null : <span className="n tnum">{n}</span>}
            </button>
          );
        })}
      </div>
    </div>
  );

  if (!q) {
    return (
      <>
        {head}
        <Note kind="info" title="Search finds one record; the scope bar narrows a list">
          Use search when you already know what you are looking for &mdash; a matriculation number a student has quoted
          on the phone, a verification code on a document an employer has sent in. Use Records &amp; queries when you
          want everyone who matches a description.
        </Note>
        <TwoCol>
          <Panel title="What you can search for">
            <DTable
              cols={["Type", "Example|num"]}
              rows={[
                [<Two a="Matriculation number" b="Exact matches jump straight to the record" key="1" />, <span className="tnum sub2" key="1v">MOAUM/CSC/23/1487</span>],
                [<Two a="Student or staff name" b="Surname or other names, in any order" key="2" />, <span className="sub2" key="2v">Adamu, or Grace</span>],
                [<Two a="Staff number" b="" key="3" />, <span className="tnum sub2" key="3v">MOAUM/STF/1142</span>],
                [<Two a="Course code or title" b="" key="4" />, <span className="tnum sub2" key="4v">CSC 311, or Algorithms</span>],
                [<Two a="Verification code" b="From a certificate or transcript" key="5" />, <span className="tnum sub2" key="5v">7QJ4M-2XKPB-9RTVC-4HN8D-6WZQY</span>],
              ]}
            />
          </Panel>
          <Panel title="Recent searches" right="Yours, on this computer">
            <PBody>
              <div style={{ display: "flex", flexDirection: "column", gap: 7, alignItems: "flex-start" }}>
                {recent.length === 0 ? (
                  <span className="sub2">Nothing yet. What you search for is listed here, on this computer only.</span>
                ) : (
                  recent.map((r) => (
                    <button className="srch__recent" key={r} onClick={() => { setTerm(r); go(r); }}>
                      <Ico name="clock" size={13} stroke="var(--faint)" w={2} />
                      {r}
                    </button>
                  ))
                )}
              </div>
            </PBody>
          </Panel>
        </TwoCol>
        <Note kind="bad" title="Every search for a person is recorded against your account">
          Looking a student up is processing their personal data whether or not you change anything, so the search term,
          the time and your office go to the audit trail. The Registrar reviews that log quarterly. Search for people you
          have business with.
        </Note>
      </>
    );
  }

  const exact = result?.exact ?? null;

  return (
    <>
      {head}
      {exact ? (
        <Note
          kind="ok"
          title={`Exact match on ${exact.identifier}`}
          action={
            exact.kind === "students" ? (
              <StudentOpen id={exact.id} label={`Open ${exact.name}`} kind="primary" />
            ) : undefined
          }
        >
          {KIND_LABEL[exact.kind].replace(/s$/, "")} &middot; {exact.name}. An identifier typed in full goes straight to
          the record.
        </Note>
      ) : null}

      {hits.length === 0 ? (
        <Note
          kind="bad"
          title={`Nothing matches “${q}”`}
          action={
            <Link className="btn btn--ghost btn--sm" href="/records">
              Browse by scope instead
            </Link>
          }
        >
          Check the spelling, or try part of the name rather than all of it. A record that exists but has not yet been
          brought onto the register will not appear here &mdash; if you have business with it, the Registry can act on it,
          recorded either way.
        </Note>
      ) : (
        KINDS.slice(1).map((k) => {
          const rows = hits.filter((h) => h.kind === k[0]);
          if (!rows.length) return null;
          return (
            <Panel title={k[1]} right={`${rows.length} ${rows.length === 1 ? "match" : "matches"}`} key={k[0]}>
              <DTable
                cols={["Identifier", "Name", "Detail", "Status|mid", "Action|num"]}
                rows={rows.map(hitRow)}
                texts={rows.map((h) => `${h.identifier} ${h.name} ${h.detail}`)}
                title={k[1]}
              />
            </Panel>
          );
        })
      )}
    </>
  );
}
