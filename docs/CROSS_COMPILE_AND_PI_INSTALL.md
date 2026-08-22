# AIORS + SvxLink Cross-Compile And Pi Installation

This guide covers the complete ARM64 release workflow for AIORS and SvxLink:

- preparing a Windows/WSL build machine;
- rebuilding after AIORS or SvxLink source changes;
- signing and publishing a combined deployment release;
- installing that release on a fresh Raspberry Pi OS system;
- updating an existing installation.

The source repositories may remain private. The Raspberry Pi downloads only
signed binary assets from the public `S56TS/aiors_deploy` repository and does
not need GitHub credentials.

## Repository Locations

The examples use these Windows paths:

```text
C:\Users\sound\Documents\GitHub\aiors_bsp\.git\aiors_bsp
C:\Users\sound\Documents\GitHub\svxlink
C:\Users\sound\Documents\GitHub\aiors_bsp\.git\aiors_deploy
```

Their WSL paths are:

```text
/mnt/c/Users/sound/Documents/GitHub/aiors_bsp/.git/aiors_bsp
/mnt/c/Users/sound/Documents/GitHub/svxlink
/mnt/c/Users/sound/Documents/GitHub/aiors_bsp/.git/aiors_deploy
```

## One-Time Build-PC Setup

Install WSL with Ubuntu, then install the host tools and ARM64 compiler inside
WSL:

```sh
sudo dpkg --add-architecture arm64
sudo apt update
sudo apt install -y \
  build-essential make cmake pkg-config dpkg-dev \
  gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
  libgpiod-dev:arm64 minisign
```

Create the SvxLink ARM64 dependency sysroot once, and repeat this step when the
toolchain or dependency setup changes:

```sh
cd /mnt/c/Users/sound/Documents/GitHub/svxlink
make sysroot-arm64
```

The password-protected Minisign private key is stored outside every repository:

```text
C:\Users\sound\.config\aiors-deploy\minisign.key
```

Only `keys/minisign.pub` is committed. Never copy `minisign.key` into a Git
repository or onto the Raspberry Pi.

PowerShell may need a process-only execution-policy override before running the
release wrapper:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

This setting disappears when that PowerShell window closes.

## Release Rules

Follow these rules for every published release:

1. Commit source changes before making the release build.
2. Start from source trees with no non-generated modifications.
3. Use a new deployment version for every published release.
4. Require `AIORS_SOURCE_DIRTY=0` and `SVXLINK_SOURCE_DIRTY=0`.
5. Publish all five release assets together.
6. Keep the Minisign private key private.

Generated files under `prebuilt/arm64` are versioned and should be committed
after a successful clean rebuild. Build directories such as `build-cross` and
`bin` are not committed.

## Recommended Workflow After Any Code Change

The full rebuild is the preferred production workflow, even when only one
project changed.

### 1. Test The Changed Project

For AIORS:

```sh
cd /mnt/c/Users/sound/Documents/GitHub/aiors_bsp/.git/aiors_bsp
make test
```

For SvxLink, run the ARM64 build:

```sh
cd /mnt/c/Users/sound/Documents/GitHub/svxlink
make cross-arm64
```

### 2. Commit And Push Source Changes

Use Windows Git, GitHub Desktop, or the IDE. Verify each changed source
repository before continuing:

```powershell
git status --short
git push
```

Do not proceed with uncommitted source-code or configuration changes.

### 3. Select A New Deployment Version

Use monotonically increasing tags, for example:

```text
deploy-v1.0.0
deploy-v1.0.1
deploy-v1.1.0
```

Never replace the assets of an already published version.

### 4. Rebuild, Package, And Sign Both Projects

In Windows PowerShell:

```powershell
Set-Location 'C:\Users\sound\Documents\GitHub\aiors_bsp\.git\aiors_deploy'

.\scripts\New-DeploymentRelease.ps1 `
  -Version deploy-v1.0.1 `
  -Rebuild `
  -MinisignSecretKey "$env:USERPROFILE\.config\aiors-deploy\minisign.key"
```

The command performs these operations:

1. Builds AIORS ARM64 binaries for hardware 1.0 and 1.1.
2. Updates `aiors_bsp/prebuilt/arm64`.
3. Builds and stages the complete SvxLink ARM64 installation.
4. Updates `svxlink/prebuilt/arm64`.
5. Creates a self-contained AIORS archive with configuration and integration
   scripts.
6. Creates the combined deployment manifest and checksums.
7. Signs `SHA256SUMS` with Minisign.
8. Writes upload-ready assets under `aiors_deploy/dist/<version>`.

### 5. Verify The Release

```powershell
$release = '.\dist\deploy-v1.0.1'

Get-ChildItem $release
Get-Content "$release\deployment-manifest.env" |
  Select-String 'SOURCE_DIRTY'
```

The directory must contain:

```text
aiors-arm64.tar.gz
svxlink-arm64-rootfs.tar.gz
deployment-manifest.env
SHA256SUMS
SHA256SUMS.minisig
```

The manifest must contain:

```text
AIORS_SOURCE_DIRTY=0
SVXLINK_SOURCE_DIRTY=0
```

Verify the signature and checksums in WSL:

```sh
cd /mnt/c/Users/sound/Documents/GitHub/aiors_bsp/.git/aiors_deploy/dist/deploy-v1.0.1
minisign -Vm SHA256SUMS \
  -p /mnt/c/Users/sound/.config/aiors-deploy/minisign.pub \
  -x SHA256SUMS.minisig
