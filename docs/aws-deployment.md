# The portal on AWS

How the production portal is deployed to Amazon Web Services, how it gets there
from an empty account, how the data moves from Railway, and how to roll back.
Railway and the `CI` workflow are unchanged; AWS runs beside them until the
University cuts DNS over, and Railway can be retired afterwards.

What was inspected before any of this was written, and what it found, is in
§1. The brief that asked for MariaDB, BLOB columns and local upload folders
does not describe this repository, and the deployment follows the repository.

## 1. What the application actually is

| | |
|---|---|
| API | Spring Boot 4.1, Java 21, plain JDBC. `:8081`. Actuator with liveness/readiness probes already on (`/actuator/health`, `/actuator/health/liveness`). |
| Frontend | Next.js (App Router, server-rendered). A BFF: the browser talks only to the frontend, which calls the API over the private network (`PORTAL_API_URL`). Must run as a container; it is not a static site. |
| Database | PostgreSQL 17. About 7 GiB in production, 4 of them the hash-chained audit spine. Migrations are psql scripts (`db/V###__*.sql`) applied by `db/migrate.sh`, which keeps a SHA-256 ledger and refuses an edited file. No Flyway. |
| Files | Nothing on a filesystem. Candidate passports are base64 in `admissions.attachment.payload` (109,740 rows, 428 MiB); other uploads are `bytea` blob tables, about 20 MiB in all. `admissions.attachment.object_key` already exists for an object store and is unused. Moving files to S3 is **phase 2**, after the portal runs on AWS (§9). |
| Secrets | `DATABASE_URL`, `MOAUM_AUTH_HMAC_SECRET` and (development only) `PORTAL_API_TOKEN`. Gateway, mail and SMS credentials are stored encrypted in the database and set from the Bursary and ICT screens. Nothing is committed. |
| Jobs | Seven `@Scheduled` jobs in the API (session transitions, deferments, hostel, helpdesk auto-close, examiner reminders, notice dispatch, audit-chain verifier). No distributed lock, so the API runs **one task** until one is added. |
| Images | `api/Dockerfile` (now non-root, with `curl` for the health check) and `frontend/Dockerfile` (already non-root). Built from the repository root. |
| Prototype | `web/` stays on Railway. It is not production. |

## 2. Architecture

```
                 students, staff, gateways
                            │ HTTPS (ACM certificate)
                            ▼
                Application Load Balancer  (public subnets, 2 AZs)
                  default ──────────────► frontend  (ECS Fargate, :3000)
                  /api/v1/payments/webhook/* ─┐           │  http://api:8081
                  paydirect/*, quickteller/* ─┴► api     ◄┘  (Service Connect, private)
                                               (ECS Fargate, :8081)
                                                    │ 5432, TLS
                                                    ▼
                                      RDS for PostgreSQL 17  (private subnets,
                                      Multi-AZ, encrypted, 14-day backups)

   migrate task (one-off, api image, `bash db/migrate.sh`)  ── run by the deploy workflow before each roll
   NAT gateway  ── outbound only: Interswitch, Paystack, Flutterwave, SMTP, SMS
   Secrets Manager ── DB master password (managed by RDS), HMAC secret, gateway/SSO secrets
   CloudWatch ── logs (90 days) and alarms → SNS topic
   ops bucket ── private, encrypted, versioned; dumps for the data move, expire in 30 days
   bastion (optional, SSM only) ── psql to the private database; off after go-live
```

Why ECS Fargate and not App Runner: the migrations must run as a separate
one-off task before each roll, the API must talk to a private RDS, and the
frontend reaches the API by a private name. App Runner does the last two with a
VPC connector but has no one-off task; ECS has all three without extra parts.

| AWS service | Resource | Terraform file |
|---|---|---|
| VPC | 2 public + 2 private subnets, one NAT | `network.tf` |
| RDS | `moaumpp-prod`, PostgreSQL 17, `db.t4g.medium`, gp3 50 GiB (autoscales to 500), Multi-AZ, encrypted, deletion protection, final snapshot | `rds.tf` |
| ECR | `moaumpp/api`, `moaumpp/frontend`; immutable tags; scan on push; last 30 kept | `ecr.tf` |
| ECS | cluster `moaumpp-prod`; services `api`, `frontend`; task definition `moaumpp-prod-migrate` | `ecs.tf` |
| ALB | HTTPS 443 (TLS 1.3 policy), HTTP 80 → 301; gateway callbacks routed to the API | `alb.tf` |
| Secrets Manager | `moaumpp-prod/MOAUM_AUTH_HMAC_SECRET` (generated), `moaumpp-prod/<name>` for each gateway/SSO secret (created as `unset`) | `secrets.tf` |
| IAM | task execution role (pull, logs, read secrets); task role (ECS Exec only, S3 later); GitHub OIDC deploy role | `ecs.tf`, `github-oidc.tf` |
| CloudWatch | `/ecs/moaumpp-prod/{api,frontend,migrate}`; alarms: ALB 5xx, unhealthy targets, ECS CPU/memory, RDS CPU/storage/connections | `ecs.tf`, `monitoring.tf` |
| S3 | `moaumpp-prod-ops-<account>` | `bastion.tf` |
| EC2 | `moaumpp-prod-bastion` (only with `enable_bastion=true`) | `bastion.tf` |

