## Input Variables
variable "app_name" {
  type    = string
}

variable "app_environment" {
  type    = string
}

variable "region" {
  type = string
}

variable "backend_port" {
  type = string
}

variable "db_port" {
  type = string
}

variable "https_port" {
  type = number
  default = 443
}

variable "custom_domain_name" {
  type = string
}

variable "hosted_zone_id" {
  type = string
}

variable "github_owner" {
  type = string
}

variable "github_frontend_repo" {
  type = string
}

variable "github_backend_repo" {
  type = string
}

variable "github_token" {
  type = string
}

## Default Variables

variable "min_capacity" {
  type    = number
  default = 2
}

variable "max_capacity" {
  type    = number
  default = 4
}

variable "min_percentage" {
  type    = number
  default = 50
}

variable "max_percentage" {
  type    = number
  default = 200
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "target_value_scale_in" {
  type    = number
  default = 25
}

variable "target_value_scale_out" {
  type    = number
  default = 75
}

variable "scale_in_cooldown" {
  type    = number
  default = 60
}

variable "scale_out_cooldown" {
  type    = number
  default = 60
}







