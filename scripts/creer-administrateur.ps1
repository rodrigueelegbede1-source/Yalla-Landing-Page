$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$envPath = if ($env:YALLA_ENV) { $env:YALLA_ENV } else { Join-Path $env:USERPROFILE 'Downloads\jarvis-starter-kit\.env' }

if (-not (Test-Path $envPath)) { throw "Fichier .env introuvable : $envPath" }
$variables = @{}
Get-Content $envPath | ForEach-Object {
    if ($_ -match '^([^#=]+)=(.*)$') { $variables[$matches[1].Trim()] = $matches[2].Trim().Trim('"', "'") }
}

$url = $variables['SUPABASE_URL']
$service = $variables['SUPABASE_SERVICE_ROLE_KEY']
$anon = $variables['SUPABASE_ANON_KEY']
if (-not $url -or -not $service -or -not $anon) { throw 'SUPABASE_URL, SUPABASE_ANON_KEY ou SUPABASE_SERVICE_ROLE_KEY absent du .env' }

$name = if ($args.Count -ge 1) { $args[0] } else { 'Administrateur Yalla' }
$rawPhone = if ($args.Count -ge 2) { $args[1] } else { '0706303030' }
$phone = ($rawPhone -replace '[^0-9]', '')
if ($phone.StartsWith('00225')) { $phone = $phone.Substring(2) }
if ($phone.Length -eq 10) { $phone = "225$phone" }
if ($phone.Length -ne 13) { throw "Numero ivoirien invalide : $rawPhone" }

$email = "$phone@yalla.ci"

$lookup = Join-Path $env:TEMP "yalla-create-admin-lookup-$PID.json"
& curl.exe -fsS -o $lookup -H "apikey: $service" -H "Authorization: Bearer $service" `
    "$url/rest/v1/utilisateurs?telephone=eq.$phone&select=id,auth_user_id,role"
if ($LASTEXITCODE -ne 0) { throw 'Lecture Supabase impossible' }
$existing = @(Get-Content $lookup -Raw | ConvertFrom-Json)
Remove-Item $lookup -Force -ErrorAction SilentlyContinue
if ($existing.Count -gt 0 -and $existing[0].PSObject.Properties.Name -contains 'role') {
    throw "Un utilisateur existe deja pour $($phone.Substring(3)). Aucun doublon cree."
}

$password = $env:YALLA_ADMIN_PASSWORD
if (-not $password) {
    $alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'.ToCharArray()
    $bytes = New-Object byte[] 10
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $password = -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
}
if ($password.Length -lt 8) { throw 'Le mot de passe doit contenir au moins 8 caractères' }

$authBody = @{ email = $email; password = $password; email_confirm = $true } | ConvertTo-Json -Compress
$authFile = Join-Path $env:TEMP "yalla-create-admin-auth-$PID.json"
$authResponse = Join-Path $env:TEMP "yalla-create-admin-auth-response-$PID.json"
Set-Content $authFile $authBody -NoNewline
& curl.exe -fsS -o $authResponse -X POST -H "apikey: $service" -H "Authorization: Bearer $service" `
    -H 'Content-Type: application/json' --data-binary "@$authFile" "$url/auth/v1/admin/users"
if ($LASTEXITCODE -ne 0) { throw 'Création Supabase Auth impossible' }
$auth = Get-Content $authResponse -Raw | ConvertFrom-Json
if (-not $auth.id) { throw 'Supabase Auth n’a pas renvoyé d’identifiant utilisateur' }
Remove-Item $authFile,$authResponse -Force -ErrorAction SilentlyContinue

try {
    $userBody = @{
        nom = $name
        telephone = $phone
        role = 'administrateur'
        auth_user_id = $auth.id
    } | ConvertTo-Json -Compress
    $userFile = Join-Path $env:TEMP "yalla-create-admin-user-$PID.json"
    Set-Content $userFile $userBody -NoNewline
    & curl.exe -fsS -o NUL -X POST -H "apikey: $service" -H "Authorization: Bearer $service" `
        -H 'Content-Type: application/json' -H 'Prefer: return=minimal' --data-binary "@$userFile" "$url/rest/v1/utilisateurs"
    if ($LASTEXITCODE -ne 0) { throw 'Création de la ligne administrateur impossible' }
    Remove-Item $userFile -Force -ErrorAction SilentlyContinue
}
catch {
    try { & curl.exe -sS -o NUL -X DELETE -H "apikey: $service" -H "Authorization: Bearer $service" "$url/auth/v1/admin/users/$($auth.id)" } catch {}
    throw "La ligne administrateur n'a pas ete creee; le compte Auth a ete annule. $($_.Exception.Message)"
}

Write-Output "Administrateur cree : $name"
Write-Output "Identifiant : $($phone.Substring(3))"
Write-Output "Mot de passe : $password"
Write-Output 'Conservez ce mot de passe : il ne sera plus affiche.'
