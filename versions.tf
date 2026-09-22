terraform {
  required_version = ">= 1.5, < 2.0"
  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~> 1.284"
    }
  }
}
