import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";

/** s/transcript — the transcript request now lives under My Documents (V262) */
export default function Page() {
  redirect("/student/documents?new=TRANSCRIPT");
}
