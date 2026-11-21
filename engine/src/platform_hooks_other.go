//go:build !ios

package main

import "github.com/veandco/go-sdl2/sdl"

// Platform hooks; only iOS needs them (see util_ios.go).
func platformBeforeWindow(flags sdl.WindowFlags) sdl.WindowFlags { return flags }
func platformAfterWindow(window *sdl.Window)                     {}
func platformAppSuspended(suspended bool)                        {}
func applyIOSConfigOverrides(cfg *Config)                        {}
