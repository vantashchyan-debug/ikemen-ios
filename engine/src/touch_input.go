package main

import "sync/atomic"

// Virtual (on-screen / touch) controller.
//
// A platform layer (the native UIKit overlay on iOS) reports which game
// buttons are held as a bitmask. The mask is OR-ed into the local input of the
// configured player slot inside InputReader.LocalInput, so it behaves exactly
// like a keyboard or gamepad: menus, fights, training, command buffers etc.
//
// Bit order matches the [14]bool layout used by GetKeyboardState:
//
//	0 U, 1 D, 2 L, 3 R, 4 a, 5 b, 6 c, 7 x, 8 y, 9 z, 10 s, 11 d, 12 w, 13 m
const touchButtonCount = 14

var (
	touchButtonMask atomic.Uint32
	touchPlayerSlot atomic.Int32 // 0-based player index the touch pad drives
)

// TouchSetState replaces the full virtual button state.
func TouchSetState(player int, mask uint32) {
	if player < 0 || player > 7 {
		player = 0
	}
	touchPlayerSlot.Store(int32(player))
	touchButtonMask.Store(mask & (1<<touchButtonCount - 1))
}

// TouchKey injects a raw keyboard key (SDL keycode) press or release.
// Used for system keys such as Escape, Pause or F-keys from touch buttons.
func TouchKey(keycode int, down bool) {
	var noMods ModifierKey
	if down {
		OnKeyPressed(Key(keycode), noMods)
	} else {
		OnKeyReleased(Key(keycode), noMods)
	}
}

// touchInputFor returns the virtual pad state for the given 0-based player.
func touchInputFor(in int) (out [touchButtonCount]bool, ok bool) {
	mask := touchButtonMask.Load()
	if mask == 0 || int(touchPlayerSlot.Load()) != in {
		return out, false
	}
	for i := 0; i < touchButtonCount; i++ {
		out[i] = mask&(1<<uint(i)) != 0
	}
	return out, true
}
