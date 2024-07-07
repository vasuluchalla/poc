variable "database_name" {
  type        = string
  default     = "poc"
  description = "RDS postgres database name"
}


variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for EC2"
}


variable "key_name" {
  type        = string
  default     = "app-key"
  description = "EC2 key name"
}

variable "username_db" {
  type        = string
  default     = "postgres"
  description = "Username rds"
}

variable "pwd_db" {
  type        = string
  default     = "postgres"
  description = "Password rds"
}


variable "airflow_instance_type" {
  type        = string
  default     = "t2.xlarge"
  description = "Airflow instance typ ec2"
}

variable "aws_ami" {
  type        = string
  default     = "ami-0e872aee57663ae2d"
}