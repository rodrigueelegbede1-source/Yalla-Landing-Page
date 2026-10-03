$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mobile = Join-Path $root 'mobile'

function Require-Command([string] $name, [string] $hint) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "$name introuvable dans le PATH. $hint"
    }
    Write-Host "OK $name"
}

Write-Host 'Yalla - pre-vol de release'
Require-Command 'flutter' 'Installez Flutter et redemarrez PowerShell.'
Require-Command 'java' 'Installez un JDK compatible Android.'

$keyProperties = Join-Path $mobile 'android\key.properties'
if (-not (Test-Path $keyProperties)) {
    throw 'mobile/android/key.properties absent : impossible de certifier une release.'
}

Push-Location $mobile
try {
    flutter pub get
    flutter analyze
    flutter test
    flutter build apk --release --target-platform android-arm,android-arm64
} finally {
    Pop-Location
}

$apk = Join-Path $mobile 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $apk)) {
    throw "APK absente apres compilation : $apk"
}

$sizeMb = [math]::Round((Get-Item $apk).Length / 1MB, 2)
if ($sizeMb -gt 49) {
    throw "APK trop volumineuse ($sizeMb Mo), limite de publication: 49 Mo."
}

$apksigner = Get-Command apksigner -ErrorAction SilentlyContinue
if ($apksigner) {
    & $apksigner.Source verify --verbose $apk
    if ($LASTEXITCODE -ne 0) {
        throw 'La signature APK est invalide.'
    }
} else {
    Write-Warning 'apksigner absent : verification cryptographique reportee.'
}

Write-Host "RELEASE VALIDEE: $apk ($sizeMb Mo)"
