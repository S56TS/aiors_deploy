#!/usr/bin/env sh
set -eu

usage() {
  echo "usage: $0 VERSION AIORS_REPO SVXLINK_REPO [MINISIGN_SECRET_KEY]" >&2
  exit 2
}

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then usage; fi

version=$1
aiors_repo=$2
svxlink_repo=$3
signing_key=${4:-${MINISIGN_SECRET_KEY:-}}

case "$version" in
  ''|*[!A-Za-z0-9._-]*)
    echo "invalid release version: $version" >&2
    exit 2
    ;;
esac

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
aiors_repo=$(CDPATH='' cd -- "$aiors_repo" && pwd)
svxlink_repo=$(CDPATH='' cd -- "$svxlink_repo" && pwd)

for tool in git make tar sha256sum sed awk install; do
  command -v "$tool" >/dev/null || {
    echo "missing required tool: $tool" >&2
    exit 1
  }
done

[ -d "$aiors_repo/.git" ] || {
  echo "not an AIORS Git repository: $aiors_repo" >&2
  exit 1
}
[ -d "$svxlink_repo/.git" ] || {
  echo "not a SvxLink Git repository: $svxlink_repo" >&2
  exit 1
}

if [ "${REBUILD:-0}" = 1 ]; then
  echo "Refreshing AIORS ARM64 prebuilts"
  make -C "$aiors_repo" prebuilt-arm64
  echo "Refreshing SvxLink ARM64 prebuilt bundle"
  make -C "$svxlink_repo" prebuilt-arm64
fi

aiors_prebuilt="$aiors_repo/prebuilt/arm64"
svxlink_prebuilt="$svxlink_repo/prebuilt/arm64"
aiors_manifest="$aiors_prebuilt/manifest.env"
svxlink_manifest="$svxlink_prebuilt/manifest.env"
svxlink_bundle="$svxlink_prebuilt/svxlink-rootfs.tar.gz"
minisign_public_key="$repo_dir/keys/minisign.pub"

for filename in \
  "$aiors_manifest" \
  "$aiors_prebuilt/SHA256SUMS" \
  "$aiors_prebuilt/hw-1.0/aiorsd" \
  "$aiors_prebuilt/hw-1.0/aiorsctl" \
  "$aiors_prebuilt/hw-1.1/aiorsd" \
  "$aiors_prebuilt/hw-1.1/aiorsctl" \
  "$aiors_prebuilt/aiors-mqtt-agent" \
  "$aiors_repo/deploy/svxlink.conf" \
  "$aiors_repo/etc/aiors/aiors.cfg" \
  "$aiors_repo/etc/aiors-mqtt/agent.conf" \
  "$aiors_repo/etc/systemd/system/aiors-mqtt-agent.service" \
  "$aiors_repo/etc/udev/rules.d/99-aiors.rules" \
  "$aiors_repo/scripts/install_aiors_svxlink.sh" \
  "$aiors_repo/scripts/install_prebuilt_payload.sh" \
  "$svxlink_manifest" \
  "$svxlink_prebuilt/SHA256SUMS" \
  "$svxlink_bundle"; do
  [ -r "$filename" ] || {
    echo "missing release input: $filename" >&2
    exit 1
  }
done

echo "Verifying project checksums"
(cd "$aiors_prebuilt" && sha256sum -c SHA256SUMS)
(cd "$svxlink_prebuilt" && sha256sum -c SHA256SUMS)

manifest_value() {
  sed -n "s/^$2=//p" "$1" | awk 'NR == 1 { print; exit }'
}

