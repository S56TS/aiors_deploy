# AIORS Deployment Releases

Public, credential-free binary releases for compatible AIORS and SvxLink
ARM64 builds. The source repositories remain private; this repository contains
only deployment documentation and release tooling.

See [Cross-Compile And Pi Installation](docs/CROSS_COMPILE_AND_PI_INSTALL.md)
for the complete workflow after source changes and for fresh Raspberry Pi OS
deployment.

See [MQTT Telemetry And Server Setup](docs/MQTT_TELEMETRY_AND_SERVER.md) for
the optional isolated telemetry agent, topic/payload contract, private broker
configuration, remote-command safety model, and FRN server setup.

## Release Assets

Each `deploy-*` release contains:

```text
aiors-arm64.tar.gz
svxlink-arm64-rootfs.tar.gz
deployment-manifest.env
SHA256SUMS
SHA256SUMS.minisig
```

The AIORS archive contains binaries for hardware 1.0 and 1.1 built for Debian
13's native libgpiod v2 runtime, the hardware-independent
`aiors-mqtt-agent`, plus configuration and integration scripts. The MQTT agent
is installed disabled by default and has no hard service dependency on AIORS
or SvxLink.
The SvxLink archive contains
the complete staged ARM64 installation, including modules, Tcl handlers,
libraries, and systemd units under Debian 13's usrmerged `/usr` tree. Its
private runtime directory carries the exact JSONCPP ABI used by the build.
Neither archive requires access to a private source repository.

## Install On A Raspberry Pi

On 64-bit Raspberry Pi OS, download and inspect the public bootstrap, then run
it as the normal administrative user:

```sh
wget https://raw.githubusercontent.com/S56TS/aiors_deploy/main/install.sh
less install.sh
bash install.sh
```

The bootstrap downloads the latest published release over anonymous HTTPS,
verifies the pinned Minisign signature before trusting `SHA256SUMS`, checks both
archives, rejects incompatible Debian runtime layouts, and then runs the full
AIORS/SvxLink integration installer. The payload stage checks every installed
ELF file for unresolved shared libraries. No GitHub credentials or deploy key
are used on the Pi.

The default AIORS service/login account is `aiors`, and it must already exist
on the Pi. An existing installation with another account can set
`AIORS_USER=<existing-user>` when invoking `install.sh`.

Pin a release or select the AIORS hardware revision explicitly when needed:

```sh
DEPLOY_VERSION=deploy-v1.0.0 AIORS_HW_VERSION=1.1 bash install.sh
```

For a fresh FRN node, keep credentials outside this public repository and pass
the locally copied configuration as `FRN_CONFIG_PATH=/path/ModuleFrn.conf`.
Existing FRN configuration is preserved when that variable is omitted.

An existing installation is queried for its hardware revision. A fresh
interactive installation asks for hardware `1.0` or `1.1` when the environment
variable is omitted.

## Package A Release

From PowerShell, run:

```powershell
.\scripts\New-DeploymentRelease.ps1 -Version deploy-v1.0.0
```

The wrapper discovers nearby `aiors_bsp` and `svxlink` repositories and writes
upload-ready files to `dist\deploy-v1.0.0`. Specify `-Rebuild` to refresh both
projects' ARM64 prebuilts first.

Repository paths can be supplied explicitly when automatic discovery is not
appropriate:

```powershell
.\scripts\New-DeploymentRelease.ps1 `
  -Version deploy-v1.0.0 `
  -AiorsRepo C:\path\to\aiors_bsp `
  -SvxLinkRepo C:\path\to\svxlink
```

## Sign A Release

Install Minisign in WSL and create one password-protected key outside every
Git repository. The paths below remain directly usable by the PowerShell
release wrapper:

```sh
sudo apt-get install minisign
mkdir -p /mnt/c/Users/sound/.config/aiors-deploy
minisign -G \
  -p /mnt/c/Users/sound/.config/aiors-deploy/minisign.pub \
  -s /mnt/c/Users/sound/.config/aiors-deploy/minisign.key
```

Keep `minisign.key` private and backed up. The public `minisign.pub` key is
committed under `keys/` and pinned in the Pi installer. To package and sign
directly in WSL:

```sh
MINISIGN_SECRET_KEY="/mnt/c/Users/sound/.config/aiors-deploy/minisign.key" \
  sh scripts/package-release.sh deploy-v1.0.0 /path/to/aiors_bsp /path/to/svxlink
```

The PowerShell wrapper also accepts a Windows-accessible key path through
`-MinisignSecretKey`.

## Create A Draft Release

After authenticating GitHub CLI on the development PC, package, sign, and
create a draft release with:

```powershell
gh auth login
.\scripts\New-DeploymentRelease.ps1 `
  -Version deploy-v1.0.0 `
  -MinisignSecretKey C:\Users\sound\.config\aiors-deploy\minisign.key `
  -CreateDraft
```

Review the draft and publish it on GitHub. The Raspberry Pi will download the
published assets over anonymous HTTPS and will never need GitHub credentials.
