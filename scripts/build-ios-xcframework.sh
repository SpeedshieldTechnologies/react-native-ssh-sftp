#!/bin/bash
# Builds ios/RNSSHClientDeps.xcframework from ios/XCFrameworkBuild (the Citadel wrapper package).
#
# Not committed to git - built fresh at publish time and shipped as a binary in the npm
# tarball, the same way lib/ is built from src/ and shipped without being checked in.
#
# The recipe (validated by hand before being scripted):
#   1. Archive the wrapper for iOS device and iOS Simulator via xcodebuild. The wrapper's
#      Package.swift scopes -enable-library-evolution to just this one target, not globally -
#      Citadel's own swift-nio dependency has real @inlinable/library-evolution incompatibilities
#      that block a global evolution build. Only our own thin wrapper needs a stable interface;
#      Citadel is consumed via @_implementationOnly import and never needs one.
#   2. Combine every target's .o files (our wrapper + all of Citadel's dependency tree) into one
#      static archive per slice with libtool. Swift/Xcode does not do this step for us.
#   3. Assemble a Headers/ directory per slice: our own .swiftmodule (with its .swiftinterface,
#      which is what makes `xcodebuild -create-xcframework` accept a non-ABI-stable static
#      archive at all) plus every dependency's raw Clang modulemap + headers, copied straight
#      from the resolved SPM checkouts - required for the C targets in the dependency graph
#      (CNIOPosix, CCryptoBoringSSL, etc) to resolve at all.
#   4. xcodebuild -create-xcframework the two slices together.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER_DIR="$ROOT_DIR/ios/XCFrameworkBuild"
BUILD_DIR="$WRAPPER_DIR/build"
OUT_DIR="$ROOT_DIR/ios"
XCFRAMEWORK_NAME="RNSSHClientDeps"
XCFRAMEWORK_PATH="$OUT_DIR/$XCFRAMEWORK_NAME.xcframework"

rm -rf "$BUILD_DIR" "$XCFRAMEWORK_PATH"

archive_and_assemble() {
  local platform_arg="$1"      # e.g. "generic/platform=iOS"
  local derived_data="$2"      # e.g. build/DerivedData-device
  local products_subdir="$3"   # e.g. Release-iphoneos
  local slice_dir="$4"         # e.g. build/out/device

  echo "==> Building for $platform_arg"
  (cd "$WRAPPER_DIR" && xcodebuild build \
    -scheme "$XCFRAMEWORK_NAME" \
    -destination "$platform_arg" \
    -derivedDataPath "$derived_data" \
    -configuration Release \
    SKIP_INSTALL=NO \
    -quiet)

  local prod="$derived_data/Build/Products/$products_subdir"
  local intermediates="$derived_data/Build/Intermediates.noindex/$XCFRAMEWORK_NAME.build/$products_subdir/$XCFRAMEWORK_NAME.build/Objects-normal"
  local checkouts="$derived_data/SourcePackages/checkouts"

  mkdir -p "$slice_dir/Modules"

  # 1. Combine every target's object file into one static archive.
  libtool -static -o "$slice_dir/lib$XCFRAMEWORK_NAME.a" "$prod"/*.o 2>&1 | grep -v "has no symbols" || true

  # 2. Copy every Swift target's compiled module.
  cp -R "$prod"/*.swiftmodule "$slice_dir/Modules/" 2>/dev/null || true

  # 3. Inject our own module's .swiftinterface (emitted only for this target - see Package.swift)
  #    so -create-xcframework accepts the archive.
  for arch_dir in "$intermediates"/*/; do
    local arch triple
    arch="$(basename "$arch_dir")"
    for f in "$arch_dir/$XCFRAMEWORK_NAME.swiftinterface" "$arch_dir/$XCFRAMEWORK_NAME.private.swiftinterface"; do
      [ -e "$f" ] || continue
      # Map arch dir name -> the triple Xcode named the .swiftmodule slice after.
      triple="$(basename "$(find "$slice_dir/Modules/$XCFRAMEWORK_NAME.swiftmodule" -iname "*$arch*.swiftmodule" | head -1)" .swiftmodule)"
      [ -n "$triple" ] || continue
      cp "$f" "$slice_dir/Modules/$XCFRAMEWORK_NAME.swiftmodule/$triple.$(basename "$f" | sed "s/^$XCFRAMEWORK_NAME\.//")"
    done
  done

  # 4. Copy every C target's modulemap + headers (auto-generated ones reference their original
  #    checkout path by absolute path, which is fine for local validation but not for a
  #    redistributable artifact - so we also pull the real, checked-in modulemaps directly).
  find "$checkouts" -path "*/include/module.modulemap" | while read -r mm; do
    local inc_dir target_name
    inc_dir="$(dirname "$mm")"
    target_name="$(basename "$(dirname "$inc_dir")")"
    for f in "$inc_dir"/*; do
      local base
      base="$(basename "$f")"
      if [ "$base" = "module.modulemap" ]; then
        cp "$f" "$slice_dir/Modules/$target_name.modulemap"
      else
        cp "$f" "$slice_dir/Modules/$base" 2>/dev/null || true
      fi
    done
  done
}

archive_and_assemble "generic/platform=iOS" "$BUILD_DIR/DerivedData-device" "Release-iphoneos" "$BUILD_DIR/out/device"
archive_and_assemble "generic/platform=iOS Simulator" "$BUILD_DIR/DerivedData-sim" "Release-iphonesimulator" "$BUILD_DIR/out/sim"

echo "==> Creating $XCFRAMEWORK_PATH"
xcodebuild -create-xcframework \
  -library "$BUILD_DIR/out/device/lib$XCFRAMEWORK_NAME.a" -headers "$BUILD_DIR/out/device/Modules" \
  -library "$BUILD_DIR/out/sim/lib$XCFRAMEWORK_NAME.a" -headers "$BUILD_DIR/out/sim/Modules" \
  -output "$XCFRAMEWORK_PATH"

echo "==> Done: $XCFRAMEWORK_PATH"
