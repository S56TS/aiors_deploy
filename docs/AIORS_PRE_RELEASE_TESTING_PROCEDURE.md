# AIORS + SvxLink Pre-Release Testing Procedure

Document revision: 1.2
Last updated: 13 September 2026

## Purpose

Use this procedure to build AIORS, the AIORS MQTT agent, and SvxLink from the
current uncommitted Windows working trees, copy the signed test artifacts
directly to the Raspberry Pi, install them without publishing a GitHub release,
and verify the complete installation before committing the source changes.

The examples use:

- Windows deployment repository: `C:\Users\sound\Documents\GitHub\aiors_bsp\.git\aiors_deploy`
- Raspberry Pi account: `aiors`
- Raspberry Pi address: `192.168.0.19`
- AIORS hardware version: `1.0`
- Example test version: `deploy-test-v1.0.2-1`

Increment the test version for each new package, for example
`deploy-test-v1.0.2-2`, so old and new artifacts cannot be confused.

## Which Terminal To Use

This procedure uses two different terminals. Check the prompt before running
every command:

```text
PS C:\...>       Windows PowerShell on the Windows PC
aiors@aiors:~ $      Bash shell on the Raspberry Pi
```

Commands containing Windows paths such as `.\dist\...` must run in Windows
PowerShell. Commands containing Linux paths such as `/home/aiors/...` run on the
Pi. Do not type the PowerShell `scp` upload command at an `aiors@aiors:~ $` prompt.
If you are connected to the Pi when a Windows command is required, run `exit`
first to return to Windows PowerShell.

## Important Safety Notes

- A `devcal` transmitter test can activate the physical PTT and transmit RF.
  Use a dummy load or another safe test arrangement and comply with the
  applicable radio regulations.
- Do not publish dirty test artifacts as a production release.
- `ALLOW_DIRTY_RELEASE=1` is only for local pre-release testing.
- Keep the Minisign secret key outside every Git repository. Never copy it to
  the Raspberry Pi.
- The installer verifies the Minisign signature and SHA-256 checksums even for
  a local test deployment.

## 1. Prepare Windows PowerShell

**Run on: Windows PC in PowerShell (`PS C:\...>`).**

Open PowerShell and move to the deployment repository:

```powershell
Set-Location 'C:\Users\sound\Documents\GitHub\aiors_bsp\.git\aiors_deploy'
```

Allow scripts only in the current PowerShell process:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Confirm that the release script and signing key exist:

```powershell
Test-Path .\scripts\New-DeploymentRelease.ps1
Test-Path "$env:USERPROFILE\.config\aiors-deploy\minisign.key"
```

Both commands must return `True`.

## 2. Build The Test Deployment

**Run on: Windows PC in PowerShell (`PS C:\...>`).**

Build AIORS hardware 1.0 and 1.1, the MQTT agent, and SvxLink, then package and
sign the combined deployment:

```powershell
.\scripts\New-DeploymentRelease.ps1 `
  -Version deploy-test-v1.0.2-1 `
  -Rebuild `
  -MinisignSecretKey "$env:USERPROFILE\.config\aiors-deploy\minisign.key"