aiors_arch=$(manifest_value "$aiors_manifest" ARCH)
svxlink_arch=$(manifest_value "$svxlink_manifest" ARCH)
[ "$aiors_arch" = arm64 ] || {
  echo "AIORS manifest architecture is '$aiors_arch', expected arm64" >&2
  exit 1
}
[ "$(manifest_value "$aiors_manifest" LIBGPIOD_SONAME)" = libgpiod.so.3 ] || {
  echo "AIORS manifest must target Debian 13 libgpiod.so.3" >&2
  exit 1
}
[ "$(manifest_value "$aiors_manifest" MQTT_AGENT)" = aiors-mqtt-agent ] || {
  echo "AIORS manifest does not contain the MQTT agent" >&2
  exit 1
}
[ "$(manifest_value "$aiors_manifest" MQTT_LIBMOSQUITTO_SONAME)" = libmosquitto.so.1 ] || {
  echo "AIORS MQTT agent must target libmosquitto.so.1" >&2
  exit 1
}
[ "$(manifest_value "$aiors_manifest" MQTT_SQLITE_SONAME)" = libsqlite3.so.0 ] || {
  echo "AIORS MQTT agent must target libsqlite3.so.0" >&2
  exit 1
}
[ "$(manifest_value "$aiors_manifest" MQTT_CJSON_SONAME)" = libcjson.so.1 ] || {
  echo "AIORS MQTT agent must target libcjson.so.1" >&2
  exit 1
}
[ "$svxlink_arch" = arm64 ] || {
  echo "SvxLink manifest architecture is '$svxlink_arch', expected arm64" >&2
  exit 1
}
[ "$(manifest_value "$svxlink_manifest" SYSTEMD_UNIT_DIR)" = /usr/lib/systemd/system ] || {
  echo "SvxLink manifest is not usrmerge-safe for Debian 13" >&2
  exit 1
}
[ "$(manifest_value "$svxlink_manifest" GPIOD_SONAME)" = libgpiod.so.3 ] || {
  echo "SvxLink manifest must target Debian 13 libgpiod.so.3" >&2
  exit 1
}
if tar -tzf "$svxlink_bundle" | sed 's#^\./##' |
    grep -Eq '^(bin|sbin|lib)(/|$)'; then
  echo "SvxLink archive contains a legacy top-level usrmerge path" >&2
  exit 1
fi

dist_root="$repo_dir/dist"
output_dir="$dist_root/$version"
work_dir="$dist_root/.$version.tmp.$$"
aiors_payload=""

