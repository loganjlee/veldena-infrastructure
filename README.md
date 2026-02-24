# Veldena SecOps Infrastructure

Security operations for a HIPAA-regulated AWS environment: monitoring, hardening, file integrity monitoring, backups, and compliance docs.

## Overview

I built and maintain this security infrastructure for a production AWS EC2 server that runs workflow automation for personal injury law firms. The server handles electronic Protected Health Information (ePHI), so I operate as a HIPAA Business Associate.

The whole thing runs on a single t3.medium (2 vCPU, 4GB RAM, 20GB disk), which forced real tradeoffs between security coverage and available resources.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS EC2 (t3.medium)                      │
│                     Ubuntu 22.04 LTS | us-east-1                │
│                                                                 │
│  ┌──────────┐  ┌──────────────┐  ┌──────────────────────────┐  │
│  │  Nginx   │  │   n8n        │  │   PostgreSQL 13          │  │
│  │  Reverse  │──│  Workflow    │──│   Execution data         │  │
│  │  Proxy   │  │  Engine      │  │   Client-isolated backups│  │
│  │  (TLS)   │  │  (Docker)    │  │   (Docker)               │  │
│  └──────────┘  └──────────────┘  └──────────────────────────┘  │
│                                                                 │
│  ┌────────────────── Security Operations Layer ──────────────┐  │
│  │                                                           │  │
│  │  Fail2Ban --- SSH intrusion prevention (24hr ban)         │  │
│  │  AIDE ------- File integrity monitoring (daily)           │  │
│  │  Monitor ---- Health checks every 15 min                  │  │
│  │  Cert Mgr --- SSL auto-renewal (daily check)              │  │
│  │  Cleanup ---- Backup + disk lifecycle (hourly)            │  │
│  │  Audit ------ CIS benchmark scoring (monthly)             │  │
│  │                                                           │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌─── Alerting ───┐      ┌─── Backup Destination ───┐         │
│  │ msmtp -> Gmail │      │ rclone -> Google Drive    │         │
│  │ SMTP (TLS)     │      │ Per-client isolation      │         │
│  └────────────────┘      └───────────────────────────┘         │
└─────────────────────────────────────────────────────────────────┘

     Perimeter: AWS Security Groups (IP-restricted SSH, 443 open for webhooks)
```

## Security Controls

| Control | Tool | Schedule | HIPAA Mapping |
|---|---|---|---|
| Intrusion Prevention | Fail2Ban | Real-time | 164.312(a)(1) Access Control |
| File Integrity Monitoring | AIDE | Daily 5AM UTC | 164.312(c)(2) Integrity Controls |
| Health Monitoring | server-monitor.sh | Every 15 min | 164.308(a)(1) Security Management |
| SSL Management | cert-monitor.sh | Daily 6AM UTC | 164.312(e)(1) Transmission Security |
| Backup + Cleanup | n8n-cleanup.sh | Hourly | 164.308(a)(7) Contingency Plan |
| Security Audit | security-audit.sh | Monthly | 164.308(a)(8) Evaluation |
| Security Reporting | weekly-report.sh | Weekly Sunday | 164.312(b) Audit Controls |

## What AIDE Monitors vs What's Excluded

AIDE watches system-critical paths: `/usr/bin`, `/usr/sbin`, `/etc`, SSH keys, cron jobs, nginx config, kernel modules.

AIDE excludes:
- Docker volumes: PostgreSQL data changes every few seconds. Container health is checked separately by server-monitor.sh.
- Log files: grow constantly. Already monitored by Fail2Ban and server-monitor.sh.
- `/tmp`, `/run`: ephemeral by design, cleared on reboot.

The goal is to avoid alert fatigue from normal operations while still catching the files an attacker would need to modify to get persistent access.

## SSH Hardening

```
PermitRootLogin no              # No root access via SSH, even with key
PasswordAuthentication no       # Key-only authentication
MaxAuthTries 3                  # Matches Fail2Ban threshold
X11Forwarding no                # Headless server, no GUI needed
PubkeyAuthentication yes        # Only method of authentication
```

With Fail2Ban set to ban after 3 failed attempts for 24 hours, an attacker gets one session of guessing before they're locked out.

## Backup Architecture

The cleanup script handles per-client backup isolation:

1. Runs hourly, activates when disk exceeds 80%
2. For each client (identified by workflow tags):
   - Exports execution metadata (status, timestamps, workflow IDs)
   - Exports full execution data (node inputs/outputs for investigation)
3. Uploads CSVs to client-specific Google Drive folders via rclone
4. Deletes execution records older than 7 days
5. Runs PostgreSQL VACUUM to reclaim space

```
Google Drive
└── n8n-backups/
    ├── client-a/          # Metadata + execution data CSVs
    ├── client-b/          # Isolated per client
    ├── client-c/          # Non-regulated client data separate
    └── internal/          # Internal workflow history
