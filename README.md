# modules/oss

CIS/AIA-compliant Alibaba Cloud OSS bucket module with server-side encryption, access control, logging, and network restriction.

## Compliance Coverage

| Control | Source | Implementation |
|---|---|---|
| 5.1 Bucket ACL private | CIS v2.0.0 | `alicloud_oss_bucket_acl` = "private" (hard-coded) |
| 5.1/5.2 Block public access | CIS v2.0.0 | `alicloud_oss_bucket_public_access_block` = true (hard-coded) |
| 5.3 Access logging | CIS v2.0.0 | `alicloud_oss_bucket_logging` (enabled by default) + `logging_role` bound end-to-end (auto-managed RAM role for KMS-encrypted delivery) |
| 5.4 Secure transfer (HTTPS) | CIS v2.0.0 | `alicloud_oss_bucket_https_config` TLS 1.2+ + deny-HTTP bucket policy |
| 5.6 URL signature HTTPS only | CIS v2.0.0 | Covered by HTTPS config enforcement |
| 5.7 Network access restricted | CIS v2.0.0 | Bucket policy with IP/VPC deny conditions |
| 5.8 SSE with Service Key | CIS v2.0.0 | `server_side_encryption_rule` KMS (default, no CMK ID) |
| 5.9 SSE with BYOK | CIS v2.0.0 | `server_side_encryption_rule` KMS + `kms_master_key_id` |
| Secure transfer required | AIA v1.2 | Same as CIS 5.4 |
| No blob anonymous access | AIA v1.2 | Same as CIS 5.1/5.2 |
| Customer-managed key | AIA v1.2 | BYOK mode (CIS 5.9) |
| Firewall/Endpoint | AIA v1.2 | `allowed_source_ips` / `allowed_source_vpcs` |
| Soft delete enabled | AIA v1.2 | Versioning = Enabled |
| Minimum TLS version | AIA v1.2 | `tls_versions = ["TLSv1.2"]` |
| ZRS redundancy (HA) | AIA v1.2 | `redundancy_type = "ZRS"` (default) |
| Resource lock | AIA v1.2 | `deletion_protection = true` (locks force_destroy) |

## Usage

```hcl
module "oss" {
  source = "../../modules/oss"

  bucket_name     = "my-app-data-bucket"
  storage_class   = "Standard"
  redundancy_type = "ZRS"

  # Encryption — BYOK (CIS 5.9 / AIA CMK)
  sse_algorithm     = "KMS"
  kms_master_key_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

  # Logging (CIS 5.3)
  logging_enabled   = true
  target_log_bucket = "my-log-bucket"
  log_prefix        = "oss-access-log/"

  # Versioning (AIA soft-delete)
  versioning_status = "Enabled"

  # Network restriction (CIS 5.7)
  allowed_source_ips  = ["10.0.0.0/8", "172.16.0.0/12"]
  allowed_source_vpcs = ["vpc-xxxxxx"]

  # Tags
  tags = {
    Project     = "my-project"
    Environment = "prod"
    Owner       = "platform-team"
  }
}
```

### Alternative — reuse the account-wide `AliyunOSSLoggingDefaultRole`

If your account already authorized the console default role once (via **一键授权**), skip the per-bucket managed role and reuse it:

```hcl
module "oss" {
  source = "../../modules/oss"

  bucket_name = "my-app-data-bucket"

  # KMS-encrypted logs still need an authorization role, but reuse
  # the account-wide default one instead of a per-bucket managed role.
  sse_algorithm               = "KMS"
  logging_enabled             = true
  create_logging_service_role = false                        # do NOT create a module-owned role
  logging_role                = "AliyunOSSLoggingDefaultRole" # bind the console default role
}
```

## Locked Defaults (cannot be overridden)

| Setting | Value | Rationale |
|---|---|---|
| Bucket ACL | `private` | CIS 5.1 |
| Public access block | `true` | CIS 5.1/5.2 |
| HTTPS config enabled | `true` | CIS 5.4/5.6 |
| TLS versions | `["TLSv1.2"]` (default) | AIA TLS minimum |
| SSE enabled | Always on | CIS 5.8 |
| Deny HTTP policy | `true` (default) | CIS 5.4 |

