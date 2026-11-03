param(
    [switch]$Release
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

# Environment invariants for multi-partition workstation:
$env:JAVA_HOME = 'C:\Users\Dias\.jdks\temurin-17'
$env:GRADLE_USER_HOME = 'D:\Gradle'
$env:TEMP = 'E:\Temp'
$env:TMP = 'E:\Temp'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter SDK tidak ditemukan. Install Flutter dan Android SDK terlebih dahulu."
}

if (-not (Test-Path "android")) {
    flutter create --platforms=android --project-name mototext_ble --org com.mototext .
}

$ManifestPath = "android/app/src/main/AndroidManifest.xml"
$ManifestText = Get-Content $ManifestPath -Raw
$Permissions = @(
    '    <uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />',
    '    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />',
    '    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />',
    '    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />',
    '    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />',
    '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />',
    '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
    '    <uses-permission android:name="android.permission.VIBRATE" />'
)
foreach ($permissionLine in $Permissions) {
    if ($permissionLine -match 'android:name="([^"]+)"') {
        $permissionName = $Matches[1]
        if ($ManifestText -notmatch [regex]::Escape($permissionName)) {
            $ManifestText = [regex]::Replace(
                $ManifestText,
                '(<manifest\b[^>]*>)',
                [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Value + "`r`n" + $permissionLine },
                1
            )
        }
    }
}
$ManifestText = [regex]::Replace($ManifestText, 'android:label="[^"]+"', 'android:label="MotoAlert"', 1)
Set-Content -Path $ManifestPath -Value $ManifestText -Encoding utf8

# flutter_local_notifications 20+ requires core-library desugaring.
$GradleKtsPath = "android/app/build.gradle.kts"
$GradleGroovyPath = "android/app/build.gradle"
if (Test-Path $GradleKtsPath) {
    $GradlePath = $GradleKtsPath
    $GradleText = Get-Content $GradlePath -Raw
    if ($GradleText -notmatch 'isCoreLibraryDesugaringEnabled') {
        $GradleText = [regex]::Replace($GradleText, '(compileOptions\s*\{)', '$1' + "`r`n        isCoreLibraryDesugaringEnabled = true", 1)
    }
    if ($GradleText -notmatch 'multiDexEnabled') {
        $GradleText = [regex]::Replace($GradleText, '(defaultConfig\s*\{)', '$1' + "`r`n        multiDexEnabled = true", 1)
    }
    if ($GradleText -notmatch 'desugar_jdk_libs') {
        $GradleText = [regex]::Replace($GradleText, '(dependencies\s*\{)', '$1' + "`r`n    coreLibraryDesugaring(`"com.android.tools:desugar_jdk_libs:2.1.4`")", 1)
    }
    Set-Content -Path $GradlePath -Value $GradleText -Encoding utf8
} elseif (Test-Path $GradleGroovyPath) {
    $GradlePath = $GradleGroovyPath
    $GradleText = Get-Content $GradlePath -Raw
    if ($GradleText -notmatch 'coreLibraryDesugaringEnabled') {
        $GradleText = [regex]::Replace($GradleText, '(compileOptions\s*\{)', '$1' + "`r`n        coreLibraryDesugaringEnabled true", 1)
    }
    if ($GradleText -notmatch 'multiDexEnabled') {
        $GradleText = [regex]::Replace($GradleText, '(defaultConfig\s*\{)', '$1' + "`r`n        multiDexEnabled true", 1)
    }
    if ($GradleText -notmatch 'desugar_jdk_libs') {
        $GradleText = [regex]::Replace($GradleText, '(dependencies\s*\{)', '$1' + "`r`n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'", 1)
    }
    Set-Content -Path $GradlePath -Value $GradleText -Encoding utf8
}

flutter pub get
dart format lib
flutter analyze
flutter test
if ($Release) {
    flutter build apk --release --target-platform android-arm,android-arm64
    Write-Host "APK Release: $Root\build\app\outputs\flutter-apk\app-release.apk"
} else {
    flutter build apk --debug
    Write-Host "APK Debug: $Root\build\app\outputs\flutter-apk\app-debug.apk"
}
