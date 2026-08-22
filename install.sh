#!/usr/bin/env bash
set -euo pipefail

RELEASE_REPO="${RELEASE_REPO:-S56TS/aiors_deploy}"
DEPLOY_VERSION="${DEPLOY_VERSION:-latest}"
DEPLOY_ASSET_DIR="${DEPLOY_ASSET_DIR:-}"
VERIFY_ONLY="${VERIFY_ONLY:-0}"
ALLOW_DIRTY_RELEASE="${ALLOW_DIRTY_RELEASE:-0}"
MINISIGN_PUBLIC_KEY='RWTNHcQlVd9btokgGZNKfJGPa8ftkBd3N4Z1gYjhjQejcPRCPBDn0Grh'

WORK_DIR=""
CURRENT_STEP="startup"

log() {
  CURRENT_STEP="$*"
  printf '\n==> %s\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local rc=$?
  [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
  if [[ "$rc" -ne 0 ]]; then
    printf 'ERROR: deployment failed during: %s\n' "$CURRENT_STEP" >&2
  fi
  exit "$rc"
}
trap cleanup EXIT HUP INT TERM

manifest_value() {
  local manifest=$1 key=$2
  sed -n "s/^${key}=//p" "$manifest" | head -n1
}

archive_is_safe() {
  local archive=$1
  if tar -tzf "$archive" | sed 's#^\./##' | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
    return 1
  fi
}

case "$DEPLOY_VERSION" in
  ''|*[!A-Za-z0-9._-]*)
    die "invalid DEPLOY_VERSION: $DEPLOY_VERSION"
    ;;
esac

if [[ "$EUID" -eq 0 ]]; then
  SUDO=()
else
  command -v sudo >/dev/null || die "sudo is required"
  SUDO=(sudo)
fi

missing_tools=0
for tool in minisign sha256sum tar wget; do
  command -v "$tool" >/dev/null || missing_tools=1
done
if [[ "$missing_tools" == "1" || ! -r /etc/ssl/certs/ca-certificates.crt ]]; then
  log "Installing release verification tools"
  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" apt-get install -y ca-certificates wget tar minisign
fi
for tool in minisign sha256sum tar wget; do
  command -v "$tool" >/dev/null || die "missing required tool after package installation: $tool"
done

WORK_DIR="$(mktemp -d)"
assets=(
  aiors-arm64.tar.gz
  svxlink-arm64-rootfs.tar.gz
  deployment-manifest.env
  SHA256SUMS
  SHA256SUMS.minisig
)

if [[ -n "$DEPLOY_ASSET_DIR" ]]; then
  log "Loading deployment assets from $DEPLOY_ASSET_DIR"
  for asset in "${assets[@]}"; do
    [[ -r "$DEPLOY_ASSET_DIR/$asset" ]] || die "missing local release asset: $asset"
    cp "$DEPLOY_ASSET_DIR/$asset" "$WORK_DIR/$asset"
  done
else
  if [[ "$DEPLOY_VERSION" == "latest" ]]; then
    release_url="https://github.com/${RELEASE_REPO}/releases/latest/download"
  else
    release_url="https://github.com/${RELEASE_REPO}/releases/download/${DEPLOY_VERSION}"
  fi

  log "Downloading AIORS deployment $DEPLOY_VERSION"
  for asset in "${assets[@]}"; do
    wget --https-only --secure-protocol=TLSv1_2 --tries=3 \
      --output-document="$WORK_DIR/$asset.part" "$release_url/$asset"
    mv "$WORK_DIR/$asset.part" "$WORK_DIR/$asset"
  done
fi

log "Verifying signed release checksums"
minisign -Vm "$WORK_DIR/SHA256SUMS" \
  -x "$WORK_DIR/SHA256SUMS.minisig" \
  -P "$MINISIGN_PUBLIC_KEY"
(cd "$WORK_DIR" && sha256sum -c SHA256SUMS)

for asset in aiors-arm64.tar.gz svxlink-arm64-rootfs.tar.gz deployment-manifest.env; do
  grep -Fq "  $asset" "$WORK_DIR/SHA256SUMS" || die "SHA256SUMS does not cover $asset"
done

manifest="$WORK_DIR/deployment-manifest.env"
[[ "$(manifest_value "$manifest" ARTIFACT_FORMAT)" == "1" ]] || die "unsupported artifact format"
[[ "$(manifest_value "$manifest" ARCH)" == "arm64" ]] || die "release architecture is not arm64"
[[ "$(manifest_value "$manifest" AIORS_PAYLOAD_LAYOUT)" == "1" ]] || die "unsupported AIORS payload layout"
manifest_version="$(manifest_value "$manifest" DEPLOYMENT_VERSION)"
if [[ "$DEPLOY_VERSION" != "latest" && "$manifest_version" != "$DEPLOY_VERSION" ]]; then
  die "release version mismatch: requested $DEPLOY_VERSION, received $manifest_version"
fi
if [[ "$ALLOW_DIRTY_RELEASE" != "1" ]] && {
  [[ "$(manifest_value "$manifest" AIORS_SOURCE_DIRTY)" != "0" ]] ||
  [[ "$(manifest_value "$manifest" SVXLINK_SOURCE_DIRTY)" != "0" ]];
}; then
  die "release was built from an uncommitted source tree"
fi

archive_is_safe "$WORK_DIR/aiors-arm64.tar.gz" || die "AIORS archive contains an unsafe path"
archive_is_safe "$WORK_DIR/svxlink-arm64-rootfs.tar.gz" || die "SvxLink archive contains an unsafe path"

if [[ "$VERIFY_ONLY" == "1" ]]; then
  log "Release verification completed"
  printf 'Verified deployment: %s\n' "$manifest_version"
  exit 0
fi

[[ "$(uname -m)" == "aarch64" ]] || die "this deployment requires 64-bit Raspberry Pi OS (aarch64)"

log "Preparing verified installation payload"
payload_dir="$WORK_DIR/payload"
mkdir -p "$payload_dir/aiors"
tar -xzf "$WORK_DIR/aiors-arm64.tar.gz" -C "$payload_dir/aiors"
cp "$WORK_DIR/svxlink-arm64-rootfs.tar.gz" "$payload_dir/svxlink-arm64-rootfs.tar.gz"
cp "$manifest" "$payload_dir/deployment-manifest.env"
[[ -x "$payload_dir/aiors/scripts/install_aiors_svxlink.sh" ]] ||
  die "AIORS archive does not contain the deployment installer"

log "Running AIORS and SvxLink binary deployment"
RELEASE_PAYLOAD_DIR="$payload_dir" \
AIORS_HW_VERSION="${AIORS_HW_VERSION:-}" \
  bash "$payload_dir/aiors/scripts/install_aiors_svxlink.sh"

log "Deployment completed"
printf 'Installed deployment: %s\n' "$manifest_version"
