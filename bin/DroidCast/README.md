# DroidCast_raw 1.1 for Android 14

`DroidCast_raw-release-1.1.apk` is built from
[`Torther/DroidCast_raw`](https://github.com/Torther/DroidCast_raw), branch
`DroidCast_raw`, at commit `1517faf7ff830abe3b5f90bae5c18be8a7b646d0`.

The upstream source needs the adjacent
`android14-set-pixel-format.patch` to capture screenshots on Android 14. The
patch changes the reflective lookup for `setPixelFormat` from
`getDeclaredMethod` to `getMethod` because the method is inherited on Android
14.

## Build

```sh
git clone --branch DroidCast_raw https://github.com/Torther/DroidCast_raw.git
cd DroidCast_raw
git checkout 1517faf7ff830abe3b5f90bae5c18be8a7b646d0
git submodule update --init --recursive
git apply /path/to/android14-set-pixel-format.patch

export JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home'
export ANDROID_HOME="$HOME/Library/Android/sdk"
./gradlew assembleRelease
```

Copy `app/build/outputs/apk/release/DroidCast_raw-release-1.1.apk` into this
directory.

The release APK is intentionally unsigned. ALAS pushes it to the device and
loads it with `app_process`; it does not install it with `adb install`.

Expected SHA-256:

```text
2a15a2ad41c3286c17fa42260af8b04d39898b11824e6940a5538ad70efae5ff
```

On Android 14, ALAS launches the service with
`LD_PRELOAD=/system/lib64/libandroid_servers.so`.

## Start the emulator and DroidCast

From the ALAS repository:

```sh
./bin/DroidCast/start-droidcast-emulator.sh
```

The script starts AVD `small` on `emulator-5554`, pushes the adjacent release
APK, starts DroidCast, and forwards port `53516`. Override its defaults with
`AVD_NAME`, `EMULATOR_PORT`, `DROIDCAST_PORT`, `DROIDCAST_APK`, or
`ANDROID_SDK_ROOT`.
