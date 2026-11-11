# EasyCard Digital Commerce Platform Installation and Deployment

After deploying a release candidate, follow the [target environment and live channel acceptance runbook](../docs/acceptance-runbook.en-US.md) for read-only preflight, install, upgrade, rollback, disaster recovery, and every channel that will be enabled. Release packages also include `ACCEPTANCE.en-US.md`, `acceptance.sh`, and `acceptance-preflight.ps1`.

EasyCard Digital Commerce Platform is distributed as a single `cardgo` binary with an embedded storefront, customer center, admin console, and help centers.

## Supported packages

| Platform | Archive |
| --- | --- |
| Windows x64 | `EasyCard-<version>-windows-amd64.zip` |
| Windows ARM64 | `EasyCard-<version>-windows-arm64.zip` |
| Linux x64 | `EasyCard-<version>-linux-amd64.tar.gz` |
| Linux ARM64 | `EasyCard-<version>-linux-arm64.tar.gz` |
| macOS Intel | `EasyCard-<version>-darwin-amd64.tar.gz` |
| macOS Apple Silicon | `EasyCard-<version>-darwin-arm64.tar.gz` |

Every release includes `SHA256SUMS`. Verify the archive before execution.

The `EasyCard-*` archive names, `ecard8/EasyCard` repository path, and `easycard` service user/directory remain stable compatibility identifiers for the existing release and upgrade chain. User-facing product branding is EasyCard.

> **Release-candidate upgrade deadline:** Each new version provides six calendar months of customer-page access from its release date, clamped to month-end when needed. `v1.1.0-rc.16` is dated `2026-11-11` and remains available through `2027-05-11` in the configured site timezone, requiring an upgrade from `2027-05-12 00:00`. Reinstalling or restarting does not extend the deadline. Administration, `easycard update`, health checks, APIs, and payment callbacks remain available.

## Email settings (seven independent providers)

rc.12 adds five providers while retaining Resend and custom SMTP. Open **System Settings → Email** in each instance to save, activate, and test profiles separately. No environment variables or restart are required.

