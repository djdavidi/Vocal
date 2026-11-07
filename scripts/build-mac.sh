#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build --product VocalAppCheck -c release --disable-sandbox
vocal_bin_dir="$(swift build --show-bin-path -c release)"
vocal_app_dir="$PWD/dist/Vocal.app"
mkdir -p "$vocal_app_dir/Contents/MacOS" "$vocal_app_dir/Contents/Resources"
mkdir -p "$vocal_app_dir/Contents/Frameworks"
cp "$vocal_bin_dir/VocalAppCheck" "$vocal_app_dir/Contents/MacOS/Vocal"
cp -Rf "$vocal_bin_dir/llama.framework" "$vocal_app_dir/Contents/Frameworks/"
codesign --force --sign - "$vocal_app_dir/Contents/Frameworks/llama.framework"
# Discard obsolete resources from earlier prototype dependencies.
for vocal_bundle in "$vocal_app_dir/Contents/Resources/"*.bundle(N); do
    rm -rf "$vocal_bundle"
done
# Only ZIPFoundation carries a resource bundle in the current dependency graph.
vocal_bundle="$vocal_bin_dir/ZIPFoundation_ZIPFoundation.bundle"
if [[ -d "$vocal_bundle" ]]; then
    cp -Rf "$vocal_bundle" "$vocal_app_dir/Contents/Resources/"
fi
# This is a local development bundle. SwiftPM's macOS resource accessor also
# retains the absolute build-directory fallback; keep .build beside the repo.
cat > "$vocal_app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Vocal</string>
<key>CFBundleIdentifier</key><string>com.david.vocal.prototype.mac</string>
<key>CFBundleName</key><string>Vocal</string>
<key>CFBundleDisplayName</key><string>Vocal</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Listen to your spoken messages for local conversation. Audio is not recorded to disk.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>Transcribe your speech locally for the offline conversation prototype.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$vocal_app_dir"
print "Built: $vocal_app_dir"
