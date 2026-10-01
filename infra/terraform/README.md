# MOAUMPP on AWS (ECS Fargate + RDS)

Not yet applied or validated: `terraform validate` and `plan` have not been run.

## What it builds

- VPC, 2 AZs: public subnets (load balancer, NAT), private subnets (tasks, database)
- RDS PostgreSQL 17, encrypted, Multi-AZ, 14-day backups, master password in Secrets Manager
- ECR repos `moaumpp/api` and `moaumpp/frontend`
- ECS Fargate cluster with two services: `frontend` (Next.js, :3000) and `api` (Spring Boot, :8081)
- Frontend reaches the API at `http://api:8081` (ECS Service Connect), never through the internet
- ALB: everything to the frontend, except the payment gateway callbacks (`/api/v1/payments/webhook/*`, `paydirect/*`, `quickteller/start|return`), which go straight to the API
- A one-off `migrate` task definition that runs `bash db/migrate.sh` from the API image
- Secrets Manager entries for `MOAUM_AUTH_HMAC_SECRET` (generated) and the gateway/SMS/SSO secrets (created as `unset`)

## First deploy

```bash
cd infra/terraform
terraform init
terraform apply -var portal_url=https://portal.example.edu.ng -var certificate_arn=<acm-arn>   # creates ECR first-run services with no images yet

# build and push (from the repository root)
aws ecr get-login-password | docker login --username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com
docker build -f api/Dockerfile      -t <ecr_api>:latest .      && docker push <ecr_api>:latest
docker build -f frontend/Dockerfile -t <ecr_frontend>:latest . && docker push <ecr_frontend>:latest

# migrate, then start the services
aws ecs run-task --cluster <cluster> --launch-type FARGATE --task-definition <migrate_task_definition> \
  --network-configuration "awsvpcConfiguration={subnets=[<private_subnets>],securityGroups=[<tasks_security_group>]}"
aws ecs update-service --cluster <cluster> --service api      --force-new-deployment
aws ecs update-service --cluster <cluster> --service frontend --force-new-deployment
```

Then set each gateway secret (`aws secretsmanager put-secret-value --secret-id moaumpp-prod/MOAUM_PAYSTACK_SECRET --secret-string ...`), force a new API deployment, and give Interswitch the callback addresses from the Bursary screen.

## To check before go-live

- `db/V001` creates roles and extensions; confirm the RDS master user (`rds_superuser`) is allowed to.
- The database has no public access: run `psql` through a bastion or ECS Exec.
- `/actuator/health` is public by design in the API; leave it off the internet-facing rules if you add a WAF.
- Uploaded files are still `bytea` in RDS (see the storage discussion); size the instance accordingly.
- One NAT gateway is a single point of failure for outbound calls (gateways, SMTP, SMS).
