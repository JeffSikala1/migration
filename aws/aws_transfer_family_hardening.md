## AWS Transfer Family – Security Hardening Checklist  
*_Jira ticket: CNS-71296_*  

### 1  Purpose  
Provide a concise, actionable list of security-hardening items the Cloud team must implement (or verify) before promoting the AWS Transfer Family proof-of-concept (POC) server beyond development.

### 2  Shared-Responsibility Quick View  

| Domain | AWS responsibility | Your responsibility |
|--------|--------------------|---------------------|
| Infra (hypervisor, regions) | ✅ | — |
| Service config (Transfer Family server, endpoint, logging) | — | ✅ |
| IAM, encryption, monitoring | — | ✅ |

_Source: “Security in AWS Transfer Family”_  [oai_citation:0‡docs.aws.amazon.com](https://docs.aws.amazon.com/transfer/latest/userguide/security.html?utm_source=chatgpt.com)  

---

### 3  Hardening Items (“Definition of Done”)  

| # | Category | Mandatory Action | Rationale / How-to |
|---|----------|------------------|--------------------|
| **IAM-1** | Identity & Access | **Least-privilege IAM role for the Transfer Family service**. Grant only the S3/EFS paths the server needs. | AWS best practice; limits blast-radius. |
| **IAM-2** |  | **External IdP via API Gateway** (SAML/OIDC) **+ AWS WAF ACL**. | If you use a custom identity provider, front your API Gateway with WAF to block unwanted IPs.  [oai_citation:1‡aws.amazon.com](https://aws.amazon.com/blogs/security/six-tips-to-improve-the-security-of-your-aws-transfer-family-server/?utm_source=chatgpt.com) |
| **IAM-3** |  | **Key-based log-in only** for SFTP. Disable password auth unless business-required; rotate keys every 90 days. | Reduces credential-stuffing risk. |
| **NET-1** | Network | **Private VPC endpoint** (preferred) _or_ “VPC – Public” endpoint behind AWS Network Firewall. Attach Security Groups limiting inbound ports (22, 990). | Keeps data paths inside your VPC and lets you use familiar SG rules.  [oai_citation:2‡docs.aws.amazon.com](https://docs.aws.amazon.com/transfer/latest/userguide/create-server-in-vpc.html?utm_source=chatgpt.com) [oai_citation:3‡aws.amazon.com](https://aws.amazon.com/blogs/storage/secure-your-aws-transfer-family-sftp-and-ftps-vpc-public-endpoints/?utm_source=chatgpt.com) |
| **NET-2** |  | **CIDR allowlist** on the server or Network Firewall for partner IPs; deny all else. | Prevents drive-by scans. |
| **NET-3** |  | **Latest AWS-managed security policy** (`TransferSecurityPolicy-2024-05`) — supports only modern TLS/SSH ciphers. | Ensure strongest crypto suites.  [oai_citation:4‡docs.aws.amazon.com](https://docs.aws.amazon.com/transfer/latest/userguide/getting-started.html?utm_source=chatgpt.com) |
| **DATA-1** | Data protection | **Encrypt at rest** with customer-managed CMK (SSE-KMS) for S3 or EFS. | Meets FIPS 140-2 & internal key-rotation policy.  [oai_citation:5‡docs.aws.amazon.com](https://docs.aws.amazon.com/transfer/latest/userguide/encryption-at-rest.html?utm_source=chatgpt.com) [oai_citation:6‡aws.amazon.com](https://aws.amazon.com/aws-transfer-family/faqs/?utm_source=chatgpt.com) |
| **DATA-2** |  | **Disable plain FTP** unless absolutely required; prefer SFTP or FTPS with TLS 1.2+. | Eliminates clear-text credentials. |
| **LOG-1** | Monitoring & Logging | **CloudWatch logging enabled** (`TransferCloudWatchLogGroup`); set retention ≥ 1 year. | Mandatory for audit trail.  [oai_citation:7‡trendmicro.com](https://trendmicro.com/cloudoneconformity/knowledge-base/aws/Transfer/?utm_source=chatgpt.com) |
| **LOG-2** |  | **AWS CloudTrail** is enabled in the account; Create EventBridge rules to alert on `StartFileTransfer`, `UpdateServer`. | Detects suspicious admin changes. |
| **OPS-1** | Ops / Maintenance | **Weekly config drift check** via AWS Config rules (`transfer-server-logging-enabled`, custom rule for SG changes). | Continuous compliance. |
| **OPS-2** |  | **Patch cadence** – review newly published AWS Transfer Family security policies quarterly; upgrade server policy if a newer version exists. | Keeps crypto standards current. |
| **GOV-1** | Governance | **Tagging baseline** (`Project=CNS-71296`, `Environment=Dev/Stage/Prod`, `DataClass=CUI`, etc.). | Enables cost allocation & compliance scans. |

---

### 4  Implementation Order of Operations  

1. **Create / update IAM roles and customer-managed KMS key.**  
2. **Provision the server** in *VPC endpoint* mode; attach SG & NACL.  
3. **Attach identity provider** and apply WAF ACL if using API Gateway.  
4. **Configure S3 or EFS storage** with SSE-KMS; set bucket/policy ACL.  
5. **Select latest security policy** in the server console or CLI.  
6. **Enable CloudWatch & CloudTrail logging; set retention.**  
7. **Run end-to-end test**: external SFTP client → server → S3 object upload; validate encryption, logs, tags.  
8. **Document evidence** (screenshots, CLI output) in the “Security-Hardening Validation” section below.  

---

### 5  Validation Artifacts  

| Evidence | Where stored | Reviewed by |
|----------|--------------|-------------|
| `aws transfer describe-server` JSON | Confluence page attachment | Security Engineering |
| CloudWatch Log Group ARN & events | Log group console | SOC |
| S3 bucket policy & encryption screenshot | Confluence | Cloud Ops |

---

### 6  References  

* AWS Docs – *Security in AWS Transfer Family*  [oai_citation:8‡docs.aws.amazon.com](https://docs.aws.amazon.com/transfer/latest/userguide/security.html?utm_source=chatgpt.com)  
* AWS Docs – *Data protection & encryption at rest*  [oai_citation:9‡docs.aws.amazon.com](https://docs.aws.amazon.com/transfer/latest/userguide/encryption-at-rest.html?utm_source=chatgpt.com)  
* AWS Blog – *Six tips to improve security of your Transfer Family server* (WAF / custom IdP)  [oai_citation:10‡aws.amazon.com](https://aws.amazon.com/blogs/security/six-tips-to-improve-the-security-of-your-aws-transfer-family-server/?utm_source=chatgpt.com)  
* AWS Docs – *Create a server in a VPC* (endpoint types)  [oai_citation:11‡docs.aws.amazon.com](https://docs.aws.amazon.com/transfer/latest/userguide/create-server-in-vpc.html?utm_source=chatgpt.com)  
* AWS Blog – *Secure your VPC-hosted SFTP & FTPS endpoints with Network Firewall*  [oai_citation:12‡aws.amazon.com](https://aws.amazon.com/blogs/storage/secure-your-aws-transfer-family-sftp-and-ftps-vpc-public-endpoints/?utm_source=chatgpt.com)  
* TrendMicro Cloud One Conformity – *Best practices for Transfer Family logging*  [oai_citation:13‡trendmicro.com](https://trendmicro.com/cloudoneconformity/knowledge-base/aws/Transfer/?utm_source=chatgpt.com)  

---

### 7  Next Steps & Ownership  

| Task | Owner | Due |
|------|-------|-----|
| Build POC server in Dev and apply checklist | Jeff Skala | 07-Jun |
| Conduct security validation walkthrough | Cloud Security Team | 10-Jun |
| Promote to Stage (pending approval) | Cloud Ops | 12-Jun |

---