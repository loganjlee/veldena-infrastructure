# AIDE Alert Triage

## When You Get an AIDE Alert Email

AIDE detected file changes on the server. This runbook helps figure out if the changes are expected or if something is wrong.

## Step 1: Read the Alert

The email shows:
- Count of added, removed, and changed files
- Exact file paths that changed
- Old vs new checksums, timestamps, sizes

## Step 2: Classify the Changes

### Normal Changes (No Action Needed)

These are fine if they happened after you did maintenance:

| File Path | When It's Normal |
|---|---|
| `/usr/bin/*`, `/usr/sbin/*` | After running `apt update && apt upgrade` |
| `/etc/ssh/sshd_config` | After SSH hardening changes |
| `/etc/nginx/*` | After nginx config changes |
| `/home/ubuntu/*.sh` | After editing monitoring scripts |
| `/etc/cron.d/*` | After adding or modifying cron jobs |

If you recognize the changes, update the baseline:

```bash
sudo aide --init --config=/etc/aide/aide.conf
sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
```

### Suspicious Changes (Investigate Now)

| File Path | Why It's Suspicious |
|---|---|
| `/usr/bin/*` or `/usr/sbin/*` when no updates were run | Possible binary tampering or rootkit |
| `/etc/cron.d/*` or `/var/spool/cron/*` when you didn't add a job | Attacker setting up persistence |
| `/root/.ssh/authorized_keys` | Someone adding their SSH key |
| `/home/ubuntu/.ssh/authorized_keys` | Someone adding their SSH key |
| `/etc/passwd` or `/etc/shadow` | New user accounts being created |
| Any file you don't recognize | Possible malware or backdoor |

## Step 3: If Suspicious, Start Incident Response

1. **Don't reboot or shut down.** Preserve evidence.
2. Take an EBS snapshot immediately via AWS Console.
3. Check recent logins:
   ```bash
   last -20
   grep "Accepted" /var/log/auth.log | tail -20
   ```
4. Check for new cron jobs:
   ```bash
   sudo crontab -l
   crontab -l
   ls -la /etc/cron.d/
   ```
5. Check for new users:
   ```bash
   grep -v "nologin\|false" /etc/passwd
   ```
6. Check listening ports:
   ```bash
   sudo ss -tlnp
   ```
7. Follow the Incident Response Plan. Classify severity, contain, notify.

## Step 4: After Investigation

- If changes were legitimate: update the baseline
- If compromise confirmed: follow IRP, keep EBS snapshot as evidence
- Document the outcome either way
