package main

import "testing"

// The sighting rule (sighting.go), folded the way the platform
// leaves fold it: classify the observation, then observe it.

func foldSight(s *playerSighting, sessionID int, obs []windowObs) (bool, bool) {
	candidate, rule := classifyPlayerCandidate(obs)
	return s.observe(sessionID, candidate, rule)
}

var (
	obsEditorOnly = []windowObs{
		{class: "VPinball", width: 1920, height: 1080},
	}
	obsEditorPlusBigUnknown = []windowObs{
		{class: "VPinball", width: 1280, height: 900},
		{class: "SDL_app", width: 1024, height: 768},
	}
	obsEditorPlusTooltip = []windowObs{
		{class: "VPinball", width: 1280, height: 900},
		{class: "ToolTip", width: 120, height: 40},
	}
	obsEditorPlusVPPlayer = []windowObs{
		{class: "VPinball", width: 1280, height: 900},
		{class: "VPPlayer", width: 1920, height: 1080},
	}
)

// The faf0673 lesson, preserved: editor alone, however large,
// however long, is a load state - never a sighting.
func TestSightingEditorOnlyNeverSights(t *testing.T) {
	s := &playerSighting{}
	for i := 0; i < 5; i++ {
		present, stamped := foldSight(s, 1, obsEditorOnly)
		if present || stamped {
			t.Fatalf("obs %d: editor-only observation presented/stamped (present=%v stamped=%v)", i, present, stamped)
		}
	}
	if ok, _ := s.hasSighted(1); ok {
		t.Fatal("editor-only session latched a sighting")
	}
}

// A substantial non-editor window beside the editor: present only
// from the second consecutive poll, stamped then, rule named.
func TestSightingClassFreeNeedsPersistence(t *testing.T) {
	s := &playerSighting{}
	present, stamped := foldSight(s, 1, obsEditorPlusBigUnknown)
	if present || stamped {
		t.Fatalf("first poll: present=%v stamped=%v, want both false (persistence gate)", present, stamped)
	}
	if ok, _ := s.hasSighted(1); ok {
		t.Fatal("sighting latched on the first poll of a class-free candidate")
	}
	present, stamped = foldSight(s, 1, obsEditorPlusBigUnknown)
	if !present || !stamped {
		t.Fatalf("second poll: present=%v stamped=%v, want both true", present, stamped)
	}
	ok, rule := s.hasSighted(1)
	if !ok || rule != sightRuleClassFree {
		t.Fatalf("hasSighted = %v, %q; want true, %q", ok, rule, sightRuleClassFree)
	}
	// Persistence continues: still present on later polls, no
	// second stamp.
	present, stamped = foldSight(s, 1, obsEditorPlusBigUnknown)
	if !present || stamped {
		t.Fatalf("third poll: present=%v stamped=%v, want true/false", present, stamped)
	}
}

// A tooltip-sized unknown window is not a playfield, at any
// persistence.
func TestSightingTooltipUnknownNeverSights(t *testing.T) {
	s := &playerSighting{}
	for i := 0; i < 4; i++ {
		present, stamped := foldSight(s, 1, obsEditorPlusTooltip)
		if present || stamped {
			t.Fatalf("obs %d: tooltip-sized window presented/stamped", i)
		}
	}
	if ok, _ := s.hasSighted(1); ok {
		t.Fatal("tooltip-sized window latched a sighting")
	}
}

// The classic path: a VPPlayer-class window sights on the FIRST
// poll, exactly as the old rule behaved.
func TestSightingVPPlayerImmediate(t *testing.T) {
	s := &playerSighting{}
	present, stamped := foldSight(s, 1, obsEditorPlusVPPlayer)
	if !present || !stamped {
		t.Fatalf("VPPlayer first poll: present=%v stamped=%v, want both true", present, stamped)
	}
	if ok, rule := s.hasSighted(1); !ok || rule != sightRuleClassic {
		t.Fatalf("hasSighted = %v, %q; want true, %q", ok, rule, sightRuleClassic)
	}
}

// A candidate that flickers out restarts its persistence streak;
// the latched sighting survives the flicker but presence drops
// with the window (that drop is the editor landing).
func TestSightingFlickerResetsStreakNotLatch(t *testing.T) {
	s := &playerSighting{}
	foldSight(s, 1, obsEditorPlusBigUnknown) // streak 1
	present, _ := foldSight(s, 1, obsEditorOnly)
	if present {
		t.Fatal("candidate gone: present must drop at once")
	}
	present, stamped := foldSight(s, 1, obsEditorPlusBigUnknown) // streak 1 again
	if present || stamped {
		t.Fatalf("flickered candidate: present=%v stamped=%v on its first poll back, want false/false", present, stamped)
	}
	present, stamped = foldSight(s, 1, obsEditorPlusBigUnknown) // streak 2
	if !present || !stamped {
		t.Fatalf("second consecutive poll: present=%v stamped=%v, want true/true", present, stamped)
	}
	// Presence can drop after sighting (the exit itself) without
	// unlatching the sighting.
	present, _ = foldSight(s, 1, obsEditorOnly)
	if present {
		t.Fatal("player gone after sighting: present must be false")
	}
	if ok, _ := s.hasSighted(1); !ok {
		t.Fatal("sighting unlatched when the player window closed")
	}
}

// A new session starts unsighted, whatever the last one did.
func TestSightingSessionReset(t *testing.T) {
	s := &playerSighting{}
	foldSight(s, 1, obsEditorPlusVPPlayer)
	if ok, _ := s.hasSighted(1); !ok {
		t.Fatal("session 1 should have sighted")
	}
	if ok, _ := s.hasSighted(2); ok {
		t.Fatal("session 2 inherited session 1's sighting")
	}
	present, _ := foldSight(s, 2, obsEditorPlusBigUnknown)
	if present {
		t.Fatal("session 2's first class-free poll presented - the streak is per-session")
	}
}