case "$output_dir" in
  "$repo_dir"/dist/*) ;;
  *) echo "unsafe output directory: $output_dir" >&2; exit 1 ;;
esac

cleanup() {
  [ -z "$aiors_payload" ] || [ ! -d "$aiors_payload" ] || rm -rf "$aiors_payload"
  [ ! -d "$work_dir" ] || rm -rf "$work_dir"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$dist_root" "$work_dir"

echo "Creating AIORS release archive"
aiors_payload=$(mktemp -d)
mkdir -p \
  "$aiors_payload/prebuilt/arm64" \
  "$aiors_payload/deploy" \
  "$aiors_payload/etc/aiors" \
  "$aiors_payload/etc/aiors-mqtt" \
  "$aiors_payload/etc/systemd/system" \
  "$aiors_payload/etc/udev/rules.d" \
  "$aiors_payload/scripts"
cp -R "$aiors_prebuilt/." "$aiors_payload/prebuilt/arm64/"
find "$aiors_payload/prebuilt/arm64" -type d -exec chmod 0755 {} \;
find "$aiors_payload/prebuilt/arm64" -type f -exec chmod 0644 {} \;
chmod 0755 \
  "$aiors_payload/prebuilt/arm64/hw-1.0/aiorsd" \
  "$aiors_payload/prebuilt/arm64/hw-1.0/aiorsctl" \
  "$aiors_payload/prebuilt/arm64/hw-1.1/aiorsd" \
  "$aiors_payload/prebuilt/arm64/hw-1.1/aiorsctl" \
  "$aiors_payload/prebuilt/arm64/aiors-mqtt-agent"
install -m 0644 "$aiors_repo/deploy/svxlink.conf" "$aiors_payload/deploy/svxlink.conf"
install -m 0644 "$aiors_repo/etc/aiors/aiors.cfg" "$aiors_payload/etc/aiors/aiors.cfg"
install -m 0644 "$aiors_repo/etc/aiors-mqtt/agent.conf" \
  "$aiors_payload/etc/aiors-mqtt/agent.conf"
install -m 0644 "$aiors_repo/etc/systemd/system/aiors-mqtt-agent.service" \
  "$aiors_payload/etc/systemd/system/aiors-mqtt-agent.service"
install -m 0644 "$aiors_repo/etc/udev/rules.d/99-aiors.rules" \
  "$aiors_payload/etc/udev/rules.d/99-aiors.rules"
install -m 0755 "$aiors_repo/scripts/install_aiors_svxlink.sh" \
  "$aiors_payload/scripts/install_aiors_svxlink.sh"
install -m 0755 "$aiors_repo/scripts/install_prebuilt_payload.sh" \
  "$aiors_payload/scripts/install_prebuilt_payload.sh"
tar --sort=name --mtime='@0' --numeric-owner --owner=0 --group=0 \
  -C "$aiors_payload" -czf "$work_dir/aiors-arm64.tar.gz" .
rm -rf "$aiors_payload"
aiors_payload=""

cp "$svxlink_bundle" "$work_dir/svxlink-arm64-rootfs.tar.gz"

aiors_archive_sha=$(sha256sum "$work_dir/aiors-arm64.tar.gz" | awk '{print $1}')
svxlink_archive_sha=$(sha256sum "$work_dir/svxlink-arm64-rootfs.tar.gz" | awk '{print $1}')
aiors_manifest_sha=$(sha256sum "$aiors_manifest" | awk '{print $1}')
svxlink_manifest_sha=$(sha256sum "$svxlink_manifest" | awk '{print $1}')
aiors_source_dirty=0
if grep -q -- '-dirty' "$aiors_prebuilt/hw-1.0/.version" ||
   grep -q -- '-dirty' "$aiors_prebuilt/hw-1.1/.version"; then
  aiors_source_dirty=1
fi

cat > "$work_dir/deployment-manifest.env" <<EOF
ARTIFACT_FORMAT=1
DEPLOYMENT_VERSION=$version
ARCH=arm64
AIORS_ARCHIVE=aiors-arm64.tar.gz
AIORS_ARCHIVE_SHA256=$aiors_archive_sha
AIORS_VERSION=$(manifest_value "$aiors_manifest" AIORS_VERSION)
AIORS_SOURCE_COMMIT=$(manifest_value "$aiors_manifest" SOURCE_COMMIT)
AIORS_SOURCE_DIRTY=$aiors_source_dirty
AIORS_HW_VERSIONS=1.0,1.1
AIORS_PAYLOAD_LAYOUT=2
AIORS_LIBGPIOD_SONAME=$(manifest_value "$aiors_manifest" LIBGPIOD_SONAME)
AIORS_MQTT_AGENT=$(manifest_value "$aiors_manifest" MQTT_AGENT)
AIORS_MQTT_LIBMOSQUITTO_SONAME=$(manifest_value "$aiors_manifest" MQTT_LIBMOSQUITTO_SONAME)
AIORS_MQTT_SQLITE_SONAME=$(manifest_value "$aiors_manifest" MQTT_SQLITE_SONAME)
AIORS_MQTT_CJSON_SONAME=$(manifest_value "$aiors_manifest" MQTT_CJSON_SONAME)
AIORS_MANIFEST_SHA256=$aiors_manifest_sha
SVXLINK_ARCHIVE=svxlink-arm64-rootfs.tar.gz
SVXLINK_ARCHIVE_SHA256=$svxlink_archive_sha
SVXLINK_SOURCE_COMMIT=$(manifest_value "$svxlink_manifest" SOURCE_COMMIT)
SVXLINK_SOURCE_DESCRIBE=$(manifest_value "$svxlink_manifest" SOURCE_DESCRIBE)
SVXLINK_SOURCE_DIRTY=$(manifest_value "$svxlink_manifest" SOURCE_DIRTY)
SVXLINK_GPIOD_SONAME=$(manifest_value "$svxlink_manifest" GPIOD_SONAME)
SVXLINK_BUNDLED_JSONCPP=$(manifest_value "$svxlink_manifest" BUNDLED_JSONCPP)
SVXLINK_BUNDLED_RUNTIME_DIR=$(manifest_value "$svxlink_manifest" BUNDLED_RUNTIME_DIR)
SVXLINK_SYSTEMD_UNIT_DIR=$(manifest_value "$svxlink_manifest" SYSTEMD_UNIT_DIR)
SVXLINK_MANIFEST_SHA256=$svxlink_manifest_sha
EOF

(cd "$work_dir" && sha256sum \
  aiors-arm64.tar.gz \
  svxlink-arm64-rootfs.tar.gz \
  deployment-manifest.env > SHA256SUMS)

if [ -n "$signing_key" ]; then
  command -v minisign >/dev/null || {
    echo "minisign is required when a signing key is supplied" >&2
    exit 1
  }
  [ -r "$signing_key" ] || {
    echo "cannot read Minisign secret key: $signing_key" >&2
    exit 1
  }
  [ -r "$minisign_public_key" ] || {
    echo "missing Minisign public key: $minisign_public_key" >&2
    exit 1
  }
  echo "Signing SHA256SUMS"
  minisign -Sm "$work_dir/SHA256SUMS" \
    -s "$signing_key" \
    -x "$work_dir/SHA256SUMS.minisig" \
    -t "AIORS deployment $version"
  minisign -Vm "$work_dir/SHA256SUMS" \
    -p "$minisign_public_key" \
    -x "$work_dir/SHA256SUMS.minisig"
else
  echo "WARNING: no Minisign key supplied; SHA256SUMS.minisig was not created" >&2
fi

rm -rf "$output_dir"
mv "$work_dir" "$output_dir"
trap - EXIT HUP INT TERM

echo "Release assets ready: $output_dir"
