#!/bin/bash
###############################################################################
# build-release.sh — Build unwad.exe and bundle GTK4 DLLs for Windows release
#
# Run from the MonsterMash/MonsterMash/ directory inside an MSYS2 MinGW64 shell.
#
# Usage:
#   ./build-release.sh
#
# Output:
#   dist/MonsterMash-win64.zip — portable release archive
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

DIST_DIR="$SCRIPT_DIR/dist"
STAGE_DIR="$DIST_DIR/MonsterMash"

echo "=== MonsterMash Release Builder ==="
echo ""

###############################################################################
# CHECK PREREQUISITES
###############################################################################

if ! command -v crystal &> /dev/null; then
  echo "ERROR: crystal not found. Run this from an MSYS2 MinGW64 shell with crystal installed."
  echo "  pacman -S mingw-w64-x86_64-crystal mingw-w64-x86_64-shards"
  exit 1
fi

if ! command -v shards &> /dev/null; then
  echo "ERROR: shards not found."
  echo "  pacman -S mingw-w64-x86_64-shards"
  exit 1
fi

TARGET=$(crystal env | grep CRYSTAL_TARGET 2>/dev/null || crystal --version | grep target)
if [[ "$TARGET" != *"gnu"* && "$TARGET" != *"windows"* ]]; then
  echo "WARNING: Crystal may not be the MinGW64 version. Expected target containing 'gnu'."
  echo "  Current: $TARGET"
  echo "  Make sure you're using the MSYS2 MinGW64 Crystal, not the MSVC one."
fi

# Detect MSYS2 MinGW64 prefix
MINGW_PREFIX="$(dirname "$(which crystal)")/.."
if [ ! -d "$MINGW_PREFIX/share/glib-2.0" ]; then
  # Fallback: try common locations
  for candidate in /mingw64 /c/msys64/mingw64 /usr/x86_64-w64-mingw32; do
    if [ -d "$candidate/share/glib-2.0" ]; then
      MINGW_PREFIX="$candidate"
      break
    fi
  done
fi
echo "  Using MinGW prefix: $MINGW_PREFIX"

###############################################################################
# INSTALL SHARDS
###############################################################################

echo "[1/6] Installing shards..."
shards install --production 2>&1 | tail -5
echo ""

###############################################################################
# BUILD EXECUTABLE
###############################################################################

echo "[2/6] Building unwad.exe..."
crystal build unwad.cr -o unwad.exe --release 2>&1
echo "  Built: unwad.exe ($(du -h unwad.exe | cut -f1))"
echo ""

###############################################################################
# PREPARE STAGING DIRECTORY
###############################################################################

echo "[3/6] Preparing staging directory..."
rm -rf "$DIST_DIR"
mkdir -p "$STAGE_DIR"

# Copy the executable
cp unwad.exe "$STAGE_DIR/"

# Copy jeutool binaries
cp jeutool.exe "$STAGE_DIR/" 2>/dev/null || true
cp jeutool-linux "$STAGE_DIR/" 2>/dev/null || true
cp jeutool-macos "$STAGE_DIR/" 2>/dev/null || true

# Copy bundled WADs
cp big_backpack.wad "$STAGE_DIR/" 2>/dev/null || true
cp target-spy-v1.14.pk3 "$STAGE_DIR/" 2>/dev/null || true

# Copy Built_In_Actors
if [ -d "Built_In_Actors" ]; then
  cp -r Built_In_Actors "$STAGE_DIR/"
fi

# Create empty directories for first run
mkdir -p "$STAGE_DIR/Source"
mkdir -p "$STAGE_DIR/IWADs"

echo ""

###############################################################################
# BUNDLE GTK4 DLLS
###############################################################################

echo "[4/6] Bundling GTK4 DLLs..."

# Run ldd on the original exe (not staged copy) to get mingw64 paths.
# If DLLs exist locally they may shadow the mingw64 ones in ldd output,
# so we also do a recursive ldd on the mingw64 DLLs themselves.
ldd "$SCRIPT_DIR/unwad.exe" | grep mingw64 | awk '{print $3}' > /tmp/dll_list.txt