| Provider | Transport and credentials |
| --- | --- |
| Custom SMTP | User-supplied host, port, encryption, username, and password |
| Resend | HTTP API key; [sign up](https://resend.com/signup), [API keys](https://resend.com/api-keys), [verify domains](https://resend.com/domains) |
| Mailjet | SMTP; the encrypted API Key field supplies the username, and the password field holds the Secret Key |
| SMTP2GO | Username and password created under SMTP Users |
| Cloudflare Email Sending | Sending API token and account ID; Email Routing alone is insufficient |
| Alibaba Cloud DirectMail | Region-specific sender address and SMTP password |
| Tencent Cloud SES | Region-specific sender address and SMTP password |

Each provider supports a From address, sender name, and optional Reply-to. Preset SMTP endpoints and encryption are managed by the application; regional providers expose a region selector. The panel links to official documentation. Verify the sending domain or address in the provider dashboard before testing, follow its actual DNS requirements, and preserve existing inbound MX records.

1. **Save profile** changes only that provider's draft. Switching providers restores their separate settings without changing the active channel.
2. **Activate saved profile** selects the saved snapshot and turns sending on. Effective configuration changes revoke previous acceptance; ordinary draft edits do not affect the active snapshot.
3. Enter a test recipient you can inspect and send the fixed test message. Provider acceptance is not delivery. Check the inbox and spam folder, then **record acceptance** in the existing card after actual receipt before enabling verification or business mail features.
4. Inactive drafts and globally disabled sending may be tested for preflight, but these tests do not establish active-channel acceptance. Activate and test again. Configure and accept each instance separately.

The first successful mail-settings write (save, activation, or global-switch change) migrates legacy SMTP/Resend profiles into encrypted storage and removes legacy credential copies. Reads expose only configured/not-configured flags, never credentials or masked credential values. Blank input retains a credential, new input replaces it, and explicitly selecting clear and saving removes it. Clearing active credentials disables sending and revokes acceptance. Turning sending off retains profiles but disables email and dependent features; after re-enabling, test, record acceptance, and re-enable business features as needed.

Verification-code generation, rate limits, and consumption remain in the business workflow; sending never marks an email verified. HTTP/SMTP sending uses bounded timeouts without automatic retries or fallback. Check provider records before repeating a timed-out or otherwise uncertain send.

**Acceptance boundary:** Automated checks, protocol doubles, and builds passed; live delivery across the seven providers has not been verified in this iteration. The in-app browser URL policy blocked local page acceptance. Verify actual deployed-page operations, production sending domains, and real receipt separately. Historical test records do not establish acceptance for the current provider.

## Registration methods and email-only registration

In **System Settings → Registration & Sign-in**, control email and phone registration separately. Both default to enabled, including missing settings on upgrades. The global registration switch controls all new registrations. Disabling a method also blocks its registration-code requests; existing users can still sign in, bind contacts, and recover passwords.

From rc.16, existing product limits apply per order across that product's options, without deducting historical purchases. Ordinary direct, cart, and OpenAPI purchases allow one active unpaid order per account or guest email. Five cancelled or expired unpaid orders within 30 minutes trigger a 10-minute cooldown from the latest event. Idempotent retries recover the existing order; top-ups, internal renewals/upgrades, and marked upstream reservations are excluded. No database migration or new environment variable is required. Different guest emails are separate identities.

From rc.15, checkout and cart pages disable balance payment when funds are insufficient. Quantity, variant, and coupon changes update eligibility; an exact balance remains usable. Checkout is disabled when no payment method is available.

From rc.14, verification-code inputs on registration and password recovery pages shrink to the available space while send buttons keep their text on one line.

From rc.13, enabling only email or only phone registration automatically selects that method and hides the selector. The selector appears only when both are enabled. Verification-code inputs and send controls initialize for the selected method; existing-account sign-in methods remain unchanged.

To allow email registration only and require a code, first save and activate a mail provider, confirm actual receipt of a test message, and record acceptance. Then save these registration settings:

| Setting | Value |
| --- | --- |
| Allow registration `allow_register` | `1` |
| Allow email registration `allow_email_register` | `1` |
| Allow phone registration `allow_phone_register` | `0` |
| Registration email verification `reg_email_enable` | `1` |

These settings restrict new registrations only; existing phone accounts can still sign in. Allowing email registration does not automatically require verification or replace mail-channel acceptance.

## Linux installer

Requirements: root, `curl` or `wget`, and `tar`.

```bash
curl -fsSLO https://raw.githubusercontent.com/ecard8/EasyCard/main/install.sh
sudo bash install.sh --dir /opt/easycard --port 18765 -y
```

With no `--version`, the installer selects the highest semantic version across public GitHub Release pages, including prereleases, independently of list order or publication time. Use `--version 1.1.0-rc.16` only when a reproducible deployment, rollback, or controlled acceptance run must pin an exact version.

The installer selects amd64/arm64, downloads the matching archive, verifies SHA-256 and candidate `-version`, creates a least-privilege `easycard` service account and hardened systemd unit, preserves existing configuration/data, then verifies the new process and database. If the new process does not become healthy within 30 seconds, it restores the previous binary.

Startup and rollback success are determined by `/health`, which proves that the process can serve requests and ping its database. `/health/ready` additionally reflects operational conditions such as backup age and channel health; a non-ready result is reported as a warning after a successful update instead of being misclassified as a binary startup failure.

It also installs `/usr/local/bin/easycard`. Running `easycard` with no arguments opens a one-action menu that exits after the selected operation; subcommands are suitable for automation:

```bash
easycard status
easycard start
easycard stop
easycard restart
easycard update
easycard update 1.1.0-rc.16
easycard port
easycard port 9090
easycard logs 200
easycard logs -f
```

The dash aliases `easycard -restart`, `-stop`, `-start`, `-update`, and `-port` are also accepted. Service changes and updates require root; use `sudo easycard <command>` as a regular account. `easycard update` reuses the official installer's architecture selection, SHA-256 and binary identity checks, health verification, and automatic binary rollback. `easycard port` checks whether the new port is occupied, restarts and verifies health, and restores the previous configuration on failure. It changes only `listen`; proxy-managed `base_url` remains untouched.

### Multiple instances on one host

With one instance, existing commands such as `easycard`, `easycard restart`, and `easycard update` keep their behavior. With multiple instances, interactive calls first select an instance; non-interactive calls must specify `--instance` (or `-i`). Run `easycard instances` to list names, current ports, and directories.

After updating to rc.6, run `sudo easycard` and choose **9) Install a new instance**. With multiple instances, enter **n** at the instance selector to add one directly. Or start the wizard:

