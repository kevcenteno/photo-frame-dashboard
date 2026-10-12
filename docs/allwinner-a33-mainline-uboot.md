# Allwinner A33 / PF1007L: root ADB with mainline U-Boot

Tested on one PF1007L on 2026-10-10, from a macOS (Apple silicon) host. The unit is the
**USB-C-only** type described in
[the PF1007L guide](allwinner-a33-pf1007l.md#second-unit-usb-c-only-no-dc-jack): no DC jack,
one USB-C port, a TF slot, an eMMC of exactly 30,535,680 sectors, and the same
`…PF1007L-321-OS-AIMOR.0.20260113` firmware.

The [boot access notes](allwinner-a33-boot-access.md) got root with a custom,
unpublished FEL reader/writer. This guide does the same job with **stock, published tools**:
mainline U-Boot v2025.10, loaded over FEL, exposing the eMMC to the host as a
**read-only** USB disk. That gives a full backup, then a guarded write of the same boot
patch, then root ADB over USB.

Follow the [repository's backup, approval and privacy rules](../README.md#rules-we-learned-the-hard-way)
and read [the AiMOR remote root shell notes](aimor-remote-root-shell.md) first. Everything
below is from one unit. Check each value on your own unit; stop at the first mismatch.

Scripts are in [`scripts/a33-uboot/`](../scripts/a33-uboot). Host-specific scripts end in
`-macos.py`; on Linux use the guide's `lsblk`/`dd` equivalents.

## 1. Get USB data on the USB-C-only unit

The PF1007L guide records this unit type as "the port supplies power only". On this unit,
USB data works. Two things hid it:

| Symptom | Cause | Fix |
| --- | --- | --- |
| USB-C to USB-C from a Mac: no power, no device. `ioreg` shows `ConnectionActive = No` on the port | The frame appears to lack the USB-C CC pull-down resistors, so a USB-C host never detects it or turns on VBUS | Use a **USB-A to USB-C** cable (into a USB-A port, adapter or hub) |
| Frame powered from a hub, but no device on the host | The USB 3 hub's **USB 2.0 half** was missing from the USB tree. The frame is USB 2.0 only | Check that a "USB2.0 Hub" appears in the tree. Moving the hub to the other Mac port brought it back. Then power-cycle the frame |

With a working path, this unit enumerated as:

| State | USB ID |
| --- | --- |
| Stock AiMOR | `1f3a:1000` "Android" |
| FEL (stub card) | `1f3a:efe8`; `sunxi-fel version` → `soc=00001667(A33)` |
| Read-only U-Boot `ums` | "UMS disk 0/1" mass storage |
| After the boot patch | `1f3a:1002`, mass storage + ADB |

On macOS, `ioreg -p IOUSB -l -w0` lists the tree. Vendor `1f3a` is 7994 in decimal.

## 2. FEL from the SD card (macOS)

Follow section 2 of the [PF1007L guide](allwinner-a33-pf1007l.md#2-use-an-sd-card-for-stable-fel-if-adb-is-absent):
same `sunxi-tools` commit, same stub hash. `sunxi-fel` builds on macOS after
`brew install libusb dtc pkgconf`, and needs no sudo.

The guide's card commands are for Linux. `fel-card-macos.py` is a port with the same
checks (MBR only, no partition before sector 8192, independent re-read, refuses to
overwrite a backup) plus a guard on the exact disk size:

```sh
diskutil list external physical          # before and after inserting the card
diskutil info diskN | grep 'Disk Size'   # the exact byte count
sudo python3 -I scripts/a33-uboot/fel-card-macos.py backup  diskN <exact-bytes>
# With the owner approving this card write:
sudo python3 -I scripts/a33-uboot/fel-card-macos.py write   diskN <exact-bytes>
# Later, to undo:
sudo python3 -I scripts/a33-uboot/fel-card-macos.py restore diskN <exact-bytes>
```

A 32 GB SDHC card worked. On the USB-C-only unit, pulling the USB cable is the power
switch: cable out, card in, cable back. The screen stays dark in FEL.

## 3. Build the read-only U-Boot

`build-uboot.sh` fetches U-Boot v2025.10 (`e50b1e87`, the same base as the boot access
notes), applies [`pf1007l-uboot.patch`](../scripts/a33-uboot/pf1007l-uboot.patch) and builds
it in Docker (Colima works). Output goes to the ignored `diagnostics/a33-uboot-out/`.

```sh
scripts/a33-uboot/build-uboot.sh
```

The patch adds a `pf1007l_backup_defconfig` and a device tree based on the Q8 A33 tablet
reference design:

| Change | Why |
| --- | --- |
| DRAM 456 MHz, ZQ 15291 | The values the boot access notes verified on this board |
| `MMC_SUNXI_SLOT_EXTRA=2` and an 8-bit MMC2 node | The eMMC is on MMC2, 8-bit |
| USB OTG `dr_mode = "peripheral"`, `USB_MUSB_GADGET` | The host must stay the host |
| VBUS drive and `usb0_id_det` removed | The frame is powered **from** the host's VBUS. The stock tablet config can drive VBUS itself |
| `VIDEO_SUNXI` off | The tablet's LCD GPIOs are unverified on this PCB |
| `BOOTDELAY=-2` | No serial console is attached, so noise on the console pin cannot stop autoboot |
| `CRC32_VERIFY` | The write script checks every payload on the device (section 6) |
| **Read-only `ums`**, two layers | `ums_write_sector` refuses all writes, and the LUN reports write-protect to the host |

The build prints where the SPL code ends. Here it was `0x456a`, about 6.6 KB below the
early global-data/stack area. See the boot access notes for why that matters.

The boot access notes say a full RAM-booted U-Boot did not enumerate as a USB disk on
their unit. With the OTG, VBUS and ID changes above, `ums` enumerated on this one.
Which of those changes was decisive was not tested.

## 4. Expose the eMMC read-only and back it up

With the frame in FEL, and the owner approving this RAM payload:

```sh
diagnostics/sunxi-tools/sunxi-fel -v -p uboot diagnostics/a33-uboot-out/u-boot-sunxi-with-spl.bin \
  write 0x43100000 diagnostics/a33-uboot-out/ums-readonly.scr
```

U-Boot runs `ums 0 mmc 0,1`: the SD card and the eMMC appear as two disks. Identify the
eMMC by size. Here it was "UMS disk 1", 15,634,268,160 bytes, **Media Read-Only: Yes**.
If macOS offers to initialize a disk, choose **Ignore**.

```sh
diskutil list external physical
diskutil info diskN | grep -E 'Media Name|Disk Size|Read-Only'
sudo python3 -I scripts/a33-uboot/emmc-macos.py backup diskN <exact-bytes>
```

`emmc-macos.py` refuses a writable disk, copies the whole eMMC, re-reads it independently,
rejects `0xCC` filler, then gzips it and verifies the readback. Here: about 12.6 MB/s,
two matching passes, zero filler runs, a 372 MB gzip. This is a **full** eMMC backup, not
just system and boot. Keep it private: it holds Wi-Fi credentials and identifiers.

The partition layout matched the tested unit in the PF1007L guide: env at sector 139264,
**boot at 172032**, system (1 GiB ext4) at 237568, **recovery at 2400256**. Parse your own.
`UDISK` (p1) is listed past the end of the eMMC, as the PF1007L guide notes.

### Only the SD card appears: the `nohs` build

On one USB-C unit (firmware `…20260529`, Samsung eMMC with CID name `AG2GC`, Linux host),
the default build showed only one disk after about 45 s: the SD card. The eMMC never appeared.
An MMC command trace from U-Boot showed why. The eMMC identified itself, returned its EXT_CSD
and accepted the 4-bit bus switch. Then it stopped answering after the CMD6 `HS_TIMING`
switch (`03b90100`), and every later command timed out: `unable to select a mode: -110`.
The 4-bit, 26 MHz and no-PMIC settings from upstream #16 alone did not help, because the
sunxi driver always turns on the high-speed modes.

[`pf1007l-uboot-nohs.patch`](../scripts/a33-uboot/pf1007l-uboot-nohs.patch) adds a variant on
top of the default patch:

- a `pf1007l,no-mmc-hs` device-tree flag that makes `sunxi_mmc` drop the high-speed modes;
- `sun8i-a33-pf1007l-backup-nohs.dts`: eMMC at 4-bit, 26 MHz, with that flag;
- `pf1007l_backup_nohs_defconfig`: `SUNXI_NO_PMIC` and the CPU at 408 MHz, as in #16;
- no CTRL+C abort in `ums`, as in #16.

```sh
scripts/a33-uboot/build-uboot.sh nohs    # output: diagnostics/a33-uboot-nohs-out/
```

Use the same `sunxi-fel` commands with that directory. With it, the eMMC came up in about
25 s as a second read-only disk. The backup ran at about 6.6 MB/s (two passes, about 80
minutes). The guarded boot write and the `verify` pass also worked. On Linux, run the
backup from upstream #13's `emmc-macos.py` with the whole disk (`sdb`) and its `lsblk -b` size.

The binary used on that unit was this variant built with extra diagnostics (console
recording, FAT write and a command to save the console log to the SD card). The patch
leaves those out. This exact build has not been run on a frame yet.

Use the default build first. It is faster on the units where it works.

## 5. Build the boot patch from your own backup

```sh
python3 -I scripts/a33-uboot/boot-patch.py backups/a33-emmc-full.img <boot-start-sector>
```

`boot-patch.py` only reads your backup. It:

- requires the sector to be a partition start holding a legacy `ANDROID!` image with a
  2048-byte page, no second stage and a matching SHA-1 image ID;
- changes only the `sys.usb.config=mass_storage` action in `init.sun8i.usb.rc`, with the
  same text as the boot access notes, and refuses if the stock action is not there exactly once;
- recompresses the ramdisk and refuses if it does not fit the original slot;
- re-parses both images: exactly one cpio entry may differ, header changes are limited to the
  ramdisk size (bytes 16–19) and image ID (bytes 576–595), nothing after the slot may change;
- writes payloads, `plan.json`, and guarded U-Boot scripts to `diagnostics/a33-boot-patch/`.

**The header write is two sectors, not one.** The image ID ends at byte 595, in the second
sector. Writing only the first 512 bytes would pair a new ramdisk size with the old ID.
Here the ranges were header `[172032, 172034)` and ramdisk `[192004, 203060)`, the same as the
boot access notes.

## 6. Guarded write

`write-boot.scr` runs on the device. It reads the current header and ramdisk slot from the
eMMC, then writes the ramdisk and then the header **only if** all four payloads match their
CRC-32 (`crc32 -v`) **and** the eMMC still holds the original bytes (`cmp.b`). If any check
fails, nothing is written. Either way it ends in read-only `ums`.

With the owner approving **this specific boot-partition write**, power-cycle into FEL and run:

```sh
P=diagnostics/a33-boot-patch
diagnostics/sunxi-tools/sunxi-fel -v uboot diagnostics/a33-uboot-out/u-boot-sunxi-with-spl.bin \
  write 0x50000000 $P/orig-header.bin  write 0x51000000 $P/orig-ramdisk.bin \
  write 0x52000000 $P/new-header.bin   write 0x53000000 $P/new-ramdisk.bin \
  write 0x43100000 $P/write-boot.scr
```

There is no console, so the host verifies the result. When the eMMC reappears read-only:

```sh
sudo python3 -I scripts/a33-uboot/emmc-macos.py verify diskN <exact-bytes>
```

This reads the whole eMMC. Every byte must equal the backup, except the planned ranges,
which must equal the patched payloads. A mismatch only in the boot ranges means the guard
refused the write.

A first attempt here read the 5.4 MiB payloads back over FEL before starting U-Boot. The
read timed out (`usb_bulk_recv() ERROR -7`). `sunxi-fel` stopped before "Starting U-Boot",
so nothing was written, and the frame needed a power cycle. The cause was not found. Checking
the payloads with `crc32 -v` on the device avoids the large FEL reads.

**Undo:** `restore-boot.scr` is the mirror image. It writes the original bytes back only if
the eMMC holds exactly the patched bytes. Load the same four payloads with `restore-boot.scr`
at `0x43100000`, then run `emmc-macos.py verify-original`.

## 7. Boot and continue with the PF1007L guide

Unplug, remove the card, plug back in. AiMOR boots as before. Here USB showed `1f3a:1002`,
and `adb -d shell id` returned `uid=0(root)` without `su`. Continue at
[section 3 of the PF1007L guide](allwinner-a33-pf1007l.md#3-confirm-root-adb-before-the-android-setup).
Disable AiMOR and `com.DeviceTest` before the frame spends more time online.

## 8. Notes from this unit after root

Observations from the setup in the PF1007L guide (launcher, WebView 106, kiosk):

- **No SystemUI.** The firmware has no `com.android.systemui`: no status bar, navigation bar or
  notification shade. Settings has no Back button. `qemu.hw.mainkeys=0` in `build.prop`
  (the [BIUFRAME fix](biuframe-setup-guide.md)) has no effect here; it was reverted.
  To leave an app, power-cycle into a Home app or use `adb shell input keyevent KEYCODE_HOME`.
- **Boot broadcasts are filtered.** Allwinner's `BackgroundManagerService` delivers
  `BOOT_COMPLETED` only to a built-in whitelist (AiMOR, the updater, Frameo and others).
  `dumpsys background` shows it. Logcat shows `prevent from boot complete broadcast: <package>`.
  A kiosk with a boot receiver will not start. Declaring the kiosk activity as a
  `HOME` app does work: Android opens Home at boot. Expect the first page load to fail
  until Wi-Fi is up, so retry.
- **Let's Encrypt.** The stock trust store has no ISRG Root X1; the kiosk logged
  `Trust anchor for certification path not found` (`net_error -202`). Adding it as
  `/system/etc/security/cacerts/6187b673.0` (root:root 0644; PEM block first, then the
  `openssl x509 -text -fingerprint -sha1` dump, like the stock files) fixed it. Check the
  SHA-256 fingerprint `96:BC:EC:06:26:49:76:F3:74:60:77:9A:CF:28:C5:A7:CF:E8:A3:C0:AA:E1:1A:8F:FC:EE:05:C0:BD:DF:08:C6`
  against a second source before installing. The guide's alternative, a host proxy, avoids
  changing `/system`.
- **WebView 106 features**, measured with `CSS.supports` and syntax checks in the kiosk:

  | Missing | Present |
  | --- | --- |
  | `oklch()`, `color-mix()` (Tailwind v4 colours), CSS nesting, `#rrggbbaa`, `:has()` | `@layer`, `@property`, grid, flex `gap`, `aspect-ratio`, container queries, `backdrop-filter`, async/await, `?.`, `??`, `#private`, `Array.at`, `findLast`, `structuredClone`, `fetch`, `EventSource`, `WebSocket`, ES modules |

  Viewport 1280×800, `devicePixelRatio` 1.
- **Time zone.** It shipped as `America/New_York`. `adb shell service call alarm 3 s16 <Area/City>`
  changes it.
- **Speaker.** The A33 `audiocodec` drives a working speaker. The kiosk's
  `setMediaPlaybackRequiresUserGesture(false)` lets a page autoplay audio. No microphone
  feature is declared.
