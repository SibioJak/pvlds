//go:build !windows

package main

// Session-close sending off Windows: there is no VPX and no window
// messaging here. The Linux build exists to exercise the DECISION
// logic (closer.go) end to end in smokes - the watchdog logs each
// decision it reaches, and the smoke's stub process plays VPX's
// part (including dying, as VPX would when a close lands). The
// shipping Windows leaves are in closer_windows.go.

func sendFrontEndControlsClose(_ int) bool { return false }

func sendEditorClose(_ uintptr) bool { return false }
