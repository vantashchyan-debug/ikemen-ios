#!/usr/bin/env bash
# Builds Ikemen GO for iOS (arm64, iOS 14+) and produces an UNSIGNED .ipa.
# Runs on macOS with Xcode (GitHub Actions "macos-14"/"macos-15" runners work).
#
#   ios/build_ios.sh                 -> build-ios/Ikemen_GO-engine.ipa (engine only)
#   GAME_DIR=/path/to/game ios/build_ios.sh
#                                    -> build-ios/Ikemen_GO.ipa (with game assets)
#
# Without GAME_DIR the .ipa contains only the engine; add your game on Linux
# with ios/make_ipa.sh (no Mac needed for that step).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD_DIR:-$ROOT/build-ios}"
PREFIX="$BUILD/prefix"
DL="$BUILD/downloads"
FW="$BUILD/frameworks"
MIN_IOS=14.0
SDL_VER="${SDL_VER:-2.32.10}"
MVK_VER="${MVK_VER:-v1.4.2}"
XMP_VER="${XMP_VER:-4.7.4}"
VERSION="${APP_VERSION:-1.0.0}"
BUILD_NO="${APP_BUILD:-$(date +%Y%m%d%H%M)}"
BUNDLE_ID="${BUNDLE_ID:-com.ikemen.go.ios}"
DISPLAY_NAME="${DISPLAY_NAME:-Ikemen GO}"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

command -v xcrun >/dev/null || { echo "xcrun not found: this script needs macOS + Xcode" >&2; exit 1; }
for tool in cmake go pkg-config; do
	command -v "$tool" >/dev/null || { echo "missing tool: $tool (brew install $tool)" >&2; exit 1; }
done

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
CLANG="$(xcrun --sdk iphoneos -f clang)"
ARCH_FLAGS=(-arch arm64 -isysroot "$SDK" "-miphoneos-version-min=$MIN_IOS")
mkdir -p "$PREFIX" "$DL" "$FW"

fetch() { # url out
	if [ ! -s "$2" ]; then
		curl -fL --retry 3 -o "$2.part" "$1"
		mv "$2.part" "$2"
	fi
}

cmake_ios() { # src build [extra args...]
	local src="$1" bld="$2"; shift 2
	cmake -S "$src" -B "$bld" \
		-DCMAKE_SYSTEM_NAME=iOS \
		-DCMAKE_OSX_SYSROOT=iphoneos \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" \
		-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
		"$@"
	cmake --build "$bld" --config Release -j "$JOBS"
	cmake --install "$bld" --config Release
}

# ---------------------------------------------------------------- SDL2
if [ ! -f "$PREFIX/lib/libSDL2.a" ]; then
	log "SDL2 $SDL_VER"
	fetch "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VER/SDL2-$SDL_VER.tar.gz" "$DL/sdl2.tar.gz"
	rm -rf "$BUILD/SDL2-src" && mkdir -p "$BUILD/SDL2-src"
	tar -xzf "$DL/sdl2.tar.gz" -C "$BUILD/SDL2-src" --strip-components=1
	cmake_ios "$BUILD/SDL2-src" "$BUILD/SDL2-build" \
		-DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST=OFF \
		-DSDL_VULKAN=ON -DSDL_METAL=ON
fi

# ---------------------------------------------------------------- libxmp
if [ ! -f "$PREFIX/lib/libxmp.a" ]; then
	log "libxmp $XMP_VER"
	fetch "https://github.com/libxmp/libxmp/releases/download/libxmp-$XMP_VER/libxmp-$XMP_VER.tar.gz" "$DL/libxmp.tar.gz"
	rm -rf "$BUILD/xmp-src" && mkdir -p "$BUILD/xmp-src"
	tar -xzf "$DL/libxmp.tar.gz" -C "$BUILD/xmp-src" --strip-components=1
	cmake_ios "$BUILD/xmp-src" "$BUILD/xmp-build" -DBUILD_SHARED=OFF -DBUILD_STATIC=ON
	# some versions name it libxmp-static.a
	[ -f "$PREFIX/lib/libxmp.a" ] || cp "$(find "$PREFIX/lib" -name 'libxmp*.a' | head -1)" "$PREFIX/lib/libxmp.a"
fi

# ---------------------------------------------------------------- MoltenVK
if [ ! -d "$FW/MoltenVK.framework" ]; then
	log "MoltenVK $MVK_VER"
	fetch "https://github.com/KhronosGroup/MoltenVK/releases/download/$MVK_VER/MoltenVK-ios.tar" "$DL/MoltenVK-ios.tar"
	rm -rf "$BUILD/mvk" && mkdir -p "$BUILD/mvk"
	tar -xf "$DL/MoltenVK-ios.tar" -C "$BUILD/mvk"
	src="$(find "$BUILD/mvk" -path '*dynamic/MoltenVK.xcframework/ios-arm64/MoltenVK.framework' -type d | head -1)"
	[ -n "$src" ] || { echo "MoltenVK.framework (ios-arm64) not found in archive" >&2; exit 1; }
	cp -R "$src" "$FW/"