## Variables (24 total)

| Variable | Type | Default | Description |
|---|---|---|---|
| `bucket_name` | string | (required) | Globally unique bucket name |
| `storage_class` | string | `"Standard"` | Standard / IA / Archive / ColdArchive / DeepColdArchive |
| `redundancy_type` | string | `"ZRS"` | LRS or ZRS (cross-AZ) |
| `resource_group_id` | string | `""` | Resource group ID |
| `sse_algorithm` | string | `"KMS"` | KMS or AES256 |
| `kms_master_key_id` | string | `""` | CMK ID for BYOK; empty = ServiceKey |
| `kms_data_encryption` | string | `""` | SM4 or empty |
| `tls_versions` | list(string) | `["TLSv1.2"]` | Allowed TLS versions |
| `logging_enabled` | bool | `true` | Enable access logging |
| `target_log_bucket` | string | `""` | Log target bucket (empty = self) |
| `log_prefix` | string | `"access-log/"` | Log object key prefix |
| `create_logging_service_role` | bool | `null` | Create RAM role for KMS-encrypted log delivery; null = auto (logging + KMS) |
| `logging_service_role_name` | string | `""` | Logging role name; empty = `oss-logging-<bucket>` |
| `logging_service_principal` | string | `"oss.aliyuncs.com"` | Trusted service principal for the logging role |
| `logging_role` | string | `""` | RAM role NAME bound to the log config (console authorization role). Empty = bind managed role; set `"AliyunOSSLoggingDefaultRole"` to reuse the account default role |
| `versioning_status` | string | `"Enabled"` | Enabled or Suspended |
| `lifecycle_rules` | list(object) | `[]` | Lifecycle management rules |
| `allowed_source_ips` | list(string) | `[]` | IP/CIDR allowlist |
| `allowed_source_vpcs` | list(string) | `[]` | VPC ID allowlist |
| `custom_bucket_policy` | string | `""` | Custom policy JSON (overrides auto-gen) |
| `deny_http_access` | bool | `true` | Deny HTTP via bucket policy |
| `force_destroy` | bool | `false` | Allow destroy with objects |
| `deletion_protection` | bool | `true` | Lock force_destroy to false |
| `tags` | map(string) | `{}` | Additional tags |

## Outputs

### Functional

| Output | Description |
|---|---|
| `bucket_id` | Bucket name/ID |
| `bucket_domain` | External endpoint |
| `bucket_intranet_domain` | VPC-internal endpoint |
| `bucket_creation_date` | Creation timestamp |
| `bucket_storage_class` | Storage class |
| `bucket_redundancy_type` | LRS or ZRS |
| `logging_service_role_name` | RAM role for KMS-encrypted log delivery (null when not created) |
| `logging_role_bound` | RAM role name bound to the log config (console authorization role); null when none |

### Compliance Markers

| Output | CIS/AIA Control |
|---|---|
| `compliance_acl_private` | CIS 5.1 |
| `compliance_public_access_blocked` | CIS 5.1/5.2 |
| `compliance_logging_enabled` | CIS 5.3 |
| `compliance_logging_role_configured` | CIS 5.3 (KMS log delivery role) |
| `compliance_https_enforced` | CIS 5.4/5.6 |
| `compliance_tls_version` | AIA TLS minimum |
| `compliance_sse_enabled` | CIS 5.8 |
| `compliance_sse_algorithm` | CIS 5.8/5.9 |
| `compliance_sse_byok` | CIS 5.9 / AIA CMK |
| `compliance_deny_http` | CIS 5.4 |
| `compliance_network_restricted` | CIS 5.7 |
| `compliance_versioning_enabled` | AIA soft-delete |
| `compliance_deletion_protection` | AIA resource lock |
| `compliance_zrs_redundancy` | AIA HA |

## Provider Requirements

| Provider | Version |
|---|---|
| `aliyun/alicloud` | `~> 1.284` |
| Terraform | `>= 1.5, < 2.0` |

