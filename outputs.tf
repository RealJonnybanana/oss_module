#---------------------------------------------------------------
# Functional outputs
#---------------------------------------------------------------
output "bucket_id" {
  description = "The name (ID) of the OSS bucket."
  value       = alicloud_oss_bucket.this.id
}

output "bucket_domain" {
  description = "The bucket domain name (external endpoint)."
  value       = alicloud_oss_bucket.this.extranet_endpoint
}

output "bucket_intranet_domain" {
  description = "The bucket intranet domain name (VPC-internal endpoint)."
  value       = alicloud_oss_bucket.this.intranet_endpoint
}

output "bucket_creation_date" {
  description = "The creation date of the bucket."
  value       = alicloud_oss_bucket.this.creation_date
}

output "bucket_storage_class" {
  description = "The storage class of the bucket."
  value       = alicloud_oss_bucket.this.storage_class
}

output "bucket_redundancy_type" {
  description = "Data redundancy type (LRS or ZRS)."
  value       = var.redundancy_type
}

#---------------------------------------------------------------
# Compliance markers — CIS 5.x / AIA controls
#---------------------------------------------------------------
output "compliance_acl_private" {
  description = "CIS 5.1 — Bucket ACL is set to private."
  value       = alicloud_oss_bucket_acl.this.acl == "private"
}

output "compliance_public_access_blocked" {
  description = "CIS 5.1/5.2 — Public access block is enabled."
  value       = alicloud_oss_bucket_public_access_block.this.block_public_access
}

output "compliance_logging_enabled" {
  description = "CIS 5.3 — Access logging is enabled."
  value       = var.logging_enabled
}

output "logging_service_role_name" {
  description = "Name of the Terraform-managed RAM role for KMS-encrypted log delivery, or null when not created."
  value       = local.enable_logging_service_role ? alicloud_ram_role.logging[0].role_name : null
}

output "compliance_logging_role_configured" {
  description = "CIS 5.3 support — True when a RAM role for KMS-encrypted log delivery is managed by Terraform."
  value       = local.enable_logging_service_role
}

output "logging_role_bound" {
  description = "RAM role NAME bound to the bucket log-delivery config (OSS 'LoggingRole' / console authorization role). Null when no role is bound."
  value       = local.effective_logging_role != "" ? local.effective_logging_role : null
}

output "compliance_https_enforced" {
  description = "CIS 5.4/5.6 — HTTPS-only access enforced via TLS config."
  value       = true
}

output "compliance_tls_version" {
  description = "AIA TLS minimum — TLS versions allowed."
  value       = var.tls_versions
}

output "compliance_sse_enabled" {
  description = "CIS 5.8 — Server-side encryption is enabled."
  value       = true
}

output "compliance_sse_algorithm" {
  description = "CIS 5.8/5.9 — SSE algorithm in use (KMS or AES256)."
  value       = var.sse_algorithm
}

output "compliance_sse_byok" {
  description = "CIS 5.9 / AIA CMK — True when customer-managed KMS key is used."
  value       = local.is_byok
}

output "compliance_deny_http" {
  description = "CIS 5.4 — Bucket policy denies HTTP (non-HTTPS) access."
  value       = var.deny_http_access
}

output "compliance_network_restricted" {
  description = "CIS 5.7 — Network access restricted to specific IPs or VPCs."
  value       = length(var.allowed_source_ips) > 0 || length(var.allowed_source_vpcs) > 0
}

output "compliance_versioning_enabled" {
  description = "AIA soft-delete — Versioning status."
  value       = alicloud_oss_bucket_versioning.this.status == "Enabled"
}

output "compliance_deletion_protection" {
  description = "AIA resource lock — force_destroy is disabled."
  value       = !local.effective_force_destroy
}

output "compliance_zrs_redundancy" {
  description = "AIA HA — True when ZRS (cross-AZ) redundancy is enabled."
  value       = var.redundancy_type == "ZRS"
}
