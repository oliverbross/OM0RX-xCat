#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
app_dir="$repo_dir/dist/OM0RX-xCat.app"
contents_dir="$app_dir/Contents"

if [[ "$app_dir" != "$repo_dir/dist/OM0RX-xCat.app" ]]; then
    print -u2 "Refusing unexpected app output path: $app_dir"
    exit 1
fi

swift build --package-path "$repo_dir" -c release
bin_dir="$(swift build --package-path "$repo_dir" -c release --show-bin-path)"

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$bin_dir/OM0RX-xCat" "$contents_dir/MacOS/OM0RX-xCat"
cp "$repo_dir/Resources/Info.plist" "$contents_dir/Info.plist"
chmod 755 "$contents_dir/MacOS/OM0RX-xCat"

signing_identity="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    identity_output="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    signing_identity="$(print -r -- "$identity_output" \
        | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
        | sed -n '1p')"
fi

if [[ -z "$signing_identity" ]]; then
    print -u2 "A Developer ID Application identity is required."
    exit 1
fi

codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "$repo_dir/Resources/OM0RXXCat.entitlements" \
    --sign "$signing_identity" \
    "$app_dir"
codesign --verify --deep --strict --verbose=2 "$app_dir"
print "$app_dir"
