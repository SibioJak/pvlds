package main

// Shared foreground-fact fixtures for the watchdog's decision
// tests: the field inventories' own vocabulary (class +
// owning pid), with the identities the pinned sessions
// carried. fgOf synthesizes a snapshot whose foreground is a
// window of the given class and owner, with the editor and
// SDL flags the leaves derive - the shape fgwatch_test.go and
// the focus tests build on.

const (
	gamePID = 5264
	vdPID   = 9932
)

func fgOf(class string, pid int) windowState {
	ws := windowState{inputAgeMs: -1}
	ws.fgClass = class
	ws.fgPID = pid
	ws.fgIsGame = pid == gamePID
	ws.fgIsEditor = class == editorWindowClass && pid == gamePID
	ws.fgIsSDL = class == sdlWindowClass && pid == gamePID
	return ws
}
