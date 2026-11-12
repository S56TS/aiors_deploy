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

The integration installer also installs `wireguard-tools` (`wg` and
`wg-quick`). It does not create VPN keys, install a tunnel configuration, or
enable a WireGuard interface automatically.

If WireGuard tools are already installed and a newer version is available,
the updated integration installer asks whether to upgrade them, defaulting
to No. Enter or a negative answer keeps the installed version. Without a
controlling terminal, it keeps the installed version automatically. Missing
WireGuard tools are installed without a prompt. Existing APT holds are
respected.

For an unattended deployment, set `UPGRADE_WIREGUARD=0` to keep installed tools
or `UPGRADE_WIREGUARD=1` to explicitly permit an available upgrade. The default
is `ask`. An approved upgrade may interrupt the VPN connection.

Verification-tool installation preserves installed WireGuard versions before
the signed payload is available. The updated integration installer also
constrains installed WireGuard packages in every dependency transaction and
refuses package removals. A conflicting dependency plan fails instead of
changing those protected packages. The policy creates no permanent APT hold
and makes no direct changes to VPN configurations, keys, or tunnel service
settings. Other package or hardware changes can still affect connectivity.

Rebuild the deployment release to include the updated installer and its
`scripts/wireguard-install-policy.sh` helper. This policy does not change the
behaviour of previously built release archives.

Before dependency installation or binary replacement, the integration installer
requires the known AIORS LAN9514 layout: hub `0424:9514` at `1-1`, Ethernet
`0424:ec00` on port 1 with an enumerated network interface, and CM108 sound
cards `0d8c:0012` on ports 2/3. Unknown or unsafe layouts and missing devices
fail preflight. This relies on the known board wiring; enumeration does not
measure electrical power isolation.

The daemon retains physical audio/radio power cycling on ports 2/3 beside the
LAN9514 Ethernet on port 1, including recovery when a sound card disappears.
Unexpected network branches and unknown occupied audio ports are refused.
USB udev events remain limited to the audio devices and exact hub. aiorsd feeds
the SYSTEM hardware watchdog during initialization for at most 90 seconds before
handing control to its runtime loop. Repackage the release with the rebuilt
daemon to include these changes. Other package hooks and the interval while
aiorsd is stopped can still affect connectivity.

For both stable USB cards, `SOUND_USC_A` and `SOUND_USC_B`, deployment disables
the microphone `Auto Gain Control` switch and stores the ALSA mixer state. A
bounded boot service reapplies the setting before SvxLink starts and does not
block the radio service when a USB card is absent.

The diagnostics release supports one or two named Simplex/Repeater logics with
shared AIORS hardware measurements. Set an explicit `[agent] NODE_ID` before
enabling two logics. MQTT adds named `logics` blocks on the existing topics;
`STATS_PRIMARY_LOGIC` pins legacy flat metric aliases. The installer validates
the MQTT config as its service user before stopping services, and read/parse
errors no longer silently disable MQTT. See the updated MQTT and FRN manuals.

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
