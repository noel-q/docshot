#!/bin/zsh
set -euo pipefail

# Creates a drag-to-Applications DMG for local testing. This is deliberately
# not a notarised release package and must not be described as one.

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
output_dir="${1:-${repo_root}/dist}"
archive_path="${output_dir}/DocShot.xcarchive"
app_path="${archive_path}/Products/Applications/DocShot.app"
dmg_path="${output_dir}/DocShot-macos-development.dmg"
staging_dir=""

cleanup() {
  [[ -n "${staging_dir}" && -d "${staging_dir}" ]] && rm -rf "${staging_dir}"
}
trap cleanup EXIT

if [[ -e "${archive_path}" || -e "${dmg_path}" ]]; then
  print -u2 "Refusing to overwrite an existing package. Remove or rename: ${output_dir}"
  exit 1
fi

mkdir -p "${output_dir}"

xcodebuild archive \
  -project "${repo_root}/DocShot.xcodeproj" \
  -scheme DocShot \
  -configuration Release \
  -archivePath "${archive_path}"

if [[ ! -d "${app_path}" ]]; then
  print -u2 "Archive completed but DocShot.app was not found at ${app_path}"
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "${app_path}"

staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/DocShot-dmg.XXXXXX")"
ditto "${app_path}" "${staging_dir}/DocShot.app"
ln -s /Applications "${staging_dir}/Applications"
hdiutil create -volname "DocShot" -srcfolder "${staging_dir}" -ov -format UDZO "${dmg_path}"

print "Created development DMG: ${dmg_path}"
print "Open it, drag DocShot to Applications, then eject the disk image."
print "This DMG is Apple Development-signed only. It is not notarised for public distribution."