## 3. Environment and secrets

The API reads its settings from the environment (`api/src/main/resources/application.properties`);
the names below are the application's own, not new ones.

| Variable | API task gets it from | Value |
|---|---|---|
| `JDBC_DATABASE_URL` | environment | `jdbc:postgresql://<rds-endpoint>:5432/moaumpp?sslmode=require` |
| `PGUSER` | environment | `moaum_admin` |
| `PGPASSWORD` | Secrets Manager (RDS-managed secret, key `password`) | |
| `DB_POOL_SIZE` | environment | `10` (variable `db_pool_size`) |
| `MOAUM_PORTAL_URL` | environment | `portal_url` variable, e.g. `https://portal.moaum.edu.ng` |
| `PORT` | environment | `8081` |
| `MOAUM_AUTH_HMAC_SECRET` | Secrets Manager | generated at first apply |
| `MOAUM_FLUTTERWAVE_SECRET`, `MOAUM_FLUTTERWAVE_HASH`, `MOAUM_PAYSTACK_SECRET`, `MOAUM_PAYDIRECT_USERNAME`, `MOAUM_PAYDIRECT_PASSWORD`, `MOAUM_QUICKTELLER_MAC_KEY`, `MOAUM_QUICKTELLER_CHS_MAC_KEY`, `MOAUM_NOTICES_TOKEN`, `MOAUM_SSO_CLIENT_SECRET` | Secrets Manager | `unset` until you set them; the API treats a blank the same as absent |

| `MOAUM_FILES_PROVIDER` | environment | `S3` (Railway: `DB`, the default) |
| `MOAUM_FILES_BUCKET` | environment | `terraform output files_bucket` |
| `MOAUM_FILES_REGION` | environment | the region |
| `MOAUM_FILES_MIGRATE` | environment | `files_migrate` variable: `true` only while the existing files are being moved (§5a) |

The migrate task gets `DATABASE_URL` (no password in it) and `PGPASSWORD` from
the same secret; `psql` honours `PGPASSWORD`.

The frontend task gets `PORTAL_API_URL=http://api:8081`, `HOSTNAME=0.0.0.0`,
`PORT=3000`, `NODE_ENV=production`. In production the BFF forwards the signed-in
user's token; `PORTAL_API_TOKEN` is a development fallback and is not set.

On Railway the same API reads one `DATABASE_URL`; `DatabaseUrlConfig` prefers it
when present. Both shapes work; nothing in the code changed for AWS.

GitHub (Settings → Environments → `production` → Variables, not secrets):

| Variable | Value |
|---|---|
| `AWS_DEPLOY_ROLE_ARN` | `terraform output github_deploy_role_arn` |
| `PORTAL_URL` | the public URL, same as `portal_url` |
| `ECS_DESIRED_COUNT` | `1` (see §1, jobs) |

## 4. First deployment, from an empty account

Prerequisites: an AWS account with a user or role able to create the resources
in §2; Terraform ≥ 1.6; Docker; the AWS CLI; the University's domain and the
ability to add a DNS record for it.

1. **Certificate.** In ACM, region `af-south-1`, request a certificate for the
   portal's hostname and validate it by DNS. Note its ARN.

2. **Repositories first**, so the images have somewhere to go:
   ```bash
   cd infra/terraform
   terraform init
   terraform apply -target=aws_ecr_repository.svc -var portal_url=https://portal.<domain>
   ```

3. **Push the first images**, tagged with the commit you are deploying:
   ```bash
   cd ../..
   sha=$(git rev-parse HEAD)
   account=$(aws sts get-caller-identity --query Account --output text)
   reg=$account.dkr.ecr.af-south-1.amazonaws.com
   aws ecr get-login-password --region af-south-1 | docker login --username AWS --password-stdin $reg
   docker build -f api/Dockerfile      -t $reg/moaumpp/api:$sha .      && docker push $reg/moaumpp/api:$sha
   docker build -f frontend/Dockerfile -t $reg/moaumpp/frontend:$sha . && docker push $reg/moaumpp/frontend:$sha
   ```

