# Who opened a student's record (V530)

The audit trail records changes and student searches. Since V530 the portal also records who **looked at** a student's record.

## What is recorded

`people.record_view`: each time an office opens a student's record, it records the student, the person (`viewer_id`), the office
they acted in and which record was opened. Two records count:

- `STUDENT_RECORD`: the student record (Student 360, `GET /api/v1/student/students/{id}`)
- `SUPPORT_RECORD`: ICT Support's record of the student (`GET /api/v1/helpdesk/support/students/{id}`)

A view is recorded only once the record has been answered (200). It is recorded once for each person, office and record within
ten minutes, so moving between the record's tabs counts as one view. These are never recorded:

- a student reading their own portal;
- an applicant;
- ICT Support's read-only view of a student's portal, which `helpdesk.portal_view` (V521) already records.

The API's `RecordViewLog` interceptor writes the row through `people.log_record_view`, in a transaction of its own after the
record's read-only one. A failure to record never fails the record.

The log is append-only: an update or a delete is refused (`RECORD_VIEW_APPEND_ONLY`). A row goes only with its student, when a
student record itself is removed (a cascade). The log is off the audit spine, since it is itself the record of reads.

## Who reads it

- **The student**, on their profile: "Who has opened your record", for the last twelve months, showing the office and when.
  The officer's name is not shown (`GET /api/v1/me/record-views`).
- **Internal Audit**, the Deputy Director of Audit and super, on **Record Views** (`/audit/record-views`): every view with the
  person, filtered by days, office, the student or a name or number, and exportable to Excel (`GET /api/v1/audit/record-views`).
