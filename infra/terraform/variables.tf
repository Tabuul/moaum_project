variable "region" {
  type    = string
  default = "eu-west-1"
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
  description = "ACM certificate for the portal's domain. Empty = HTTP only (for a first test, never for the University's data)."
  type        = string
  default     = ""
}

variable "portal_url" {
  description = "Public URL of the portal, e.g. https://portal.moaum.edu.ng (MOAUM_PORTAL_URL)."
  type        = string
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "db_allocated_storage" {
  type    = number
  default = 50
}

variable "db_multi_az" {
  type    = bool
  default = true
}

variable "api_image_tag" {
  type    = string
  default = "latest"
}

variable "frontend_image_tag" {
  type    = string
  default = "latest"
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
  type    = number
  default = 2
}

variable "app_secret_names" {
  description = "API settings kept in Secrets Manager. Created empty; fill each in the console or CLI, then redeploy."
  type        = list(string)
  default = [
    "MOAUM_FLUTTERWAVE_SECRET", "MOAUM_FLUTTERWAVE_HASH", "MOAUM_PAYSTACK_SECRET",
    "MOAUM_PAYDIRECT_USERNAME", "MOAUM_PAYDIRECT_PASSWORD",
    "MOAUM_QUICKTELLER_MAC_KEY", "MOAUM_QUICKTELLER_CHS_MAC_KEY",
    "MOAUM_NOTICES_TOKEN", "MOAUM_SSO_CLIENT_SECRET",
  ]
}
