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

case "$(uname -s)" in
	Linux)  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 "$GO" build -ldflags "-s -w" -o build/pvlds_watchdog . ;;
	Darwin) CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 "$GO" build -ldflags "-s -w" -o build/pvlds_watchdog . ;;
esac
echo "host:    build/pvlds_watchdog"
