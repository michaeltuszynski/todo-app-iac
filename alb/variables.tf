variable "health_check_path" {
  description = "The path to use for the health check"
  type        = string
  default     = "/health"
}

variable "vpc_id" {
  description = "The ID of the VPC to deploy the ALB into"
  type        = string
}

variable "cidr_block" {
  description = "The CIDR block of the VPC to deploy the ALB into"
  type        = string
}

variable "public_subnets" {
  description = "The public subnets to deploy the ALB into"
  type        = list(string)
}

variable "backend_port" {
  description = "The port to use for the backend"
  type        = number
}

variable "application_paths" {
  description = "The paths to use for the application"
  type        = list(string)
}

variable "custom_domain_name" {
  description = "The custom domain name to use for the ALB"
  type        = string
}

variable "app_name" {
  type = string
}

variable "hosted_zone_id" {
  type = string
}