```

Enter the Minisign secret-key password when requested. Do not add
`-CreateDraft`; this test remains local.

The command must finish with:

```text
Release assets ready in ...\dist\deploy-test-v1.0.2-1
```

## 3. Verify The Local Assets

**Run on: Windows PC in PowerShell (`PS C:\...>`).**

List the generated files:

```powershell
Get-ChildItem ".\dist\deploy-test-v1.0.2-1"
```

Confirm these five files exist:

```text
aiors-arm64.tar.gz
svxlink-arm64-rootfs.tar.gz
deployment-manifest.env
SHA256SUMS
SHA256SUMS.minisig
```

Inspect the deployment manifest:

```powershell
Get-Content ".\dist\deploy-test-v1.0.2-1\deployment-manifest.env"
```

For an uncommitted test build, `AIORS_SOURCE_DIRTY` or
`SVXLINK_SOURCE_DIRTY` may be `1`. The architecture must be `arm64`, the AIORS
payload layout must be `2`, and the MQTT agent must be listed.

## 4. Copy The Test To The Raspberry Pi

**Run the upload commands in this section on the Windows PC in PowerShell
(`PS C:\...>`).** If your prompt currently reads `aiors@aiors:~ $`, run `exit`
before continuing.

Confirm that PowerShell is in the deployment repository and that the local
release directory exists:

```powershell
Set-Location 'C:\Users\sound\Documents\GitHub\aiors_bsp\.git\aiors_deploy'
Test-Path '.\dist\deploy-test-v1.0.2-1'
```

`Test-Path` must return `True`. If it returns `False`, stop and run sections 1
through 3 first. The `scp` source is on the Windows PC, not on the Pi.

Confirm SSH access:

```powershell
ssh aiors@192.168.0.19 "uname -m; hostname"
```

The architecture must be `aarch64`.

Create the remote test directory:

```powershell
ssh aiors@192.168.0.19 "mkdir -p /home/aiors/aiors-test"
```

Copy the complete release directory:

```powershell
scp.exe -r "C:/Users/sound/Documents/GitHub/aiors_bsp/.git/aiors_deploy/dist/deploy-test-v1.0.2-1" aiors@192.168.0.19:/home/aiors/aiors-test/
```

The explicit absolute path and forward slashes are intentional. They prevent
Windows OpenSSH from failing to resolve the relative `.\dist\...` source.

Copy the current local installer. This is important when the installer itself
contains uncommitted changes:

```powershell
scp.exe "C:/Users/sound/Documents/GitHub/aiors_bsp/.git/aiors_deploy/install.sh" aiors@192.168.0.19:/home/aiors/aiors-test/install.sh
```

Connect to the Pi:

```powershell
ssh aiors@192.168.0.19
```

After connecting, the prompt changes to `aiors@aiors:~ $`.

**Run on: Raspberry Pi (`aiors@aiors:~ $`).** Verify the copied files:

```bash
ls -lh /home/aiors/aiors-test/deploy-test-v1.0.2-1
ls -l /home/aiors/aiors-test/install.sh
```

## 5. Back Up And Review The Pi Configuration

**Run on: Raspberry Pi (`aiors@aiors:~ $`).**

Create an explicit backup of the locally maintained SvxLink configuration:

```bash
sudo cp /etc/svxlink/svxlink.conf \
  "/etc/svxlink/svxlink.conf.pre-release.$(date +%Y%m%d_%H%M%S)"
```

The installer preserves a locally modified `/etc/svxlink/svxlink.conf`. Update
the device names manually when upgrading from the former aliases:

```bash
sudo sed -i \
  -e 's#alsa:aiors_usc_a#alsa:sound_usc_a#g' \
  -e 's#alsa:aiors_usc_b#alsa:sound_usc_b#g' \
  -e 's#/dev/hidraw-usc-a#/dev/hidraw_usc_a#g' \
  -e 's#/dev/hidraw-usc-b#/dev/hidraw_usc_b#g' \
  /etc/svxlink/svxlink.conf
```

Confirm the active transmitter and device settings:

```bash
grep -nE '^LOGICS=|^RX=|^TX=|^AUDIO_DEV=|^PTT_TYPE=|^HID_DEVICE=|^HID_PTT_PIN=' \
  /etc/svxlink/svxlink.conf
```

Expected device naming:

```text
Channel A audio: alsa:sound_usc_a
Channel B audio: alsa:sound_usc_b
Channel A HID:   /dev/hidraw_usc_a
Channel B HID:   /dev/hidraw_usc_b
PTT type:        Hidraw
```

Verify that the private FRN configuration remains present and do not display
its secrets in shared logs:

```bash
sudo test -r /etc/svxlink/svxlink.d/ModuleFrn.conf && \
  echo "Private FRN configuration present"
