variable "app_name" {
  description = "The name of the application"
  type        = string
}

variable "custom_domain_name" {
  description = "The custom domain name for the application"
  type        = string
}

variable "hosted_zone_id" {
  description = "The ID of the Route53 hosted zone"
  type        = string
}
