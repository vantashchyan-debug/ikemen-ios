//go:build ios
// +build ios

package vulkan

// iOS: MoltenVK is linked into the app; the engine passes SDL's
// vkGetInstanceProcAddr through SetGetInstanceProcAddr, exactly like macOS,
// so the shared desktop wrapper (vk_wrapper_desktop.c) is used.
// (Ikemen iOS port: the upstream legacy MVK iOS bindings were removed.)

const (
	// UsePlatformIos means enabled support of MoltenVK.
	UsePlatformIos = 1
)