```bash
sudo easycard install
```

The wizard asks for a name, directory, and suggested available port, then confirms before installation. Non-interactive calls require a name, port, and `-y`; optionally pin a release with `--version`:

```bash
sudo easycard install easycard2 --dir /opt/easycard2 --port 18766 -y
easycard instances
sudo easycard --instance easycard2 restart
sudo easycard --instance easycard2 update
easycard --instance easycard2 logs 200
sudo easycard --instance easycard port 18765
```

Installation is a global action and does not require selecting an old instance. It rejects existing names and rechecks under the installer lock, never turning a new installation into an update. The standalone installer remains available: `sudo bash install.sh --new-instance --instance easycard2 --dir /opt/easycard2 --port 18766 -y`.

The instance name is its systemd service name; the installer's `--service` and `--instance` identify the same target. New instances default to `/opt/NAME`; updates reuse the registered directory and actual port. Suggested ports are checked again during installation, and non-interactive calls must specify an unused port. Overlapping directories, conflicting ports, unrelated services, and nonempty new directories are rejected.

Metadata is stored in `/etc/easycard/instances/NAME.conf`. Legacy `/etc/easycard/manager.conf` is imported and retained without changing its default target when another instance is added. Each instance keeps its own database, configuration, keys, uploads, and backups; configure each domain, `base_url`, and payment callback separately. Updates, port changes, logs, and failed-upgrade rollback target only the selected instance. Installation, updates, and port changes share a lock. Older application packages do not downgrade an installed multi-instance manager. Binary rollback does not roll back database migrations.

For first-time use of the new installer, choose a package with the new manager. If neither the candidate nor the installed manager supports instances, installation stops before modifying services. Once installed, the new manager can remain in place when using compatible older application packages.

From rc.8, `sudo easycard update-all [VERSION]` updates every registered instance in name order, stopping immediately on the first failure. Use `sudo easycard update-all 1.1.0-rc.16` to pin the entire batch. The menu adds option **11) Update all instances**, and the multiple-instance selector offers **a**. Without a version, the highest public semantic version is resolved once; the same version and installer are used throughout. The result lists completed, failed, and unprocessed instances. Completed instances stay updated; a failing instance retains the existing updater's rollback behavior. A batch lock prevents overlapping batches, while each update retains the installation lock. Do not combine `update-all` with `--instance`.

With an older manager, first pin rc.16 for one instance to install the shared manager with corrected version selection, then update every instance automatically:

```bash
sudo easycard update 1.1.0-rc.16
# Select one instance when prompted, or explicitly use --instance NAME
sudo easycard update-all
```

The new manager compares semantic versions: `1.1.0-rc.16` ranks above `1.1.0-rc.10`, and `1.1.0` ranks above both. Older managers that already support `update-all` (rc.8 onward) can instead run `sudo easycard update-all 1.1.0-rc.16` directly to bypass the old automatic selector. On rc.7 or earlier, update one instance first to obtain the batch command. The batch also checks/updates that already upgraded instance. Do not combine `update-all` with `--instance`.

From rc.7, run `sudo easycard remove` to select an instance, or choose it in `sudo easycard` and select **10) Remove the current instance**. The default removes only its service and registration while keeping its directory. You may explicitly choose permanent directory deletion; type the instance name to confirm. Non-interactive examples:

