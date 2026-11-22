//go:build ios

package main

/*
#cgo CFLAGS: -DSDL_MAIN_HANDLED
#include <stdlib.h>
#include <stdint.h>

// Implemented by the native iOS shell (ios/src/*.m), resolved at final link.
extern void        IKOverlayInstall(void);
extern void        IKOverlayInstallWindow(void *sdlWindow);
extern void        IKOverlaySetSuspended(int suspended);
extern const char* IKPreferredLanguage(void);
*/
import "C"

import (
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"strings"
	"unsafe"

	findfont "github.com/flopp/go-findfont"
	"github.com/veandco/go-sdl2/sdl"
)

// Folders shipped read-only inside the app bundle (Ikemen.app/game/<dir>).
// They are symlinked into the writable work directory. If the user puts a real
// folder with the same name into Documents/Ikemen (Files app), it is used
// instead, which allows modding without rebuilding the .ipa.
var iosAssetDirs = []string{"data", "external", "font", "chars", "stages", "sound", "video", "art"}

//export SDL_main
func SDL_main(argc C.int, argv **C.char) C.int {
	runtime.LockOSThread()

	// iPhone 12 Pro has 6 GB RAM; iOS kills apps well before that. A soft
	// limit makes the GC work harder instead of letting jetsam kill us.
	debug.SetMemoryLimit(1600 << 20)

	// Hints that must be set before SDL_Init / window creation.
	sdl.SetHint("SDL_IOS_ORIENTATIONS", "LandscapeLeft LandscapeRight")
	sdl.SetHint("SDL_IOS_HIDE_HOME_INDICATOR", "2") // dim + defer edge gestures
	sdl.SetHint("SDL_IOS_IDLE_TIMER_DISABLED", "1")
	sdl.SetHint("SDL_ACCELEROMETER_AS_JOYSTICK", "0")
	// Point SDL straight at the bundled MoltenVK (Vulkan -> Metal).
	if exe, err := os.Executable(); err == nil {
		mvk := filepath.Join(filepath.Dir(exe), "Frameworks", "MoltenVK.framework", "MoltenVK")
		if _, err := os.Stat(mvk); err == nil {
			sdl.SetHint("SDL_VULKAN_LIBRARY", mvk)
		}
	}

	if err := prepareIOSWorkdir(); err != nil {
		ShowErrorDialog("Failed to prepare game files:\n" + err.Error())
		return 1
	}
	if len(os.Args) == 0 {
		os.Args = []string{"Ikemen_GO"}
	} else {
		os.Args = os.Args[:1] // ignore launch arguments from UIKit
	}
	realMain()
	return 0
}

func iosBundleGameDir() string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepath.Join(filepath.Dir(exe), "game")
}

func prepareIOSWorkdir() error {
	bundle := iosBundleGameDir()
	home := os.Getenv("HOME")
	if home == "" {
		return fmt.Errorf("HOME is not set")
	}
	work := filepath.Join(home, "Documents", "Ikemen")
	if err := os.MkdirAll(work, 0755); err != nil {
		return err
	}

	for _, d := range iosAssetDirs {
		src := filepath.Join(bundle, d)
		if _, err := os.Stat(src); err != nil {
			continue
		}
		dst := filepath.Join(work, d)
		if fi, err := os.Lstat(dst); err == nil {
			if fi.Mode()&os.ModeSymlink == 0 {
				continue // user override (real folder)
			}
			// The bundle path changes on every reinstall/update: always refresh.
			os.Remove(dst)
		}
		if err := os.Symlink(src, dst); err != nil {
			return fmt.Errorf("symlink %s: %w", d, err)
		}
	}

	// Seed writable save/ (config.ini, stats...) without overwriting user data.
	seed := filepath.Join(bundle, "save")
	if _, err := os.Stat(seed); err == nil {
		filepath.WalkDir(seed, func(p string, d fs.DirEntry, err error) error {
			if err != nil {
				return nil
			}
			rel, _ := filepath.Rel(seed, p)
			target := filepath.Join(work, "save", rel)
			if d.IsDir() {
				os.MkdirAll(target, 0755)
				return nil
			}
			if _, err := os.Stat(target); err == nil {
				return nil
			}
			return copyFileIOS(p, target)
		})
	}
	for _, d := range []string{"save/replays", "save/logs", "cache"} {
		os.MkdirAll(filepath.Join(work, d), 0755)
	}
	return os.Chdir(work)
}

