#!/bin/zsh
set -euo pipefail

# Creates a local, Apple Development-signed ZIP for testers. This is deliberately
# not a notarised release package and must not be described as one.

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
output_dir="${1:-${repo_root}/dist}"
archive_path="${output_dir}/DocShot.xcarchive"
app_path="${archive_path}/Products/Applications/DocShot.app"
zip_path="${output_dir}/DocShot-macos-development.zip"

if [[ -e "${archive_path}" || -e "${zip_path}" ]]; then
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
ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${zip_path}"

print "Created development package: ${zip_path}"
print "This ZIP is Apple Development-signed only. It is not notarised for public distribution."
