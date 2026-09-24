import type { Me } from "@/components/proto/Shell";
import type { LibraryDeskData } from "@/lib/library";
import { LinkBtn, Note, Panel, PBody, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { money } from "@/lib/format";

const d0 = (iso: string | null | undefined) => { if (!iso) return "—"; try { return new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short" }); } catch { return "—"; } };

/** The Librarian's home: circulation at a glance — what is out, what is overdue, the fines owed, and the
 *  patrons behind them — from the same /library/desk the circulation screen works. */
export function LibraryDashboard({ me, desk }: { me: Me | null; desk: LibraryDeskData | null }) {
  const t = desk?.tiles;
  const overdue = desk?.overdue ?? [];
  const fines = desk?.fines ?? [];
  const perDay = Number(desk?.setting?.fine_per_day ?? 0);
  const finesUnpaid = Number(t?.fines_unpaid ?? 0);
  return (
    <>
      {(t?.overdue ?? 0) || finesUnpaid ? (
        <Note kind="bad" title={`${t?.overdue ?? 0} loan${(t?.overdue ?? 0) === 1 ? "" : "s"} overdue · ${money(finesUnpaid)} in unpaid fines`}
          action={<LinkBtn kind="urgent" href="/library/circulation">Open circulation</LinkBtn>}>
          A fine is posted on return at the rate in force, settled against a reference the student generates or waived with a reason. A patron with a fine outstanding does not clear.
        </Note>
      ) : (
        <Note kind="ok" title="Nothing overdue, and no fine outstanding" action={<LinkBtn kind="primary" href="/library/circulation">Open circulation</LinkBtn>}>
          Loans, returns, renewals and reservations are handled on the circulation desk.
        </Note>
      )}

      <Tiles items={[
        ["On loan", String(t?.on_loan ?? 0), null, "Items out now", "/library/circulation"],
        ["Overdue", String(t?.overdue ?? 0), (t?.overdue ?? 0) ? "var(--red-ink)" : "var(--green-ink)", "Past the due date", "/library/circulation"],
        ["Fines unpaid", money(finesUnpaid), finesUnpaid ? "var(--red-ink)" : "var(--green-ink)", "Awaiting settlement"],
        ["Stock", String(t?.stock ?? 0), null, `${t?.waiting ?? 0} on waiting lists`],
      ]} />

      <Panel title="Overdue loans" right={overdue.length ? `${overdue.length} · fines post on return` : "None overdue"}>
        {overdue.length ? (
          <DTable cols={["Patron", "Item", "Due|mid", "Days|mid", "Fine so far|num"]}
            rows={overdue.slice(0, 10).map((x) => [
              <Two key="p" a={x.patron} b={x.number ?? x.staff_number ?? ""} />,
              <span key="i">{x.title}</span>,
              <span className="tnum sub2" key="d">{d0(x.due_on)}</span>,
              <b className="tnum ink-red" key="n">{x.days_overdue}</b>,
              <span className="tnum" key="f">{money(x.days_overdue * perDay)}</span>,
            ])} texts={overdue.map((x) => `${x.patron} ${x.number ?? ""} ${x.title}`)} />
        ) : <PBody><div className="sub2">Nothing is overdue. An item shows here the day after its due date, and its fine grows until it is returned.</div></PBody>}
      </Panel>

      <Panel title="Fines unpaid" right={fines.length ? `${fines.length} to settle` : "None"}>
        {fines.length ? (
          <DTable cols={["Patron", "Item", "Returned|mid", "Fine|num"]}
            rows={fines.slice(0, 10).map((x) => [
              <Two key="p" a={x.patron} b={x.number ?? x.staff_number ?? ""} />,
              <span key="i">{x.title}</span>,
              <span className="tnum sub2" key="r">{d0(x.returned_at)}</span>,
              <b className="tnum ink-red" key="f">{money(Number(x.fine ?? 0))}</b>,
            ])} texts={fines.map((x) => `${x.patron} ${x.number ?? ""} ${x.title}`)} />
        ) : <PBody><div className="sub2">No fine is waiting. A fine is settled against the student&rsquo;s payment reference, or waived by you with the reason on the record.</div></PBody>}
      </Panel>

      <Panel title="Library desks" right={me?.name ? `Signed in as ${me.name}` : "University Library"}>
        <PBody>
          <div className="grid--fill">
            <LinkBtn kind="ghost" href="/library/circulation">Circulation</LinkBtn>
            <LinkBtn kind="ghost" href="/clearance">Student clearance</LinkBtn>
            <LinkBtn kind="ghost" href="/support">Help &amp; requests</LinkBtn>
          </div>
        </PBody>
      </Panel>
    </>
  );
}