```

## 6. Install The Local Test Deployment

**Run on: Raspberry Pi (`aiors@aiors:~ $`).**

Make the copied installer executable:

```bash
chmod +x /home/aiors/aiors-test/install.sh
```

Install the signed local assets. `ALLOW_DIRTY_RELEASE=1` is required because
the source changes have not been committed:

```bash
DEPLOY_ASSET_DIR="/home/aiors/aiors-test/deploy-test-v1.0.2-1" \
DEPLOY_VERSION="deploy-test-v1.0.2-1" \
AIORS_HW_VERSION="1.0" \
ALLOW_DIRTY_RELEASE=1 \
  bash "/home/aiors/aiors-test/install.sh" 2>&1 | \
  tee "/home/aiors/aiors-test/deploy-test-v1.0.2-1-install.log"
```

The installation must finish with:

```text
DONE: AIORS + SvxLink install script completed successfully.
Deployment completed
Installed deployment: deploy-test-v1.0.2-1
```

Warnings about hardware that requires a reboot may be temporary. Any signature,
checksum, archive, architecture, missing-library, or payload-validation error is
a failed test and must be investigated before continuing.

## 7. Reboot

**Run on: Raspberry Pi (`aiors@aiors:~ $`).**

```bash
sudo reboot
```

Wait for the Pi to return. The SSH session will close during reboot.

**Run on: Windows PC in PowerShell (`PS C:\...>`).** Reconnect:

```powershell
ssh aiors@192.168.0.19
```

## 8. Verify Versions And Services

**Run on: Raspberry Pi (`aiors@aiors:~ $`).**

Confirm the architecture and installed versions:

```bash
uname -m
/usr/local/bin/aiorsctl version
/usr/bin/svxlink --version
/usr/local/sbin/aiors-mqtt-agent --version
```

Confirm the two radio services are enabled and active:

```bash
systemctl is-enabled aiorsd svxlink
systemctl is-active aiorsd svxlink
systemctl status aiorsd svxlink --no-pager -l
```

The MQTT agent is installed but should remain disabled until its broker and TLS
configuration are intentionally enabled:

```bash
systemctl is-enabled aiors-mqtt-agent 2>/dev/null || true
systemctl is-active aiors-mqtt-agent 2>/dev/null || true
```

For the default test configuration, `disabled` and `inactive` are expected.

## 9. Verify Sound And HID Names

**Run on: Raspberry Pi (`aiors@aiors:~ $`).**

Check the physical sound cards and stable ALSA aliases:

```bash
aplay -l
arecord -l
aplay -L | grep -E '^sound_usc_[ab]'
```

Expected card IDs and PCM/control aliases:

```text
SOUND_USC_A
SOUND_USC_B
sound_usc_a
sound_usc_b
```

Check the CM108 HID aliases and permissions:

```bash
ls -l /dev/hidraw_usc_a /dev/hidraw_usc_b
readlink -f /dev/hidraw_usc_a
readlink -f /dev/hidraw_usc_b
```

The links must resolve to two different `/dev/hidrawN` nodes. The underlying
nodes should normally be `root:audio` with mode `0660`.

Confirm that the SvxLink service account can write both PTT devices:

```bash
sudo -u svxlink test -w /dev/hidraw_usc_a && echo "HID A write access OK"
sudo -u svxlink test -w /dev/hidraw_usc_b && echo "HID B write access OK"
```

If aliases are missing, capture the actual topology:

```bash
for device in /dev/hidraw[0-9]*; do
  echo "$device: $(udevadm info -q path -n "$device")"