4. **Everything else**, with the services created at zero tasks so nothing
   starts before the schema and the data exist:
   ```bash
   cd infra/terraform
   terraform apply -var portal_url=https://portal.<domain> -var certificate_arn=<acm-arn> \
     -var api_image_tag=$sha -var frontend_image_tag=$sha -var desired_count=0 \
     -var alarm_email=ict@<domain> -var enable_bastion=true
   ```
   RDS takes 15–20 minutes. Confirm the alarm e-mail subscription when it arrives.

5. **Schema.** Run the migrate task once by hand (the workflow does this on
   every later deploy):
   ```bash
   cluster=$(terraform output -raw cluster)
   subnets=$(terraform output -json private_subnets)
   sg=$(terraform output -raw tasks_security_group)
   aws ecs run-task --cluster $cluster --launch-type FARGATE \
     --task-definition $(terraform output -raw migrate_task_definition) \
     --network-configuration "awsvpcConfiguration={subnets=$subnets,securityGroups=[$sg],assignPublicIp=DISABLED}"
   aws logs tail /ecs/$cluster/migrate --follow
   ```
   `db/V001` creates `pgcrypto` and the `app_*` roles; the RDS master user
   (`rds_superuser`) may do both. The run ends with `schema: N migrations
   applied` and `── done ──`.

6. **Data** — §5. Skip for a smoke test with an empty database.

7. **GitHub.** Create the `production` environment and the three variables in
   §3. Optionally require a reviewer on it: then every deploy waits for approval.

8. **Start the services** with the first real deploy: Actions → *Deploy to AWS
   (production)* → *Run workflow*, `sha` blank. It reuses the images pushed in
   step 3, runs the migrations again (a no-op), rolls both services to
   `ECS_DESIRED_COUNT` tasks, and asks the portal for its front page.

9. **DNS.** Point the hostname at `terraform output alb_dns_name` (a CNAME, or a
   Route 53 alias). Until then, test with `curl -H "Host: portal.<domain>" https://<alb-dns>/ -k`.

10. **Gateways.** Set each secret the University uses:
    ```bash
    aws secretsmanager put-secret-value --secret-id moaumpp-prod/MOAUM_PAYSTACK_SECRET --secret-string '...'
    ```
    then roll the API (`aws ecs update-service --cluster moaumpp-prod --service api --force-new-deployment`),
    and give Interswitch/Paystack/Flutterwave the new callback addresses from the
    Bursary screen. The callback paths are routed straight to the API by the ALB.

11. **Bastion off.** `terraform apply ... -var enable_bastion=false` once the data
    is in and verified.

## 5. Moving the data from Railway

Read-only on the Railway side; nothing there is changed or deleted. The dump is
taken while Railway is still live, so plan a short write freeze (or a second,
final dump) right before cutover.

1. **Dump on Railway**, from inside the API container (it has `pg_dump`):
   ```bash
   railway ssh --service moaum-api -- bash -c 'pg_dump "$DATABASE_URL" -Fc --no-owner --no-privileges' > moaumpp.dump
   ```
   About 7 GiB uncompressed; custom format compresses it. Keep this file: it is
   also the pre-migration backup the brief asks for.

2. **Into the ops bucket:**
   ```bash
   aws s3 cp moaumpp.dump s3://$(terraform output -raw ops_bucket)/moaumpp.dump
   ```

3. **Restore from the bastion** (SSM, no SSH):
   ```bash
   aws ssm start-session --target $(terraform output -raw bastion_instance_id)
   # on the instance
   aws s3 cp s3://<ops-bucket>/moaumpp.dump /tmp/moaumpp.dump
   export PGPASSWORD=$(aws secretsmanager get-secret-value --secret-id <db_master_secret_arn> --query SecretString --output text | python3 -c 'import sys,json;print(json.load(sys.stdin)["password"])')
   pg_restore -h <db_endpoint> -U moaum_admin -d moaumpp --no-owner --no-privileges --clean --if-exists -j 4 /tmp/moaumpp.dump
   ```
   Restore into a database that already has the schema from step 5 of §4, so
   the `app_*` roles exist; `--clean --if-exists` replaces the empty tables.
   Roles are cluster-level and are not in a plain dump; `V001` made them.

