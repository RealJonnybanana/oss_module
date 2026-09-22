#---------------------------------------------------------------
# Locals
#---------------------------------------------------------------
locals {
  # Baseline tags — module-enforced, cannot be overridden by caller
  baseline_tags = {
    Compliance = "CIS-Alibaba-Cloud-Foundation-Benchmark-v2.0.0"
    ManagedBy  = "Terraform"
    Module     = "oss"
  }

  # Merge: baseline takes precedence over user-supplied tags
  effective_tags = merge(var.tags, local.baseline_tags)

  # Force destroy locked when deletion_protection is enabled
  effective_force_destroy = var.deletion_protection ? false : var.force_destroy

  # Logging target: self-bucket or dedicated log bucket
  effective_log_bucket = var.target_log_bucket != "" ? var.target_log_bucket : var.bucket_name

  # Encryption: BYOK when kms_master_key_id is provided (CIS 5.9), otherwise ServiceKey (CIS 5.8)
  is_byok = var.kms_master_key_id != ""

  #-------------------------------------------------------------
  # Logging service role — needed when logs are delivered to a
  # KMS-encrypted bucket. Auto-enable when create_logging_service_role
  # is null and logging is on with KMS SSE; otherwise honor the explicit
  # bool. Backward-compatible: existing callers (null + non-KMS) get no role.
  #-------------------------------------------------------------
  enable_logging_service_role = (
    var.create_logging_service_role != null
    ? var.create_logging_service_role
    : (var.logging_enabled && var.sse_algorithm == "KMS")
  )

  effective_logging_role_name = var.logging_service_role_name != "" ? var.logging_service_role_name : "oss-logging-${var.bucket_name}"

  # Role NAME actually bound to the bucket logging config (OSS PutBucketLogging
  # 'LoggingRole' / console "authorization role"). Priority:
  #   1. explicit var.logging_role (e.g. reuse account-wide AliyunOSSLoggingDefaultRole)
  #   2. the Terraform-managed role, when this module creates one (KMS logging)
  #   3. empty — no role bound (non-KMS, ServiceKey/no-SSE log delivery works without a role)
  effective_logging_role = (
    var.logging_role != ""
    ? var.logging_role
    : (local.enable_logging_service_role ? local.effective_logging_role_name : "")
  )

  # Trust policy: allow the OSS logging service to assume the role.
  logging_assume_role_policy = jsonencode({
    Version = "1"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = [var.logging_service_principal] }
      }
    ]
  })

  # Permission policy: write encrypted log objects to the log bucket.
  # KMS actions are required so the service can generate/decrypt data keys
  # for SSE-KMS objects; OSS actions allow the multipart log upload.
  logging_role_policy = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:List*",
          "kms:Describe*",
          "kms:GenerateDataKey",
          "kms:Decrypt",
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "oss:PutObject",
          "oss:AbortMultipartUpload",
        ]
        Resource = ["acs:oss:*:*:${local.effective_log_bucket}/*"]
      }
    ]
  })

  #-------------------------------------------------------------
  # Bucket policy statements — CIS 5.4 (deny HTTP) + CIS 5.7 (network)
  #-------------------------------------------------------------

  # CIS 5.4 — deny all non-HTTPS (insecure transport) access
  deny_http_statement = var.deny_http_access ? [{
    Effect    = "Deny"
    Action    = "oss:*"
    Principal = ["*"]
    Resource  = ["acs:oss:*:*:${var.bucket_name}", "acs:oss:*:*:${var.bucket_name}/*"]
    Condition = {
      Bool = {
        "acs:SecureTransport" = "false"
      }
    }
  }] : []

  # IP restriction applies ONLY to data-plane operations (same rationale
  # as VPC restriction — management APIs must remain accessible).
  ip_restrict_statement = length(var.allowed_source_ips) > 0 ? [{
    Effect    = "Deny"
    Action    = local.vpc_data_actions
    Principal = ["*"]
    Resource  = ["acs:oss:*:*:${var.bucket_name}", "acs:oss:*:*:${var.bucket_name}/*"]
    Condition = {
      NotIpAddress = {
        "acs:SourceIp" = var.allowed_source_ips
      }
    }
  }] : []

  # VPC restriction applies ONLY to data-plane operations.
  # Management APIs (GetBucketInfo, GetBucketStat, PutBucketLogging,
  # PutBucketVersioning, etc.) are NOT restricted by VPC — they must
  # remain accessible via the public endpoint for Terraform and other
  # IaC tools to function during refresh/plan/apply.
  vpc_data_actions = [
    "oss:GetObject",
    "oss:PutObject",
    "oss:DeleteObject",
    "oss:ListObjects",
    "oss:GetObjectAcl",
    "oss:PutObjectAcl",
    "oss:ListObjectVersions",
    "oss:ListParts",
    "oss:AbortMultipartUpload",
    "oss:ListMultipartUploads",
  ]

  vpc_restrict_statement = length(var.allowed_source_vpcs) > 0 ? [{
    Effect    = "Deny"
    Action    = local.vpc_data_actions
    Principal = ["*"]
    Resource  = ["acs:oss:*:*:${var.bucket_name}", "acs:oss:*:*:${var.bucket_name}/*"]
    Condition = {
      StringNotEquals = {
        "acs:SourceVpc" = var.allowed_source_vpcs
      }
    }
  }] : []

  generated_policy = {
    Version   = "1"
    Statement = concat(local.deny_http_statement, local.ip_restrict_statement, local.vpc_restrict_statement)
  }
}
