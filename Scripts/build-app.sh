#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
configuration=${1:-release}
version=${VERSION:-1.0.0}
build_number=${BUILD_NUMBER:-1}
universal_build=${UNIVERSAL_BUILD:-1}
signing_identity=${SIGNING_IDENTITY:--}
selected_sdk=${CODEX_USAGE_BAR_SDK:-}
fallback_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
app_directory="$project_directory/dist/CodexUsageBar.app"
contents_directory="$app_directory/Contents"

run_swift_build() {
    local architecture=$1
    local scratch_path="$project_directory/.build/architectures/$architecture"
    local module_cache="$scratch_path/ModuleCache"
    local -a arguments
    arguments=(
        swift build
        --configuration "$configuration"
        --product CodexUsageBar
        --arch "$architecture"
        --scratch-path "$scratch_path"
    )

    mkdir -p "$module_cache"

    if [[ -n "$selected_sdk" ]]; then
        SDKROOT="$selected_sdk" CLANG_MODULE_CACHE_PATH="$module_cache" "${arguments[@]}"
    else
        CLANG_MODULE_CACHE_PATH="$module_cache" "${arguments[@]}"
    fi
}

build_architecture() {
    local architecture=$1

    if run_swift_build "$architecture"; then
        return
    fi

    if [[ -z "$selected_sdk" && -d "$fallback_sdk" ]]; then
        selected_sdk="$fallback_sdk"
        echo "Försöker igen med $fallback_sdk" >&2
        run_swift_build "$architecture"
        return
    fi

    echo "Swift-bygget misslyckades för $architecture." >&2
    exit 1
}

binary_path() {
    local architecture=$1
    local scratch_path="$project_directory/.build/architectures/$architecture"
    local -a arguments
    arguments=(
        swift build
        --configuration "$configuration"
        --product CodexUsageBar
        --arch "$architecture"
        --scratch-path "$scratch_path"
        --show-bin-path
    )

    if [[ -n "$selected_sdk" ]]; then
        SDKROOT="$selected_sdk" "${arguments[@]}"
    else
        "${arguments[@]}"
    fi
}

cd "$project_directory"

rm -rf "$app_directory"
mkdir -p "$contents_directory/MacOS" "$contents_directory/Resources"

if [[ "$universal_build" == "1" ]]; then
    build_architecture arm64
    build_architecture x86_64

    arm64_binary="$(binary_path arm64)/CodexUsageBar"
    x86_64_binary="$(binary_path x86_64)/CodexUsageBar"

    lipo -create "$arm64_binary" "$x86_64_binary" \
        -output "$contents_directory/MacOS/CodexUsageBar"
else
    native_architecture=$(uname -m)
    build_architecture "$native_architecture"
    cp "$(binary_path "$native_architecture")/CodexUsageBar" \
        "$contents_directory/MacOS/CodexUsageBar"
fi

cp "$project_directory/Info.plist" "$contents_directory/Info.plist"
cp "$project_directory/Assets/OpenAIBlossom.png" "$contents_directory/Resources/OpenAIBlossom.png"
cp "$project_directory/Assets/OpenAIBlossom@2x.png" "$contents_directory/Resources/OpenAIBlossom@2x.png"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$contents_directory/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$contents_directory/Info.plist"

if [[ "$signing_identity" == "-" ]]; then
    codesign --force --deep --sign - "$app_directory"
else
    codesign --force --deep --options runtime --timestamp \
        --sign "$signing_identity" "$app_directory"
fi

codesign --verify --deep --strict "$app_directory"

echo "$app_directory"
