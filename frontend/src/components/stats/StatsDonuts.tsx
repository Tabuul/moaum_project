"use client";

/** the two donuts a dashboard shows: payment status and registration status, each arc a door to its rows */
import { useRouter } from "next/navigation";
import { Donut, VZ, vzNum } from "@/components/proto/vz";
import { detailHref, type StatCounts, type StatFilters } from "@/lib/stats";

export function StatsDonuts({ t, f }: { t: StatCounts; f: StatFilters }) {
  const router = useRouter();
  return (
    <div className="grid grid--2">
      <div>
        <div className="eyebrow mb-1">Payment status</div>
        <Donut capLabel="Students" capValue={vzNum(t.total)} onPick={(i) => router.push(detailHref(f, i.l === "Paid" ? "PAID" : i.l === "Not paid" ? "NOT_PAID" : "NO_CHARGE"))}
          items={[{ l: "Paid", v: t.paid, c: VZ.s3 }, { l: "Not paid", v: t.not_paid, c: VZ.crit }, ...(t.no_charge ? [{ l: "No charge stated", v: t.no_charge, c: VZ.axis }] : [])]} />
      </div>
      <div>
        <div className="eyebrow mb-1">Registration status</div>
        <Donut capLabel="Students" capValue={vzNum(t.total)} onPick={(i) => router.push(detailHref(f, i.l === "Registered" ? "REGISTERED" : i.l === "Paid not registered" ? "PAID_NOT_REGISTERED" : "NOT_PAID"))}
          items={[{ l: "Registered", v: t.registered, c: VZ.s1 }, { l: "Paid not registered", v: t.paid_not_registered, c: VZ.s4 }, { l: "Not paid", v: Math.max(0, t.total - t.registered - t.paid_not_registered), c: VZ.crit }]} />
      </div>
    </div>
  );
}
