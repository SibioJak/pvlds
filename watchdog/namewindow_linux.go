package main

// The name window's Linux leaf (namewindow.go carries
// the law): there is no desktop to hold a window on
// here, and the Linux build never ships - it exists
// to exercise the platform-free session logic in this
// repo's smokes. The leaf hands back a fresh fake
// handle per creation so the tracker's lifecycle (and
// its log edges) runs end to end in those smokes
// exactly as it will on Windows; the title itself is
// asserted by the unit tests.
var nameWindowFakeSeq uintptr

func createNameWindow(_ string) uintptr {
	nameWindowFakeSeq++
	return 0xF1540000 + nameWindowFakeSeq
}

func destroyNameWindow(_ uintptr) {}
