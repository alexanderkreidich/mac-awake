#!/usr/bin/env bash
set -euo pipefail

LABEL="com.sasha.MacAwakeHelper"
HELPER_PRODUCT_NAME="MacAwakeHelper"
PROJECT_RELATIVE_PATH="xcode/MacAwake.xcodeproj"
SCHEME="MacAwake"
CONFIGURATION="${CONFIGURATION:-Debug}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="$REPO_DIR/$PROJECT_RELATIVE_PATH"
DERIVED_DATA_PATH="$REPO_DIR/.build/DerivedData"
HELPER_SOURCE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$HELPER_PRODUCT_NAME"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/MacAwake.app"
HELPER_DEST="/Library/PrivilegedHelperTools/$LABEL"
PLIST_DEST="/Library/LaunchDaemons/$LABEL.plist"
STATE_DIR="/Library/Application Support/Mac Awake"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "error: $PROJECT_RELATIVE_PATH not found relative to repository root" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild not found. Install Xcode and select it with xcode-select." >&2
  exit 1
fi

cat <<'WARNING'
Mac Awake development helper installer

This installs a root launch daemon for local development only.
It is NOT the production signing/notarization/SMJobBless flow.
Until client code-signature validation is implemented, do not distribute this helper.

You may be prompted for your macOS administrator password.
WARNING

if [[ "${MAC_AWAKE_INSTALL_ASSUME_YES:-}" != "1" ]]; then
  read -r -p "Continue installing $LABEL? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "cancelled"; exit 0 ;;
  esac
fi

echo "==> Building $SCHEME ($CONFIGURATION)"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

if [[ ! -x "$HELPER_SOURCE" ]]; then
  echo "error: helper executable not found at $HELPER_SOURCE" >&2
  exit 1
fi

PLIST_TMP="$(mktemp -t "$LABEL.plist.XXXXXX")"
VERIFY_SOURCE=""
VERIFY_BINARY=""
cleanup() {
  rm -f "$PLIST_TMP"
  if [[ -n "$VERIFY_SOURCE" ]]; then
    rm -f "$VERIFY_SOURCE"
  fi
  if [[ -n "$VERIFY_BINARY" ]]; then
    rm -f "$VERIFY_BINARY"
  fi
}
trap cleanup EXIT

cat >"$PLIST_TMP" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>

  <key>ProgramArguments</key>
  <array>
    <string>$HELPER_DEST</string>
  </array>

  <key>MachServices</key>
  <dict>
    <key>$LABEL</key>
    <true/>
  </dict>

  <key>RunAtLoad</key>
  <false/>

  <key>StandardOutPath</key>
  <string>/var/log/$LABEL.log</string>

  <key>StandardErrorPath</key>
  <string>/var/log/$LABEL.err.log</string>
</dict>
</plist>
PLIST

plutil -lint "$PLIST_TMP" >/dev/null

echo "==> Removing any currently loaded development helper"
sudo /bin/launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
sudo /bin/launchctl bootout system "$PLIST_DEST" >/dev/null 2>&1 || true

echo "==> Installing helper binary and launch daemon"
sudo /usr/bin/install -d -o root -g wheel -m 0755 /Library/PrivilegedHelperTools
sudo /usr/bin/install -d -o root -g wheel -m 0755 /Library/LaunchDaemons
sudo /usr/bin/install -d -o root -g wheel -m 0755 "$STATE_DIR"
sudo /usr/bin/install -o root -g wheel -m 0755 "$HELPER_SOURCE" "$HELPER_DEST"
sudo /usr/bin/install -o root -g wheel -m 0644 "$PLIST_TMP" "$PLIST_DEST"

echo "==> Loading launch daemon"
sudo /bin/launchctl bootstrap system "$PLIST_DEST"
sudo /bin/launchctl enable "system/$LABEL" >/dev/null 2>&1 || true
sudo /bin/launchctl kickstart -k "system/$LABEL"

echo "==> Installed $LABEL"
echo "Helper: $HELPER_DEST"
echo "Plist:  $PLIST_DEST"
echo
printf 'Launchd status: '
if sudo /bin/launchctl print "system/$LABEL" >/dev/null 2>&1; then
  echo "loaded"
else
  echo "not loaded"
  exit 1
fi

echo "==> Verifying helper XPC status()"
VERIFY_SOURCE="$(mktemp -t "$LABEL.verify.XXXXXX.m")"
VERIFY_BINARY="$(mktemp -t "$LABEL.verify.XXXXXX")"
cat >"$VERIFY_SOURCE" <<OBJC
#import <Foundation/Foundation.h>

@protocol MacAwakeHelperXPCProtocol
- (void)statusWithReply:(void (^)(NSDictionary * _Nullable payload, NSError * _Nullable error))reply;
@end

int main(void) {
    @autoreleasepool {
        NSXPCConnection *connection = [[NSXPCConnection alloc] initWithMachServiceName:@"$LABEL" options:NSXPCConnectionPrivileged];
        connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MacAwakeHelperXPCProtocol)];
        [connection resume];

        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        __block int exitCode = 1;

        id<MacAwakeHelperXPCProtocol> proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
            fprintf(stderr, "XPC error: %s\\n", error.localizedDescription.UTF8String);
            dispatch_semaphore_signal(semaphore);
        }];

        [proxy statusWithReply:^(NSDictionary *payload, NSError *error) {
            if (error != nil) {
                fprintf(stderr, "helper status() error: %s\\n", error.localizedDescription.UTF8String);
            } else if (payload != nil) {
                NSLog(@"helper status(): %@", payload);
                exitCode = 0;
            } else {
                fprintf(stderr, "helper status() returned no payload\\n");
            }

            dispatch_semaphore_signal(semaphore);
        }];

        if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0) {
            fprintf(stderr, "helper status() timed out\\n");
            [connection invalidate];
            return 1;
        }

        [connection invalidate];
        return exitCode;
    }
}
OBJC
clang -x objective-c -fobjc-arc "$VERIFY_SOURCE" -framework Foundation -o "$VERIFY_BINARY"
"$VERIFY_BINARY"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found at $APP_PATH" >&2
  exit 1
fi

echo "==> Opening Mac Awake.app"
pkill -x MacAwake >/dev/null 2>&1 || true
open "$APP_PATH"

for _ in {1..20}; do
  if pgrep -x MacAwake >/dev/null 2>&1; then
    app_pid="$(pgrep -x MacAwake | head -n 1)"
    echo "App status: running (pid $app_pid)"
    break
  fi

  sleep 0.25
done

if ! pgrep -x MacAwake >/dev/null 2>&1; then
  echo "error: Mac Awake.app did not start" >&2
  exit 1
fi

echo
cat <<'DONE'
Installation complete. Mac Awake is open and ready in the menu bar.

Try a 5 minute timer first.

If you do not see the menu-bar icon, free one menu-bar slot near the right side
of the menu bar; macOS may hide new status items behind the notch/overflow area.

Emergency recovery:
  sudo pmset -a disablesleep 0
DONE
