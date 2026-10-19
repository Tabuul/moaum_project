"use client";

/** V572: the spillover work waiting on Student Cohorts, on the Academic Office's and the Registrar's homes — the level corrections
 *  (spillover students whose record still reads a lower level, and the rest), the recommendations not yet reconciled (graduation
 *  candidates, the spillover limit reached, the spillover years) and when Reconciliation last ran. Each figure opens the tab that
 *  does the work. Nothing is drawn while nothing waits. */
import { useEffect, useState } from "react";
import Link from "next/link";
import { LinkBtn, Note } from "@/components/proto/ui";

interface Work {
  levelCorrections: number; spilloverCorrections: number; registrationCorrections: number; arithmeticCorrections: number;
  toReconcile: number; graduationCandidates: number; limitReached: number; spilloverYears: number; review: number; incomplete: number;
  reconciled: number; lastReconciledAt: string | null;
}

const n = (v: number) => Number(v ?? 0).toLocaleString("en-NG");

export function SpilloverWork() {
  const [w, setW] = useState<Work | null>(null);
  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/cohorts/spillover-work", { cache: "no-store" }).then((r) => (r.ok ? r.json() : null))
      .then((j: { work?: Work } | null) => { if (live && j?.work) setW(j.work); }).catch(() => undefined);
    return () => { live = false; };
  }, []);
  if (!w || !(w.levelCorrections + w.toReconcile)) return null;
  const last = w.lastReconciledAt
    ? `Reconciliation last ran on ${new Date(w.lastReconciledAt).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" })}.`
    : "Reconciliation has never been run.";
  return (
    <Note kind="bad" title={`${n(w.levelCorrections + w.toReconcile)} student records wait on Student Cohorts`}
      action={<div className="row" style={{ gap: 8, flexWrap: "wrap" }}>
        {w.levelCorrections ? <LinkBtn kind="urgent" href="/cohorts?tab=levels">Level corrections ({n(w.levelCorrections)})</LinkBtn> : null}
        {w.toReconcile ? <LinkBtn kind="secondary" href="/cohorts?tab=lifecycle">Reconciliation ({n(w.toReconcile)})</LinkBtn> : null}
      </div>}>
      <ul style={{ margin: "4px 0 0", paddingLeft: 18 }}>
        {w.levelCorrections ? (
          <li>
            <Link href="/cohorts?tab=levels">{n(w.spilloverCorrections)} spillover student{w.spilloverCorrections === 1 ? "" : "s"}</Link> whose record still reads a level below
            the programme&apos;s final level{w.levelCorrections > w.spilloverCorrections ? `, and ${n(w.levelCorrections - w.spilloverCorrections)} other level correction${w.levelCorrections - w.spilloverCorrections === 1 ? "" : "s"}` : ""}.
          </li>
        ) : null}
        {w.toReconcile ? (
          <li>
            <Link href="/cohorts?tab=lifecycle">{n(w.toReconcile)} recommendation{w.toReconcile === 1 ? "" : "s"} to reconcile</Link>: {n(w.graduationCandidates)} graduation
            candidate{w.graduationCandidates === 1 ? "" : "s"}, {n(w.limitReached)} at the spillover limit for the Registry&apos;s decision, {n(w.spilloverYears)} in a spillover year.
          </li>
        ) : null}
      </ul>
      <div className="sub2" style={{ marginTop: 4 }}>
        {last} Until the levels are corrected and the recommendations reconciled, these students are charged, registered and listed at the wrong level,
        and graduation candidates do not reach the graduation list.
      </div>
    </Note>
  );
}