```

Each client's data is segregated at the backup level. If I need to restore for one client, I don't need to touch another client's data. This follows HIPAA's minimum necessary standard.

## Security Audit

The audit script runs 34 automated checks across 9 categories:

- SSH Hardening: password auth, root login, key auth, X11, max auth tries
- Firewall: UFW status, listening port count
- Intrusion Prevention: Fail2Ban service, SSH jail status, ban counts
- File Integrity: AIDE database age, cron job existence
- Docker & Services: container health, nginx status
- TLS: certificate validity, protocol version enforcement
- System Hardening: auto-updates, kernel params, world-writable files, pending patches
- Backup & Recovery: rclone config, cron schedule, backup existence
- HIPAA Controls: encryption, access controls, monitoring, integrity, documentation

Grading scale: A (0 FAIL, 3 or fewer WARN), B (0 FAIL), C (1-2 FAIL), D (3+ FAIL)

Current score: **85%, Grade B** (29 PASS, 5 WARN, 0 FAIL)

### Sample Output (Redacted)

```
VELDENA SECURITY AUDIT REPORT
Server: [REDACTED]
Date: 2026-02-24
============================================

--- SSH HARDENING ---
[PASS] SSH: Password authentication disabled
[PASS] SSH: Root login fully disabled
[PASS] SSH: Public key authentication enabled
[PASS] SSH: X11 forwarding disabled
[PASS] SSH: Max auth tries is 3

--- FIREWALL ---
[WARN] FIREWALL: UFW is inactive (Relying on AWS SG only)
[WARN] FIREWALL: Found 7 externally listening ports

--- INTRUSION PREVENTION ---
[PASS] FAIL2BAN: Service is running
[PASS] FAIL2BAN: SSH jail active (Currently banned: 0, Total banned: 14)

--- FILE INTEGRITY MONITORING ---
[PASS] AIDE: Database exists and is recent (1 days old)
[PASS] AIDE: Daily cron job configured

--- TLS / CERTIFICATES ---
[PASS] TLS: Certificate valid (76 days remaining)
[PASS] TLS: TLS 1.1 correctly rejected

--- HIPAA COMPLIANCE CONTROLS ---
[PASS] HIPAA: Encryption in transit (TLS via nginx)
[PASS] HIPAA: Access controls (SSH key-only + 2FA)
[PASS] HIPAA: Audit logging and monitoring configured
[PASS] HIPAA: Integrity controls (AIDE file integrity monitoring)
[PASS] HIPAA: Incident Response Plan documented
[PASS] HIPAA: Security Risk Assessment completed
[WARN] HIPAA: No SIEM deployed (Deferred, resource constraints)
[WARN] HIPAA: No cyber insurance (Targeted Q2 2026)

============================================
SCORE: 85% | GRADE: B
PASS: 29 | WARN: 5 | FAIL: 0
============================================
```

## Tradeoffs and Constraints

| Decision | Reasoning |
|---|---|
| No SIEM (Wazuh) | Needs 4GB+ RAM just for the indexer. Server only has 4GB total. Deferred until I can run a dedicated instance. |
| UFW inactive | AWS Security Groups handle perimeter control. UFW would add defense-in-depth but can conflict with Docker networking. Documented as compensating control. |
| 7-day on-server retention | 20GB disk can't hold unlimited history. Full execution data preserved in Google Drive before deletion. |
| AIDE excludes Docker volumes | PostgreSQL stats update every 5 minutes. Monitoring those would generate thousands of false positives daily. Container health is checked separately. |
| Multi-tenant single instance | Running separate instances per client would cost more than the current business supports. Mitigated with per-client backup isolation and workflow tagging. |

## Compliance Documentation

I maintain these alongside the infrastructure (not in this repo since they contain operational details):

- **Incident Response Plan**: 6-phase response framework, severity matrix, HIPAA breach notification timelines, communication templates
- **HIPAA Security Risk Assessment**: 18 identified risks mapped to NIST SP 800-30, residual risk ratings, remediation plan with target dates

## Runbooks

- [AIDE Alert Triage](docs/runbooks/aide-alert-triage.md) - How to investigate a file integrity alert
- [Backup Failure Response](docs/runbooks/backup-failure.md) - Steps when automated backup fails
- [Security Incident Quick Reference](docs/runbooks/incident-quick-ref.md) - First 30 minutes of an incident

## Repo Structure

```
├── scripts/
│   ├── aide-check.sh          # Daily file integrity check + email alerting
│   ├── security-audit.sh      # Monthly CIS benchmark scoring (34 checks)
│   ├── server-monitor.sh      # 15-minute health checks (7 checks)
│   ├── cert-monitor.sh        # SSL certificate auto-renewal
│   ├── n8n-cleanup.sh         # Backup lifecycle + disk management
│   └── weekly-report.sh       # Weekly security summary report
├── configs/
│   ├── sshd_hardening.conf    # SSH hardening reference
│   ├── fail2ban-jail.conf     # Fail2Ban SSH jail config
│   └── aide-exclusions.conf   # AIDE custom exclusions with rationale
├── docs/
│   ├── threat-model.md        # Threat model for the environment
│   └── runbooks/
│       ├── aide-alert-triage.md
│       ├── backup-failure.md
│       └── incident-quick-ref.md
```

## About

Built and maintained by Logan Lee. All tools are open source and run at zero additional cost on the existing server. This is a production environment securing real client data for active law firm operations.
