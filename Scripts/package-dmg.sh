#!/bin/zsh
set -euo pipefail

# Builds DocShot and packages it as a laid-out drag-to-Applications DMG.
#
#   Scripts/package-dmg.sh <output folder>             Apple Development-signed, for testers.
#                                                     Not notarised; macOS warns on first open.
#   Scripts/package-dmg.sh --release <output folder>  Developer ID-signed and notarised by Apple,
#                                                     with the ticket stapled to the DMG.
#
# Release needs, once per Mac:
#   - a "Developer ID Application" certificate in the login keychain (Xcode > Settings >
#     Accounts > Manage Certificates), and
#   - notary credentials saved in the keychain under a profile name (default docshot-notary):
#       xcrun notarytool store-credentials docshot-notary --apple-id <Apple ID> --team-id <team>
#     It asks for an app-specific password from account.apple.com. Nothing secret goes in here.
#
# The Finder layout step asks once for permission to control Finder.

release=false
if [[ "${1:-}" == "--release" ]]; then
  release=true
  shift
fi

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
output_dir="${1:-${repo_root}/dist}"
notary_profile="${DOCSHOT_NOTARY_PROFILE:-docshot-notary}"
archive_path="${output_dir}/DocShot.xcarchive"
export_dir="${output_dir}/export"
volume_name="DocShot"
work_dir=""
mounted=""

cleanup() {
  [[ -n "${mounted}" && -d "${mounted}" ]] && hdiutil detach "${mounted}" -quiet || true
  [[ -n "${work_dir}" && -d "${work_dir}" ]] && rm -rf "${work_dir}"
}
trap cleanup EXIT

fail() { print -u2 "package-dmg: $1"; exit 1 }

