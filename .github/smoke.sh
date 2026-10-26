#!/usr/bin/env bash
# Instaluje APK na emulatorze, uruchamia, dodaje grób z imieniem i sprawdza, że pojawia się na liście.
set -u
APK=$1
PKG=pl.znicz.app
adb install -r "$APK" || { echo "::error::Instalacja APK nie powiodła się"; exit 1; }
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION POST_NOTIFICATIONS RECORD_AUDIO; do
  adb shell pm grant $PKG android.permission.$p 2>/dev/null || true
done
# pozycja testowa (Celestynów)
adb emu geo fix 21.3890 52.0590 2>/dev/null || true

dump() { adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb shell cat /sdcard/ui.xml > ui.xml 2>/dev/null; }
dismiss() {
  adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1
  dump
  python3 - <<'PY'
import re,subprocess
x=open('ui.xml',encoding='utf-8',errors='ignore').read()
if "isn't responding" in x or 'nie odpowiada' in x:
    m=re.search(r'text="(?:Wait|Czekaj)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',x)
    if m:
        a,b,c,d=map(int,m.groups()); subprocess.run(['adb','shell','input','tap',str((a+c)//2),str((b+d)//2)])
        print('zamknięto okno ANR')
PY
}
tap() { # tap <regex na atrybut text/content-desc>
  python3 - "$1" <<'PY'
import re,subprocess,sys
x=open('ui.xml',encoding='utf-8',errors='ignore').read()
pat=sys.argv[1]
for m in re.finditer(r'<node [^>]*>',x):
    n=m.group(0)
    vals=[v for v in re.findall(r'(?:text|content-desc)="([^"]*)"',n) if v]
    t=next((v for v in vals if re.search(pat,v)),None)
    if t:
        b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',n)
        if b:
            a,bb,c,d=map(int,b.groups()); subprocess.run(['adb','shell','input','tap',str((a+c)//2),str((bb+d)//2)]); print('tap',t[:40]); sys.exit(0)
print('nie znaleziono',pat); sys.exit(1)
PY
}

sleep 20
dismiss
adb logcat -c
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
ok=0
for i in $(seq 1 18); do
  sleep 5
  dismiss
  if grep -q "Dodaj pierwszy grób\|Nie udało się uruchomić" ui.xml; then ok=1; break; fi
done
adb logcat -d > logcat.txt
grep -E "flutter|AndroidRuntime|FATAL|Exception" logcat.txt | tail -60 > logcat_err.txt
echo "--- UI:"; grep -o '\(text\|content-desc\)="[^"]*"' ui.xml | head -30
if grep -q "Nie udało się uruchomić" ui.xml; then
  echo "::error::Aplikacja pokazała błąd startu:%0A$(grep -o '\(text\|content-desc\)="[^"]*"' ui.xml | head -20 | sed ':a;N;$!ba;s/\n/%0A/g')"
  bash .github/report.sh logcat_err.txt
  exit 1
fi
if [ $ok -ne 1 ]; then
  echo "::error::Ekran startowy nie pojawił się w ciągu 90 s"
  bash .github/report.sh logcat_err.txt
  exit 1
fi

# Dodaj grób: imię w pierwszym polu, zapisz
tap "Dodaj pierwszy grób" || exit 1
sleep 6
dump
adb exec-out screencap -p > screen2.png
echo "--- UI formularza:"; grep -o '\(text\|content-desc\|hint\)="[^"]*"' ui.xml | head -40
python3 - <<'PY'
import re,subprocess
x=open('ui.xml',encoding='utf-8').read()
m=re.search(r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',x)
if m:
    a,b,c,d=map(int,m.groups()); subprocess.run(['adb','shell','input','tap',str((a+c)//2),str((b+d)//2)])
else:
    print("brak pola EditText")
PY
sleep 2
adb shell input text "Testowy"
sleep 1
adb shell input keyevent 111   # schowaj klawiaturę
sleep 2
dump
# przycisk „Zapisz” jest na dole – przewiń
for k in 1 2 3 4; do
  if grep -q '"Zapisz"' ui.xml; then break; fi
  adb shell input swipe 540 1900 540 600 300
  sleep 1
  dump
done
tap '^Zapisz$' || { echo "::error::Nie znaleziono przycisku Zapisz"; exit 1; }
sleep 6
dump
echo "--- UI po zapisie:"; grep -o '\(text\|content-desc\)="[^"]*"' ui.xml | head -40
if grep -q "Testowy" ui.xml; then
  echo "::notice::Smoke test OK – start, dodanie grobu i karta grobu działają"
else
  adb logcat -d | grep -E "flutter|AndroidRuntime|FATAL|Exception" | tail -60 > logcat_err.txt
  echo "::error::Po zapisie nie widać dodanego grobu%0A$(grep -o '\(text\|content-desc\)="[^"]*"' ui.xml | head -20 | sed ':a;N;$!ba;s/\n/%0A/g')"
  bash .github/report.sh logcat_err.txt
  exit 1
fi
adb logcat -d > logcat.txt
