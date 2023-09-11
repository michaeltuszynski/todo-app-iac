variable "app_name" {
  description = "The name of the application"
  type        = string
}

variable "db_port" {
  description = "The port for the database"
  type        = number
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "private_subnets" {
  description = "The IDs of the private subnets"
  type        = list(string)
}

variable "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  type        = string
}



