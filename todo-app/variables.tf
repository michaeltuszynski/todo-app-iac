variable "app_name" {
  type    = string
  default = "todo"
}

variable "app_environment" {
  type    = string
  default = "production"
}

variable "region" {
  type    = string
  default = "us-west-2"
}

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




