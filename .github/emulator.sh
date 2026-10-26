#!/usr/bin/env bash
# Własne uruchomienie emulatora (pełne logi) + test aplikacji.
set -x
APK=$1
SDK=${ANDROID_HOME:-$ANDROID_SDK_ROOT}
SM=$SDK/cmdline-tools/latest/bin/sdkmanager
AM=$SDK/cmdline-tools/latest/bin/avdmanager
IMG="system-images;android-34;google_apis;x86_64"
yes | $SM --licenses > /dev/null 2>&1
$SM "$IMG" "emulator" "platform-tools" > sdk.log 2>&1 || { echo "sdkmanager failed"; tail -20 sdk.log; }
export ANDROID_AVD_HOME=$HOME/.android/avd
mkdir -p $ANDROID_AVD_HOME/smoke.avd
cat > $ANDROID_AVD_HOME/smoke.ini <<INI
avd.ini.encoding=UTF-8
path=$ANDROID_AVD_HOME/smoke.avd
target=android-34
INI
cat > $ANDROID_AVD_HOME/smoke.avd/config.ini <<INI
image.sysdir.1=system-images/android-34/google_apis/x86_64/
abi.type=x86_64
hw.cpu.arch=x86_64
tag.id=google_apis
hw.ramSize=3072
disk.dataPartition.size=4G
hw.lcd.width=1080
hw.lcd.height=2400
hw.lcd.density=420
hw.keyboard=yes
hw.gpu.enabled=yes
INI
ls $SDK/system-images/android-34/google_apis/x86_64/ | head
export PATH=$SDK/platform-tools:$SDK/emulator:$PATH
nohup emulator -avd smoke -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect -no-snapshot -memory 3072 > emu.log 2>&1 &
timeout 300 adb wait-for-device || { echo 'EMULATOR NIE WYSTARTOWAŁ'; tail -50 emu.log; exit 3; }
for i in $(seq 1 90); do
  [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break
  sleep 5
done
adb shell getprop sys.boot_completed
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb shell input keyevent 82
timeout 400 bash .github/smoke.sh "$APK"
rc=$?
adb exec-out screencap -p > screen.png
exit $rc
