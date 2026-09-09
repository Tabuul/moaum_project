/** Course spaces, as the API states them (V035). */
export interface SpaceRow { offering_id: string; course_code: string; title: string; units: number; semester: number; lecturer: string | null; materials: number; accessed: number; due: number; weeks: number | null }
export interface TeachingRow { offering_id: string; course_code: string; title: string; units: number; semester: number; enrolled: number; materials: number; assignments: number }
export interface Material { id: string; week: number | null; title: string; kind: string; description: string | null; filename: string | null; content_type: string | null; bytes: number | null; link: string | null; published_at: string | null; created_at: string; readers: number; read_by_me: boolean }
export interface Assignment {
  id: string; title: string; brief: string | null; kind: string; opens_at: string; closes_at: string; late_hours: number; late_penalty: number; weight: number; out_of: number; created_at: string;
  submitted: number; marked: number; enrolled: number;
  my_submission_id: string | null; my_submitted_at: string | null; my_late: boolean | null; my_mark: number | null; my_feedback: string | null; my_filename: string | null; my_text: string | null;
}
export interface Space { offering_id: string; course_code: string; title: string; units: number; session: string; semester: number; enrolled: number; lecturer: string | null; sheet_stage: string | null; materials: Material[]; assignments: Assignment[] }
export interface GradebookRow { student_id: string; number: string; name: string; submitted: number; marked: number; total: number; weight_marked: number }
export interface EngagementRow extends GradebookRow { materials_read: number; materials: number; assignments: number; last_read: string | null; attended: number; held: number }
export interface Desk extends Space { gradebook: GradebookRow[]; engagement: EngagementRow[] }
export interface Submission { id: string; submitted_at: string; late: boolean; mark: number | null; marked_at: string | null; feedback: string | null; filename: string | null; text: string | null; bytes: number | null; student_id: string; number: string; name: string }

export const KINDS: [string, string][] = [["NOTES", "Lecture notes"], ["SLIDES", "Slides"], ["READING", "Reading"], ["VIDEO", "Video"], ["AUDIO", "Audio"], ["OTHER", "Other"]];

export function size(bytes: number | null | undefined): string {
  if (!bytes) return "";
  return bytes >= 1048576 ? `${(bytes / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`;
}

/** a File read as base64, for the JSON body the API takes */
export async function fileBase64(f: File): Promise<string> {
  const buf = await f.arrayBuffer();
  let bin = "";
  const bytes = new Uint8Array(buf);
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}
