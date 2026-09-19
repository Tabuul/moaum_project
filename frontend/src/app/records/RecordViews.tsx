"use client";

/**
 * recordBody() — proto/part21.html, one function per view. Every figure is
 * the database's own: where a view is not served the panel keeps its shape
 * and says why, and where a view is served but empty it says that instead of
 * showing a row that is not there.
 */
import Link from "next/link";
import type { ReactNode } from "react";
import type { RecordsResult } from "@/lib/student";
import { statusLabel, statusPill } from "@/lib/student";
import type { Scope } from "@/lib/scope";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { day } from "@/components/proto/blocks";
import { semesterText } from "@/lib/student-portal";

type Row = Record<string, unknown>;

const str = (r: Row, k: string): string => (r[k] === null || r[k] === undefined ? "" : String(r[k]));
const num = (r: Row, k: string): number | null => (typeof r[k] === "number" ? (r[k] as number) : null);

function Tnum({ children }: { children: ReactNode }) {
  return <span className="tnum">{children}</span>;
}

function Dash() {
  return <span className="sub2">&mdash;</span>;
}

/** ✓ and ✗, as the prototype prints them in the clearance grid */
function Mark({ ok }: { ok: boolean }) {
  return (
    <span style={{ color: ok ? "var(--green-ink)" : "var(--red-ink)", fontWeight: 700 }}>{ok ? "✓" : "✗"}</span>
  );
}

function Empty({ title, children }: { title: string; children: ReactNode }) {
  return (
    <PBody>
      <Note kind="info" title={title}>
        {children}
      </Note>
    </PBody>
  );
}