fi

# ---------------------------------------------------------------- Go engine
log "Go engine (c-archive)"
export CGO_ENABLED=1 GOOS=ios GOARCH=arm64 GOEXPERIMENT=arenas GOFLAGS=-mod=mod
export CC="$CLANG ${ARCH_FLAGS[*]}"
export CXX="$(xcrun --sdk iphoneos -f clang++) ${ARCH_FLAGS[*]}"
export CGO_CFLAGS="-O2 -I$PREFIX/include -I$PREFIX/include/SDL2 -Wno-deprecated-declarations -Wno-unused-command-line-argument"
export CGO_LDFLAGS="-L$PREFIX/lib -F$FW"
# SDL2's pkg-config uses -Wl,-weak_framework,... which cgo rejects by default.
# (c-archive does not link anyway; the real link happens below.)
export CGO_LDFLAGS_ALLOW='.*' CGO_CFLAGS_ALLOW='.*'
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
(
	cd "$ROOT/engine"
	go build -buildmode=c-archive -tags novideo -trimpath \
		-ldflags "-s -w -X 'main.Version=$VERSION-ios' -X 'main.BuildTime=$(date -u '+%Y.%m.%d')'" \
		-o "$BUILD/libikemen.a" ./src
)

# ---------------------------------------------------------------- link app
log "Link Ikemen.app"
APP="$BUILD/Payload/Ikemen.app"
rm -rf "$BUILD/Payload" && mkdir -p "$APP/Frameworks"
SDL_LIBS="$(pkg-config --static --libs sdl2)"
# shellcheck disable=SC2086
"$CLANG" "${ARCH_FLAGS[@]}" -fobjc-arc -fmodules -O2 \
	-I"$PREFIX/include/SDL2" -I"$PREFIX/include" -I"$ROOT/ios/src" \
	"$ROOT"/ios/src/*.m \
	"$BUILD/libikemen.a" \
	$SDL_LIBS -lxmp \
	-F"$FW" -framework MoltenVK \
	-framework UIKit -framework Foundation -framework Metal -framework QuartzCore -framework CoreGraphics \
	-framework AVFoundation -framework AudioToolbox -framework CoreAudio -framework CoreMotion \
	-framework GameController -framework CoreHaptics -framework CoreBluetooth -framework IOSurface \
	-framework Security -framework CoreFoundation -framework OpenGLES \
	-lc++ -liconv -lresolv -lm \
	-Wl,-rpath,@executable_path/Frameworks -Wl,-dead_strip \
	-o "$APP/Ikemen"

cp -R "$FW/MoltenVK.framework" "$APP/Frameworks/"
sed -e "s|__BUNDLE_ID__|$BUNDLE_ID|" -e "s|__DISPLAY_NAME__|$DISPLAY_NAME|" \
	-e "s|__VERSION__|$VERSION|" -e "s|__BUILD__|$BUILD_NO|" \
	-e "s|__SDK_NAME__|iphoneos$SDK_VERSION|" -e "s|__SDK_VERSION__|$SDK_VERSION|" \
	"$ROOT/ios/resources/Info.plist" > "$APP/Info.plist"
plutil -lint "$APP/Info.plist"
printf 'APPL????' > "$APP/PkgInfo"
sips -z 120 120 "$ROOT/ios/resources/icon.png" --out "$APP/AppIcon60x60@2x.png" >/dev/null
sips -z 180 180 "$ROOT/ios/resources/icon.png" --out "$APP/AppIcon60x60@3x.png" >/dev/null
mkdir -p "$APP/game"

# Ad-hoc signature so the bundle is structurally valid; Sideloadly/AltStore re-sign it.
codesign --force --sign - "$APP/Frameworks/MoltenVK.framework" || true
codesign --force --sign - "$APP" || true

OUT="$BUILD/Ikemen_GO-engine.ipa"
if [ -n "${GAME_DIR:-}" ]; then
	log "Adding game assets from $GAME_DIR"
	python3 "$ROOT/ios/package_game.py" --app "$APP" --game "$GAME_DIR"
	codesign --force --sign - "$APP" || true
	OUT="$BUILD/Ikemen_GO.ipa"
fi

log "Packaging $OUT"
rm -f "$OUT"
(cd "$BUILD" && /usr/bin/zip -qry "$OUT" Payload)
ls -lh "$OUT"