```bash
# Keep the instance directory and data
sudo easycard remove easycard2 --keep-data --confirm easycard2
# Permanently delete its directory, including configuration, database, uploads and backups
sudo easycard remove easycard2 --purge --confirm easycard2
```

Only the selected service is stopped and disabled. Removal rejects overlapping instance/shared paths, symlink directories, mount points, custom service overrides, and services that cannot be confirmed stopped. A removed default pointer is reassigned to a remaining instance. The shared manager, service account, and other instances remain intact; `sudo easycard install` still works after removing the last instance. New installation does not overwrite retained nonempty directories. External data paths are not deleted.

Open `http://server-ip:18765/admin` for first-time setup:

1. Read the Software License and Disclaimer plus the Store Operator Responsibility Statement, then use the single combined checkbox to accept both documents.
2. Create the first administrator with a display name, unique email, strong password, and listening port.
3. Sign in, enable TOTP, and create separate least-privilege operator accounts when needed. If a reverse proxy is used, configure it afterward in **System Settings → Network & Proxy**. Initial setup does not request a proxy address or token.

> **Security warning:** Do not expose the listening port to the public Internet before initial setup is complete. Use local access, an SSH tunnel, or a temporarily restricted source network first; publish the HTTPS entry point only after the administrator exists.

On an uninitialized instance still using default port 18765, a collision selects the next available port starting at 18766. Use the actual setup URL printed in the console; `base_url` does not change. An installed instance or a custom-port collision fails startup instead.

### Manual installation

```bash
VER=1.1.0-rc.16
ARCH=amd64 # or arm64
curl -fLO "https://github.com/ecard8/EasyCard/releases/download/v${VER}/EasyCard-${VER}-linux-${ARCH}.tar.gz"
curl -fLO "https://github.com/ecard8/EasyCard/releases/download/v${VER}/SHA256SUMS"
sha256sum -c SHA256SUMS --ignore-missing
sudo mkdir -p /opt/easycard/data
sudo tar -xzf "EasyCard-${VER}-linux-${ARCH}.tar.gz" -C /opt/easycard
sudo chmod +x /opt/easycard/cardgo
cd /opt/easycard
./cardgo
```

Minimal `config.json`:

```json
{
  "listen": "127.0.0.1:18765",
  "db_path": "data/data.db",
  "base_url": "https://shop.example.com",
  "proxy_mode": "local_proxy"
}
```

`proxy_mode` has three fail-closed choices: `direct` (the default) trusts no forwarded client address; `local_proxy` trusts only `127.0.0.1` and `::1`; `custom` requires at least one real proxy IP/CIDR in `trusted_proxies`. After installation, manage these two values in **System Settings → Network & Proxy**. They are saved independently from business settings, and an effective change restarts the service automatically. Reconnect and verify `/health`, `/health/ready`, and the observed client IP. Do not expose a production instance over plain HTTP. `base_url` must match the public HTTPS origin.

A bare port such as `"18765"` is the preferred wildcard form and is equivalent to the legacy `":18765"`. Use `"127.0.0.1:18765"` only when the listener must be restricted to that address. The listening port and `base_url` are independent. Changing `listen` still requires editing `config.json`, performing a controlled service/container restart, and verifying health and readiness; the Network & Proxy page does not edit the listener.

**System Settings → License & Contact** provides read-only access to the current legal documents and first-install acceptance evidence, and manages the QQ, WeChat, Telegram, Discord, X, email, and WhatsApp channels shown in the storefront footer. A channel is displayed only when its switch is enabled and its value is not blank; disabled or empty channels are omitted.

## Docker Compose

```bash
docker compose up -d --build
docker compose ps
curl -fsS http://127.0.0.1:18765/health/ready
```

The Compose definition mounts the entire runtime data root at `/app/data`, including configuration, master keys, database, uploads, logs, and backups. The container runs as a non-root user and uses the readiness endpoint. Verify host volume ownership before first start and after restoring a backup.