export function RecordBody({ view, result, scope }: { view: string; result: RecordsResult; scope: Scope }) {
  const rows = result.rows;
  const shown = rows.length;

  if (result.notServed) {
    return (
      <Panel title={view === "fees" ? "School fees" : "Attendance"} right="Not served yet">
        <PBody>
          <Note kind="bad" title={view === "fees" ? "School fees are not on the portal yet" : "Attendance is not on the portal yet"}>
            {result.notServed}
          </Note>
          <span className="sub2">
            The scope still selects <b className="tnum">{result.total.toLocaleString()}</b> students; what is missing is
            the ledger behind them, not the list.
          </span>
        </PBody>
      </Panel>
    );
  }

  if (view === "students") {
    return (
      <Panel title="Students" right={`${shown} of ${result.total.toLocaleString()} shown`}>
        {shown === 0 ? (
          <Empty title="Nobody is on the register in this scope">
            The register fills when the Academic Office brings a session&rsquo;s admitted candidates onto it. Until then
            this list is empty.
          </Empty>
        ) : (
          <DTable
            cols={["Matriculation number", "Name", "Level|mid", "Status|mid", "CGPA|mid", "Action|num"]}
            rows={rows.map((r) => [
              <Tnum key="m">{str(r, "matricNo") || <span className="sub2">{str(r, "admissionNo") || "—"}</span>}</Tnum>,
              <strong key="n">{str(r, "name")}</strong>,
              <Tnum key="l">{str(r, "level")}</Tnum>,
              <Pil kind={statusPill(str(r, "status"))} key="s">
                {statusLabel(str(r, "status"))}
              </Pil>,
              <Dash key="c" />,
              <Link className="btn btn--ghost btn--sm" href={`/students/${str(r, "id")}`} key="a">
                Open
              </Link>,
            ])}
            texts={rows.map((r) => `${str(r, "matricNo")} ${str(r, "name")} ${str(r, "status")}`)}
            title="Students"
          />
        )}
      </Panel>
    );
  }

  if (view === "registration") {
    const registered = rows.filter((r) => str(r, "status") !== "NOT_REGISTERED").length;
    const approved = rows.filter((r) => ["APPROVED", "LOCKED"].includes(str(r, "status"))).length;
    return (
      <>
        <Tiles
          items={[
            ["Expected", result.total.toLocaleString(), null, "In this scope"],
            ["Registered", registered, registered ? "var(--green-ink)" : null, "A registration exists"],
            ["Not registered", Math.max(0, result.total - registered), result.total - registered ? "var(--red-ink)" : null, `In ${scope.session}`],
            ["Approved", approved, null, "On the class list"],
          ]}
        />
        <Panel title="Registration" right={`${shown} shown`}>
          {shown === 0 ? (
            <Empty title="No student in this scope is on the register">
              Registration is recorded against a student; with nobody on the register there is nothing to register.
            </Empty>
          ) : (
            <DTable
              cols={["Matriculation number", "Name", "Level|mid", "Units|mid", "Submitted|mid", "Status|num"]}
              rows={rows.map((r) => [
                <Tnum key="m">{str(r, "matricNo") || <span className="sub2">&mdash;</span>}</Tnum>,
                <strong key="n">{str(r, "name")}</strong>,
                <Tnum key="l">{str(r, "level")}</Tnum>,
                num(r, "units") === null ? <Dash key="u" /> : <Tnum key="u">{num(r, "units")}</Tnum>,
                str(r, "submittedAt") ? (
                  <span className="sub2 tnum" key="s">
                    {day(str(r, "submittedAt"))}
                  </span>
                ) : (
                  <Dash key="s" />
                ),
                <Pil kind={str(r, "status") === "NOT_REGISTERED" ? "bad" : str(r, "status") === "APPROVED" || str(r, "status") === "LOCKED" ? "ok" : "info"} key="st">
                  {statusLabel(str(r, "status"))}
                </Pil>,
              ])}
              texts={rows.map((r) => `${str(r, "matricNo")} ${str(r, "name")} ${str(r, "status")}`)}
              title="Registration"
            />
          )}
        </Panel>
      </>
    );
  }

  if (view === "results") {
    return (
      <Panel title="Result sets in this scope" right="By stage">
        {shown === 0 ? (
          <Empty title="No course is taught in this scope in this session">
            A result set exists once a course is offered in the session and a score sheet is opened on it.
          </Empty>
        ) : (
          <DTable
            cols={["Course", "Candidates|mid", "Stage", "Fail rate|mid", "Action|num"]}
            rows={rows.map((r) => [
              <span key="c">
                <strong className="tnum">{str(r, "course")}</strong>
                <div className="sub2">{str(r, "title")}</div>
              </span>,
              <Tnum key="n">{num(r, "candidates") ?? 0}</Tnum>,
              str(r, "stage") ? (
                statusLabel(str(r, "stage").replace(/_/g, " "))
              ) : (
                <span style={{ color: "var(--red-ink)", fontWeight: 700 }} key="s">
                  No sheet opened
                </span>
              ),
              num(r, "failRate") === null ? <Dash key="f" /> : <Tnum key="f">{num(r, "failRate")}%</Tnum>,
              <Link className="btn btn--ghost btn--sm" href="/results/chain" key="a">
                Open
              </Link>,
            ])}
            texts={rows.map((r) => `${str(r, "course")} ${str(r, "title")} ${str(r, "stage")}`)}
            title="Results"
          />
        )}
      </Panel>
    );
  }

  if (view === "exams") {
    return (
      <Panel
        title="Examinations in this scope"
        right={`${scope.session} · ${scope.sem ? (scope.sem === "1" ? "first semester" : "second semester") : "both semesters"}`}
      >
        {shown === 0 ? (
          <Empty title="No examination session has been opened">
            An examination session is the container every score sheet hangs in. Until one is opened for {scope.session},
            there is nothing to sit.
          </Empty>
        ) : (
          <DTable
            cols={["Examination", "Window|mid", "Candidates|mid", "Cleared|mid", "State|num"]}
            rows={rows.map((r) => [
              <span key="k">
                <strong>{statusLabel(str(r, "kind"))}</strong>
                <div className="sub2">{semesterText(Number(str(r, "semester")))}</div>
              </span>,
              <span className="sub2 tnum" key="w">
                {day(str(r, "examsFrom"), false)} &ndash; {day(str(r, "examsTo"))}
              </span>,
              <Tnum key="c">{num(r, "candidates") ?? 0}</Tnum>,
              <Tnum key="cl">{num(r, "cleared") ?? 0}</Tnum>,
              <Pil kind={str(r, "state") === "OPEN" ? "ok" : str(r, "state") === "CLOSED" ? "grey" : "info"} key="s">
                {statusLabel(str(r, "state"))}
              </Pil>,
            ])}
            texts={rows.map((r) => `${str(r, "kind")} ${str(r, "state")}`)}
            title="Examinations"
          />
        )}
      </Panel>
    );
  }

  if (view === "allocation") {
    return (
      <Panel title="Course assignment in this scope" right="Who teaches what">
        {shown === 0 ? (
          <Empty title="No course is offered in this scope in this session">
            A course is offered when the department puts it up for the session; assigning the lecturer is what opens the
            score sheet.
          </Empty>
        ) : (
          <DTable
            cols={["Course", "Units|mid", "Registered|mid", "Lecturer", "Second examiner", "Action|num"]}
            rows={rows.map((r) => [
              <span key="c">
                <strong className="tnum">{str(r, "course")}</strong>
                <div className="sub2">{str(r, "title")}</div>
              </span>,
              <Tnum key="u">{str(r, "units")}</Tnum>,
              <Tnum key="r">{num(r, "registered") ?? 0}</Tnum>,
              str(r, "lecturer") ? (
                <strong key="l">{str(r, "lecturer")}</strong>
              ) : (
                <span style={{ color: "var(--red-ink)", fontWeight: 700 }} key="l">
                  Unassigned
                </span>
              ),
              str(r, "secondExaminer") ? (
                <span className="sub2" key="s">
                  {str(r, "secondExaminer")}
                </span>
              ) : (
                <span className="sub2" style={{ color: "var(--red-ink)" }} key="s">
                  Blocked
                </span>
              ),
              <Btn kind="ghost" disabled title="Course assignment is not on the portal yet" key="a">
                {str(r, "lecturer") ? "Reassign" : "Assign"}
              </Btn>,
            ])}
            texts={rows.map((r) => `${str(r, "course")} ${str(r, "title")} ${str(r, "lecturer")}`)}
            title="Course assignment"
          />
        )}
      </Panel>
    );
  }

  return (
    <Panel title="Clearance in this scope" right="Convocation">
      {shown === 0 ? (
        <Empty title="Nobody is on the register in this scope">
          Clearance is a position on a candidate: eight units, each with its own latest word. With nobody on the register
          there is no position to report.
        </Empty>
      ) : (
        <DTable
          cols={["Matriculation number", "Name", "Bursary|mid", "Dept|mid", "Library|mid", "Hostel|mid", "Status|num"]}
          rows={rows.map((r) => [
            <Tnum key="m">{str(r, "matricNo") || <span className="sub2">&mdash;</span>}</Tnum>,
            <strong key="n">{str(r, "name")}</strong>,
            <Mark ok={str(r, "BURSARY") === "CLEARED"} key="b" />,
            <Mark ok={str(r, "DEPARTMENT") === "CLEARED"} key="d" />,
            <Mark ok={str(r, "LIBRARY") === "CLEARED"} key="l" />,
            <Mark ok={str(r, "HOSTEL") === "CLEARED"} key="h" />,
            r["clear"] === true ? (
              <Pil kind="ok" key="s">
                Cleared
              </Pil>
            ) : (
              <Pil kind="bad" key="s">
                Held
              </Pil>
            ),
          ])}
          texts={rows.map((r) => `${str(r, "matricNo")} ${str(r, "name")}`)}
          title="Clearance"
        />
      )}
    </Panel>
  );
}