## Architecture Notes

This module uses **split sub-resources** per provider best practices (v1.220.0+):

- `alicloud_oss_bucket_acl` instead of inline `acl`
- `alicloud_oss_bucket_logging` instead of inline `logging`
- `alicloud_oss_bucket_versioning` instead of inline `versioning`
- `alicloud_oss_bucket_policy` instead of inline `policy`
- `alicloud_ram_role.logging` / `alicloud_ram_policy.logging` / `alicloud_ram_role_policy_attachment.logging` (`count`-gated; created only when the module manages the log-delivery role — see below)

The parent bucket has `lifecycle { ignore_changes = [acl, logging, versioning, policy] }` to prevent drift conflicts.

### Sub-resource serialization (409 avoidance)

OSS rejects concurrent bucket-metadata mutations with `409 ConcurrentUpdateBucketFailed`. To avoid this, the bucket sub-resources are chained with `depends_on` so they apply one at a time against the same bucket. When the module-managed RAM logging role is enabled, its attachment is also chained in **before** logging so the role exists at the moment `PutBucketLogging` runs:

```
acl → public_access_block → https_config → (ram_role → ram_policy → ram_role_policy_attachment) → logging → versioning → policy
```

The bucket **policy** is created **last** (`depends_on` on all of the above). This is required because the restrictive network policy (deny-HTTP + IP/VPC conditions) would otherwise block the management API calls that configure the other sub-resources (`403 AccessDenied`).

## CIS 5.5 Note (URL Signature Expiry)

CIS 5.5 requires shared URL signatures to expire within 1 hour. This is an **operational control** enforced at the application layer (SDK `expires` parameter), not configurable via Terraform bucket settings. Ensure application code sets `expires <= 3600` when generating presigned URLs.

## Logging Service Role (KMS-encrypted log delivery)

When access logs are delivered to a bucket that uses **SSE-KMS**, the OSS log-delivery service must assume a RAM role that holds KMS permissions. Without it, log delivery **fails silently** — the bucket appears configured but no log objects are ever written.

This module creates the role automatically **and binds it to the bucket's logging configuration**:

- **Auto-enable**: when `create_logging_service_role` is `null` (default) and both `logging_enabled = true` and `sse_algorithm = "KMS"`, the role is created. Set the variable to `true`/`false` to force the behavior. Existing non-KMS callers are unaffected (no role created).
- **Resources**: `alicloud_ram_role.logging` + `alicloud_ram_policy.logging` + `alicloud_ram_role_policy_attachment.logging` (all `count`-gated, so a plain non-KMS bucket is byte-for-byte unchanged).
- **Binding (the critical step)**: the resolved role name is written to `alicloud_oss_bucket_logging.logging_role` — this is the OSS `PutBucketLogging` `LoggingRole` field, shown as **授权角色 (authorization role)** in the console. **Creating the role is not enough**: if it is not bound here, the console keeps showing **暂未配置 (not configured)** and KMS-encrypted log delivery still fails silently.
- **Permissions granted** (least-privilege): `kms:GenerateDataKey`, `kms:Decrypt`, `kms:List*`, `kms:Describe*`, and `oss:PutObject` / `oss:AbortMultipartUpload` scoped to the log bucket only.
- **Trust principal**: `oss.aliyuncs.com` (configurable via `logging_service_principal`).

The role name actually bound is exposed via the `logging_role_bound` output.

> **Note**: The RAM API rejects `log.oss.aliyuncs.com` with `MalformedPolicyDocument: invalid service name`. The verified working principal is `oss.aliyuncs.com`. If Alibaba Cloud changes this, override `logging_service_principal` — confirm the exact value from `AliyunOSSLoggingDefaultRole` in the RAM console.

**Alternative (reuse account-wide default role)**: set `create_logging_service_role = false` and `logging_role = "AliyunOSSLoggingDefaultRole"`. The module then binds the account-wide console default role (create/authorize it once via **一键授权** in the OSS console) instead of a per-bucket managed role. Leaving `logging_role = ""` (default) binds the module-managed role when one is created.
