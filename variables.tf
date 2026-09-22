#---------------------------------------------------------------
# Core bucket configuration
#---------------------------------------------------------------
variable "bucket_name" {
  description = "The name of the OSS bucket. Must be globally unique across Alibaba Cloud."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "Bucket name must be 3-63 characters, lowercase alphanumeric and hyphens only, cannot start/end with hyphen."
  }
}

variable "storage_class" {
  description = "Storage class for the bucket. Valid values: Standard, IA, Archive, ColdArchive, DeepColdArchive."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "IA", "Archive", "ColdArchive", "DeepColdArchive"], var.storage_class)
    error_message = "storage_class must be one of: Standard, IA, Archive, ColdArchive, DeepColdArchive."
  }
}

variable "redundancy_type" {
  description = "Data redundancy type. ZRS provides cross-AZ redundancy for HA. Valid values: LRS, ZRS."
  type        = string
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS"], var.redundancy_type)
    error_message = "redundancy_type must be LRS or ZRS."
  }
}

variable "resource_group_id" {
  description = "Resource group ID to which the bucket belongs. Leave empty for default resource group."
  type        = string
  default     = ""
}

#---------------------------------------------------------------
# Encryption — CIS 5.8 / 5.9 / AIA CMK
#---------------------------------------------------------------
variable "sse_algorithm" {
  description = "Server-side encryption algorithm. KMS is mandatory for CIS compliance. Valid values: KMS, AES256."
  type        = string
  default     = "KMS"

  validation {
    condition     = contains(["KMS", "AES256"], var.sse_algorithm)
    error_message = "sse_algorithm must be KMS or AES256. KMS required for CIS 5.8/5.9."
  }
}

variable "kms_master_key_id" {
  description = "KMS CMK ID for BYOK encryption (CIS 5.9 / AIA customer-managed key). Leave empty for ServiceKey mode (CIS 5.8)."
  type        = string
  default     = ""
}

variable "kms_data_encryption" {
  description = "Algorithm to encrypt objects when sse_algorithm is KMS. Valid values: SM4 (for China compliance) or empty string."
  type        = string
  default     = ""

  validation {
    condition     = contains(["", "SM4"], var.kms_data_encryption)
    error_message = "kms_data_encryption must be empty or SM4."
  }
}

#---------------------------------------------------------------
# HTTPS / TLS — CIS 5.4 / 5.6 / AIA secure transfer + min TLS
#---------------------------------------------------------------
variable "tls_versions" {
  description = "Allowed TLS versions for bucket access. CIS 5.4 mandates HTTPS; AIA requires TLS 1.2+."
  type        = list(string)
  default     = ["TLSv1.2"]

  validation {
    condition     = length(var.tls_versions) > 0
    error_message = "At least one TLS version must be specified."
  }
}

#---------------------------------------------------------------
# Access logging — CIS 5.3
#---------------------------------------------------------------
variable "logging_enabled" {
  description = "Enable access logging (CIS 5.3). When true, target_log_bucket must be specified."
  type        = bool
  default     = true
}

variable "target_log_bucket" {
  description = "Target bucket name for storing access logs. If empty and logging_enabled=true, logs to self."
  type        = string
  default     = ""
}

variable "log_prefix" {
  description = "Prefix for log object keys."
  type        = string
  default     = "access-log/"
}

#---------------------------------------------------------------
# Logging service role — required when the target log bucket uses
# SSE-KMS. The OSS log-delivery service must assume a RAM role that
# holds KMS permissions (GenerateDataKey/Decrypt) plus oss:PutObject
# on the log bucket; otherwise encrypted-log delivery fails silently.
#---------------------------------------------------------------
variable "create_logging_service_role" {
  description = "Create a Terraform-managed RAM service role that lets the OSS logging-delivery service write KMS-encrypted access logs. When null (default), auto-enabled only if logging_enabled=true AND sse_algorithm=\"KMS\". Set true/false to force. Alternative: authorize AliyunOSSLoggingDefaultRole once in the RAM console."
  type        = bool
  default     = null
}

variable "logging_service_role_name" {
  description = "Name of the RAM role created for the OSS logging service. Empty = derive from bucket name (oss-logging-<bucket>)."
  type        = string
  default     = ""
}

variable "logging_service_principal" {
  description = "Trusted service principal for the OSS logging role's assume-role policy. Verify the exact value against AliyunOSSLoggingDefaultRole in the RAM console before production use."
  type        = string
  default     = "oss.aliyuncs.com"
}

variable "logging_role" {
  description = "RAM role NAME bound to the bucket's log-delivery config (maps to the OSS PutBucketLogging 'LoggingRole' / console 'authorization role'). Empty (default) = bind the Terraform-managed role when one is created (KMS-encrypted logging); otherwise no role is bound. Set to \"AliyunOSSLoggingDefaultRole\" to reuse the account-wide console default role instead of a per-bucket managed role."
  type        = string
  default     = ""
}

#---------------------------------------------------------------
# Versioning — AIA soft-delete equivalent
#---------------------------------------------------------------
variable "versioning_status" {
  description = "Bucket versioning status. Enabled provides soft-delete protection (AIA). Valid values: Enabled, Suspended."
  type        = string
  default     = "Enabled"

  validation {
    condition     = contains(["Enabled", "Suspended"], var.versioning_status)
    error_message = "versioning_status must be Enabled or Suspended."
  }
}

#---------------------------------------------------------------
# Lifecycle rules
#---------------------------------------------------------------
variable "lifecycle_rules" {
  description = "List of lifecycle rules for object management."
  type = list(object({
    id      = string
    prefix  = string
    enabled = bool
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
    noncurrent_version_transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
    expiration_days                    = optional(number, 0)
    noncurrent_version_expiration_days = optional(number, 0)
  }))
  default = []
}

#---------------------------------------------------------------
# Network access / bucket policy — CIS 5.7
#---------------------------------------------------------------
variable "allowed_source_ips" {
  description = "List of IP addresses or CIDR blocks allowed to access the bucket (CIS 5.7). Empty list means no IP restriction (policy omitted)."
  type        = list(string)
  default     = []
}

variable "allowed_source_vpcs" {
  description = "List of VPC IDs allowed to access the bucket via VPC endpoint condition. Empty list means no VPC restriction."
  type        = list(string)
  default     = []
}

variable "custom_bucket_policy" {
  description = "Custom bucket policy JSON. When set, overrides the auto-generated network restriction policy."
  type        = string
  default     = ""

  validation {
    condition     = var.custom_bucket_policy == "" || can(jsondecode(var.custom_bucket_policy))
    error_message = "custom_bucket_policy must be valid JSON or empty string."
  }
}

#---------------------------------------------------------------
# HTTPS-only bucket policy — CIS 5.4
#---------------------------------------------------------------
variable "deny_http_access" {
  description = "Deny non-HTTPS (HTTP) access to the bucket via bucket policy (CIS 5.4). Enforces secure transfer."
  type        = bool
  default     = true
}

#---------------------------------------------------------------
# Deletion protection — AIA resource lock
#---------------------------------------------------------------
variable "force_destroy" {
  description = "If true, all objects will be deleted from the bucket on destroy. Set false for production (AIA resource lock)."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Enable deletion protection. When true, force_destroy is locked to false."
  type        = bool
  default     = true
}

#---------------------------------------------------------------
# Tags
#---------------------------------------------------------------
variable "tags" {
  description = "Additional tags to merge with module baseline tags. Module baseline tags take precedence."
  type        = map(string)
  default     = {}
}
