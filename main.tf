terraform {
  required_providers {
    alicloud = {
      source  = "hashicorp/alicloud"
      version = ">= 1.170.0"
    }
    acme = {
      source  = "vancluever/acme"
      version = "2.8.0"
    }
    zerossl = {
      source = "toowoxx/zerossl"
    }
  }
}

variable "name_prefix" {
  type = string
}

variable "vswitch_id" {
  type = string
}

variable "domain" {
  type = string
}

variable "zerossl_key" {
    description = "ZeroSSL Key"
}

variable "dns_aliyun_access_key" {
  type = string
}

variable "dns_aliyun_secret_key" {
  type = string
}

variable "acao-url" {
  type = string
}

provider "acme" {
  server_url = "https://acme.zerossl.com/v2/DV90"
}

data "alicloud_vswitches" "vsw" {
  ids = [var.vswitch_id]
}


resource "alicloud_security_group" "interactsh" {
  name = "${var.name_prefix}-interactsh"
  vpc_id = data.alicloud_vswitches.vsw.vswitches.0.vpc_id #data.alicloud_vswitches.vsw.vswitches.0.vpc_id
}

resource "alicloud_security_group_rule" "all" {
  type              = "ingress"
  ip_protocol       = "all"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "-1/-1"
  priority          = 2
  security_group_id = alicloud_security_group.interactsh.id
  cidr_ip           = "0.0.0.0/0"
  description       = "攻击环境 访问 http服务"
}

resource "random_id" "token" {
    keepers = {
        name = "${var.name_prefix}-interactsh"
    }

    byte_length = 8
}

resource "alicloud_eci_container_group" "interactsh-slave" {
#   depends = [alicloud_eci_image_cache.cache]
  container_group_name = "${var.name_prefix}interactsh-slave"
  cpu                  = 0.5
  memory               = 1
  restart_policy       = "Always"
  security_group_id    = alicloud_security_group.interactsh.id
  vswitch_id           = var.vswitch_id # 交换机

  auto_create_eip = true
  eip_bandwidth   = 100

  auto_match_image_cache = true

  containers {

    image             = "projectdiscovery/interactsh-server:latest"
    name              = "${var.name_prefix}interactsh-slave"
    image_pull_policy = "IfNotPresent"

    ports {
      port     = 443
      protocol = "TCP"
    }

    ports {
      port     = 80
      protocol = "TCP"
    }

    ports {
      port     = 587
      protocol = "TCP"
    }

    ports {
      port     = 389
      protocol = "TCP"
    }

    ports {
      port     = 25
      protocol = "TCP"
    }

    ports {
      port     = 53
      protocol = "TCP"
    }
    ports {
      port     = 53
      protocol = "UDP"
    }
    volume_mounts {
        mount_path = "/etc/ssl/certs/"
        name       = "certs"
    }
    volume_mounts {
        mount_path = "/etc/ssl/private/"
        name       = "private"
    }
    volume_mounts {
        mount_path = "/data/"
        name       = "entrypoint"
    }
    commands = ["sh","/data/entrypoint.sh"]
  }

  /* config 目录*/
  volumes {
    name = "certs"
    type = "ConfigFileVolume"

    config_file_volume_config_file_to_paths {
      content = base64encode(module.zerossl_alicloud.certificate_pem)
      path    = "interactsh.crt"
    }
  }

  volumes {
    name = "private"
    type = "ConfigFileVolume"

    config_file_volume_config_file_to_paths {
      content = base64encode(module.zerossl_alicloud.private_key)
      path    = "interactsh.key"
    }
  }

  volumes {
    name = "entrypoint"
    type = "ConfigFileVolume"

    config_file_volume_config_file_to_paths {
      content = base64encode(local.entrypoint)
      path    = "entrypoint.sh"
    }
  }

}

locals {
    entrypoint = <<EOF
#!/bin/sh
set -x
IP=`wget  ip.zip.ms -O - 2>/dev/null`
interactsh-server -domain ${var.domain} -wc -ip $IP -t ${random_id.token.hex} -se -cidl 4 -cidn 6 -acao-url ${var.acao-url} -cert /etc/ssl/certs/interactsh.crt -privkey /etc/ssl/private/interactsh.key
EOF
}


module "dns" {
  source               = "terraform-alicloud-modules/dns/alicloud"
  existing_domain_name = var.domain
  version              = "1.5.0"
  records = [
    {
      rr       = "ns1"
      type     = "A"
      ttl      = 600
      value    = alicloud_eci_container_group.interactsh-slave.internet_ip
      priority = 1
    },
    {
      rr       = "ns2"
      type     = "A"
      ttl      = 600
      value    = alicloud_eci_container_group.interactsh-slave.internet_ip
      priority = 1
    },
    {
      rr       = "*"
      type     = "NS"
      ttl      = 600
      value    = "ns1.${var.domain}"
      priority = 1
    },
    {
      rr       = "*"
      type     = "NS"
      ttl      = 600
      value    = "ns2.${var.domain}"
      priority = 1
    },
    {
      rr       = "@"
      type     = "A"
      ttl      = 600
      value    = alicloud_eci_container_group.interactsh-slave.internet_ip
      priority = 1
    }

  ]
}

module "zerossl_alicloud" {
  source  = "Explorer1092/zerossl_alicloud/x"
  version = "1.0.5"
  aliyun_access_key = var.dns_aliyun_access_key
  aliyun_secret_key = var.dns_aliyun_secret_key
  common_name = var.domain
  subject_alternative_names = ["*.${var.domain}"]
  zerossl_key = var.zerossl_key
}

output "public_ip" {
  value = alicloud_eci_container_group.interactsh-slave.internet_ip
}

output "private_ip" {
  value = alicloud_eci_container_group.interactsh-slave.intranet_ip
}

output "token" {
  value = random_id.token.hex
}