#!/usr/bin/env bash
# Build the read-only PF1007L U-Boot (mainline v2025.10 + pf1007l-uboot.patch) in Docker.
# Outputs go to the ignored diagnostics/a33-uboot-out/. Nothing here touches a device.
#
#   scripts/a33-uboot/build-uboot.sh
#   scripts/a33-uboot/build-uboot.sh nohs   # + pf1007l-uboot-nohs.patch, to diagnostics/a33-uboot-nohs-out/
#
# Use the nohs variant only when the default build's ums shows the SD card but not the eMMC.
# See docs/allwinner-a33-mainline-uboot.md section 4.
#
# Needs git and a running Docker daemon (Docker Desktop, Colima, or Docker on Linux).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
VARIANT="${1:-}"
case "$VARIANT" in
  "") SRC="$REPO/diagnostics/u-boot"; OUT="$REPO/diagnostics/a33-uboot-out"
      DEFCONFIG=pf1007l_backup_defconfig; PATCHES=("$HERE/pf1007l-uboot.patch") ;;
  nohs) SRC="$REPO/diagnostics/u-boot-nohs"; OUT="$REPO/diagnostics/a33-uboot-nohs-out"
      DEFCONFIG=pf1007l_backup_nohs_defconfig
      PATCHES=("$HERE/pf1007l-uboot.patch" "$HERE/pf1007l-uboot-nohs.patch") ;;
  *) echo "usage: $0 [nohs]"; exit 1 ;;
esac
COMMIT=e50b1e8715011def8aff1588081a2649a2c6cd47 # v2025.10

if [ ! -d "$SRC/.git" ]; then
  git init -q "$SRC"
  git -C "$SRC" remote add origin https://github.com/u-boot/u-boot.git
  git -C "$SRC" fetch -q --depth 1 origin "$COMMIT"
  git -C "$SRC" checkout -q FETCH_HEAD
fi
[ "$(git -C "$SRC" rev-parse HEAD)" = "$COMMIT" ] || { echo "STOP: $SRC is not at $COMMIT"; exit 1; }

if [ -z "$(git -C "$SRC" status --porcelain)" ]; then
  for p in "${PATCHES[@]}"; do git -C "$SRC" apply "$p"; done
else
  # Already patched: the working tree must equal HEAD plus exactly these patches.
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  export GIT_INDEX_FILE="$TMP/want"
  git -C "$SRC" read-tree HEAD
  for p in "${PATCHES[@]}"; do git -C "$SRC" apply --cached "$p"; done
  want="$(git -C "$SRC" write-tree)"
  export GIT_INDEX_FILE="$TMP/have"
  git -C "$SRC" read-tree HEAD && git -C "$SRC" add -A
  have="$(git -C "$SRC" write-tree)"
  unset GIT_INDEX_FILE
  [ "$want" = "$have" ] || { echo "STOP: $SRC has changes other than ${PATCHES[*]##*/}"; exit 1; }
fi

docker build -q -t pf1007l-uboot-build "$HERE" > /dev/null
mkdir -p "$OUT"
cp "$HERE/ums-readonly.cmd" "$OUT/"

docker run --rm -e DEFCONFIG="$DEFCONFIG" -v "$SRC":/src:ro -v "$OUT":/out pf1007l-uboot-build bash -c '
set -e
export CROSS_COMPILE=arm-linux-gnueabihf-
cp -a /src /tmp/src && cd /tmp/src
make O=/build "$DEFCONFIG" > /dev/null
make O=/build -j"$(nproc)" > /out/build.log 2>&1 || { tail -40 /out/build.log; exit 1; }
cp /build/u-boot-sunxi-with-spl.bin /build/.config /out/
mkimage -C none -A arm -T script -d /out/ums-readonly.cmd /out/ums-readonly.scr > /dev/null
grep -E "^CONFIG_(DRAM_CLK|DRAM_ZQ|MMC_SUNXI_SLOT_EXTRA|USB_MUSB_GADGET|CMD_USB_MASS_STORAGE|CRC32_VERIFY|BOOTDELAY|SUNXI_NO_PMIC|SYS_CLK_FREQ)=" /build/.config
'

# The SPL must stay clear of the early stack/global-data area (about 0x5f20 with the
# default 0x2000 early malloc). See docs/allwinner-a33-boot-access.md.
# Only the eGON length counts: binman pads a short SPL with 0xFF up to it.
python3 -I - "$OUT/u-boot-sunxi-with-spl.bin" <<'EOF'
import struct, sys
image = open(sys.argv[1], 'rb').read()
if image[4:12] != b'eGON.BT0':
    sys.exit("STOP: no eGON header")
length = struct.unpack_from('<I', image, 16)[0]
spl = image[:min(length, 0x6000)]
end = max(i for i, b in enumerate(spl) if b not in (0, 0xff)) + 1
print(f"SPL code ends at {end:#x}")
if end > 0x5e00:
    sys.exit("STOP: SPL is too close to the stack/global-data area")
EOF

shasum -a 256 "$OUT/u-boot-sunxi-with-spl.bin" "$OUT/ums-readonly.scr" 2>/dev/null \
  || sha256sum "$OUT/u-boot-sunxi-with-spl.bin" "$OUT/ums-readonly.scr"
