//go:build !windows && !linux

package main

// The name window off Windows/Linux (namewindow.go
// carries the law): no window is ever created, so the
// raise logs its could-not-create line and the launch
// goes ahead without the feed - the honest shape for
// a platform with no desktop wired up. The shipping
// build is Windows; the logic-exercising build is
// Linux; both have real leaves.
func createNameWindow(_ string) uintptr { return 0 }

func destroyNameWindow(_ uintptr) {}