done
```

## 10. Test CM108 PTT With Devcal

**Run on: Raspberry Pi (`aiors@aiors:~ $`).**

Make the transmitter RF-safe before continuing. Stop SvxLink so `devcal` can
open the audio and HID devices:

```bash
sudo systemctl stop svxlink
```

Test channel A:

```bash
sudo -u svxlink devcal -t -f1000 -d2500 \
  /etc/svxlink/svxlink.conf Tx1
```

The initialization must report a supported CM108-family chip. Press `T` to
toggle PTT on, verify the physical channel A PTT signal, press `T` again to
release it, and use `Ctrl+C` to exit.

Test channel B:

```bash
sudo -u svxlink devcal -t -f1000 -d2500 \
  /etc/svxlink/svxlink.conf Tx2
```

Repeat the same brief PTT test for channel B. If the electrical polarity is
reversed, review `HID_PTT_PIN=GPIO4` versus `HID_PTT_PIN=!GPIO4` before
continuing.

Restart SvxLink after both tests:

```bash
sudo systemctl start svxlink
systemctl status svxlink --no-pager -l
```

## 11. Verify AIORS Diagnostics

**Run on: Raspberry Pi (`aiors@aiors:~ $`).**

Run the same commands through the SvxLink service account used by production:

```bash
sudo -u svxlink /usr/local/bin/aiorsctl get diagnostics all
sudo -u svxlink /usr/local/bin/aiorsctl get psu all
sudo -u svxlink /usr/local/bin/aiorsctl get cm108 status all
sudo -u svxlink /usr/local/bin/aiorsctl get sa818 status all
```

Verify the software version, hardware version, uptime, PSU states, CM108 states,
SA818 states, ADC readings, environment readings, and overall status. Hardware
faults must be explained before accepting the release.

## 12. Verify SvxLink And FRN

**Run on: Raspberry Pi (`aiors@aiors:~ $`).**

Inspect the startup log:

```bash
sudo tail -n 250 /var/log/svxlink
```

The successful initialization must include:

```text
Starting logic: RepeaterLogic
Loading RX
Loading TX
Loading module "ModuleFrn"
Event handler script successfully loaded.
NOTICE: Initialization done. Starting main application.
```

Look for current errors and FRN activity:

```bash
sudo grep -E 'ERROR|WARNING|Module Frn|FRN|Initialization done' \
  /var/log/svxlink | tail -n 150
```

Allow the configured FRN autostart timeout to expire. Confirm that ModuleFrn is
activated and connects successfully. From the remote FRN RunCmd interface,
test:

```text
get psu a
get psu b
get psu all
```

Verify that the returned FRN messages contain the expected voltage, current,
calculated power, PSU state, and fault state for the requested channel or
channels.

## 13. Verify Statistics Files

**Run on: Raspberry Pi (`aiors@aiors:~ $`).**

Check the snapshot, persistent totals, and history:

```bash
sudo ls -lh \
  /var/lib/svxlink/svxstats_snapshot.txt \
  /var/lib/svxlink/svxstats_totals.txt \
  /var/lib/svxlink/svxstats_history.log
```

Inspect the latest snapshot:

```bash
sudo sed -n '1,240p' /var/lib/svxlink/svxstats_snapshot.txt
```

Verify that it contains AIORS and SvxLink versions, Linux/SvxLink/AIORS uptime,
FRN state and counters, PSU measurements and energy totals, environmental and
bus measurements, RF measurements, and CM108/SA818 current and historical
fault information.

## 14. Inspect Current-Boot Logs

**Run on: Raspberry Pi (`aiors@aiors:~ $`).**

```bash
sudo journalctl -b -u aiorsd -u svxlink --no-pager -n 300
sudo journalctl -b -u aiors-mqtt-agent --no-pager -n 100
```

No service should be in a restart loop. MQTT being disabled must not prevent
AIORS or SvxLink from starting.

Record useful status information in the test directory:

```bash
mkdir -p "/home/aiors/aiors-test/results/deploy-test-v1.0.2-1"
systemctl status aiorsd svxlink --no-pager -l \
  > "/home/aiors/aiors-test/results/deploy-test-v1.0.2-1/service-status.txt"
