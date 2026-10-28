#!/bin/zsh
# Double-click to build Squish (Release), install it to /Applications, and relaunch it.

ROOT="${0:A:h}"
APP="$ROOT/build/mac/Build/Products/Release/Squish.app"

pause_before_exit() {
    if [[ -t 0 ]]; then
        echo
        read -k 1 "?Press any key to close this window…"
        echo
    fi
}

fail() {
    echo
    echo "Squish could not be built."
    echo "$1"
    pause_before_exit
    exit 1
}

cd "$ROOT" || fail "The Squish source folder could not be opened."

/usr/bin/xcodebuild -version >/dev/null 2>&1 \
    || fail "Install Xcode 26, open it once to finish setup, and try again."

echo "Building Squish ($(git branch --show-current 2>/dev/null || echo "unknown branch"))…"
echo

/usr/bin/xcodebuild -project Squish.xcodeproj -scheme Squish -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath build/mac -quiet build \
    || fail "See the build output above for details."

[[ -d "$APP" ]] || fail "The build finished without creating Squish.app."

# Quit a running copy so the new one can replace it. Builds before 2026-10
# used the com.squish.app identifier.
if /usr/bin/pgrep -xq Squish; then
    for id in com.danielmccullum.Squish com.squish.app; do
        /usr/bin/osascript -e "if application id \"$id\" is running then tell application id \"$id\" to quit" 2>/dev/null
    done
    for _ in {1..20}; do /usr/bin/pgrep -xq Squish || break; sleep 0.25; done
fi

rm -rf /Applications/Squish.app
/usr/bin/ditto "$APP" /Applications/Squish.app || fail "Squish.app could not be copied into Applications."

# Register Open With and the Squish Images service with the system.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Squish.app
/System/Library/CoreServices/pbs -update 2>/dev/null

/usr/bin/open /Applications/Squish.app

echo
echo "Squish is installed in Applications and running."
pause_before_exit
