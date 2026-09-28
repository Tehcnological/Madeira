#!/bin/bash
# Stage 5: native iOS unix-side static libraries that are NOT committed:
#   app/Madeira/libntdll_unix.a      (wine ntdll + crypto/net/dwrite unixlibs)
#   app/Madeira/libwin32u_unix.a     (wine win32u + merged freetype)
#   app/Madeira/libwineserver.a      (wineserver-as-thread, symbol-renamed)
#   app/Madeira/libdxmt_combined.a   (DXMT unix side + airconv + LLVM)
set -euo pipefail
source "$GITHUB_ACTION_PATH/common.sh"

cd "$REPO"

ensure_submodule wine
ensure_submodule research/dxmt

# Sub-builds write compiler diagnostics to obj/*.err and only print file
# names. On failure, dump the non-empty ones so the annotation shows them.
run_build() {
    local dir=$1; shift
    local rc=0
    bash "$dir/build.sh" "$@" || rc=$?
    for f in "$dir"/obj/*.err "$dir"/obj/err-*.txt; do
        [ -s "$f" ] || continue
        grep -q "error:" "$f" || continue
        echo "--- compile errors in $f"
        grep "error:" "$f" | head -n 8
    done
    [ "$rc" -eq 0 ] || exit "$rc"
}

echo "==> [5a] ntdll-unix"
run_build build/ntdll-unix
file app/Madeira/libntdll_unix.a

echo "==> [5b] win32u-unix"
run_build build/win32u-unix
file app/Madeira/libwin32u_unix.a

echo "==> [5c] wineserver (build base archive from wine/server, then patch)"
bash "$GITHUB_ACTION_PATH/build-wineserver-base.sh"
run_build build/wineserver all
file app/Madeira/libwineserver.a

echo "==> [5d] dxmt-ios unix side + LLVM combine"
run_build build/dxmt-ios
# Without Apple's Metal Shader Converter package the madeira-d3d12 objects are
# skipped, but winemetal (unix call 127) and ContentView.swift still reference
# them. Link a stand-in that reports the converter as unavailable.
if [ ! -f build/dxmt-ios/obj/madeira_ir_unix.o ]; then
    echo "==> [5d-] madeira-d3d12 skipped upstream; linking CI stub"
    xcrun -sdk iphoneos clang -arch arm64 -isysroot "$SDK" -miphoneos-version-min=18.0 -O2 \
        -I research/madeira-d3d12/src \
        -c "$GITHUB_ACTION_PATH/stubs/madeira_d3d12_stub.c" \
        -o build/dxmt-ios/obj/madeira_d3d12_stub.o
fi
cd build/dxmt-ios
rm -f libdxmt_combined.a
xcrun -sdk iphoneos libtool -static -o libdxmt_combined.a \
    obj/*.o ../../toolchains/llvm-ios-build/lib/*.a
cp libdxmt_combined.a ../../app/Madeira/
cd "$REPO"
file app/Madeira/libdxmt_combined.a

echo "Stage 5 complete."
ls -la app/Madeira/libntdll_unix.a app/Madeira/libwin32u_unix.a \
       app/Madeira/libwineserver.a app/Madeira/libdxmt_combined.a