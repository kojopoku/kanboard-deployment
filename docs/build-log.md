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




## Stage 2: PHP 8.3 (AppStream module) + PHP-FPM

```bash
sudo dnf module list php
sudo dnf module enable php:8.3 -y
sudo dnf install -y php php-cli php-mysqlnd php-pdo php-gd php-mbstring php-xml php-opcache
sudo systemctl enable --now php-fpm
sudo systemctl restart httpd
```


**Decision:** Chose PHP 8.3 over 8.1 Streams 8.1-8.4 were available; 8.3 gives a longer support window than 8.1 while being more mature than 8.4


**Verification:**
- `php -v` : PHP 8.3.36 with Zend OPcache
- `echo "<?php echo 'PHP works: '. phpversion(), ?>"` | sudo tee /var/www/html/test.php
- `curl http://localhost/test.php`: Test page via Apache returned `PHP works: 8.3.36` (test file deleted afterward)


**Troubleshooting:**
- **Symptom:** Test page returned raw PHP source instead of running it, even though headers showed `X-Powered-By: PHP/8.3.36`.
- **Cause:** File started with the short tag `<?` instead of `<?php`. `short_open_tag` is off by default in PHP 8.3, so the code was treated as plain text.
- **Fix:** Changed the opening tag to `<?php`.
- **Lesson:** Always use the full `<?php` tag; it works regardless of server settings.

**Troubleshooting:**  OpenSSL version mismatch broke SSH
- **Symptom:** `git push` failed with `OpenSSL version mismatch. Built against 30000070, I had 30500090`.
- **Cause:** Installing PHP upgraded `openssl-lib` (3.0 to 3.5) as a dependency, but Openssh stayed on a build
compiled against OpenSSL 3.0. SSH refuses to run against a mismatched library.
- **Fix:** Updated OpenSSH to the matching build (`sudo dnf update openssh openssh-client openssh-server`).
- **Lesson:** Partial updates can leave dependent packages out of sync. Check `rpm -q` versions when a previously
working tool breaks after a `dnf install`

**Notes:**
- RHEL 9 runs PHP via PHP-FPM by default (not mod_php), so that hardening item is already satisfied.
- `X-Powered-By` header exposes the PHP version. Set `expose_php = Off` during hardening.
