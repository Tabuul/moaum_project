import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { CollegeSeam, type CollegeData } from "./CollegeSeam";

export const dynamic = "force-dynamic";

export default async function CollegePage() {
  const [me, college] = await Promise.all([api<Me>("/api/v1/iam/me"), api<CollegeData>("/api/v1/staff/college/CHS")]);

  return (
    <Shell route="t/college" me={me.ok ? me.data : null}>
      <CollegeSeam college={college.ok ? college.data : null} problem={college.ok ? null : college.problem} />
    </Shell>
  );
}
