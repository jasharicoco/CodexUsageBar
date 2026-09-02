#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
app_directory="$project_directory/dist/CodexUsageBar.app"
require_notarization=${REQUIRE_NOTARIZATION:-0}

if [[ ! -d "$app_directory" ]]; then
    echo "Bygg appen först med Scripts/build-app.sh." >&2
    exit 1
fi

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$app_directory/Contents/Info.plist")
archive_name="CodexUsageBar-v$version-macOS-universal.zip"
archive_path="$project_directory/dist/$archive_name"
checksum_path="$archive_path.sha256"
notarization_mode=""

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notarization_mode="profile"
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    notarization_mode="apple-id"
fi

if [[ "$require_notarization" == "1" && -z "$notarization_mode" ]]; then
    echo "Notarisering krävs, men inga Apple-uppgifter har konfigurerats." >&2
    exit 1
fi

rm -f "$archive_path" "$checksum_path"
ditto -c -k --sequesterRsrc --keepParent "$app_directory" "$archive_path"

if [[ "$notarization_mode" == "profile" ]]; then
    xcrun notarytool submit "$archive_path" \
        --keychain-profile "$NOTARY_PROFILE" --wait
elif [[ "$notarization_mode" == "apple-id" ]]; then
    xcrun notarytool submit "$archive_path" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait
fi

if [[ -n "$notarization_mode" ]]; then
    xcrun stapler staple "$app_directory"
    xcrun stapler validate "$app_directory"

    rm -f "$archive_path"
    ditto -c -k --sequesterRsrc --keepParent "$app_directory" "$archive_path"
fi

cd "$project_directory/dist"
shasum -a 256 "$archive_name" > "$archive_name.sha256"

echo "$archive_path"
echo "$checksum_path"
