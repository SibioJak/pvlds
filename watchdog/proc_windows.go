package main

import (
	"os/exec"
	"strings"
	"syscall"
	"unsafe"
)

var (
	kernel32                  = syscall.NewLazyDLL("kernel32.dll")
	procQueryFullProcessImage = kernel32.NewProc("QueryFullProcessImageNameW")
)

const (
	processQueryLimitedInformation = 0x1000
	detachedProcess                = 0x00000008
	createNewProcessGroup          = 0x00000200
)

// snapshotPIDs enumerates every live pid via the Toolhelp snapshot.
func snapshotPIDs() map[int]bool {
	out := map[int]bool{}
	snap, err := syscall.CreateToolhelp32Snapshot(syscall.TH32CS_SNAPPROCESS, 0)
	if err != nil {
		return out
	}
	defer syscall.CloseHandle(snap)
	var entry syscall.ProcessEntry32
	entry.Size = uint32(unsafe.Sizeof(entry))
	if err := syscall.Process32First(snap, &entry); err != nil {
		return out
	}
	for {
		out[int(entry.ProcessID)] = true
		if err := syscall.Process32Next(snap, &entry); err != nil {
			break
		}
	}
	return out
}

func processAlive(pid int) bool {
	if pid <= 0 {
		return false
	}
	return snapshotPIDs()[pid]
}

// processImagePath returns the full image path of a process, or "".
func processImagePath(pid int) string {
	h, err := syscall.OpenProcess(processQueryLimitedInformation, false, uint32(pid))
	if err != nil {
		return ""
	}
	defer syscall.CloseHandle(h)
	buf := make([]uint16, syscall.MAX_PATH*2)
	size := uint32(len(buf))
	r, _, _ := procQueryFullProcessImage.Call(uintptr(h), 0, uintptr(unsafe.Pointer(&buf[0])), uintptr(unsafe.Pointer(&size)))
	if r == 0 {
		return ""
	}
	return syscall.UTF16ToString(buf[:size])
}

func samePath(a, b string) bool {
	return strings.EqualFold(filepathClean(a), filepathClean(b))
}

func filepathClean(p string) string {
	return strings.ReplaceAll(p, "/", "\\")
}

// findPIDsByExe prefers full image-path matches; if none, falls back
// to basename matches from the snapshot's exe names.
func findPIDsByExe(exePath string) []int {
	var full []int
	var base []int
	wantBase := exePath
	if idx := strings.LastIndexAny(wantBase, `\/`); idx >= 0 {
		wantBase = wantBase[idx+1:]
	}
	snap, err := syscall.CreateToolhelp32Snapshot(syscall.TH32CS_SNAPPROCESS, 0)
	if err != nil {
		return nil
	}
	defer syscall.CloseHandle(snap)
	var entry syscall.ProcessEntry32
	entry.Size = uint32(unsafe.Sizeof(entry))
	if err := syscall.Process32First(snap, &entry); err != nil {
		return nil
	}
	for {
		pid := int(entry.ProcessID)
		name := syscall.UTF16ToString(entry.ExeFile[:])
		if strings.EqualFold(name, wantBase) {
			if img := processImagePath(pid); img != "" && samePath(img, exePath) {
				full = append(full, pid)
			} else {
				base = append(base, pid)
			}
		}
		if err := syscall.Process32Next(snap, &entry); err != nil {
			break
		}
	}
	if len(full) > 0 {
		return full
	}
	return base
}

// startDetached starts the process in its own group, detached from
// any console, and returns its pid without waiting on it.
func startDetached(path string, args []string) (int, error) {
	cmd := exec.Command(path, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{
		CreationFlags: detachedProcess | createNewProcessGroup,
		HideWindow:    false,
	}
	if err := cmd.Start(); err != nil {
		return 0, err
	}
	pid := cmd.Process.Pid
	go cmd.Wait() // reap the handle; we never read the result
	return pid, nil
}
