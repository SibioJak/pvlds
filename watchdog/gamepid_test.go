package main

import "testing"

// FIX113: the session's game is the pid the launcher launched
// (gamepid.go). The field shape these fixtures pin
// (pvlds-fix113/droscoe_watchdog.log): the launched player
// (pid 9004) dies at table end while a SECOND process of the
// same exe - the user's editor, pid 17304 - lives on. The old
// gameAlive adopted 17304 as the session's game; the session
// duties then inventoried it, focus-pushed it, and on two
// occasions closed it.

func TestResolveSessionGamePIDContractPidRules(t *testing.T) {
	// Launched pid alive: it is the game, whatever else runs.
	if alive, pid := resolveSessionGamePID(9004, true, []int{17304}, 4242); !alive || pid != 9004 {
		t.Errorf("contract alive with bystander discovered: got (%v, %d), want (true, 9004)", alive, pid)
	}
	// Launched pid DEAD, bystander alive and discovered: the
	// game is dead. This is the droscoe case - the bystander
	// must not be adopted.
	if alive, pid := resolveSessionGamePID(9004, false, []int{17304}, 4242); alive || pid != 9004 {
		t.Errorf("contract dead with bystander discovered: got (%v, %d), want (false, 9004)", alive, pid)
	}
	// Launched pid dead, nothing discovered: still the
	// contract's pid that is reported (dead), not 0.
	if alive, pid := resolveSessionGamePID(9004, false, nil, 4242); alive || pid != 9004 {
		t.Errorf("contract dead, none discovered: got (%v, %d), want (false, 9004)", alive, pid)
	}
}

func TestResolveSessionGamePIDDiscoveryWindow(t *testing.T) {
	// No pid in the contract yet (the launcher's pre-spawn
	// write window): the first discovered pid stands in.
	if alive, pid := resolveSessionGamePID(0, false, []int{17304, 9004}, 4242); !alive || pid != 17304 {
		t.Errorf("pid 0 with discoveries: got (%v, %d), want (true, 17304)", alive, pid)
	}
	// The watchdog never adopts itself.
	if alive, pid := resolveSessionGamePID(0, false, []int{4242}, 4242); alive || pid != 0 {
		t.Errorf("only self discovered: got (%v, %d), want (false, 0)", alive, pid)
	}
	if alive, pid := resolveSessionGamePID(0, false, []int{4242, 9004}, 4242); !alive || pid != 9004 {
		t.Errorf("self then game discovered: got (%v, %d), want (true, 9004)", alive, pid)
	}
	// Nothing running: no game.
	if alive, pid := resolveSessionGamePID(0, false, nil, 4242); alive || pid != 0 {
		t.Errorf("pid 0, none discovered: got (%v, %d), want (false, 0)", alive, pid)
	}
}
