```
terraform {
  required_providers {
    alicloud = {
      source  = "hashicorp/alicloud"
      version = "1.170.0"
    }
  }
}

variable "aliyun_access_key" {
  type      = string
}

variable "aliyun_secret_key" {
  type      = string
}

variable "region" {
	default = "cn-hongkong"
}

provider "alicloud" {
  region     = var.region
  access_key = var.aliyun_access_key
  secret_key = var.aliyun_secret_key
}

module "interactsh" {
    source  = "Explorer1092/interactsh/x"
#   version = "1.0.0"
    name_prefix = ""
    vswitch_id = ""
    domain = "zzz.ms"
    acao-url = ""
    zerossl_key = ""
    dns_aliyun_access_key = var.aliyun_access_key
    dns_aliyun_secret_key = var.aliyun_secret_key
}
```