4. **Verify** before anything points at it:
   ```sql
   SELECT count(*) FROM public.schema_migration;            -- same as Railway (303 at the time of writing)
   SELECT count(*) FROM people.student;                     -- 54,572 at the time of writing
   SELECT count(*) FROM admissions.attachment;              -- 109,740
   SELECT count(*) FROM audit.entries;
   \i db/verify.sql                                         -- read-only checks the migrator runs
   ```
   The audit chain is verified by the API's own `AuditChainVerifier` after the
   service starts; its finding is in the API log.

5. **Timezone and encoding:** both databases are `UTF8`; timestamps are
   `timestamptz`, so the server timezone does not change a stored instant. RDS
   defaults to UTC, as Railway does.

## 5a. Moving the files to S3 (after go-live)

From V310 every uploaded file has two possible homes: its bytes in the database
(`content`/`bytes` column) or an object in the files bucket (`object_id` →
`platform.file_object`: key, type, size, SHA-256). With `MOAUM_FILES_PROVIDER=S3`
new uploads go to the bucket; the files already in the database are moved by
the API's `FileMigrationJob` when `MOAUM_FILES_MIGRATE=true`:

1. `terraform apply -var files_migrate=true …`, then roll the API. Every 30 s one
   API task takes up to 200 rows across the eleven file tables and the JAMB
   passports (`admissions.attachment.payload` → object, `payload - 'dataUrl'`);
   each row: put to S3, read back, SHA-256 compared, `platform.file_object`
   written, then the database bytes cleared — one transaction per row.
2. Watch `/ecs/moaumpp-prod/api` for `files: N rows of <table> moved` and finally
   `files: nothing left to move to the object store`. At the time of writing
   production holds about 110,000 passports (428 MB) and 20 MB of documents:
   roughly ten hours at the default pace, during which the portal runs
   normally.
3. `terraform apply -var files_migrate=false …`, roll the API.
4. Reclaim the space: `VACUUM (FULL) admissions.attachment;` and the eleven blob
   tables, off-peak (each takes an exclusive lock for the duration of the
   rewrite; the largest is `admissions.attachment` at 428 MB, a minute or two).

