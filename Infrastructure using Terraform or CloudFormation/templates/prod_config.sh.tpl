variable "app_env" {
  default = "production"
}

variable "db_host" {
  default = "prod-db.example.com"
}

variable "api_key" {
  default = "prod_api_key_XYZ_SECURE_DONT_COMMIT"
}

variable "instance_type" {
  default = "t2.medium"
}

variable "stop_after_minutes" {
  default = 60
}
