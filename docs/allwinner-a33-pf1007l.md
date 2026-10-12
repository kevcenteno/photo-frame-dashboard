# Allwinner A33 / PF1007L: recovery and dashboard setup

Tested on one PF1007L on 2026-10-09, using a Linux host. This frame was sold as a
BIUFRAME but has an **Allwinner A33**, not the Rockchip RK3126 in the existing
[BIUFRAME guide](biuframe-setup-guide.md). The brand name is not a hardware check.

This guide provides commands for identifying the device, entering stable FEL,
and setting up an **already rooted** unit. The stock unit had no ADB. Getting
root required a custom, board-specific RAM reader/writer and boot-ramdisk patch;
the [boot access notes](allwinner-a33-boot-access.md) describe that work and its
limits. That reader/writer is not included here. **The FEL stub card alone does
not enable ADB or root.** Two later routes use published tools instead:
[root ADB with mainline U-Boot](allwinner-a33-mainline-uboot.md) over USB, and
[root ADB over Wi-Fi from an SD card](allwinner-a33-sdcard-adb-wifi.md) without USB.
To choose a route and test your unit first, see [pf1007l-start-here.md](pf1007l-start-here.md).

**Security:** the AiMOR app runs root shell commands from a vendor server over an
unencrypted connection. Read [aimor-remote-root-shell.md](aimor-remote-root-shell.md)
before you connect the frame to your network.

