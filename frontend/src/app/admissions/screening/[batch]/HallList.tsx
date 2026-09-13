"use client";

/**
 * The hall list, as the invigilator holds it at the door: seat, name,
 * numbers, programme and the photograph the applicant uploaded, in seat
 * order. Printed from the browser; the print sheet drops the shell.
 */
import Link from "next/link";
import { docSerial } from "@/lib/exportbrand";
import { Btn, KvGrid, Note, Panel, PBody } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Passport } from "@/components/proto/blocks";

export interface HallListData {
  session: string;
  batch: { id: string; label: string; held_on: string; starts_at: string; ends_at: string; venue: string; capacity: number };
  seats: { id: string; seat: string; application_no: string; surname: string; other_names: string; jamb_key: string; programme: string; entry_mode: string; passport_id: string | null }[];
}

export function HallList({ data }: { data: HallListData }) {
  const b = data.batch;
  const day = new Date(b.held_on).toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
  return (
    <>
      <style>{`.hall-mast { display: none; } @media print { .nav, .topbar, .no-print { display: none !important; } .main { padding: 0 !important; } .card { break-inside: avoid; } .hall-mast { display: block !important; text-align: center; margin-bottom: 14px; } .hall-mast img { height: 54px; } }`}</style>
      <div className="hall-mast">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/crest.png" alt="" />
        <div style={{ fontWeight: 700, fontSize: 15 }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
        <div style={{ textTransform: "uppercase", letterSpacing: ".06em", fontSize: 11 }}>Post-UTME Screening — Hall List</div>
        <div style={{ fontSize: 10, color: "#555" }}>Batch {b.label} · {day} · Serial {docSerial("HALL")}</div>
      </div>
      <div className="no-print" style={{ display: "flex", gap: 9, flexWrap: "wrap", alignItems: "center" }}>
        <Link href={`/admissions?session=${encodeURIComponent(data.session)}`} className="btn btn--ghost btn--sm">Back to the Admissions desk</Link>
        <Btn kind="primary" onClick={() => window.print()}>Print the hall list</Btn>
      </div>
      <Panel title={`Post-UTME screening · batch ${b.label}`} right={`${data.seats.length} of ${b.capacity} seats · ${data.session}`}>
        <PBody>
          <KvGrid cls="grid--4" pairs={[
            ["Date", day],
            ["Session", `${String(b.starts_at).slice(0, 5)} – ${String(b.ends_at).slice(0, 5)}`],
            ["Venue", b.venue],
            ["Seated", `${data.seats.length}`],
          ]} />
        </PBody>
      </Panel>
      {data.seats.length ? (
        <Panel title="Seats, in order" right="Photograph checked at the door and again at the seat">
          <DTable
            cols={["Seat|mid", "Photograph|mid", "Candidate", "Application|mid", "JAMB|mid", "Programme", "Present|mid"]}
            rows={data.seats.map((s) => [
              <b className="tnum" key="s">{s.seat}</b>,
              <Passport key="p" w={42} h={52} src={s.passport_id ? `/api/bff/api/v1/admissions/sessions/${data.session}/applications/${s.id}/documents/${s.passport_id}/content` : null} alt={`${s.surname} ${s.other_names}`} />,
              <span key="n"><strong>{s.surname}</strong>, {s.other_names}</span>,
              <span className="tnum sub2" key="a">{s.application_no}</span>,
              <span className="tnum sub2" key="j">{s.jamb_key}</span>,
              <span className="sub2" key="g">{s.programme}{s.entry_mode === "DIRECT_ENTRY" ? " · DE" : ""}</span>,
              <span key="x" style={{ display: "inline-block", width: 18, height: 18, border: "1px solid var(--line)", borderRadius: 3 }} aria-label="Present" />,
            ])}
            texts={data.seats.map((s) => `${s.seat} ${s.surname} ${s.other_names} ${s.application_no} ${s.jamb_key} ${s.programme}`)}
          />
        </Panel>
      ) : (
        <Note kind="info" title="No seat has been assigned in this batch">Seat the submitted applications from the Admissions desk, and the list fills here.</Note>
      )}
      <Note kind="info" title="A candidate with no photograph on file is checked against the JAMB slip and photo identification">
        The photograph is the one the applicant uploaded; where none is, the box is grey and the door relies on identification. A candidate not on this list is not seated in this batch, whatever they say at the door.
      </Note>
    </>
  );
}