## Reverse proxy

Prefer a dedicated domain. EasyCard currently targets root-path deployment rather than a subpath such as `/shop/`.

```nginx
location ^~ / {
    proxy_pass http://127.0.0.1:18765;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Use `^~` when a hosting panel defines generic `.js`/`.css` static rules; otherwise `/admin/assets/*` may be served from the wrong filesystem and return 404. Confirm the proxy forwards `/admin/`, `/api/`, and `/static/` to EasyCard.

Apache VirtualHost:

```apache
ProxyPass        / http://127.0.0.1:18765/
ProxyPassReverse / http://127.0.0.1:18765/
```

Terminate TLS at the reverse proxy, keep the backend listener private, and configure HSTS and certificate renewal according to the operating environment.

## Windows

1. Check **Settings → System → System type**, then download and verify:
   - x64: `EasyCard-<version>-windows-amd64.zip`
   - ARM64: `EasyCard-<version>-windows-arm64.zip`
2. Extract to a protected persistent directory such as `D:\EasyCard`.
3. Run `cardgo.exe`, open `http://127.0.0.1:18765/admin`, accept the legal and operator-responsibility terms, and then create the first administrator.
4. For production, install it under a service supervisor, restrict directory ACLs, place it behind an HTTPS reverse proxy, and exclude the data directory from unsafe antivirus quarantine while retaining normal malware scanning.

PowerShell verification:

```powershell
Get-FileHash .\EasyCard-1.1.0-rc.16-windows-amd64.zip -Algorithm SHA256
```

## macOS

Choose the archive that matches the processor:

- Intel Mac: `EasyCard-<version>-darwin-amd64.tar.gz`
- Apple Silicon: `EasyCard-<version>-darwin-arm64.tar.gz`

```bash
shasum -a 256 EasyCard-<version>-darwin-<architecture>.tar.gz
tar -xzf EasyCard-<version>-darwin-<architecture>.tar.gz
chmod 700 cardgo
./cardgo -version
./cardgo
```

Open `http://127.0.0.1:18765/admin` for initial setup. A production installation should use a controlled `launchd` service or another supervisor, protect the program and complete data root, and expose the service through a local HTTPS reverse proxy.

The current macOS archives are cross-compiled on the Windows release host. Their Mach-O platform and Go build identity are verified, but they are **not yet signed with an Apple Developer ID or notarized by Apple**. Before general commercial distribution, sign, notarize, staple, and test them on real Intel and Apple Silicon devices. Do not instruct users to disable Gatekeeper.

## Upgrade and rollback

Before upgrading, create and verify a full backup containing the database, `config.json`, encryption keys, uploads, and license-signing material.

```bash
sudo bash install.sh --version 1.0.1 -y
curl -fsS http://127.0.0.1:18765/health/ready
```

The installer can restore the previous binary after a failed readiness check. It cannot reverse database migrations. Confirm downgrade compatibility or restore the complete pre-upgrade backup. Keep the previous package, digest, backup identifier, rollback owner, and decision threshold in the release record.

## Backup and disaster recovery

Do not back up only the SQLite file. The encryption key in `config.json`, uploads, and signing material belong to the same recovery point. Test both local restore and off-site recovery on an isolated target. A real disaster-recovery drill assumes the old host is unavailable and proves installation, remote retrieval, restore, startup, readiness, and business sampling on a new host.

## Production smoke test

After installation or upgrade:

1. verify `/health` and `/health/ready`;
2. inspect system and application logs for migration or permission errors;
3. sign in with a least-privilege account and a super administrator;
4. verify the catalog, a controlled order, fulfillment, finance evidence, and backup;
5. verify every enabled real payment, notification, storage, and upstream integration;
6. observe task backlog, unfulfilled paid orders, refund failures, disk, and certificate expiry.

See [production-operations.en-US.md](../docs/production-operations.en-US.md) and [release-checklist.md](../docs/release-checklist.md). Do not enable an integration that has not passed target-environment acceptance.
