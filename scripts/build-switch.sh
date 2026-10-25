#!/usr/bin/env bash
# Build build/ShatteredPD/build-switch/ShatteredPD.nro with SwitchGDX.
# Needs: JDK 17+, unzip, rsync, cmake, ninja, devkitPro (DEVKITPRO set) with
#   switch-dev switch-zlib switch-libvorbis switch-zziplib switch-sdl2 switch-sdl2_mixer
#   switch-freetype switch-glad switch-curl switch-mesa switch-libdrm_nouveau
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${DEVKITPRO:=/opt/devkitpro}"
export DEVKITPRO
JOBS="${JOBS:-$(nproc)}"
VERSION="$(sed -n "s/^\s*appVersionName = '\(.*\)'/\1/p" build.gradle)"
CLEARWING="$(sed -n "s/^\s*clearwingVersion = '\(.*\)'/\1/p" build.gradle)"

# Clearwing transpiler: JitPack does not serve the 3.1.x builds, so build the
# matching tag from source (its Gradle 7.4 wrapper needs a JDK 17, not newer).
CW_DIR="$ROOT/build/clearwing-$CLEARWING"
TRANSPILER_JAR="$CW_DIR/transpiler/build/libs/transpiler-$CLEARWING.jar"
if [ ! -f "$TRANSPILER_JAR" ]; then
    rm -rf "$CW_DIR"
    git clone --depth 1 -b "v$CLEARWING" https://github.com/TheLogicMaster/clearwing-vm "$CW_DIR"
    (cd "$CW_DIR" && JITPACK=1 bash ./gradlew --no-daemon --console=plain :transpiler:shadowJar)
fi

./gradlew --no-daemon --console=plain :switch:switchDeps

DEPS="$ROOT/switch/build/switch-deps"
OUT="$ROOT/build/ShatteredPD"       # directory name becomes the NRO name
DIST="$ROOT/build/dist"
rm -rf "$DIST"
mkdir -p "$DIST/src" "$DIST/romfs/classpath" "$OUT"

SWITCHGDX_JAR="$(ls "$DEPS"/switchgdx/*.jar)"

echo "== Transpiling Java bytecode to C++"
java -jar "$TRANSPILER_JAR" \
    --input "$DEPS"/libs/*.jar "$SWITCHGDX_JAR" "$DEPS/classes" \
    --output "$DIST" \
    --config "$ROOT/switch/switch.json"

echo "== Collecting native sources and resources"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for jar in "$DEPS"/libs/*.jar "$SWITCHGDX_JAR"; do
    rm -rf "$TMP/x" && mkdir "$TMP/x"
    unzip -q -o "$jar" -d "$TMP/x" || true
    # Native code shipped inside jars
    (cd "$TMP/x" && find . -type f \( -name '*.cpp' -o -name '*.hpp' -o -name '*.h' -o -name '*.c' \) \
        -print0 | rsync -a --from0 --files-from=- ./ "$DIST/src/")
    # Everything else that is not class files goes on the romfs classpath
    (cd "$TMP/x" && find . -type f \
        -not -name '*.class' -not -name '*.gwt.xml' \
        -not -name '*.cpp' -not -name '*.hpp' -not -name '*.h' -not -name '*.c' \
        -not -path './META-INF/*' -not -path './switchgdx/*' -print0 \
        | rsync -a --from0 --files-from=- ./ "$DIST/romfs/classpath/")
done

# SwitchGDX CMake project template (switchgdx/project/** -> project root)
rm -rf "$TMP/x" && mkdir "$TMP/x"
unzip -q -o "$SWITCHGDX_JAR" 'switchgdx/project/*' -d "$TMP/x"
cp -r "$TMP/x/switchgdx/project/." "$DIST/"

cp -r "$ROOT/core/src/main/assets/." "$DIST/romfs/"
cp -r "$ROOT/desktop/src/main/assets/." "$DIST/romfs/"
cp "$ROOT/switch/icon.jpg" "$DIST/icon.jpg"

# Sync into the stable build dir so unchanged files keep their timestamps
rsync -crh --delete --checksum --exclude '/build-*' "$DIST/" "$OUT/"

echo "== Building NRO"
cd "$OUT"
export APP_TITLE="Shattered Pixel Dungeon" APP_AUTHOR="Evan Debenham, TheLogicMaster, axewoo" APP_VERSION="$VERSION"
export CMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --toolchain DevkitA64Libnx.cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -B build-switch .
cmake --build build-switch -j"$JOBS"
ls -la build-switch/*.nro