func copyFileIOS(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

// Runtime-only config tweaks for iPhone (not written back to config.ini).
func applyIOSConfigOverrides(cfg *Config) {
	cfg.Video.RenderMode = "Vulkan 1.3"
	cfg.Video.Fullscreen = true
	cfg.Video.Borderless = false
	cfg.Video.WindowWidth, cfg.Video.WindowHeight = 0, 0
	cfg.Video.RendererDebugMode = false
	// Shadow maps need layered rendering that MoltenVK only partly exposes.
	cfg.Video.EnableModelShadow = false
	// Apple GPUs resolve MSAA on-tile, but >4x is wasted on a 460 ppi screen.
	if cfg.Video.MSAA > 4 {
		cfg.Video.MSAA = 4
	}
	if cfg.Video.Framerate <= 0 || cfg.Video.Framerate > 60 {
		cfg.Video.Framerate = 60
	}
	// Internal resolution: Veils of Blood is authored at 1280x720. Rendering more than that only costs GPU time
	// and battery (the swapchain itself stays at the native 2532x1170, so text and lines remain sharp).
	if cfg.Video.GameWidth > 1280 || cfg.Video.GameHeight > 720 {
		cfg.Video.GameWidth, cfg.Video.GameHeight = 1280, 720
	}
	// Decoding whole BGM tracks to RAM costs hundreds of MB with FLAC music.
	cfg.Sound.BGMRAMBuffer = false
	cfg.Debug.DumpLuaTables = false
}

func platformBeforeWindow(flags sdl.WindowFlags) sdl.WindowFlags {
	return flags | sdl.WINDOW_ALLOW_HIGHDPI | sdl.WINDOW_FULLSCREEN | sdl.WINDOW_BORDERLESS
}

func platformAfterWindow(window *sdl.Window) {
	// Pass SDL's own window: the native shell takes its UIWindow from it instead of searching the
	// app's window list (SDL2 windows are not attached to a UIScene, so on iOS 26+ that search finds nothing).
	C.IKOverlayInstallWindow(unsafe.Pointer(window))
}

func platformAppSuspended(suspended bool) {
	if suspended {
		TouchSetState(int(touchPlayerSlot.Load()), 0)
		C.IKOverlaySetSuspended(1)
	} else {
		C.IKOverlaySetSuspended(0)
	}
}

// ---------------------------------------------------------------------------
// Bridge called from the native touch overlay (main thread, inside SDL pump).

//export IkemenTouchSetState
func IkemenTouchSetState(player C.int, mask C.uint32_t) {
	TouchSetState(int(player), uint32(mask))
}

//export IkemenTouchKey
func IkemenTouchKey(keycode C.int, down C.int) {
	TouchKey(int(keycode), down != 0)
}

//export IkemenGameIsRunning
func IkemenGameIsRunning() C.int {
	if sys.gameRunning {
		return 1
	}
	return 0
}

// IkemenPlayerFacing returns 1 if the player's root char faces right, -1 if
// left. Lets touch macros use facing-relative directions (F/B, numpad 236...).
//
//export IkemenPlayerFacing
func IkemenPlayerFacing(player C.int) C.int {
	p := int(player)
	if !sys.gameRunning || p < 0 || p >= len(sys.chars) || len(sys.chars[p]) == 0 || sys.chars[p][0] == nil {
		return 1
	}
	if sys.chars[p][0].facing < 0 {
		return -1
	}
	return 1
}

// ---------------------------------------------------------------------------
// Platform utility implementations (desktop versions live in util_desktop.go)

func NewLogWriter() io.Writer {
	return os.Stderr
}

func ShowInfoDialog(message, title string) {
	fmt.Fprintf(os.Stderr, "INFO [%s]: %s\n", title, message)
	sdl.ShowSimpleMessageBox(sdl.MESSAGEBOX_INFORMATION, title, message, nil)
}

func ShowErrorDialog(message string) {
	fmt.Fprintf(os.Stderr, "ERROR: %s\n", message)
	sdl.ShowSimpleMessageBox(sdl.MESSAGEBOX_ERROR, "I.K.E.M.E.N Error", message, nil)
}

func LoadFntTtf(f *Fnt, fontfile string, filename string, height int32) {
	fileDir := SearchFile(filename, []string{fontfile, sys.motif.Def, "", "data/"}, "font/")
	if fp := FileExist(fileDir); len(fp) == 0 {
		var err error
		fileDir, err = findfont.Find(fileDir)
		if err != nil {
			panic(fmt.Errorf("failed to find ttf font %v: %w", fileDir, err))
		}
	}
	if height == -1 {
		height = int32(f.Size[1])
	} else {
		f.Size[1] = uint16(height)
	}
	ttf, err := gfxFont.LoadFont(fileDir, height, int(sys.gameWidth), int(sys.gameHeight))
	if err != nil {
		panic(fmt.Errorf("failed to load ttf font %v: %w", fileDir, err))
	}
	f.ttf = ttf.(Font)
	f.palettes = make([][256]uint32, 1)
	for i := 0; i < 256; i++ {
		f.palettes[0][i] = 0
	}
}

func selectRenderer(cfgVal string) (Renderer, FontRenderer) {
	return &Renderer_VK{}, &FontRenderer_VK{}
}

func Logcat(s string) {
	fmt.Fprintln(os.Stderr, s)
}

func osPreferredLanguage() string {
	if p := C.IKPreferredLanguage(); p != nil {
		return strings.ToLower(C.GoString(p))
	}
	return ""
}