# If no mingw64 DLLs found (local copies shadowed them), scan for lib*.dll
# in the ldd output that resolve to the script directory and find their
# mingw64 equivalents
if [ ! -s /tmp/dll_list.txt ]; then
  ldd "$SCRIPT_DIR/unwad.exe" | grep -v WINDOWS | grep -v System32 | awk '{print $1}' | while read dllname; do
    if [ -f "$MINGW_PREFIX/bin/$dllname" ]; then
      echo "$MINGW_PREFIX/bin/$dllname"
    fi
  done > /tmp/dll_list.txt
fi
while IFS= read -r dll; do
  cp "$dll" "$STAGE_DIR/"
done < /tmp/dll_list.txt
rm -f /tmp/dll_list.txt

# Copy MinGW runtime DLLs (may not show in ldd but needed at runtime)
for dll in libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll; do
  if [ -f "$MINGW_PREFIX/bin/$dll" ] && [ ! -f "$STAGE_DIR/$dll" ]; then
    cp "$MINGW_PREFIX/bin/$dll" "$STAGE_DIR/"
  fi
done

DLL_COUNT=$(ls "$STAGE_DIR/"*.dll 2>/dev/null | wc -l)
echo "  Bundled $DLL_COUNT DLLs"
echo ""

###############################################################################
# BUNDLE GTK4 RUNTIME DATA
###############################################################################

echo "[5/6] Bundling GTK4 runtime data..."

# GLib schemas (required for GTK settings)
mkdir -p "$STAGE_DIR/share/glib-2.0/schemas"
cp $MINGW_PREFIX/share/glib-2.0/schemas/gschemas.compiled "$STAGE_DIR/share/glib-2.0/schemas/"

# GDK pixbuf loaders (required for image loading)
PIXBUF_DIR="$STAGE_DIR/lib/gdk-pixbuf-2.0/2.10.0"
mkdir -p "$PIXBUF_DIR/loaders"
cp $MINGW_PREFIX/lib/gdk-pixbuf-2.0/2.10.0/loaders/*.dll "$PIXBUF_DIR/loaders/"
if [ -f $MINGW_PREFIX/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache ]; then
  cp $MINGW_PREFIX/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache "$PIXBUF_DIR/"
fi

echo "  Bundled schemas and pixbuf loaders"
echo ""

###############################################################################
# CREATE ZIP ARCHIVE
###############################################################################

echo "[6/6] Creating release archive..."
cd "$DIST_DIR"
ZIP_NAME="MonsterMash-win64.zip"
rm -f "$ZIP_NAME"

if command -v zip &> /dev/null; then
  zip -r "$ZIP_NAME" MonsterMash/ -q
elif command -v 7z &> /dev/null; then
  7z a "$ZIP_NAME" MonsterMash/ > /dev/null
else
  echo "WARNING: Neither zip nor 7z found. Staging directory is ready at:"
  echo "  $STAGE_DIR"
  echo "  Manually zip the MonsterMash/ folder to create the release."
  exit 0
fi

ZIP_SIZE=$(du -h "$ZIP_NAME" | cut -f1)
echo "  Created: dist/$ZIP_NAME ($ZIP_SIZE)"
echo ""

###############################################################################
# SUMMARY
###############################################################################

echo "=== Release build complete ==="
echo ""
echo "  Archive: $DIST_DIR/$ZIP_NAME"
echo "  Contents:"
echo "    - unwad.exe (GTK4 GUI + CLI)"
echo "    - $(ls "$STAGE_DIR/"*.dll | wc -l) bundled DLLs"
echo "    - GTK4 runtime data (schemas, pixbuf loaders)"
echo "    - jeutool binaries"
echo "    - Built_In_Actors/"
echo "    - Empty Source/ and IWADs/ directories"
echo ""
echo "  Users can extract and double-click unwad.exe — no MSYS2 needed."