Follow the [repository's backup, approval and privacy rules](../README.md#rules-we-learned-the-hard-way).
Do not run `scripts/biuframe-setup.sh apply`, `rkdeveloptool`, Rockchip loaders,
or Rockchip partition offsets on an Allwinner unit.

## 1. Identify the board and firmware

Record Settings → About before changing anything. On this unit:

| Item | Observed value |
| --- | --- |
| About-screen model | PF1007L |
| Firmware | `YHK.F-null-A33-1001-D1024-PF1007L-321-OS-AIMOR.0.20260113` |
| AiMOR version | 6.0.78 — the app version, **not** the Android version |
| PCB | EFERCRO `PF1007L_MB_V1.0` |
| SoC | Allwinner A33; confirmed by FEL, not just the firmware name |
| Android after ADB access | 6.0.1 / SDK 23 / `armeabi-v7a` |
| Android model / product / device | `AEEZO` / `astar_m86_8723cs` / `astar-m86_8723cs` |
| Build fingerprint | `AEEZO/astar_m86_8723cs/astar-m86_8723cs:6.0.1/MOB30R/20260113:eng/test-keys` |
| RAM / display | 1 GiB / 1280 × 800, density 160 |
| Storage | Samsung `KLMAG2WEMB-B031`, nominal 16 GB eMMC |
| Stock USB | `1f3a:1000`, mass storage only |
| Stable FEL USB | `1f3a:efe8`; `sunxi-fel version` identifies A33 |
| USB after the boot patch | `1f3a:1002`, mass storage + ADB |

The board was opened to confirm markings. Opening it is not needed to read the
About screen or try the SD recovery route. There is no verified disassembly
procedure in this guide; do not pry off shields or short storage pins to enter FEL.

### Second unit: USB-C only, no DC jack

A second PF1007L has the same About-screen model and the same firmware string.
Its hardware is different:

| Item | First unit | Second unit |
| --- | --- | --- |
| Power | DC jack | No DC jack. Power comes through the USB-C port. |
| Ports | DC jack, USB device/OTG port | One USB-C port, one TF (microSD) slot, one power/reset button |
| USB data | `1f3a:1000` stock, `1f3a:efe8` in FEL | None. The port supplies power only. |
| eMMC | Samsung `KLMAG2WEMB-B031` | Samsung `AGND3R`, 30,535,680 sectors |

The second unit never shows a USB device on the host.
This is true in stock Android, with the reset button, and in FEL from the stub card.
The screen stays dark with the stub card, so the Boot ROM does read the TF slot.
Thus, USB ADB and the `sunxi-fel` steps in section 2 do not apply to this unit.

The TF slot is the only data path at boot.
A U-Boot image on the SD card can read and write the eMMC without USB.
A boot ramdisk patch that sets `service.adb.tcp.port=5555` and starts `adbd` at boot
gives root ADB over Wi-Fi. With this property set, `adbd` does not use USB.
After that, use `adb connect <frame-ip>:5555`.
Replace `adb -d` with `adb -s <frame-ip>:5555` in all commands in this guide.

A third PF1007L of this USB-C-only type (same firmware, same 30,535,680-sector eMMC)
**did** show USB data: stock `1f3a:1000` and FEL `1f3a:efe8`. A USB-C to USB-C cable from
a Mac gave nothing, not even power, but a USB-A to USB-C cable worked, through a hub
port with a working USB 2.0 path. Try that before ruling out USB. See
[root ADB with mainline U-Boot](allwinner-a33-mainline-uboot.md#1-get-usb-data-on-the-usb-c-only-unit).

On the second unit, the MBR says that `UDISK` (`/data`, p1) ends at sector 30,633,984.
The eMMC ends at sector 30,535,680. The kernel cuts p1 at the end of the disk.
Do not read past sector 30,535,680.

The first unit, as tested:

Use a USB **data** cable and the device/OTG port, with the normal DC supply:

```sh
lsusb
adb devices -l
```

Disconnect other Android devices. Later commands use `adb -d`, which selects a
USB device and refuses multiple USB targets. If ADB is already available, verify
the properties in section 3 and skip FEL. If it says `unauthorized`, accept the
debugging prompt on the frame; that state is different from no ADB interface.

## 2. Use an SD card for stable FEL, if ADB is absent

The recessed Reset button exposed `1f3a:efe8` for about three seconds during
startup, but version queries failed. The Android recovery menu, Test App password
dialog and keyboard-settings detour did not provide a usable ADB route. A USB
identity alone is not proof that the Boot ROM protocol is responding.

A spare SD card containing the official FEL boot stub gave **persistent,
queryable FEL**. It does not modify internal eMMC. Removing it and cold-booting
returns to the normal internal boot path.

The [linux-sunxi FEL documentation](https://linux-sunxi.org/FEL#Through_a_special_SD_card_image)
explains this method. The eGON stub requires non-secure boot; it is not guaranteed
to work on another board or a secure-boot unit.

### Build the host tool and verify the stub

You need Git, a C compiler, make, pkg-config, and the libusb/libfdt development
headers. Install those using your host distribution's package manager. The
following pins the upstream revision used for this unit:

```sh
git clone https://github.com/linux-sunxi/sunxi-tools.git diagnostics/sunxi-tools
git -C diagnostics/sunxi-tools checkout d7bbd172a5da601a08f94479de308c6fb714a19a
make -C diagnostics/sunxi-tools sunxi-fel
python3 - <<'PY'
from pathlib import Path
import hashlib
p = Path('diagnostics/sunxi-tools/bin/fel-sdboot.sunxi')
b = p.read_bytes()
assert len(b) == 8192
assert b[4:12] == b'eGON.BT0'
assert hashlib.sha256(b).hexdigest() == '2ccec08a026840571f3804671ba72afae840db27112a43f2b1f122075bc808bc'
print('Verified official 8192-byte FEL SD stub')
PY
```

### Prepare only a positively identified spare card

These are **Linux host commands**. Do not substitute a guessed disk name. Use
`lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS` before and after inserting the reader,
identify the **whole card**, and unmount each of its partitions. The following
procedure is restricted to an MBR card whose partitions begin at or beyond 4 MiB,
matching the layout tested here. It rejects GPT and earlier partition starts.
If that check fails, stop; do not overwrite the partition table to force a match.

Set `FEL_SD_CARD` to the card's whole-device path, not a partition:

```sh
export FEL_SD_CARD=/dev/REPLACE_WITH_SPARE_SD_CARD
sudo env FEL_SD_CARD="$FEL_SD_CARD" python3 - <<'PY'
import gzip, hashlib, json, os, stat, struct, subprocess
from pathlib import Path

card = Path(os.environ['FEL_SD_CARD']).resolve(strict=True)
os.umask(0o077)
assert stat.S_ISBLK(card.stat().st_mode), 'Not a block device'
tree = json.loads(subprocess.check_output(
    ['lsblk', '--json', '-o', 'NAME,MOUNTPOINTS', str(card)], text=True))
def check_unmounted(nodes):
    for node in nodes:
        assert not any(node.get('mountpoints', [])), 'Unmount the card first'
        check_unmounted(node.get('children', []))
check_unmounted(tree['blockdevices'])
stub = Path('diagnostics/sunxi-tools/bin/fel-sdboot.sunxi').read_bytes()
assert len(stub) == 8192
assert hashlib.sha256(stub).hexdigest() == '2ccec08a026840571f3804671ba72afae840db27112a43f2b1f122075bc808bc'
fd = os.open(card, os.O_RDONLY)
try:
    before = os.pread(fd, 4 * 1024 * 1024, 0)
    assert len(before) == 4 * 1024 * 1024
    assert before[510:512] == b'\x55\xaa', 'Expected MBR'
    parts = [before[446+i*16:462+i*16] for i in range(4)]
    active = [p for p in parts if p[4]]
    assert active and all(p[4] != 0xee for p in active), 'GPT/empty layout not supported'
    assert all(struct.unpack_from('<I', p, 8)[0] >= 8192 for p in active), 'Partition too close to stub'
    assert os.pread(fd, len(before), 0) == before, 'Independent reread differs'
finally:
    os.close(fd)
out = Path('backups/a33-fel-card-prefix.bin.gz')
out.parent.mkdir(exist_ok=True)
with gzip.open(out, 'xb') as f:
    f.write(before)
assert gzip.decompress(out.read_bytes()) == before
print('Card prefix backed up; SHA-256:', hashlib.sha256(before).hexdigest())
PY
```

The backup step deliberately refuses to overwrite an existing backup. Keep it
with a private note identifying the card. Recheck `lsblk` immediately before the
write; unplug/replug or disk-name changes invalidate the target selection.
With the owner approving this card write and boot-code execution:

```sh
sudo dd if=diagnostics/sunxi-tools/bin/fel-sdboot.sunxi of="$FEL_SD_CARD" bs=1024 seek=8 count=8 conv=notrunc,fsync
sudo env FEL_SD_CARD="$FEL_SD_CARD" python3 - <<'PY'
import gzip, os
from pathlib import Path
before = gzip.decompress(Path('backups/a33-fel-card-prefix.bin.gz').read_bytes())
stub = Path('diagnostics/sunxi-tools/bin/fel-sdboot.sunxi').read_bytes()
expected = before[:8192] + stub + before[16384:]
with open(os.environ['FEL_SD_CARD'], 'rb') as f:
    assert f.read(len(before)) == expected, 'Card readback mismatch; stop'
print('Exactly 8192 bytes changed at byte offset 8192')
PY
```

1. Unplug **both DC power and USB** from the frame.
2. Insert the prepared card, then reconnect power and the USB data cable.
3. Run `lsusb`, then `diagnostics/sunxi-tools/sunxi-fel version` with only this
   Allwinner device connected. Expected output includes `soc=00001667(A33)`.
4. If permissions fail, fix host USB access; do not treat it as a firmware failure.
   If the query hangs or identifies another SoC, stop and retain the backup.

Keep the recovery card. To undo its preparation, identify/unmount that **same
card**, restore the saved 4 MiB prefix, and reread it to compare with the backup.
To boot Android, disconnect both power sources, remove the FEL card, and reconnect.

**At this point you have recovery access, not root.** `sunxi-fel read` reads
CPU-addressable memory; a Boot ROM or SRAM dump is not an eMMC/Android backup.
The [boot access notes](allwinner-a33-boot-access.md) explain the missing storage
reader and the patch that eventually enabled root ADB on the tested unit.
[Root ADB with mainline U-Boot](allwinner-a33-mainline-uboot.md) continues from here
with published tools: a read-only `ums` backup, then a guarded boot write.

## 3. Confirm root ADB before the Android setup

Only continue once Android boots and ADB actually works:

```sh
adb devices -l
adb -d shell id
adb -d shell getprop ro.product.model
adb -d shell getprop ro.product.cpu.abi
adb -d shell getprop ro.build.version.sdk
adb -d shell getprop ro.build.fingerprint
adb -d shell getprop sys.boot_completed
adb -d shell getenforce
```

This unit returned `uid=0(root)` directly, SDK `23`, `armeabi-v7a`, the fingerprint
in section 1, `sys.boot_completed=1`, and SELinux `Disabled`. It did not need
`su -c` or `adb root`. If shell is not root, or the firmware/board differs, stop:
the system paths and package names below need independent verification.

After a reboot, our host ADB server sometimes failed to rediscover the frame.
`adb kill-server` followed by `adb start-server` fixed discovery. This restarts
the host server and affects other ADB sessions; it does not root the device.

## 4. Back up before modifying Android

Keep all captures in ignored `backups/` or `diagnostics/`. Do not publish the
serial, eMMC CID, Wi-Fi details, full property dumps, vendor APKs or flash images.

Identify partitions on **your** device first:

```sh
adb -d shell 'ls -l /dev/block/by-name; cat /proc/partitions'
adb -d shell 'cat /sys/class/block/mmcblk0p7/size; mount'
```

On the tested unit, `system` resolved to `mmcblk0p7`, 2,097,152 sectors of 512
bytes (1,073,741,824 bytes), mounted read-only. Check both before using this example:

```sh
mkdir -p backups
adb -d exec-out 'dd if=/dev/block/by-name/system bs=1048576 2>/dev/null' > backups/a33-system.img.partial
wc -c < backups/a33-system.img.partial
# Expected ONLY for the matching tested layout: 1073741824
```

Reject an unexpected length or repeated `0xCC` filler. Independently capture the
read-only partition again, compare with `cmp`, record SHA-256, then compress and
verify gzip decompression against that hash. Rename `.partial` only after those
checks pass. Also preserve boot/recovery and the exact original WebView tree:

```sh
adb -d exec-out 'toybox tar -C /system/app -cf - webview 2>/dev/null' > backups/a33-stock-webview.tar
```

Independently reread that tar, compare byte-for-byte, and inspect its members
before any replacement. A `dd`/`tar` error may otherwise leave a misleading file.
Old `adbd` can merge remote stderr into binary `exec-out` output; the `2>/dev/null`
in these commands prevents a `dd` status footer from contaminating the image.

The tested session independently verified the whole system partition and boot
image. Recovery had partial spot checks rather than a complete second reread.
This was **not a full-device backup**: userdata, hardware boot areas and every
partition tail were not captured. Before root, the owner explicitly accepted
the limited boot backup covering every proposed modified sector. Do not silently
claim that as compliance with the repository's full backup rule.

## 5. Install a launcher and optional Firefox fallback

Download on the host, verify the hashes, then install. These are the same pinned
sources as the existing guide; importing its download references does not make
its Rockchip `apply` script suitable for this board.

| APK | Source | SHA-256 |
| --- | --- | --- |
| Rootless Launcher 3.9.1 | [F-Droid](https://f-droid.org/repo/amirz.rootless.nexuslauncher_30911.apk) | `7fa44d560dc4577374d45176220de2c0b00a71e09d6d148cdea4e0a52d38404a` |
| Firefox 143.0.4 ARMv7 | [Mozilla archive](https://archive.mozilla.org/pub/fenix/releases/143.0.4/android/fenix-143.0.4-android-armeabi-v7a/fenix-143.0.4.multi.android-armeabi-v7a.apk) | `af560738627d4efc9ace75e708fc48aad6a24c78ef43a89daca27e16ff3829f8` |
| WebView 106.0.5249.126 ARM | [LineageOS at `4b0ae494a7dd`](https://raw.githubusercontent.com/LineageOS/android_external_chromium-webview_prebuilt_arm/4b0ae494a7dd/webview.apk) | `e2edc1f89ec1608b169da9e7ffc037190b70c7825f0be29694f4cae719980580` |

Use private local filenames `diagnostics/rootless.apk`, `diagnostics/firefox.apk`
and `diagnostics/webview.apk` below. Inspect APK signatures, package/version and
minimum SDK with Android build-tools as well as verifying SHA-256.

With the owner approving these installations:

```sh
adb -d install diagnostics/rootless.apk
# Optional fallback; the kiosk does not require Firefox:
adb -d install diagnostics/firefox.apk
adb -d shell am start -a android.intent.action.MAIN -c android.intent.category.HOME -p amirz.rootless.nexuslauncher
```

Confirm the new launcher is visible before disabling the vendor launcher:

```sh
adb -d shell pm disable com.efercro.os.aimor
adb -d shell input keyevent KEYCODE_HOME
```

Select Rootless Launcher as the Home default if prompted.
Disabling AiMOR also closes its remote root shell connection.
See [aimor-remote-root-shell.md](aimor-remote-root-shell.md).
Also disable `com.DeviceTest`. It runs as the system user and has an unprotected receiver
that enables or disables components of any package.

The observed vendor
updater was `com.yhk.qeota`, with an active download service. Check that package
on your device before disabling it:

```sh
adb -d shell dumpsys package com.yhk.qeota
adb -d shell pm disable com.yhk.qeota
adb -d shell am force-stop com.yhk.qeota
adb -d shell am force-stop org.mozilla.firefox
adb -d shell settings put global animator_duration_scale 0
```

Record existing animation settings first. Window and transition scales were
already zero on our unit. Do not blanket-disable Android core services.

**Wait for package settings to reach disk before rebooting.** Our first immediate
reboot lost the updater-disable and Firefox-stopped states. `sync` alone does
not force Package Manager's asynchronous XML update. Check the private
`/data/system/users/0/package-restrictions.xml` until the relevant package entries
show `enabled="2"` for disabled packages and `stopped="true"` for Firefox.
Then reboot, check `dumpsys package` again, and check `ps` for restarted processes.
Do not publish that XML. `enabled=2` is the expected `dumpsys` disabled state.

## 6. Upgrade WebView before using the kiosk

Stock WebView was **44.0.2403.119**. The dashboard targets Chrome 106, so a kiosk
using the stock engine was not sufficient. Firefox worked without changing
WebView, but used substantially more RAM in our snapshots.

WebView 106 is an old 2022 engine; these instructions document compatibility
with Android 6, not a current or secure general-purpose browser. Root ADB and
the old OS are also unsuitable for exposing to an untrusted network.

After verifying the system and WebView backups and obtaining approval for this
specific `/system` replacement:

1. Extract **all** `lib/armeabi-v7a/*.so` from the verified WebView APK on the host.
   The tested APK contains `libchromium_android_linker.so`,
   `libcrashpad_handler_trampoline.so` and `libwebviewchromium.so`.
2. Stage the APK/libraries under `/data/local/tmp`, outside the live WebView tree.
3. Check free space with `adb -d shell toybox df -k /system`. Keep enough space
   for both old and new trees; our conservative staging check required 300,000 KiB.
4. Remount `/system` read-write and create `/system/homehq-new-webview` with
   `webview.apk` and `lib/arm/*.so`. Directories must be 0755, files 0644, owner
   root:root. Refuse existing staging or rollback paths rather than overwriting them.
5. Read back every staged file with `adb exec-out` and compare with the host
   bytes **before** touching `/system/app/webview`.
6. Move the original whole tree to `/system/homehq-stock-webview` (outside the
   scanned `app`/`priv-app` directories), then move the new tree to
   `/system/app/webview`. This preserves the original APK **and its odex** and
   avoids leaving an old oat directory in the new tree.
7. Read back every live file again, verify ownership/modes, run `sync`, and remount
   `/system` read-only. Check package-state persistence from section 5, then reboot.
8. Confirm `adb -d shell dumpsys package com.android.webview` reports
   `versionName=106.0.5249.126`, and confirm the kiosk actually renders. Check
   `adb -d logcat -d` privately for `Failed to load library`/`dlopen failed`.

Replacing just the APK can report version 106 while failing at runtime: Android
6 does not extract the compressed native libraries for this system app. Verify
the library files and a real page, not just Package Manager's version number.

Undo before proceeding if a check fails: stop the kiosk, remount `/system`
read-write, move the new live tree aside, restore the preserved original whole
tree to `/system/app/webview`, verify it against the backup, remount read-only,
and reboot. Keep the working launcher/Firefox fallback while testing.

## 7. Build the fullscreen kiosk and serve the demo over USB

The existing [`dashboard/kiosk/`](../dashboard/kiosk) is already a minimal
WebView Activity with immersive mode: it does not have a browser URL bar. Build
using JDK 17, Android build-tools 34.0.0 and platform android-34 as described in
[`build.sh`](../dashboard/kiosk/build.sh); set `ANDROID_HOME` to your SDK directory.
Its default URL is Wes's hosted demo. Change it locally to your own URL, or use
the explicit VIEW intent below to override it.

```sh
cd dashboard
npm ci
npm run build
# Keep this terminal running:
npm run preview -- --host 127.0.0.1 --port 4173 --strictPort
```

In another terminal, from the repository root:

```sh
dashboard/kiosk/build.sh
adb -d install dashboard/kiosk/build/homehq.apk
adb -d reverse tcp:4173 tcp:4173
adb -d shell 'am start -a android.intent.action.VIEW -d "http://127.0.0.1:4173/#home" -n com.wesbos.homehq/.MainActivity'
```

This URL is **localhost on the frame**, forwarded to the host by ADB. It does not
require opening a host firewall port or using the frame's changing Wi-Fi address.
Keep the host server and USB connected. Recreate the reverse mapping after a
device/ADB restart. Hold two fingers still for **1.5 seconds** to exit to the
launcher. Boot auto-start is not implemented by this procedure.

The dashboard contains **sample data**, not your real calendar. Older Android
trust stores can reject external HTTPS images even though the local HTML loads.
That happened with Picsum on this unit. Our local setup used a host image proxy
with normal upstream TLS verification; that proxy and our lighter dashboard
profile are local changes, **not included in this documentation-only PR**.
Use trusted locally served images, or investigate the specific certificate chain
before changing the system CA store. Do not bypass certificate validation.

Quote the entire remote command when URLs contain `&`, for example:

```sh
adb -d shell 'am start -a android.intent.action.VIEW -d "http://127.0.0.1:4173/?diag=0#home" -n com.wesbos.homehq/.MainActivity'
```

`adb shell` joins its arguments for the remote shell; unquoted query-string `&`
can split the command. Ordinary `am start` worked; Firefox's `am start -W`
sometimes timed out even when the page had loaded.

## 8. Measure memory before adding swap

```sh
adb -d shell cat /proc/meminfo
adb -d shell cat /proc/swaps
adb -d shell cat /sys/block/zram0/disksize
adb -d shell cat /sys/block/zram0/mem_used_total
adb -d shell dumpsys meminfo
adb -d shell dumpsys meminfo com.wesbos.homehq
adb -d shell ps
```

This unit already had **256 MiB zRAM**, unlike the Rockchip unit's original
128 MiB. We did not add swap or copy its SuperSU startup hooks. With the custom
kiosk and local lighter dashboard, a final snapshot showed:

| Measurement | Observed |
| --- | --- |
| Firefox processes in earlier snapshot, combined PSS | 387,039 KiB (about 378 MiB) |
| Kiosk PSS in final snapshot | 81,513 KiB (about 80 MiB) |
| System free/reclaimable RAM in final snapshot | 706,327 KiB |
| Swap capacity / usage | 262,140 KiB / 260 KiB |
| zRAM physical memory used | 40 KiB |

These are snapshots with different configurations, not a controlled benchmark
or a guarantee for other pages. No valid before/after touch-latency comparison
was obtained. Extra swap was not indicated by this workload. First reduce
background apps, image dimensions, animated effects and hidden-view work, then
measure again; do not assume the Rockchip swap prescription applies.

## 9. Harden after setup

Tested on one USB-C-only PF1007L on 2026-10-12 (firmware `…PF1007L-V10-1680.0.20260529`,
the tested boot image), after section 8 of [aimor-remote-root-shell.md](aimor-remote-root-shell.md),
WebView 106 and the kiosk. Do this before the frame joins Wi-Fi. Root ADB over USB keeps working
after every step: `adbd` runs as root and does not use `su`.

What the stock firmware exposes:

| Finding | Check |
| --- | --- |
| SELinux is off from boot, not just permissive | `getenforce` prints `Disabled`; `/proc/cmdline` has `androidboot.selinux=disabled` |
| Any app can run `su` and get root silently | `ls -l /system/xbin/su` shows `-rwsr-sr-x root shell` |
| The connectivity check goes to a vendor server | `settings get global captive_portal_server` prints `status.eqoe.cn` |
| A vendor factory GL test is a privileged app | `com.android.gl2jni` in `/system/priv-app/tomas/` |
| Disabling vendor apps does not survive a factory reset | The disabled state is in `/data`; a reset from Settings re-enables AiMOR |
| Any app can set `service.*`/`debug.*` properties and stop or start init services | See "Any app can control init" below |
| A boot script opens `/system/media` to everyone | `/system/bin/preinstall.sh` runs as root at every boot and does `chmod 0777 /system/media`; `ls -ld /system/media` shows `drwxrwxrwx` |
| Three memory tools are setuid root | `/system/xbin/procmem`, `procrank`, `librank` are `-rwsr-sr-x root root` |
| A vendor ID file on shared storage | `/sdcard/vuid.txt` and an `/sdcard/aimor/` folder |
| A Wi-Fi network may already be saved | `grep -c 'network=' /data/misc/wifi/wpa_supplicant.conf` |

There were no listening network ports (`netstat -lntu`, apart from `adbd` on 127.0.0.1), no
navigation bar and no Home key, so the Home app is the only way out by touch.

1. Make `su` root-only. Record the old mode first; the undo is `chmod 6755`.

   ```sh
   adb -d shell 'mount -o remount,rw /system && chmod 0700 /system/xbin/su; sync; mount -o remount,ro /system'
   adb -d shell ls -l /system/xbin/su    # -rwx------ root shell
   ```

2. Turn off the connectivity check, so joining Wi-Fi contacts nobody. Once a LAN time server
   exists, also point NTP at it: `settings put global ntp_server <lan-ip>`.

   ```sh
   adb -d shell settings put global captive_portal_detection_enabled 0
   adb -d shell settings delete global captive_portal_server
   ```

3. Disable apps a wall-mounted kiosk does not use. Each one is undone with `pm enable <package>`.

   ```sh
   adb -d shell 'for p in com.android.gl2jni jp.co.omronsoft.openwnn com.svox.pico \
     com.android.smspush com.android.mms.service com.android.captiveportallogin \
     com.android.statementservice com.android.managedprovisioning com.android.location.fused \
     com.android.pacprocessor com.android.proxyhandler com.android.vpndialogs \
     com.android.providers.calendar com.android.backupconfirm com.android.sharedstoragebackup \
     com.android.htmlviewer; do pm disable $p; done'
   ```

   Keep Settings, `SettingsProvider`, `Shell` (ADB), `PackageInstaller`, `DefaultContainerService`
   (installs), the media and storage providers, `DocumentsUI`, `KeyChain`, `CertInstaller`,
   `InputDevices`, `DownloadProvider`, WebView, and the LatinIME keyboard (needed to type a
   Wi-Fi password). `rild` and `sayeye` still run as native services; neither opens a port.

4. Move the vendor apps out of `/system/priv-app`, so a factory reset cannot bring AiMOR back.
   First copy the three directories to the host and compare each file, as for WebView in
   section 6. Keep that copy private; do not commit or publish it.

   ```sh
   adb -d shell 'set -e; mount -o remount,rw /system
     mkdir /system/homehq-disabled-vendor; chmod 0700 /system/homehq-disabled-vendor
     for d in launcher_aimor frame_ota DeviceTest; do mv /system/priv-app/$d /system/homehq-disabled-vendor/; done
     sync; mount -o remount,ro /system'
   ```

   On the next framework start, `PackageManager` logs `System package … no longer exists; wiping
   its data` for each, and `pm path com.efercro.os.aimor` prints nothing. Undo: move the three
   directories back to `/system/priv-app` and restart. AiMOR's old data is gone.

5. Stop the boot script and close the other permission holes. `preinstall.sh` checks for
   `/data/system.preinstall` but creates a different file, so it runs at every boot. The tar files it
   extracts do not exist. Undo: `rm /data/system.preinstall`, then `chmod 0777 /system/media` and
   `chmod 6755` on the three tools, inside the same remount.

   ```sh
   adb -d shell 'set -e; touch /data/system.preinstall; chmod 0600 /data/system.preinstall
     mount -o remount,rw /system; chmod 0755 /system/media
     chmod 0755 /system/xbin/procmem /system/xbin/procrank /system/xbin/librank
     sync; mount -o remount,ro /system'
   ```

6. Copy `/sdcard/vuid.txt` and `/sdcard/aimor` to a private folder on the host, then delete them
   from the frame: `adb -d shell rm -r /sdcard/vuid.txt /sdcard/aimor`.

7. If `wpa_supplicant.conf` has a `network={` block you did not add, copy the file to the host,
   then rewrite it without the block and empty `networkHistory.txt`. Writing with `cat … >` keeps
   the file's owner and mode (`wifi:wifi 0660`). Do this with Wi-Fi off. Undo: write the copy back.

   ```sh
   sed '/^network={/,$d' wpa_supplicant.conf > wpa_new.conf     # on the host, from the copy
   adb -d push wpa_new.conf /data/local/tmp/
   adb -d shell 'cat /data/local/tmp/wpa_new.conf > /data/misc/wifi/wpa_supplicant.conf
     rm /data/local/tmp/wpa_new.conf; > /data/misc/wifi/networkHistory.txt; sync'
   ```

8. Restart the framework with `adb -d shell stop; adb -d shell start` (`adb reboot` can hang on
   these units), then check: Home still shows, no app crashes in `logcat`, and
   `netstat -lntu` lists no ports other than 127.0.0.1.

A factory reset from Settings re-enables the packages from step 3, restores the vendor
connectivity-check server (it is the `SettingsProvider` default), removes the kiosk and launcher,
and deletes the guard file from step 5. Run this section again after any reset. Steps 1 and 4 and
the WebView swap survive, because they are on `/system`.

### Any app can control init

With SELinux disabled, Android 6's property service only checks the property prefix against the
caller's uid. That stops nothing that matters here. Tested on 2026-10-12, running as a normal app
uid (`su 10022`, the launcher's uid):

- `setprop debug.homehq.proptest app` and `setprop service.homehq.test 1` worked.
- `setprop ctl.stop perfprofd` stopped a root service (`init.svc.perfprofd` went from `running` to
  `stopped`; it was started again as root afterwards).

So native code in any app, for example after a WebView exploit, can very likely run
`setprop service.adb.tcp.port 5555` and `setprop ctl.restart adbd`. `adbd` reads that property,
runs as root and has `ro.adb.secure=0`, so the result is root ADB with no authentication, on the
network and on 127.0.0.1. This last step was not run, because it drops the ADB session. Android 6
init can also pass arguments to a root service through `ctl.start <service>:<args>` (not tested
here), which may give other routes to root. Firewall rules on the frame would close the `adbd`
route but not those.

The only full fix is SELinux in enforcing mode, which is untested on this firmware. Until then,
treat any code that runs on the frame as root:

- Only install apps you trust. The kiosk should load only your own server's pages.
- Put the frame on a separate network segment with no internet access. Allow only the dashboard
  server's address and port, and block every other device from connecting to the frame. A rule on
  the same subnet cannot do this, because traffic between hosts on one subnet never reaches the
  router.

`adbd` also listens on 127.0.0.1:5037. In testing, connecting to it from the frame restarted the
ADB server on the connected computer, so it appears to lead back to the host. This only matters
while the frame is connected to a computer over USB.

Still open after these steps: anyone with a USB cable gets a root shell (this is also the
recovery path), the 2016 security patch level and the Linux 3.4 kernel, SELinux remains off,
and the trust store dates from 2016 (it lacks ISRG Root X1 and still has WoSign, StartCom and CNNIC).
Block the frame from the internet on the router, and limit the kiosk to your own dashboard's address.

## Undo and hand-off

- Re-enable vendor apps with `pm enable com.efercro.os.aimor` and
  `pm enable com.yhk.qeota`, then start Home. Android 6's `pm` here lacked
  `default-state`: this restores functionality with explicitly enabled state
  rather than the original default-enabled state.
- Restore the original animator setting; if originally unset, use
  `settings delete global animator_duration_scale`.
- Restore the whole original WebView tree using section 6, not just its APK.
- Undo section 9: `chmod 6755 /system/xbin/su`, `pm enable` each disabled package, move the
  vendor directories back from `/system/homehq-disabled-vendor`, follow the undo in steps 5 to 7, and
  `settings put global captive_portal_server status.eqoe.cn` if you want the stock check back.
- Uninstall newly added apps only after a working Home launcher is restored.
- `adb -d reverse --remove tcp:4173` removes the USB dashboard mapping.
- Keep verified boot/system backups and the FEL card private and available.
  Restoring a boot patch requires the same board-specific, bounded storage writer;
  `sunxi-fel` alone does not provide an eMMC restore command.

This setup does not update Android, configure automatic
startup, or integrate real calendar data. Those are separate tasks.
