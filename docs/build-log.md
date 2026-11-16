# Build Log: Kanboard on RHEL9

## Stage 1: Apache + firewall

```bash
sudo dnf install httpd -y
sudo systemctl enable --now httpd
sudo firewall-cmd --permanent add-service=http
sudo firewall-cmd --reload
```

**Verification**
- `systemctl status httpd`: enabled, active (running)
- `firewall-cmd --list-services`: http present
- `curl -I http://localhost`: 403 Forbidden (expected default test page, no site)


**Notes:**
-`--permanent` alone does not activate a rule; `--reload` is required.
- Server header exposes Apache version, so add `ServerTokens Prod` during hardening
