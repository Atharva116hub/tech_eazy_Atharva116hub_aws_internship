variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "key_name" {
  type    = string
  default = "techeazy-key"
}

variable "security_group_name" {
  type    = string
  default = "Techeazy SG"
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "repo_url" {
  type    = string
  default = "https://github.com/techeazy-consulting/techeazy-devops"
}

variable "app_name" {
  type    = string
  default = "techeazy-devops"
}

variable "app_port" {
  type    = number
  default = 80
}

variable "stop_after_minutes" {
  type    = number
  default = 0
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "stage" {
  type = string
  validation {
    condition     = contains(["Dev", "Prod", "Development", "Production"], title(var.stage))
    error_message = "The stage must be one of: 'Dev', 'Prod', 'Development', or 'Production'."
  }
}

variable "app_env" {
  type    = string
  default = "default"
}

variable "db_host" {
  type    = string
  default = "default-db.example.com"
}

variable "api_key" {
  type      = string
  sensitive = true
  default   = "default_api_key"
}
