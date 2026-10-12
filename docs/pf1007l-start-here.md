# PF1007L (Allwinner A33): start here

Many frames sold as BIUFRAME and similar brands are the **PF1007L**, with an Allwinner A33
board. This is not the Rockchip BIUFRAME in the video. This page combines what three owners found
on three units. It has a test sequence. Use the tests to find out, before you write anything to the
frame, whether your unit matches a tested one and which route to use.

Each step lists a pass condition. **Stop at the first step that fails.** Then report your results
(see [Report your unit](#report-your-unit)). Do not work around a failed check.

Detailed guides behind this page:

| Guide | Covers |
| --- | --- |
| [allwinner-a33-pf1007l.md](allwinner-a33-pf1007l.md) | Identification, FEL with an SD card (Linux), and everything **after** root: backup, launcher, WebView 106, kiosk, memory |
| [allwinner-a33-boot-access.md](allwinner-a33-boot-access.md) | How the first unit was rooted (custom tool, not published), and the boot-ramdisk change |
| [allwinner-a33-mainline-uboot.md](allwinner-a33-mainline-uboot.md) | **Route U:** root ADB over USB with mainline U-Boot over FEL (macOS scripts) |
| [allwinner-a33-sdcard-adb-wifi.md](allwinner-a33-sdcard-adb-wifi.md) | **Route S:** root ADB over Wi-Fi from the SD card only, no USB data (Windows + WSL scripts) |
| [aimor-remote-root-shell.md](aimor-remote-root-shell.md) | **Read first.** The stock app gives the vendor server a root shell |

Follow the [repository rules](../README.md#rules-we-learned-the-hard-way): the owner approves each
write, a verified backup comes first, and dumps stay private.

## Known units

| | Unit A | Unit B | Unit C |
| --- | --- | --- | --- |
| Source | [#2](https://github.com/wesbos/photo-frame-dashboard/pull/2) | [#3](https://github.com/wesbos/photo-frame-dashboard/pull/3), [#5](https://github.com/wesbos/photo-frame-dashboard/pull/5) | [#4](https://github.com/wesbos/photo-frame-dashboard/pull/4) |
| Power and ports | DC jack + USB OTG port | USB-C only, TF slot, button | USB-C only, TF slot, button |
| eMMC | Samsung `KLMAG2WEMB-B031` | Samsung `AGND3R`, 30,535,680 sectors | 30,535,680 sectors |
| USB data | Yes | Not seen | Yes, **USB-A to USB-C cable only** |
| Firmware | `YHK.F-null-A33-1001-D1024-PF1007L-321-OS-AIMOR.0.20260113` | same | same |
| Boot image | 15,886,336 bytes at sector 172032 | same, SHA-256 `d71c313d…` | same sectors |
| Host | Linux | Windows + WSL | macOS (Apple silicon) |
| Root route | Custom FEL reader/writer (not published) | **Route S** | **Route U** |

Unit B and unit C have the same firmware and eMMC size. Unit C's USB worked only after a cable
change, so Unit B's "no USB data" may have been a cable problem too. That has not been tested.

## The USB-A to USB-C rule

On USB-C-only units, **use a USB-A to USB-C data cable**. Plug it into a USB-A port, or into a
USB-A port on a hub or adapter.

A USB-C to USB-C cable gave unit C **no power and no data**. The frame appears to lack the USB-C CC
pull-down resistors. Without them, a USB-C host or charger never detects the frame and never turns
on power. The same likely applies to USB-C chargers. For normal use, power the frame from a USB-A
charger with an A-to-C cable.

Other things that hid USB data on unit C:

- **A charge-only cable.** Use a cable that you know carries data, for example one that works
  with a phone.
- **A USB 3 hub without its USB 2.0 half.** The frame is USB 2.0 only. On macOS, check that a
  "USB2.0 Hub" appears in the USB tree. Moving the hub to a different port fixed it. Then
  power-cycle the frame.

## Test sequence

**Try for ADB in this order, and stop at the first that works:**

1. **Stock ADB over USB** ([T3](#t3-usb-data-test)). No changes to the frame.
2. **Stock ADB over the network** ([T3b](#t3b-network-adb-test)). No changes to the frame.
3. **Boot patch written from an SD card** (T4 onward). Use this only if 1 and 2 both fail. It
   writes to the frame's boot partition. Both patch routes need an SD card. Route U (USB) is
   preferred over Route S (SD card only), because it takes a full backup and verifies it over USB.

Ideally no one needs step 3. If your frame gives ADB at step 1 or 2,
[report it](#report-your-unit): it would mean that some units ship with ADB already on.

### T1. Read the About screen (no tools)

Settings → About. Record the model and firmware string.

**Pass:** the model is `PF1007L` and the firmware is
`YHK.F-null-A33-1001-D1024-PF1007L-321-OS-AIMOR.0.20260113`.

- `A33` in the firmware string with a different date or build: the routes may still work, but your
  unit is untested. Continue with the read-only tests only, and report your results.
- Not A33 (for example a Rockchip `rk312x` firmware): this page does not apply. See the
  [BIUFRAME guide](biuframe-setup-guide.md).

Do not connect the frame to Wi-Fi yet. Read [aimor-remote-root-shell.md](aimor-remote-root-shell.md)
first.

### T2. Ports

Look at the frame. Record **DC jack + USB port** (like unit A) or **USB-C only** (like units B and C).

### T3. USB data test

Use a USB-A to USB-C data cable, as described above. Connect the frame to the computer and let it
boot to the AiMOR screen. Then look for vendor ID `1f3a`:

```sh
# macOS
system_profiler SPUSBDataType | grep -i -B4 -A6 '0x1f3a'
# Linux
lsusb | grep -i 1f3a
# Windows (PowerShell)
Get-PnpDevice -PresentOnly | Where-Object InstanceId -match 'VID_1F3A'
# Any OS, with the Android platform tools
adb devices -l
```

| Result | Meaning | Next |
| --- | --- | --- |
| `adb devices` lists the frame as `device` | You have ADB over USB | Go to [T7](#t7-confirm-root-adb) |
| `adb devices` lists the frame as `unauthorized` | ADB is on, but waits for approval on the screen | Accept the "Allow USB debugging" prompt on the frame. Units B and C have no SystemUI, so the prompt may never appear. Then continue at T3b and report it |
| `1f3a:1000` (product "Android"), no ADB | USB data works. This is the stock state on all tested units | Go to T3b. If that fails, **Route U** (T4) |
| Nothing, after you try the checklist below | No USB data path | Go to T3b. If that fails, **Route S** (T5) |

Before you decide on "nothing", try each of these:

1. A different A-to-C cable that you know carries data.
2. A USB-A port directly on the computer, and also a USB 2.0 hub.
3. Unplug and replug the frame (on USB-C-only units the cable is the power switch).
4. A different computer.

### T3b. Network ADB test

The tested units did not have network ADB on stock firmware. Port 5555 was closed on unit A. Test
yours anyway: it is free, and it changes nothing on the frame.

This test needs the frame on Wi-Fi. Then AiMOR connects to the vendor server, which can send it
root commands (see [aimor-remote-root-shell.md](aimor-remote-root-shell.md)). If you can, first
block outbound TCP port 7806 from the frame on your router. Keep the test short.

Find the frame's IP address in your router's client list, or in Settings → About → Status on the
frame. Then, from a computer on the same network:

```sh
nc -vz -w 3 <frame-ip> 5555        # Windows: Test-NetConnection <frame-ip> -Port 5555
adb connect <frame-ip>:5555
adb -s <frame-ip>:5555 shell id
```

| Result | Next |
| --- | --- |
| `uid=0(root)` or another `uid` | You have ADB over the network. Set a static IP for the frame, then go to [T7](#t7-confirm-root-adb) and use `adb -s <frame-ip>:5555` |
| `unauthorized` | Accept the prompt on the frame if one appears, and report it |
| Connection refused or timed out | No network ADB. Continue: **Route U** (T4) if T3 found `1f3a:1000`, otherwise **Route S** (T5) |

Take the frame off Wi-Fi again until you finish [T8](#t8-lock-it-down-before-the-frame-stays-online).

### T4. Route U: FEL test (non-destructive to the frame)

Do this only if T3 found `1f3a:1000`.

Make the FEL stub SD card. On Linux, use section 2 of the
[PF1007L guide](allwinner-a33-pf1007l.md#2-use-an-sd-card-for-stable-fel-if-adb-is-absent). On
macOS, use `scripts/a33-uboot/fel-card-macos.py`. See
[section 2 of the U-Boot guide](allwinner-a33-mainline-uboot.md#2-fel-from-the-sd-card-macos).
These write 8 KiB to a spare card's unused boot area. They do not write to the frame.

Remove power, insert the card, reconnect the cable. The screen stays dark.

```sh
diagnostics/sunxi-tools/sunxi-fel version
```

**Pass:** the USB ID is `1f3a:efe8` and the output contains `soc=00001667(A33)`.

Then continue with the [U-Boot guide](allwinner-a33-mainline-uboot.md) sections 3 and 4. They build
a U-Boot with writes removed. It exposes the eMMC to the host as a **read-only** disk, and you
take a full backup. Go to T6 with that backup.

To use this route on Linux, run the FEL steps from the PF1007L guide. Use the guide's
`lsblk`/`dd` method instead of `emmc-macos.py`. That backup step is not scripted for Linux yet.

### T5. Route S: SD boot and eMMC dump test (read-only on the frame)

Do this if T3 found no USB device. It also works on units with USB.

The A33 Boot ROM tries the SD card before the eMMC. A card with U-Boot in its boot area therefore
runs before Android, without USB. Follow sections 3 to 6 of the
[SD card guide](allwinner-a33-sdcard-adb-wifi.md). The dump script runs on the frame. It reads the
first 2 GiB of the eMMC twice per chunk and writes the chunks to the card. It does not write to the
eMMC.

**Card choice:** use a **32 GB or smaller (SDHC) card formatted FAT32**. U-Boot cannot read exFAT.
Most cards larger than 32 GB come as exFAT, and Windows formats them as exFAT too. The card needs
2.2 GB free for the dump.

**Pass:** `check-dump.py` prints `stage: finished` and `emmc_dev: ok`, and all 32 chunks (`00`
to `1f`) are `ok`.

If no `a33-status.txt` appears on the card at all, U-Boot did not run. Stop and report it.

Hosts: the card-writing script (`fel-sdcard.py`) is **Windows-only**. The U-Boot build needs Linux
or WSL. A macOS card-writing script does not exist yet.

### T6. Compatibility gate: is your boot image the tested one?

This is the main test. It shows whether the boot patch was tested on the same bytes that your unit
has. It only reads your backup.

```sh
# Route U, full eMMC image:
dd if=backups/a33-emmc-full.img bs=512 skip=172032 count=31028 2>/dev/null | shasum -a 256
# Route S, 64 MiB chunks (chunk 01 starts at sector 131072):
dd if=backups/pf1007-emmc/emmc-01.bin bs=512 skip=40960 count=31028 2>/dev/null | shasum -a 256
```

On Linux, `sha256sum` replaces `shasum -a 256`. Route S also prints this hash as `original` in
`REPORT.txt` (section 7 of the SD card guide).

| Check | Tested value |
| --- | --- |
| Partition starts (sectors) | env 139264, **boot 172032**, system 237568, recovery 2400256 |
| Boot image | `ANDROID!` header, 2048-byte page, 15,886,336 bytes |
| Boot image SHA-256 (unit B) | `d71c313ddaa4693948acb20af7740ccb56c88bf9376746a47fce2d00c14fc6a4` |
| eMMC size, USB-C units | 30,535,680 sectors (15,634,268,160 bytes) |

`check-dump.py` and `emmc-macos.py` print the partition table. `boot-patch.py` (Route U) refuses a
sector that is not a partition start.

**Pass:** the boot starts at 172032 and the SHA-256 matches. Then the patch has been tested on
your exact boot image.

**On mismatch:**

- **Route S** refuses to continue. `build-write.sh` accepts only that SHA-256. Do not edit it.
  Report the hash.
- **Route U** checks the structure, not a fixed hash. It requires the exact stock USB init action,
  a ramdisk that fits, and only the expected header bytes changed. A different hash is
  **untested**. Report it, and ask in an issue before you write.

### Write the patch (owner approval for this specific write)

Pick **one** route. Undo with the same route.

| | Route U ([U-Boot guide](allwinner-a33-mainline-uboot.md) sections 5 to 7) | Route S ([SD card guide](allwinner-a33-sdcard-adb-wifi.md) sections 7 to 10) |
| --- | --- | --- |
| Result | Root ADB over **USB** (`1f3a:1002`), no key needed | Root ADB over **Wi-Fi** on port 5555, only your `adbkey` is accepted |
| Ramdisk change | `init.sun8i.usb.rc`: adds ADB to the USB functions | `default.prop`, `init.rc`, new `/adb_keys` |
| Bytes written | 2 header sectors + the ramdisk slot (5.4 MiB) | Whole boot image (15.9 MB, 31,028 sectors) |
| On-device guard | CRC-32 of each payload, and the eMMC must still hold the original bytes | SHA-256 of the file and of the current partition |
| Host verify | Whole eMMC compared with the backup + plan | Status file on the card (`OK_WRITTEN_AND_VERIFIED`) |
| Undo | `restore-boot.scr` | `sdcard-restore/` script |
| Risk | Interrupted power during a 5 MiB write | **Do not cut power** during the write. An interrupted write cannot be repaired with the published scripts |

Both patches were checked offline on a synthetic boot image of the same size. Both changed only the
documented ramdisk files and kept the kernel identical. Route U's write ranges came out as
`[192004, 203060)` and `[172032, 172034)`, the same ranges that were written on the real units.

### T7. Confirm root ADB

```sh
# Route U / USB:          use  adb -d
# Route S / Wi-Fi:        adb connect <ip>:5555, then use  adb -s <ip>:5555
adb -d shell id                          # uid=0(root)
adb -d shell getprop ro.build.fingerprint
adb -d shell getprop sys.boot_completed  # 1
```

**Pass:** `uid=0(root)` and the fingerprint
`AEEZO/astar_m86_8723cs/astar-m86_8723cs:6.0.1/MOB30R/20260113:eng/test-keys`.

Route S: set a static IP on the frame. The Wi-Fi MAC changes at each boot, so the DHCP address
changes too.

### T8. Lock it down before the frame stays online

Do section 8 of [aimor-remote-root-shell.md](aimor-remote-root-shell.md): block TCP 7806, install a
launcher, then disable `com.efercro.os.aimor`, `com.yhk.qeota` and `com.DeviceTest`. Wait until
`package-restrictions.xml` shows `enabled="2"`, then reboot.

```sh
adb shell 'netstat -an | grep :7806'
```

**Pass:** no output after the reboot.

### Then set it up

Continue with sections 4 to 9 of the [PF1007L guide](allwinner-a33-pf1007l.md#4-back-up-before-modifying-android):
launcher, WebView 106, kiosk, memory and [hardening](allwinner-a33-pf1007l.md#9-harden-after-setup).
Do the hardening before the frame joins Wi-Fi: on stock firmware any app can get root through `su`. Known differences on these units, from
[section 8 of the U-Boot guide](allwinner-a33-mainline-uboot.md#8-notes-from-this-unit-after-root):

- No SystemUI: no status bar or navigation bar. `qemu.hw.mainkeys` does nothing.
- `BOOT_COMPLETED` goes only to a whitelist. For auto-start, make the kiosk a Home app.
- No ISRG Root X1 in the trust store, so Let's Encrypt sites fail in WebView. Add the root
  certificate or use a local proxy.
- WebView 106 lacks `oklch()`, `color-mix()`, CSS nesting and `:has()`. Tailwind v4 colours break.
- The time zone ships as `America/New_York`.

## For agents

- First, [check for new issues and pull requests](../README.md#check-for-updates-and-send-back-what-you-find).
  This page summarizes PRs #2 to #5. A newer PR may cover your unit.
- Run T1 to T6 in order. They are read-only for the frame's eMMC. Do not start T4 or T5 until
  T3 (USB ADB) and T3b (network ADB) have both failed. T4 and T5 write only to a spare
  SD card, and only with the owner's approval.
- Stop at the first failed pass condition, and print the [report](#report-your-unit).
- Never edit a hash, size, sector or disk-name guard in a script to make it pass.
- Before the write step, show the owner the route, the exact bytes to be written and the undo path.
  Get explicit approval for that write.
- Do not commit anything in `backups/` or `diagnostics/`, and do not publish serials, MAC
  addresses or the full SHA-256 of a whole-eMMC image.

## Report your unit

Open an issue or PR with this, whether your unit passed or failed. Each report makes the tested range
wider. Agents: follow [the README's PR steps](../README.md#check-for-updates-and-send-back-what-you-find).

```text
About model / firmware:
AiMOR version:
Ports (DC jack, or USB-C only):
Cable and port that gave USB data (or none):
T3 USB IDs seen / adb devices output:
T3b network ADB result (port 5555):
T4 sunxi-fel version output (or skipped):
T5 check-dump stage / chunks (or skipped):
eMMC size in sectors:
Boot partition start sector:
Boot image SHA-256 (sector 172032, 31,028 sectors):
Route used and result:
Host OS:
First failed step and its exact output:
```

The boot image SHA-256 is a firmware hash, not a device identifier, so it is safe to publish.
Do not include serials, MAC addresses, Wi-Fi details or hashes of the whole eMMC.
