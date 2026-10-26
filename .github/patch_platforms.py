#!/usr/bin/env python3
"""Dostosowuje foldery android/ i ios/ wygenerowane przez `flutter create` do potrzeb aplikacji Znicz.
Skrypt jest idempotentny – można go uruchamiać wielokrotnie."""
import plistlib
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def patch_gradle():
    p = ROOT / 'android/app/build.gradle.kts'
    s = p.read_text()
    s = re.sub(r'applicationId = "[^"]*"', 'applicationId = "pl.znicz.app"', s)
    s = s.replace('minSdk = flutter.minSdkVersion', 'minSdk = maxOf(flutter.minSdkVersion, 24)')
    if 'isCoreLibraryDesugaringEnabled' not in s:
        s = s.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
    if 'create("znicz")' not in s:
        s = s.replace('    buildTypes {', '''    // Stały klucz w repo, żeby każda nowa wersja instalowała się jako aktualizacja.
    signingConfigs {
        create("znicz") {
            storeFile = file("znicz.jks")
            storePassword = "znicz123"
            keyAlias = "znicz"
            keyPassword = "znicz123"
        }
    }

    buildTypes {''', 1)
        s = s.replace('signingConfig = signingConfigs.getByName("debug")', '''signingConfig = signingConfigs.getByName("znicz")
            // R8 potrafi usunąć klasy wtyczek – wyłączone dla pewności
            isMinifyEnabled = false
            isShrinkResources = false''')
    if 'desugar_jdk_libs' not in s:
        s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    p.write_text(s)


PERMS = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.RECORD_AUDIO',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.RECEIVE_BOOT_COMPLETED',
    'android.permission.ACCESS_MEDIA_LOCATION',
]

RECEIVERS = '''        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
'''

QUERIES = '''        <intent>
            <action android:name="android.speech.RecognitionService" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="geo" />
        </intent>
        <intent>
            <action android:name="android.intent.action.DIAL" />
            <data android:scheme="tel" />
        </intent>
'''


def patch_manifest():
    p = ROOT / 'android/app/src/main/AndroidManifest.xml'
    s = p.read_text()
    m = re.search(r'<manifest[^>]*>', s)
    add = ''.join(f'    <uses-permission android:name="{x}"/>\n' for x in PERMS if x not in s)
    if add:
        s = s[: m.end()] + '\n' + add + s[m.end():]
    s = re.sub(r'android:label="[^"]*"', 'android:label="Znicz"', s, count=1)
    if 'usesCleartextTraffic' not in s:
        # http:// w sieci domowej (NAS bez HTTPS)
        s = s.replace('<application', '<application\n        android:usesCleartextTraffic="true"', 1)
    if 'ScheduledNotificationReceiver' not in s:
        s = s.replace('    </application>', RECEIVERS + '    </application>', 1)
    if 'RecognitionService' not in s:
        if '<queries>' in s:
            s = s.replace('<queries>', '<queries>\n' + QUERIES, 1)
        else:
            s = s.replace('</manifest>', '    <queries>\n' + QUERIES + '    </queries>\n</manifest>')
    p.write_text(s)


IOS_KEYS = {
    'CFBundleDisplayName': 'Znicz',
    'CFBundleName': 'Znicz',
    'NSLocationWhenInUseUsageDescription': 'Lokalizacja zapisuje dokładne miejsce grobu i prowadzi do niego kompasem.',
    'NSCameraUsageDescription': 'Aparat służy do fotografowania nagrobków i odczytu napisów.',
    'NSPhotoLibraryUsageDescription': 'Dostęp do zdjęć pozwala dodać zdjęcie grobu z galerii.',
    'NSMicrophoneUsageDescription': 'Mikrofon służy do dyktowania danych grobu.',
    'NSSpeechRecognitionUsageDescription': 'Rozpoznawanie mowy zamienia dyktowane dane na tekst.',
    'UIFileSharingEnabled': True,
    'LSSupportsOpeningDocumentsInPlace': False,
    'NSAppTransportSecurity': {'NSAllowsArbitraryLoads': True},
    'LSApplicationQueriesSchemes': ['https', 'tel', 'comgooglemaps', 'maps'],
}


def patch_ios():
    p = ROOT / 'ios/Runner/Info.plist'
    with p.open('rb') as f:
        d = plistlib.load(f)
    d.update(IOS_KEYS)
    with p.open('wb') as f:
        plistlib.dump(d, f)
    # ML Kit wymaga iOS 15.5
    pod = ROOT / 'ios/Podfile'
    shutil.copy(ROOT / '.github/Podfile.template', pod)
    pbx = ROOT / 'ios/Runner.xcodeproj/project.pbxproj'
    s = pbx.read_text()
    s = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;', 'IPHONEOS_DEPLOYMENT_TARGET = 15.5;', s)
    pbx.write_text(s)


if __name__ == '__main__':
    patch_gradle()
    patch_manifest()
    patch_ios()
    print('Platformy przygotowane')
