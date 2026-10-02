# MOAUMPP on AWS: Terraform

The infrastructure for the production portal on AWS: VPC, RDS for PostgreSQL 17,
ECR, ECS Fargate (api + frontend), ALB, Secrets Manager, CloudWatch alarms, the
GitHub OIDC deploy role, and an optional SSM bastion for the data move.

The runbook, from an empty AWS account to go-live, is `docs/aws-deployment.md`.
Nothing here is applied automatically: the deploy workflow only pushes images and
rolls services; infrastructure changes are `terraform apply` by an administrator.

Not yet validated against a real account: `terraform validate` and `plan` have not
been run in this repository (no Terraform on the authoring machine). Run both
before the first apply.

```bash
cd infra/terraform
terraform init
terraform validate
terraform plan  -var portal_url=https://portal.<university-domain> -var certificate_arn=<acm-arn>
```
