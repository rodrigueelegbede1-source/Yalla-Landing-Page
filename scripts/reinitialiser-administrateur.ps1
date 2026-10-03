$ErrorActionPreference = 'Stop'
$envPath = if ($env:YALLA_ENV) { $env:YALLA_ENV } else { Join-Path $env:USERPROFILE 'Downloads\jarvis-starter-kit\.env' }
if (-not (Test-Path $envPath)) { throw "Fichier .env introuvable : $envPath" }

$vars = @{}
Get-Content $envPath | ForEach-Object {
    if ($_ -match '^([^#=]+)=(.*)$') { $vars[$matches[1].Trim()] = $matches[2].Trim().Trim('"', "'") }
}
$url = $vars['SUPABASE_URL']
$service = $vars['SUPABASE_SERVICE_ROLE_KEY']
$anon = $vars['SUPABASE_ANON_KEY']
if (-not $url -or -not $service -or -not $anon) { throw 'SUPABASE_URL, SUPABASE_ANON_KEY ou SUPABASE_SERVICE_ROLE_KEY absent du .env' }

$phone = '2250706303030'
$lookupFile = Join-Path $env:TEMP "yalla-admin-lookup-$PID.json"
try {
    & curl.exe -fsS -o $lookupFile -H "apikey: $service" -H "Authorization: Bearer $service" `
        "$url/rest/v1/utilisateurs?telephone=eq.$phone&select=auth_user_id,role,nom"
    if ($LASTEXITCODE -ne 0) { throw 'La lecture du compte Supabase a échoué' }
    $users = @(Get-Content $lookupFile -Raw | ConvertFrom-Json)
} finally {
    Remove-Item $lookupFile -Force -ErrorAction SilentlyContinue
}
if ($users.Count -ne 1) { throw "Compte administrateur introuvable ou ambigu pour 0706303030" }
if ($users[0].role -ne 'administrateur') { throw "Le compte existe mais son rôle est $($users[0].role), pas administrateur" }
if (-not $users[0].auth_user_id) { throw 'Le compte administrateur n’a pas d’identité Auth rattachée' }

$password = $env:YALLA_ADMIN_PASSWORD
if (-not $password) {
    $alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'.ToCharArray()
    $bytes = New-Object byte[] 10
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $password = -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
}
if ($password.Length -lt 8) { throw 'Le mot de passe doit contenir au moins 8 caractères' }
$body = @{ password = $password } | ConvertTo-Json -Compress
$bodyFile = Join-Path $env:TEMP "yalla-admin-password-$PID.json"
try {
    Set-Content -Path $bodyFile -Value $body -NoNewline
    & curl.exe -fsS -o NUL -X PUT -H "apikey: $service" -H "Authorization: Bearer $service" `
        -H 'Content-Type: application/json' --data-binary "@$bodyFile" `
        "$url/auth/v1/admin/users/$($users[0].auth_user_id)"
    if ($LASTEXITCODE -ne 0) { throw 'La réinitialisation Supabase a échoué' }
} finally {
    Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue
}

Write-Output 'Mot de passe administrateur réinitialisé.'
Write-Output 'Identifiant : 0706303030'
Write-Output "Mot de passe : $password"
Write-Output 'Conservez ce mot de passe : il ne sera plus affiché.'
