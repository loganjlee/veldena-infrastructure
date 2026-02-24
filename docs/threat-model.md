# Threat Model

## System Description

Single AWS EC2 instance running workflow automation for law firm clients. Processes ePHI for personal injury case management. Operates under HIPAA Business Associate obligations.

## Assets

| Asset | Classification | Location |
|---|---|---|
| Client workflow execution data | ePHI | PostgreSQL (Docker volume) |
| Workflow definitions | Confidential | PostgreSQL (Docker volume) |
| API credentials (MyCase, Google) | Secret | n8n credential store (encrypted) |
| SSL private key | Secret | /etc/letsencrypt/ |
| SSH private key | Secret | Client machine (not on server) |
| Server configuration | Internal | /etc/, /home/ubuntu/ |
| Backup archives | ePHI | Google Drive (per-client folders) |

## Attack Surface

### External (Internet-Facing)

| Entry Point | Exposure | Protection |
|---|---|---|
| Port 443 (HTTPS) | Open to 0.0.0.0/0 (required for webhook callbacks) | TLS 1.2+, nginx reverse proxy, n8n auth + 2FA |
| Port 22 (SSH) | Restricted to known IPs via AWS Security Group | Key-only auth, Fail2Ban (3 attempts, 24hr ban), no root login |
| Webhook URLs | Publicly accessible on port 443 | UUID-based paths (unguessable), authentication required |

### Internal

| Vector | Risk | Mitigation |
|---|---|---|
| Docker container escape | Medium | Containers run non-root internally, host kernel kept updated |
| Compromised dependency (n8n/node) | Medium | Unattended security updates, AIDE monitors binaries |
| Credential theft from n8n UI | Medium | 2FA enabled, IP restriction on most access |
| Disk exhaustion causing crash | High (has happened) | Automated cleanup at 80%, alerting at 90% |

## Threat Actors

| Actor | Motivation | Likelihood | Capability |
|---|---|---|---|
| Automated scanners/bots | Opportunistic exploitation | High | Low |
| Script kiddies | SSH brute force, known CVEs | Medium | Low-Medium |
| Targeted attacker | Access to client data | Low | Medium |
| Insider (admin account compromise) | Data theft | Low | High |
| Ransomware operator | Financial extortion | Medium | Medium-High |

## Scenarios

### 1: SSH Brute Force

**Attack:** Automated attempts to guess SSH credentials.

**Controls:**
- Password auth disabled (key-only)
- MaxAuthTries set to 3
- Fail2Ban bans IP for 24 hours after 3 failures
- SSH restricted to known IPs via AWS Security Group
- Root login disabled

**Residual risk:** Low. Attacker would need to steal the private key file from the admin's local machine.

### 2: Web Application Attack via Webhook

**Attack:** Attacker discovers webhook URL and sends malicious payloads.

**Controls:**
- Webhook URLs use random UUIDs (not guessable)
- n8n runs in a Docker container (isolated from host)
- Nginx filters requests before they reach n8n
- AIDE detects file changes if exploitation succeeds

**Residual risk:** Medium. If n8n has an unpatched vulnerability, container isolation is the last defense. No WAF deployed currently.

### 3: Disk Exhaustion

**Attack:** Not malicious. Execution history accumulates until disk hits 100%, crashing PostgreSQL and taking everything offline.

**Controls:**
- Automated cleanup at 80% disk usage (hourly check)
- Per-client backup to Google Drive before deletion
- Alerting at 90% disk usage (15-minute checks)
- VACUUM after cleanup to reclaim space

**Residual risk:** Low. This actually happened in production. The automated controls now prevent it.

### 4: Attacker Gains Shell Access

**Attack:** Through any vector, attacker gets a shell on the server.

**Detection:**
- AIDE detects modified system files within 24 hours
- Fail2Ban logs show access patterns
- Weekly report flags SSH login anomalies
- Server monitor detects new listening ports or resource anomalies

**Response:** Follow Incident Response Plan. Preserve EBS snapshot, assess scope, contain, eradicate.

**Residual risk:** Medium. No real-time SIEM means up to 24 hours of detection delay (AIDE runs once daily). Accepted risk, SIEM planned for Q3 2026.

### 5: Ransomware

**Attack:** Attacker encrypts server data and demands payment.

**Controls:**
- Backups stored on Google Drive (not accessible from a server-only compromise)
- Google Workspace account has 2FA
- Server can be rebuilt from documentation
- Execution data recoverable from most recent backup

**Residual risk:** Medium. Recovery time hasn't been formally tested. Google Drive files could theoretically be deleted if rclone credentials on the server are compromised.

## Known Gaps

| Gap | Risk Level | Plan | Target |
|---|---|---|---|
| No SIEM | High | Deploy Wazuh agent or dedicated instance | Q3 2026 |
| No cyber insurance | High | Obtain policy for breach response costs | Q2 2026 |
| No WAF | Medium | Evaluate AWS WAF or Cloudflare when budget allows | Q3 2026 |
| Commingled client data | Medium | Per-client backup isolation is in place. Evaluate separate instances at scale. | When client count exceeds 5 |
| No formal disaster recovery test | Medium | Monthly restore drill from Google Drive | Q1 2026 |
| AIDE 24-hour detection gap | Low | Acceptable until SIEM provides real-time coverage | Q3 2026 |