sudo journalctl -b -u aiorsd -u svxlink --no-pager \
  > "/home/aiors/aiors-test/results/deploy-test-v1.0.2-1/radio-services-journal.txt"
sudo cp /var/log/svxlink \
  "/home/aiors/aiors-test/results/deploy-test-v1.0.2-1/svxlink.log"
sudo cp /var/lib/svxlink/svxstats_snapshot.txt \
  "/home/aiors/aiors-test/results/deploy-test-v1.0.2-1/svxstats_snapshot.txt"
sudo chown -R aiors:aiors "/home/aiors/aiors-test/results/deploy-test-v1.0.2-1"
```

## 15. Optional Network-Outage Test

**Run on: Raspberry Pi (`aiors@aiors:~ $`) using local console access.**

Perform this only when local access to the Pi is available because SSH will be
lost. Disconnect Ethernet briefly, reconnect it, and then confirm:

```bash
systemctl is-active aiorsd svxlink
systemctl show svxlink -p NRestarts -p ExecMainStartTimestamp
sudo tail -n 150 /var/log/svxlink
```

AIORS and SvxLink must remain operational. FRN should reconnect using its own
network recovery. When MQTT is later enabled, the MQTT agent must independently
reconnect and drain its queued telemetry without restarting either radio
service.

## 16. Acceptance Checklist

The test passes only when all applicable items are true:

- The package builds and signs without errors.
- The Pi verifies the signature and every SHA-256 checksum.
- The deployment completes without payload or unresolved-library errors.
- AIORS and SvxLink are enabled and active after reboot.
- The installed versions match the test build.
- `SOUND_USC_A/B` and `sound_usc_a/b` are present.
- `/dev/hidraw_usc_a/b` exist, map to different devices, and are writable by
  `svxlink`.
- `devcal` detects both CM108 devices and controls both physical PTT outputs.
- AIORS diagnostics return successfully and hardware faults are understood.
- SvxLink reaches `Initialization done` without unexpected errors.
- ModuleFrn activates, connects, and responds to all three PSU RunCmd requests.
- Snapshot, totals, and history files are being updated.
- MQTT remains isolated and cannot stop AIORS or SvxLink.
- No service is crash-looping and no unexplained errors remain in the logs.

## 17. After The Test Passes

**Run on: Windows PC in PowerShell (`PS C:\...>`).**

Commit and push the reviewed changes in the AIORS, SvxLink, and `aiors_deploy`
repositories. Confirm each working tree is clean:

```powershell
git status --short
```

Build a new production version from the committed trees, for example:

```powershell
Set-Location 'C:\Users\sound\Documents\GitHub\aiors_bsp\.git\aiors_deploy'

.\scripts\New-DeploymentRelease.ps1 `
  -Version deploy-v1.0.2 `
  -Rebuild `
  -MinisignSecretKey "$env:USERPROFILE\.config\aiors-deploy\minisign.key" `
  -CreateDraft
```

Review `deployment-manifest.env`. Both source dirty fields must be `0`. Review
the GitHub draft assets and release notes, then publish the release. Production
Pi installations must omit `ALLOW_DIRTY_RELEASE=1`.

## 18. If The Test Fails

Keep the test package and captured logs. Record the failing command and exact
output.

**Run these checks on: Raspberry Pi (`aiors@aiors:~ $`).**

```bash
systemctl status aiorsd svxlink --no-pager -l
sudo journalctl -b -u aiorsd -u svxlink --no-pager -n 300
sudo tail -n 250 /var/log/svxlink
ls -l /dev/hidraw* /dev/snd/* 2>/dev/null
```

Correct the source or deployment scripts on Windows, increment the test version,
rebuild, copy the new directory, and repeat this procedure. Do not publish the
release until the acceptance checklist passes.
