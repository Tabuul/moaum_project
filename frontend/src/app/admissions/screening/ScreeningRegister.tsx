"use client";

/** t/screening — the whole screening register (V159): every submitted candidate for the session, the
 *  mark they were screened by (Post-UTME sat, or O'Level auto-screening / Direct Entry computed) and
 *  its source. JAMB number included, ordered by programme. Read-only. */
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface RegisterRow {
  jamb_reg_no: string; name: string; programme: string; programme_code: string | null; entry_mode: string;
  utme: number | null; olevel_scaled: number | null; post_utme: number | null; screening: number | null; source: string;
}

const SRC: Record<string, "ok" | "info" | "grey" | "bad"> = {
  "Post-UTME": "ok", "O'Level + UTME": "info", "O'Level": "info", UTME: "info", "Awaiting Post-UTME": "bad", none: "grey",
};

export function ScreeningRegister({ rows, session, sessions }: { rows: RegisterRow[]; session: string; sessions: string[] }) {
  const router = useRouter();
  const [prog, setProg] = useState("");
  const [src, setSrc] = useState("");

  const programmes = useMemo(() => Array.from(new Set(rows.map((r) => r.programme))).sort(), [rows]);
  const shown = rows.filter((r) => (!prog || r.programme === prog) && (!src || r.source === src));

  const sat = rows.filter((r) => r.source === "Post-UTME").length;
  const auto = rows.filter((r) => r.source === "O'Level" || r.source === "O'Level + UTME" || r.source === "UTME").length;
  const de = rows.filter((r) => r.entry_mode === "DIRECT_ENTRY").length;
  const awaiting = rows.filter((r) => r.source === "Awaiting Post-UTME").length;

  function download() {
    const head = ["JAMB no", "Name", "Programme", "Programme code", "Mode", "UTME", "O'Level /100", "Post-UTME", "Screening", "Source"];
    const cell = (v: string | number | null) => {
      const s = String(v ?? "");
      return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    };
    const body = shown.map((r) => [r.jamb_reg_no, r.name, r.programme, r.programme_code ?? "", r.entry_mode, r.utme ?? "", r.olevel_scaled ?? "", r.post_utme ?? "", r.screening ?? "", r.source]);
    const csv = "﻿" + [head, ...body].map((row) => row.map(cell).join(",")).join("\r\n");
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = `screening-register-${session.replace(/[^0-9]+/g, "-")}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <>
      <Note kind="info" title="The screening register — everyone, and how they were screened">
        Every candidate with a submitted application for the session, and the mark they were screened by: the
        <b> Post-UTME</b> they sat, or — for Direct Entry and programmes screened by O&rsquo;Level — a
        <b> computed</b> figure (the O&rsquo;Level aggregate scaled to 100, blended with the UTME where present). It is a
        report; it does not change the sat score or the merit engine.
      </Note>

      <div className="scope">
        <div className="scope__row">
          <div className="scope__f"><label htmlFor="sr-s">Session</label>
            <select id="sr-s" className="ws__select" value={session} onChange={(e) => router.push(`/admissions/screening?session=${encodeURIComponent(e.target.value)}`)}>
              {(sessions.includes(session) ? sessions : [session, ...sessions]).map((x) => <option key={x} value={x}>{x}</option>)}
            </select>
          </div>
          <div className="scope__f"><label htmlFor="sr-p">Programme</label>
            <select id="sr-p" className="ws__select" value={prog} onChange={(e) => setProg(e.target.value)}>
              <option value="">All programmes</option>
              {programmes.map((x) => <option key={x} value={x}>{x}</option>)}
            </select>
          </div>
          <div className="scope__f"><label htmlFor="sr-src">Screened by</label>
            <select id="sr-src" className="ws__select" value={src} onChange={(e) => setSrc(e.target.value)}>
              <option value="">Any source</option>
              <option value="Post-UTME">Post-UTME (sat)</option>
              <option value="O'Level + UTME">O&rsquo;Level + UTME</option>
              <option value="O'Level">O&rsquo;Level</option>
              <option value="UTME">UTME</option>
              <option value="Awaiting Post-UTME">Awaiting Post-UTME</option>
            </select>
          </div>
        </div>
        <div className="scope__sum">
          <span className="count">Showing <b className="tnum">{shown.length.toLocaleString()}</b> of <span className="tnum">{rows.length.toLocaleString()}</span> candidates{prog ? ` · ${prog}` : " · by programme"}</span>
          <button className="scope__clear" disabled={!shown.length} onClick={download}>Download CSV</button>
        </div>
      </div>

      <Tiles items={[
        ["Candidates", String(rows.length), null, `${session} · submitted applications`],
        ["Sat the Post-UTME", String(sat), null, "Screened by examination"],
        ["Auto O'Level", String(auto), null, "Computed screening figure"],
        ["Direct Entry", String(de), null, "O'Level basis"],
        ["Awaiting Post-UTME", String(awaiting), awaiting ? "var(--red-ink)" : null, "Exam programme, no score yet"],
      ]} />

      <Panel title="Screening register" right={`${shown.length}${shown.length !== rows.length ? ` of ${rows.length}` : ""} candidate${shown.length === 1 ? "" : "s"} · by programme`}>
        {shown.length ? (
          <DTable
            cols={["JAMB no|mid", "Name", "Programme", "Mode|mid", "UTME|num", "O’Level /100|num", "Post-UTME|num", "Screening|num", "Source|mid"]}
            rows={shown.map((r) => [
              <span className="tnum sub2" key="j">{r.jamb_reg_no}</span>,
              <strong key="n">{r.name}</strong>,
              <span className="sub2" key="p">{r.programme}{r.programme_code ? <span className="tnum"> · {r.programme_code}</span> : null}</span>,
              <span className="sub2" key="m">{r.entry_mode === "DIRECT_ENTRY" ? "Direct Entry" : r.entry_mode}</span>,
              <span className="tnum" key="u">{r.utme ?? "—"}</span>,
              <span className="tnum" key="o">{r.olevel_scaled != null ? r.olevel_scaled : "—"}</span>,
              <span className="tnum" key="pu">{r.post_utme != null ? r.post_utme : "—"}</span>,
              <b className="tnum" key="s">{r.screening != null ? r.screening : "—"}</b>,
              <Pil kind={SRC[r.source] ?? "grey"} key="src">{r.source}</Pil>,
            ])}
            texts={shown.map((r) => `${r.jamb_reg_no} ${r.name} ${r.programme} ${r.source}`)}
          />
        ) : <PBody><div className="sub2">No submitted application matches — try another session or clear the filters. A fresh intake session is empty until its applicants are committed.</div></PBody>}
      </Panel>
    </>
  );
}
