"use client";

/**
 * The Preliminary Science reports (V446): the applications by target programme, by O'Level sitting, by sex and by state of origin —
 * submitted, eligible, not eligible, with remediation, admitted — counted by the database, never by the page; and the payment
 * report (paid, pending, expired references). Each exports to Excel or to PDF on the University's letterhead, its S/N from 1.
 * The application, admission, eligibility, remediation and status reports are the desk's list under a filter, exported there.
 */
import { useEffect, useState } from "react";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { naira, pcall, when } from "@/lib/preliminary";

interface Group { code: string | null; label: string | null; submitted: number; eligible: number; not_eligible: number; remediation: number; admitted: number }
interface Analysis { session: string; byTarget: Group[]; bySittings: Group[]; bySex: Group[]; byState: Group[] }
interface Payment { application_no: string; surname: string; other_names: string; reference: string; kind: string; amount: number; generated_at: string; confirmed_at: string | null; receipt_no: string | null; channel: string | null; status: string }

const HEAD = ["S/N", "", "Submitted", "Eligible", "Not eligible", "Remediation", "Admitted"];

export function PrelimReports({ session, sessions, generatedBy, payments: mayPay }: { session: string; sessions: string[]; generatedBy: string | null; payments: boolean }) {
  const [s, setS] = useState(session);
  const [a, setA] = useState<Analysis | null>(null);
  const [pays, setPays] = useState<Payment[] | null>(null);
  const [payStatus, setPayStatus] = useState("");
  useEffect(() => {
    let live = true;
    void pcall<Analysis>(`/api/v1/admissions/preliminary/analysis?session=${encodeURIComponent(s)}`).then((r) => { if (live) { if (r.ok) setA(r.data); else notifyProblem(r.problem); } });
    return () => { live = false; };
  }, [s]);
  useEffect(() => {
    if (!mayPay) return;
    let live = true;
    void pcall<Payment[]>(`/api/v1/admissions/preliminary/payments?session=${encodeURIComponent(s)}${payStatus ? `&status=${payStatus}` : ""}`).then((r) => { if (live) { if (r.ok) setPays(r.data); else notifyProblem(r.problem); } });
    return () => { live = false; };
  }, [s, payStatus, mayPay]);

  const table = (title: string, first: string, rows: Group[], word: (g: Group) => string) => {
    const data = rows.map((g, i) => [i + 1, word(g), g.submitted, g.eligible, g.not_eligible, g.remediation, g.admitted]);
    const head = HEAD.map((h, i) => (i === 1 ? first : h));
    return (
      <Panel title={title} right={<span className="row row--inline row--tight">
        <Btn kind="ghost" size="sm" onClick={async () => downloadBlob(await brandedXlsx(`Preliminary Science: ${title}`, head, data, { sheetName: first, serial: docSerial("PRESCI"), meta: [["Session", s]] }), `preliminary-science-${first.toLowerCase().replace(/[^a-z]+/g, "-")}.xlsx`)}>Excel</Btn>
        <Btn kind="ghost" size="sm" onClick={() => brandedPrint(`Preliminary Science: ${title}`, `Session ${s}`, head, data, docSerial("PRESCI"), { meta: [["Session", s]], generatedBy })}>PDF</Btn></span>}>
        <PBody>{rows.length ? <DTable noPrint pageSize={0} cols={["S/N|num", first, "Submitted|num", "Eligible|num", "Not eligible|num", "Remediation|num", "Admitted|num"]} rows={data} /> : <div className="sub2">No application yet.</div>}</PBody>
      </Panel>
    );
  };
  const payHead = ["S/N", "Application no", "Name", "Fee", "Reference", "Amount", "Status", "Receipt", "Generated", "Verified", "Channel"];
  const payRows = (pays ?? []).map((p, i) => [i + 1, p.application_no, `${p.surname}, ${p.other_names}`, p.kind === "APPLICATION" ? "Application fee" : p.kind, p.reference,
    naira(p.amount), p.status === "PAID" ? "Paid" : p.status === "EXPIRED" ? "Expired" : "Pending", p.receipt_no ?? "", when(p.generated_at), p.confirmed_at ? when(p.confirmed_at) : "", p.channel ?? ""]);

  return (
    <>
      <PageHead title="Preliminary Science reports" description="Counted by the database for the session; the list reports are exported from the desk under a filter."
        actions={<><select className="ctl" aria-label="Session" value={s} onChange={(e) => setS(e.target.value)}>{sessions.map((x) => <option key={x}>{x}</option>)}</select><LinkBtn href="/preliminary">Preliminary Science desk</LinkBtn></>} />
      <Note kind="info" title="The application, admission, O'Level eligibility, remediation and application status reports">
        Open the desk, filter the list (by target programme, sex, state, LGA, sittings, eligibility, remediation, payment, status or date) and export it to Excel or PDF.
      </Note>
      {!a ? <Note kind="info" title="Counting…">One moment.</Note> : (
        <>
          {table("Applications by target programme", "Target programme", a.byTarget, (g) => g.label ?? "Not chosen")}
          {table("Sitting analysis", "O'Level sittings", a.bySittings, (g) => (g.code === "0" ? "No result given" : g.code === "1" ? "One sitting" : "Two sittings"))}
          {table("Applications by sex", "Sex", a.bySex, (g) => (g.code === "F" ? "Female" : g.code === "M" ? "Male" : "Not given"))}
          {table("Applications by state of origin", "State of origin", a.byState, (g) => g.label ?? "Not given")}
        </>
      )}
      {mayPay ? (
        <Panel title="Payment report" right={<span className="row row--inline row--tight">
          <select className="ctl" aria-label="Payment status" value={payStatus} onChange={(e) => setPayStatus(e.target.value)}><option value="">Every reference</option><option value="PAID">Paid</option><option value="PENDING">Pending</option><option value="EXPIRED">Expired</option></select>
          <Btn kind="ghost" size="sm" disabled={!pays?.length} onClick={async () => downloadBlob(await brandedXlsx("Preliminary Science payment report", payHead, payRows, { sheetName: "Payments", serial: docSerial("PRESCI"), meta: [["Session", s], ["Status", payStatus || "all"]] }), "preliminary-science-payments.xlsx")}>Excel</Btn>
          <Btn kind="ghost" size="sm" disabled={!pays?.length} onClick={() => brandedPrint("Preliminary Science payment report", `Session ${s}`, payHead, payRows, docSerial("PRESCI"), { meta: [["Session", s], ["Status", payStatus || "all"]], generatedBy, orientation: "landscape" })}>PDF</Btn></span>}>
          <PBody>{pays === null ? <div className="sub2">Reading…</div> : pays.length ? <DTable noPrint pageSize={50} cols={payHead.map((h, i) => (i === 0 || h === "Amount" ? `${h}|num` : h))} rows={payRows} /> : <div className="sub2">No payment reference yet.</div>}</PBody>
        </Panel>
      ) : null}
    </>
  );
}
