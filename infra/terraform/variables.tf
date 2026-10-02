variable "region" {
  type    = string
  default = "af-south-1"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "certificate_arn" {
  description = "ACM certificate (in the same region) for the portal's domain. Empty = HTTP only, for a first smoke test; never for the University's data."
  type        = string
  default     = ""
}

variable "portal_url" {
  description = "Public URL of the portal, e.g. https://portal.moaum.edu.ng (becomes MOAUM_PORTAL_URL). Never invented here: the University's domain."
  type        = string
}

variable "github_repository" {
  description = "owner/name of the GitHub repository allowed to deploy through OIDC."
  type        = string
  default     = "Tabuul/moaum_project"
}

variable "github_branch" {
  description = "The only branch whose workflow may assume the deploy role."
  type        = string
  default     = "main"
}

variable "alarm_email" {
  description = "Where CloudWatch alarms are sent. Empty = topic created, nobody subscribed."
  type        = string
  default     = ""
}

variable "enable_bastion" {
  description = "A small SSM-managed instance in the private subnet with the PostgreSQL client, for the one-time data move and for psql against the private database. Off after go-live."
  type        = bool
  default     = false
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "db_allocated_storage" {
  description = "GiB. Production on Railway is ~7 GiB today, 4 of them the audit spine; gp3 autoscales to ten times this."
  type        = number
  default     = 50
}

variable "db_multi_az" {
  type    = bool
  default = true
}

variable "db_pool_size" {
  description = "Hikari maximum pool per API task (DB_POOL_SIZE). db.t4g.medium allows ~400 connections; keep tasks x pool well under it."
  type        = number
  default     = 10
}

variable "api_image_tag" {
  description = "Image tag for the first apply only; the deploy workflow registers new revisions by commit SHA afterwards."
  type        = string
  default     = "bootstrap"
}

variable "frontend_image_tag" {
  type    = string
  default = "bootstrap"
}

variable "api_cpu" {
  type    = number
  default = 1024
}

variable "api_memory" {
  type    = number
  default = 2048
}

variable "frontend_cpu" {
  type    = number
  default = 512
}

variable "frontend_memory" {
  type    = number
  default = 1024
}

variable "desired_count" {
  description = "Tasks per service at creation. The API runs seven @Scheduled jobs with no distributed lock, so keep it at 1 until one is added. The deploy workflow owns this afterwards."
  type        = number
  default     = 1
}

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "app_secret_names" {
  description = "API settings kept in Secrets Manager. Created as 'unset'; fill each with put-secret-value, then redeploy the API."
  type        = list(string)
  default = [
    "MOAUM_FLUTTERWAVE_SECRET", "MOAUM_FLUTTERWAVE_HASH", "MOAUM_PAYSTACK_SECRET",
    "MOAUM_PAYDIRECT_USERNAME", "MOAUM_PAYDIRECT_PASSWORD",
    "MOAUM_QUICKTELLER_MAC_KEY", "MOAUM_QUICKTELLER_CHS_MAC_KEY",
    "MOAUM_NOTICES_TOKEN", "MOAUM_SSO_CLIENT_SECRET",
  ]
}