Nothing is uploaded twice: the bytes are hashed first, and an owner (a
candidate's JAMB number, an application, a ticket…) that already holds an object
with the same SHA-256 gets that object back without a put. A passport re-uploaded
unchanged writes nothing; one that changed replaces the object and the old one
is removed. Each sweep also removes objects no row points at any more (an hour
old, so an upload in progress is never touched).

Not moved by design: `platform.notice_attachment` (an email's attachments, sent
within minutes; the table is on the audit spine).

**On Railway**, the same code works with a Railway Bucket (S3-compatible, its
own endpoint and key pair; private; virtual-hosted URLs). Create the Bucket on
the project canvas, then on `moaum-api` set, as variable references to the
bucket:

| Variable on `moaum-api` | Value |
|---|---|
| `MOAUM_FILES_PROVIDER` | `S3` |
| `MOAUM_FILES_BUCKET` | `${{ Bucket.BUCKET }}` |
| `MOAUM_FILES_ENDPOINT` | `${{ Bucket.ENDPOINT }}` |
| `MOAUM_FILES_REGION` | `${{ Bucket.REGION }}` (`auto`) |
| `MOAUM_FILES_ACCESS_KEY_ID` | `${{ Bucket.ACCESS_KEY_ID }}` |
| `MOAUM_FILES_SECRET_ACCESS_KEY` | `${{ Bucket.SECRET_ACCESS_KEY }}` |
| `MOAUM_FILES_MIGRATE` | unset at first; `true` to move the existing files; unset again when done |

(`Bucket` is whatever the bucket service is named.) The sweep then runs exactly
as above. On AWS the same variables come from the task role and the Terraform.

Phase 2 was written without an AWS account to run it against: the S3 client
and the sweeper are exercised for the first time on the real bucket. Run step 1
with `MOAUM_FILES_MIGRATE_BATCH=5` for the first roll and check one moved file
of each kind downloads from the portal before raising the batch.

## 6. Every deploy after that

```
git push origin main
   └─ CI (unchanged: build reproducibility, browser harnesses, migrations + check.sql, API tests, image)
        └─ green ─► Deploy to AWS (production)
                       1. build api + frontend images, tag = commit SHA (skipped if that SHA is already in ECR)
                       2. ECS run-task: bash db/migrate.sh   ─ fails → stop, nothing deployed
                       3. register api revision, roll, wait for stable ─ never healthy → ECS rolls back
                       4. same for frontend
                       5. GET https://portal/ must be 200
        └─ green ─► Railway deploys too, until it is switched off
```

- Pushes to other branches and pull requests run CI only.
- A failed CI never reaches the deploy workflow (`workflow_run` + `conclusion == success`).
- Deploys do not overlap (`concurrency: deploy-production`).
- The deploy role can push these two images and roll these two services. It
  cannot read the database, change infrastructure, or touch anything else.

## 7. Rollback

Every image is tagged with its commit SHA and tags are immutable. To go back to
commit B after C misbehaves: Actions → *Deploy to AWS (production)* → *Run
workflow* → `sha` = B. The workflow finds B's images already in ECR, does not
rebuild, runs the migrations (a no-op: B's files are a subset of C's and the
ledger skips them), and rolls both services to B.

Migrations are not undone by a rollback. A migration that B's code cannot live
with is corrected forward with a new migration, never by editing or deleting an
applied file (`db/migrate.sh` refuses an edited file).

Without GitHub, from the CLI:
```bash
aws ecs update-service --cluster moaumpp-prod --service api --task-definition moaumpp-prod-api:<revision>
```
`aws ecs list-task-definitions --family-prefix moaumpp-prod-api` lists revisions; each one's image tag is the commit.

## 8. Operations

| Need | How |
|---|---|
| Logs | CloudWatch log groups `/ecs/moaumpp-prod/api`, `.../frontend`, `.../migrate`; or `aws logs tail /ecs/moaumpp-prod/api --follow` |
| Health | ALB target health; `aws ecs describe-services --cluster moaumpp-prod --services api frontend` |
| A shell in a task | `aws ecs execute-command --cluster moaumpp-prod --task <id> --container api --interactive --command bash` (ECS Exec is on; `psql "$JDBC..."` needs the URL rewritten as `postgres://`, or use `PGHOST`/`PGUSER`/`PGPASSWORD` already in the environment: `psql -h <host> -d moaumpp`) |
| psql from outside | the bastion (§5) over SSM; never a public database |
| Restart | `aws ecs update-service --cluster moaumpp-prod --service api --force-new-deployment` |
| Backups | RDS automated, 14 days, plus the final snapshot on deletion. Restore = RDS *Restore to point in time* into a new instance, then point `JDBC_DATABASE_URL` at it (a Terraform variable change) |
| Alarms | SNS topic `moaumpp-prod-alerts`; thresholds in `monitoring.tf` |
| Cost | one NAT gateway, two Fargate tasks, Multi-AZ `db.t4g.medium`, the ALB. The bastion costs while it exists; turn it off |

Troubleshooting:

- *Migrate task exits 1* — its output is in the workflow log. An edited applied
  migration stops it by name; put the correction in a new file.
- *API never becomes healthy; ECS rolled back* — `/ecs/moaumpp-prod/api` log.
  The usual causes are the database (security group, `sslmode`), or a secret
  still `unset` that a module insists on.
- *Frontend 502* — the API is unreachable by name: Service Connect namespace,
  or the API task not yet healthy.
- *Gateway callbacks 404* — the paths are routed to the API by the ALB rule in
  `alb.tf`; a new callback path must be added there.

## 9. What is deliberately deferred

- **Presigned URLs / CloudFront for files.** Phase 2 (V310) moves the bytes to
  S3 but every download still streams through the API after its authorisation
  check, which is what keeps student documents private. A presigned-URL path
  for large downloads, and CloudFront for anything public, are the next step
  if the API's bandwidth ever becomes the limit.
- **Passport upload as multipart.** `POST /api/v1/results/legacy/passports`
  still takes base64 JSON; with the bytes now going to S3 the database cost is
  gone, and the remaining cost is the 33 % base64 overhead in the request.
- **CloudFront and WAF in front of the ALB.** Nothing public is static yet; add
  with phase 2.
- **A second NAT gateway** if an AZ outage of outbound calls (gateways, SMTP,
  SMS) is unacceptable.

## 10. Go-live checklist

Application: backend up, front page 200, sign-in, an office screen, a student
screen, a report, a PDF, an Excel export, a passport photo shows.
Database: counts match §5, `verify.sql` clean, audit chain verified, backups on,
not publicly accessible. Security: HTTPS only, HTTP redirects, no secrets in git,
deploy role scoped, database and ops bucket private. Pipeline: a push to `main`
reaches ECS only through green CI, the migrate step shows in the log, rollback
rehearsed once with a previous SHA. Payments: one sandbox transaction per
gateway end to end, callbacks reach the API over HTTPS, a duplicate reference is
refused. Jobs: one API task; the session-transition, hostel-expiry and
deferment clocks fire once (API log). Then DNS, then Railway off.