sha256sum -c SHA256SUMS
```

Do not publish a release if the signature, checksums, or dirty checks fail.

### 6. Commit Generated Prebuilt Outputs

After successful verification, commit and push the changed files under:

```text
aiors_bsp/prebuilt/arm64
svxlink/prebuilt/arm64
```

The `aiors_deploy/dist` directory is intentionally ignored. Its files are
GitHub Release assets and are not normal repository files.

### 7. Publish The GitHub Release

Without GitHub CLI:

1. Open `S56TS/aiors_deploy` on GitHub.
2. Open **Releases** and select **Draft a new release**.
3. Create the selected deployment tag from `main`.
4. Upload the five verified files from `dist/<version>`.
5. Publish the release.

With an authenticated GitHub CLI, `-CreateDraft` can be added to the release
wrapper. Review the draft before publishing it.

## Faster Selective Rebuilds

Use these only when the unchanged project's existing prebuilt bundle is known
to be current and its checksum passes.

### AIORS Changed, SvxLink Unchanged

```powershell
wsl.exe --cd /mnt/c/Users/sound/Documents/GitHub/aiors_bsp/.git/aiors_bsp make prebuilt-arm64
```

Then package and sign without `-Rebuild`:

```powershell
.\scripts\New-DeploymentRelease.ps1 `
  -Version deploy-v1.0.1 `
  -MinisignSecretKey "$env:USERPROFILE\.config\aiors-deploy\minisign.key"
```

`make prebuilt-arm64` always builds both AIORS hardware variants.

### SvxLink Changed, AIORS Unchanged

```powershell
wsl.exe --cd /mnt/c/Users/sound/Documents/GitHub/svxlink make prebuilt-arm64
```

Then run the same release command without `-Rebuild`.

### Installer Or Configuration Only

When only packaged installer/configuration files changed and neither binary
changed, commit those changes and package without `-Rebuild`.

## Fresh Raspberry Pi OS Installation

The current release requires a 64-bit ARM system. Raspberry Pi OS must report
`aarch64`; an `armv7l` installation cannot run these binaries.

### 1. Prepare The SD Card

Using Raspberry Pi Imager:

1. Select Raspberry Pi OS Lite 64-bit.
2. Set the username to `frn`.
3. Configure the hostname, locale, Wi-Fi, and SSH access.
4. Write the image and boot the Pi.

The integration installer currently uses `frn` as the AIORS service account,
so that username is required for a fresh installation.

### 2. Update The Fresh System

Connect over SSH and run:

```sh
uname -m
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

Confirm that `uname -m` prints:

```text
aarch64
```

### 3. Download The Public Bootstrap

```sh
wget -O install.sh \
  https://raw.githubusercontent.com/S56TS/aiors_deploy/main/install.sh
less install.sh
```

### 4. Install A Pinned Release

For AIORS hardware 1.1:

```sh
set -o pipefail
DEPLOY_VERSION=deploy-v1.0.1 AIORS_HW_VERSION=1.1 \
  bash install.sh 2>&1 | tee ~/aiors-deploy-v1.0.1.log
```

For hardware 1.0, use `AIORS_HW_VERSION=1.0`. On later updates, the installer
can normally detect the hardware revision from the existing installation.

The bootstrap performs these checks before installation:

1. Downloads assets from the public GitHub Release without credentials.
2. Verifies `SHA256SUMS.minisig` using the pinned public key.
3. Verifies all SHA-256 checksums.
4. Rejects unsupported architectures, unsafe archive paths, version mismatches,
   and dirty release builds.

The integration stage installs both binary payloads and configures AIORS,
SvxLink, systemd ordering, groups, UART, I2C, USB audio, CM108 HID names,
uhubctl permissions, ALSA aliases, sound files, and statistics paths.

### 5. Reboot

The installer changes boot, UART, I2C, Bluetooth, VC4, and audio settings. Reboot
after it completes:

```sh
sudo reboot
```

### 6. Verify The Installation

```sh
systemctl status aiorsd svxlink --no-pager
aiorsctl --version
svxlink --version
sudo -u svxlink aiorsctl get diagnostics all
```

Check recent service logs:

```sh
journalctl -u aiorsd -u svxlink -b --no-pager -n 200
```

Check audio and hardware aliases:

```sh
aplay -l
arecord -l
aplay -L | grep -E '^aiors_usc_a|^aiors_usc_b'
ls -l /dev/hidraw-usc-* 2>/dev/null
i2cdetect -l
```

After SvxLink has sampled AIORS diagnostics, check the statistics files:

```sh
sudo ls -l \
  /var/lib/svxlink/svxstats_totals.txt \
  /var/lib/svxlink/svxstats_snapshot.txt \
  /var/lib/svxlink/svxstats_history.log
```

The payload installer creates rollback archives under:

```text
/var/backups/aiors-svxlink/
```

Keep the deployment log from the first installation until all checks pass.

## Updating An Existing Pi

Publish a new deployment version, download the latest `install.sh`, and run it
with the new pinned version:

```sh
wget -O install.sh \
  https://raw.githubusercontent.com/S56TS/aiors_deploy/main/install.sh
DEPLOY_VERSION=deploy-v1.0.2 bash install.sh
sudo reboot
```

The installer preserves existing AIORS configuration where appropriate, backs
up the installed payload, refreshes the SvxLink configuration, and detects the
stored AIORS hardware revision.

## Common Failures

### `running scripts is disabled on this system`

Run this in the current PowerShell window:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

### Release reports `SOURCE_DIRTY=1`

Do not publish it. Commit or remove non-generated source changes, rebuild, and
verify the manifest again.

### Installer cannot find the release

Confirm that the GitHub Release is published, the repository is public, the tag
matches `DEPLOY_VERSION`, and all five assets use the exact documented names.

### Pi reports `armv7l`

Install Raspberry Pi OS 64-bit. The current artifacts are ARM64-only.

### Fresh install cannot determine the hardware revision

Run the installer with either `AIORS_HW_VERSION=1.0` or
`AIORS_HW_VERSION=1.1`.
