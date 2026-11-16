#!/bin/sh
# Builds the PVLDS watchdog for Windows (the shipping artifact) and
# for the host platform (smoke tests). Pure Go stdlib - no cgo, so
# the Windows build is a plain cross-compile. Output is gitignored:
# the exes are build artifacts, delivered beside the launcher exe,
# never committed.
set -e
cd "$(dirname "$0")"
mkdir -p build
GO="${GO:-go}"

CGO_ENABLED=0 GOOS=windows GOARCH=amd64 "$GO" build -ldflags "-H windowsgui -s -w" -o build/pvlds_watchdog.exe .
echo "windows: build/pvlds_watchdog.exe"

# FIX129 format gate: the shipping artifact MUST be a Windows PE
# binary, verified here at the moment it is produced. In FIX128 the
# payload was assembled by hand and the extensionless host build
# (build/pvlds_watchdog, a Linux ELF) was copied under the
# LaunchPinWatchdog.exe name - it passed every audit because no
# audit ever checked the binary format. Never again.
if command -v file >/dev/null 2>&1; then
	case "$(file -b build/pvlds_watchdog.exe)" in
		*"PE32+ executable"*"MS Windows"*) echo "format check: build/pvlds_watchdog.exe is PE32+ for MS Windows" ;;
		*) echo "FATAL: build/pvlds_watchdog.exe is NOT a Windows PE binary:" >&2; file build/pvlds_watchdog.exe >&2; exit 1 ;;
	esac
else
	[ "$(head -c 2 build/pvlds_watchdog.exe)" = "MZ" ] || { echo "FATAL: build/pvlds_watchdog.exe lacks the MZ header" >&2; exit 1; }
	echo "format check: build/pvlds_watchdog.exe carries the MZ header (file(1) unavailable)"
fi

case "$(uname -s)" in
	Linux)  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 "$GO" build -ldflags "-s -w" -o build/pvlds_watchdog . ;;
	Darwin) CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 "$GO" build -ldflags "-s -w" -o build/pvlds_watchdog . ;;
esac
echo "host:    build/pvlds_watchdog"
