#---------------------------------------------------------------
# OSS Bucket — CIS 5.x / AIA compliant
#---------------------------------------------------------------
resource "alicloud_oss_bucket" "this" {
  bucket            = var.bucket_name
  storage_class     = var.storage_class
  redundancy_type   = var.redundancy_type
  resource_group_id = var.resource_group_id != "" ? var.resource_group_id : null
  force_destroy     = local.effective_force_destroy
  tags              = local.effective_tags

  # CIS 5.8 / 5.9 — Server-side encryption (mandatory)
  server_side_encryption_rule {
    sse_algorithm       = var.sse_algorithm
    kms_master_key_id   = local.is_byok ? var.kms_master_key_id : null
    kms_data_encryption = var.kms_data_encryption != "" ? var.kms_data_encryption : null
  }

  # Lifecycle rules (optional)
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules
    content {
      id      = lifecycle_rule.value.id
      prefix  = lifecycle_rule.value.prefix
      enabled = lifecycle_rule.value.enabled

      dynamic "transitions" {
        for_each = lifecycle_rule.value.transitions
        content {
          days          = transitions.value.days
          storage_class = transitions.value.storage_class
        }
      }

      dynamic "noncurrent_version_transition" {
        for_each = lifecycle_rule.value.noncurrent_version_transitions
        content {
          days          = noncurrent_version_transition.value.days
          storage_class = noncurrent_version_transition.value.storage_class
        }
      }

      dynamic "expiration" {
        for_each = lifecycle_rule.value.expiration_days > 0 ? [lifecycle_rule.value.expiration_days] : []
        content {
          days = expiration.value
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = lifecycle_rule.value.noncurrent_version_expiration_days > 0 ? [lifecycle_rule.value.noncurrent_version_expiration_days] : []
        content {
          days = noncurrent_version_expiration.value
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      acl,
      logging,
      versioning,
      policy,
      tags["CreatedOnDate"],
    ]
  }
}

#---------------------------------------------------------------
# CIS 5.1 / 5.2 — Bucket ACL = private (split sub-resource)
#---------------------------------------------------------------
resource "alicloud_oss_bucket_acl" "this" {
  bucket = alicloud_oss_bucket.this.bucket
  acl    = "private"
}

#---------------------------------------------------------------
# CIS 5.1 / 5.2 — Block all public access
#
# NOTE: OSS rejects concurrent bucket-metadata mutations with
# 409 ConcurrentUpdateBucketFailed. The bucket sub-resources below
# (acl -> public_access_block -> https_config -> logging ->
# versioning) are chained via depends_on so they apply one at a
# time against the same bucket.
#---------------------------------------------------------------
resource "alicloud_oss_bucket_public_access_block" "this" {
  bucket              = alicloud_oss_bucket.this.bucket
  block_public_access = true

  depends_on = [alicloud_oss_bucket_acl.this]
}

#---------------------------------------------------------------
# CIS 5.4 / 5.6 / AIA TLS — HTTPS-only with TLS 1.2+
#---------------------------------------------------------------
resource "alicloud_oss_bucket_https_config" "this" {
  bucket       = alicloud_oss_bucket.this.bucket
  enable       = true
  tls_versions = var.tls_versions

  depends_on = [alicloud_oss_bucket_public_access_block.this]
}

#---------------------------------------------------------------
# CIS 5.3 support — RAM service role for KMS-encrypted log delivery
#
# When access logs are delivered to a KMS-encrypted bucket, the OSS
# logging service must assume a role holding KMS + oss:PutObject
# permissions, or delivery silently fails. Created only when
# local.enable_logging_service_role is true (auto for logging + KMS).
#---------------------------------------------------------------
resource "alicloud_ram_role" "logging" {
  count = local.enable_logging_service_role ? 1 : 0

  role_name                   = local.effective_logging_role_name
  description                 = "Allows the OSS logging service to write KMS-encrypted access logs (managed by Terraform)."
  assume_role_policy_document = local.logging_assume_role_policy
  tags                        = local.effective_tags

  lifecycle {
    ignore_changes = [
      tags["CreatedOnDate"],
    ]
  }
}

resource "alicloud_ram_policy" "logging" {
  count = local.enable_logging_service_role ? 1 : 0

  policy_name     = "${local.effective_logging_role_name}-policy"
  policy_document = local.logging_role_policy
  description     = "KMS + OSS PutObject permissions for OSS log delivery (managed by Terraform)."
}

resource "alicloud_ram_role_policy_attachment" "logging" {
  count = local.enable_logging_service_role ? 1 : 0

  role_name   = alicloud_ram_role.logging[0].role_name
  policy_name = alicloud_ram_policy.logging[0].policy_name
  policy_type = "Custom"
}

#---------------------------------------------------------------
# CIS 5.3 — Access logging
#---------------------------------------------------------------
resource "alicloud_oss_bucket_logging" "this" {
  count = var.logging_enabled ? 1 : 0

  bucket        = alicloud_oss_bucket.this.bucket
  target_bucket = local.effective_log_bucket
  target_prefix = var.log_prefix

  # Authorization role (OSS PutBucketLogging 'LoggingRole'). Required for
  # KMS-encrypted log delivery; null when no role is resolved so plain
  # (non-KMS) delivery is unaffected.
  logging_role = local.effective_logging_role != "" ? local.effective_logging_role : null

  depends_on = [
    alicloud_oss_bucket_https_config.this,
    alicloud_ram_role_policy_attachment.logging,
  ]
}

#---------------------------------------------------------------
# AIA Soft-delete — Versioning (split sub-resource)
#---------------------------------------------------------------
resource "alicloud_oss_bucket_versioning" "this" {
  bucket = alicloud_oss_bucket.this.bucket
  status = var.versioning_status

  depends_on = [alicloud_oss_bucket_logging.this]
}

#---------------------------------------------------------------
# CIS 5.4 + 5.7 — Bucket policy: deny HTTP + network restriction
# Only created when deny_http_access=true OR network restrictions exist
# OR a custom policy is provided
#
# IMPORTANT: depends_on ensures the policy is created LAST, after all
# other sub-resources (logging, versioning, https_config, etc.) have been
# configured. Without this, the restrictive policy would block the
# management API calls for those sub-resources (403 AccessDenied).
#---------------------------------------------------------------
resource "alicloud_oss_bucket_policy" "this" {
  count = (var.deny_http_access || length(var.allowed_source_ips) > 0 || length(var.allowed_source_vpcs) > 0 || var.custom_bucket_policy != "") ? 1 : 0

  bucket = alicloud_oss_bucket.this.bucket
  policy = var.custom_bucket_policy != "" ? var.custom_bucket_policy : jsonencode(local.generated_policy)

  depends_on = [
    alicloud_oss_bucket_acl.this,
    alicloud_oss_bucket_https_config.this,
    alicloud_oss_bucket_logging.this,
    alicloud_oss_bucket_public_access_block.this,
    alicloud_oss_bucket_versioning.this,
  ]
}