setopt null_glob
existing=("${output_dir}"/*.dmg)
if [[ -e "${archive_path}" || ${#existing} -gt 0 ]]; then
  fail "refusing to overwrite an existing package. Remove or rename: ${output_dir}"
fi
[[ -e "/Volumes/${volume_name}" ]] && fail "eject the disk named ${volume_name} first; the layout step needs its name."

# --- Signing identity ---------------------------------------------------------------------

team_args=()
if $release; then
  identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
  [[ -n "${identity}" ]] || fail "no Developer ID Application certificate in the keychain. Create one in Xcode > Settings > Accounts > Manage Certificates once Apple approves the membership."
  team_id="${identity##*\(}"; team_id="${team_id%\)}"
  xcrun notarytool history --keychain-profile "${notary_profile}" >/dev/null 2>&1 \
    || fail "no notary credentials saved as '${notary_profile}'. Run: xcrun notarytool store-credentials ${notary_profile} --apple-id <Apple ID> --team-id ${team_id}"
  team_args=(DEVELOPMENT_TEAM="${team_id}")
  print "Signing as: ${identity}"
fi

mkdir -p "${output_dir}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/DocShot-dmg.XXXXXX")"

# --- Build ----------------------------------------------------------------------------------

xcodebuild archive \
  -project "${repo_root}/DocShot.xcodeproj" \
  -scheme DocShot \
  -configuration Release \
  -archivePath "${archive_path}" \
  "${team_args[@]}"

if $release; then
  cat > "${work_dir}/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
  <key>teamID</key><string>${team_id}</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -archivePath "${archive_path}" -exportPath "${export_dir}" \
    -exportOptionsPlist "${work_dir}/ExportOptions.plist"
  app_path="${export_dir}/DocShot.app"
else
  app_path="${archive_path}/Products/Applications/DocShot.app"
fi

[[ -d "${app_path}" ]] || fail "DocShot.app was not found at ${app_path}"
codesign --verify --deep --strict --verbose=2 "${app_path}"

# --- Checks on the app ----------------------------------------------------------------------

info="${app_path}/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info}")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${info}")"
binary="${app_path}/Contents/MacOS/DocShot"
if strings "${binary}" | grep "DOCSHOT_DEBUG_HOOKS" >/dev/null; then
  fail "the app still contains the debug hooks; a Release build must not."
fi
if $release; then
  # Read the signature once: piping codesign into grep -q fails under pipefail.
  signature="$(codesign -dvv "${app_path}" 2>&1)"
  [[ "${signature}" == *"Authority=Developer ID Application"* ]] \
    || fail "the exported app is not signed with Developer ID."
  [[ "${signature}" =~ "flags=[^ ]*runtime" ]] \
    || fail "the hardened runtime is off; notarisation needs it."
fi

if $release; then
  dmg_path="${output_dir}/DocShot-${version}-build${build}.dmg"
else
  dmg_path="${output_dir}/DocShot-macos-development.dmg"
fi

# --- Disk image layout ----------------------------------------------------------------------

stage="${work_dir}/stage"
mkdir -p "${stage}/.background"
ditto "${app_path}" "${stage}/DocShot.app"
ln -s /Applications "${stage}/Applications"
swift "${script_dir}/dmg/make-background.swift" "${work_dir}"
tiffutil -cathidpicheck "${work_dir}/background.png" "${work_dir}/background@2x.png" \
  -out "${stage}/.background/background.tiff" >/dev/null
icon_file="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "${info}" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "${info}" 2>/dev/null || true)"
[[ -n "${icon_file}" && "${icon_file}" != *.icns ]] && icon_file="${icon_file}.icns"

rw_dmg="${work_dir}/rw.dmg"
hdiutil create -volname "${volume_name}" -srcfolder "${stage}" -fs HFS+ -format UDRW -ov "${rw_dmg}" >/dev/null
mounted="/Volumes/${volume_name}"
hdiutil attach "${rw_dmg}" -mountpoint "${mounted}" -nobrowse -noautoopen -quiet

# Finder writes the window size, background and icon places into the image's .DS_Store.
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "${volume_name}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    try
      set pathbar visible of container window to false
    end try
    set the bounds of container window to {200, 120, 800, 528}
    set options to the icon view options of container window
    set arrangement of options to not arranged
    set icon size of options to 112
    set text size of options to 13
    set background picture of options to file ".background:background.tiff"
    set extension hidden of item "DocShot.app" of container window to true
    set position of item "DocShot.app" of container window to {160, 180}
    set position of item "Applications" of container window to {440, 180}
    update without registering applications
    delay 1
    close
    -- Reopened, Finder may restore its own size; set it again so the saved size sticks.
    open
    delay 1
    set the bounds of container window to {200, 120, 800, 528}
    delay 1
    close
  end tell
end tell
APPLESCRIPT

# The disk shows DocShot's icon. After the Finder step, which drops it.
if [[ -n "${icon_file}" && -f "${app_path}/Contents/Resources/${icon_file}" ]]; then
  cp "${app_path}/Contents/Resources/${icon_file}" "${mounted}/.VolumeIcon.icns"
  SetFile -a C "${mounted}" || print -u2 "package-dmg: could not set the disk icon; carrying on."
fi

sync
sleep 2
hdiutil detach "${mounted}" -quiet
mounted=""
hdiutil convert "${rw_dmg}" -format UDZO -imagekey zlib-level=9 -o "${dmg_path}" >/dev/null

# --- Sign and notarise the disk image (release) ----------------------------------------------

if $release; then
  codesign --sign "${identity}" --timestamp "${dmg_path}"
  print "Sending to Apple's notary service (usually a few minutes)..."
  xcrun notarytool submit "${dmg_path}" --keychain-profile "${notary_profile}" --wait \
    --output-format plist > "${work_dir}/notary.plist"
  notary_status="$(/usr/libexec/PlistBuddy -c 'Print :status' "${work_dir}/notary.plist")"
  if [[ "${notary_status}" != "Accepted" ]]; then
    submission="$(/usr/libexec/PlistBuddy -c 'Print :id' "${work_dir}/notary.plist")"
    xcrun notarytool log "${submission}" --keychain-profile "${notary_profile}" || true
    fail "notarisation finished as '${notary_status}' (log above)."
  fi
  xcrun stapler staple "${dmg_path}"
  xcrun stapler validate "${dmg_path}"
  spctl --assess --type open --context context:primary-signature --verbose=2 "${dmg_path}"
fi

print ""
print "Created: ${dmg_path}"
print "DocShot ${version}, build ${build}; SHA-256 $(shasum -a 256 "${dmg_path}" | cut -d' ' -f1)"
if $release; then
  print "Developer ID-signed, notarised and stapled."
else
  print "Apple Development-signed only. Not notarised: macOS warns the first time it opens."
fi
