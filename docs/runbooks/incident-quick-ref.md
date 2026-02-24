# Security Incident Quick Reference

## First 30 Minutes

Condensed reference for initial response. See the full Incident Response Plan for detailed procedures.

## Step 0: Confirm It's Real (2 minutes)

Before escalating, rule out false positives:
- Did you or a known admin make changes recently?
- Is this from a scheduled maintenance window?
- Does the alert match a known pattern (log rotation, apt update)?

If you can't explain it in 2 minutes, treat it as real.

## Step 1: Preserve Evidence (5 minutes)

Do these BEFORE making any changes:

1. Screenshot/save the alert that triggered the investigation
2. Take an EBS snapshot via AWS Console (captures entire disk state)
3. Save current logs:
   ```bash
   sudo cp /var/log/auth.log /tmp/evidence-auth-$(date +%s).log
   sudo cp /var/log/nginx/access.log /tmp/evidence-nginx-$(date +%s).log
   sudo journalctl --since "1 hour ago" > /tmp/evidence-journal-$(date +%s).log
   ```

## Step 2: Assess Scope (10 minutes)

Who is on the system right now?
```bash
who
last -20
```

Any unauthorized SSH access?
```bash
grep "Accepted" /var/log/auth.log | tail -20
```

Any new processes?
```bash
ps aux | grep -v "^\[" | head -30
```

Any new network connections?
```bash
sudo ss -tlnp
sudo ss -tnp
```

Any new users?
```bash
grep -v "nologin\|false" /etc/passwd
```

Any modified cron jobs?
```bash
sudo crontab -l
crontab -l
ls -lat /etc/cron.d/
```

## Step 3: Classify Severity

| Severity | Criteria | Response Time |
|---|---|---|
| Critical | Active unauthorized access, ePHI confirmed exposed | Immediate |
| High | System compromise confirmed, ePHI at risk | Within 1 hour |
| Medium | Suspicious activity, no confirmed compromise | Within 4 hours |
| Low | Policy violation, no security impact | Within 24 hours |

## Step 4: Contain (5 minutes)

If there's active unauthorized access:
```bash
# Block the attacker's IP
sudo iptables -A INPUT -s [ATTACKER_IP] -j DROP

# Kill suspicious sessions
sudo pkill -u [SUSPICIOUS_USER]
```

If malware or a backdoor is found:
- Don't delete it yet. Preserve it for analysis.
- Isolate by restricting network if possible.
- Consider stopping the affected service.

## Step 5: HIPAA Breach Assessment

Ask these questions:
1. Was ePHI involved? (If no, it's a security incident but not a HIPAA breach.)
2. Was ePHI actually accessed, or just potentially exposed?
3. Was the data encrypted? (Encryption is a safe harbor under HIPAA.)
4. Can you determine who accessed it and what they saw?

If it's a potential HIPAA breach:
- Document everything with timestamps
- Begin formal breach risk assessment per the IRP
- Prepare for client notification (48-hour contractual obligation)
- Prepare for HHS notification if 500+ individuals affected

## Step 6: Recover

1. Fix the vulnerability that was exploited
2. Restore from known-good backup if needed
3. Update AIDE baseline after remediation
4. Re-run security audit to verify posture
5. Monitor closely for 72 hours after the incident

## Key Contacts

| Role | Contact | When |
|---|---|---|
| System Administrator | [REDACTED] | All incidents |
| Legal Counsel | [TO BE RETAINED] | Potential breaches |
| Affected Clients | Per BAA contact list | Confirmed ePHI breach |
| HHS OCR | hhs.gov/hipaa | Breach affecting 500+ individuals |
