"use client";

/** t/migration — the migration ledger. What has actually been applied to this database, and
 *  the checksum of each file, so a migration edited after the fact is caught here, not later. */
import { Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface Row { filename: string; sha256: string; applied_at: string; applied_by: string }
export interface Ledger { count: number; latest: string | null; commit: string | null; startedAt: string; migrations: Row[] }

function when(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) + " " + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}

export function Migrations({ d }: { d: Ledger }) {
  return (
    <>
      <Note kind="info" title="The migration ledger is what has actually been applied, not what was intended">
        Each migration records the checksum of the file that was applied, so a migration edited after the fact is caught here as a mismatch rather than discovered later as a column that does not exist. The database is the record; this screen reads it.
      </Note>

      <Tiles items={[
        ["Migrations applied", String(d.count), null, "To this database"],
        ["Latest", d.latest ?? "—", null, "The highest applied"],
        ["Running commit", d.commit ? d.commit.slice(0, 12) : "local", null, "The code that answered"],
        ["Started", d.startedAt ? when(d.startedAt) : "—", null, "This API instance"],
      ]} />

      <Panel title="Applied migrations" right={`${d.count} in order`}>
        {d.migrations.length ? (
          <DTable cols={["Migration", "Applied|mid", "By|mid", "Checksum|num"]} rows={d.migrations.map((m) => [
            <span className="tnum" key="f">{m.filename}</span>,
            <span className="tnum sub2" key="a">{when(m.applied_at)}</span>,
            <span className="sub2" key="b">{m.applied_by}</span>,
            <span className="tnum sub2" key="s">{m.sha256.slice(0, 12)}</span>,
          ])} texts={d.migrations.map((m) => m.filename)} />
        ) : <PBody><div className="sub2">No migration is recorded. An empty ledger means the schema has not been built on this database.</div></PBody>}
      </Panel>

      <Note kind="info" title="Loading the old portal's data is a separate, rehearsed process">
        Bringing legacy records into this system is a data migration run against a staging database as often as it takes to get a clean run, with a validate-only pass that writes nothing and returns every rejected row with its reason. It is not shown here because none has been run against this database, and a screen that showed a rehearsal that never happened would be inventing one.
      </Note>
    </>
  );
}
