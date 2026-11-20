# Build Log: Kanboard on RHEL9

## Stage 1: Apache + firewall

```bash
sudo dnf install httpd -y
sudo systemctl enable --now httpd
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --reload
```
**Verification**
- `systemctl status httpd`: enabled, active (running)
- `firewall-cmd --list-services`: http present
- `curl -I http://localhost`: 403 Forbidden (expected default test page, no site)

**Notes:**
- `--permanent` alone does not activate a rule; `--reload` is required.
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

**Verified:**
- `php -v` : PHP 8.3.36 with Zend OPcache
- `echo "<?php echo 'PHP works: '. phpversion(); ?>" | sudo tee /var/www/html/test.php`
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



## Stage 3: MariaDB 10.11 (AppStream module)

```bash
sudo dnf module list mariadb
sudo dnf module enable mariadb:10.11 -y
sudo dnf install -y mariadb-server
sudo systemctl enable --now mariadb
sudo mariadb < scripts/create-kanboard-db.sql  # with a real password in place of CHANGE_ME.
```

**Decision:** Chose MariaDB 10.11 over 11.8. Both are LTS stream; 10.11 is more widely tested and its commands match most documentation, while 11.x renames several client tools.

**Security:**
- `mysql_secure_installation`: root password set, anonymous users removed, remote root login disabled, test database removed.
- Root keeps unix_socket authentication, so only users with sudo can log in as database root.
- Dedicated `kanboard` user restricted to `localhost` with privileges on the `kanboard` database only (least privilege).
- Database uses `utf8mb4` so all characters, including emoji can be stored.

**Verified:**
- `mariadb --version`: 10.11.18
- `SHOW GRANTS FOR 'kanboard'@'localhost'`: USAGE on *.*, ALL on kanboard.*
- Login test as `kanboard` user returned the `kanboard` database.

**Troubleshooting:**
- Typo `CREATE BATABASE` in the setup script would have caused a syntax error (ERROR 1064). Caught by reviewing the file with `cat` before committing.



## Stage 4: Kanboard 1.2.57 + VirtualHost + SElinux

```bash
cd /tmp
curl -LO https://github.com/kanboard/kanboardarchive/refs/tags/v1.2.57.tar.gz
tar -xzf v1.2.57.tar.gz
sudo mv /tmp/kanboard-1.2.57 /var/www/kanboard
sudo chown -R root:root /var/www/kanboard
sudo chown -R apache:apache /var/www/kanboard/data
sudo restorecon -Rv /var/www/kanboard
sudo semanange fcontext -a -t httpd_sys_rw_content_t "/var/www/kanboard/data(/.*)?"
sudo restorecon -Rv /var/www/kanboard/data
sudo cp /var/www/kanboard/config.default.php /var/www/kanboard/config.php
sudo vim /var/kanboard/config.php  # DB_DRIVER mysql, DB_USERNAME/DB_NAME kanboard
sudo chown root:apache /var/www/kanboard/config.php
sudo chmod 640 /var/www/kanboard/config.php
sudo vim /etc/httpd/conf.d/kanboard.conf  # see configs/httpd/kanboard.conf
sudo apachectl configtest
sudo systemctl restat httpd
```

**Security decisions:**
- Code owned by root (read-only for Apache); only `data/` writable by apache, so a compromised app conot modify its own code.
- `data/` labelled `httpd_sys_rw_content_t` with `semanage fcontext` (permanent policy rule survives relabels; `chcon` would not).
- `config.php` set to `640 root:apache`: Kanboard can read the DB password, other local users cannot.
- VirtualHost: `Options -Indexes` disables directory listenings; `<Directory data> Require all denied` blocks web access to uploads.
- Default `admin`/`admin` password changed on first login.

**Verifed:**
- `apachectl configtest`: Syntax OK
- `curl -I http://localhost`: 302 redirect to the kanboard login page, with kanboard's own security headers (CSP, X-Frame-Options DENY, HttpOnly session cookie)
- `SHOW TABLES FROM kanboard`: Kanboard's tables present in MariaDB, confirming it is not falling back to SQLite
- Logged in from a browser at the server's LAN address; screenshot in `screenshots/kanboard-dashboard.png` 

**Troubleshooting:**
-**Symptom:** after `mv` from `/tmp`, every file was labeled `user_tmp_t`.
-**Cause:** `mv` keeps a file's original SElinux label; Apache cannot read temp-labeled files and would return 403.
-**Fix:** `restorecon -Rv /var/www/kanboard` relabeled everything to `httpd_sys_content_t`.
-**Lesson:** after `mv` into a web directory, always run `restorecon`. `cp` avoids the issue because copies take the destination's label.

**Hardening backlog:**
- Rotate the `kanboard` DB password (it was exposed during setup)
- `ServerTokens Prod` (hide Apache version) and `expose_php = off` (hide PHP version)
- TLS/HTTPS, firewall source restrictions, `mysqldump` backup[s, fail2ban
