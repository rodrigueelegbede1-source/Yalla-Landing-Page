# Génère les icônes Android de Yalla, aux cinq densités, à partir de la marque.
#
#   powershell -ExecutionPolicy Bypass -File scripts/generer-icone.ps1
#
# POURQUOI DESSINER PLUTÔT QU'IMPORTER UNE IMAGE. Le motif est le même que celui
# du site : fond vert, « Y » jaune formé d'un trait et d'un carton incliné, roue
# en bas. Le garder décrit en code évite d'avoir à versionner dix PNG et à les
# regénérer à la main chaque fois que la charte bouge, et surtout il garantit
# que l'application et le site portent exactement le même signe. Un boutiquier
# qui a vu l'affiche doit reconnaître l'icône sur son téléphone.
#
# Deux jeux de fichiers sont produits, parce qu'Android en veut deux :
#
#   * `ic_launcher.png`, l'icône classique, pour Android 7 et avant ;
#   * `ic_launcher_foreground.png` plus un fond de couleur, pour l'icône
#     adaptative d'Android 8 et suivants, que le constructeur découpe en rond,
#     en carré ou en goutte selon son lanceur. Le motif y occupe 60 % du centre :
#     au-delà, les coins se font rogner par les masques les plus agressifs, et
#     c'est ainsi qu'on obtient une icône amputée sur un Tecno.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$racine = Split-Path -Parent $PSScriptRoot
$res = Join-Path $racine 'mobile\android\app\src\main\res'

$vert  = [System.Drawing.Color]::FromArgb(255, 20, 107, 58)   # #146B3A
$jaune = [System.Drawing.Color]::FromArgb(255, 255, 229, 0)   # #FFE500

# Dessine le motif dans un carré de côté $taille, à l'échelle demandée.
# $proportion vaut 1 pour l'icône classique, qui remplit toute la surface, et
# 0.60 pour le premier plan adaptatif, qui doit tenir dans la zone sûre.
function Dessiner-Motif {
    param(
        [System.Drawing.Graphics] $g,
        [int] $taille,
        [double] $proportion
    )

    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    # Repère de 100 unités, comme le SVG du site, recentré et mis à l'échelle.
    $u = $taille * $proportion / 100.0
    $dx = ($taille - 100 * $u) / 2.0
    $dy = ($taille - 100 * $u) / 2.0
    function P([double]$x, [double]$y) {
        return New-Object System.Drawing.PointF(($dx + $x * $u), ($dy + $y * $u))
    }

    $pinceau = New-Object System.Drawing.SolidBrush($jaune)
    $stylo = New-Object System.Drawing.Pen($jaune, [float](11 * $u))
    $stylo.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $stylo.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    $stylo.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round

    # La branche du Y : le trait qui descend de la gauche vers le centre.
    $g.DrawLines($stylo, @((P 28 30), (P 38 30), (P 52 60)))

    # Le carton incliné, qui fait la seconde branche du Y.
    $etat = $g.Save()
    $centre = P 64 36
    $g.TranslateTransform($centre.X, $centre.Y)
    $g.RotateTransform(-18)
    $cote = 24 * $u
    $rayon = 3 * $u
    $chemin = New-Object System.Drawing.Drawing2D.GraphicsPath
    $x0 = -$cote / 2; $y0 = -$cote / 2; $d = 2 * $rayon
    $chemin.AddArc($x0, $y0, $d, $d, 180, 90)
    $chemin.AddArc($x0 + $cote - $d, $y0, $d, $d, 270, 90)
    $chemin.AddArc($x0 + $cote - $d, $y0 + $cote - $d, $d, $d, 0, 90)
    $chemin.AddArc($x0, $y0 + $cote - $d, $d, $d, 90, 90)
    $chemin.CloseFigure()
    $g.FillPath($pinceau, $chemin)
    $chemin.Dispose()
    $g.Restore($etat)

    # La roue, en pied du Y : c'est elle qui dit « livraison » et non « lettre Y ».
    $c = P 50 72
    $r = 8 * $u
    $g.FillEllipse($pinceau, ($c.X - $r), ($c.Y - $r), (2 * $r), (2 * $r))

    $stylo.Dispose()
    $pinceau.Dispose()
}

function Ecrire-Icone {
    param([string] $chemin, [int] $taille, [bool] $avecFond, [double] $proportion)

    $bmp = New-Object System.Drawing.Bitmap($taille, $taille)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    if ($avecFond) {
        # Carré à coins arrondis, comme le favicon du site (rayon 22 sur 100).
        $pinceau = New-Object System.Drawing.SolidBrush($vert)
        $rayon = $taille * 0.22
        $d = 2 * $rayon
        $trace = New-Object System.Drawing.Drawing2D.GraphicsPath
        $trace.AddArc(0, 0, $d, $d, 180, 90)
        $trace.AddArc($taille - $d, 0, $d, $d, 270, 90)
        $trace.AddArc($taille - $d, $taille - $d, $d, $d, 0, 90)
        $trace.AddArc(0, $taille - $d, $d, $d, 90, 90)
        $trace.CloseFigure()
        $g.FillPath($pinceau, $trace)
        $trace.Dispose()
        $pinceau.Dispose()
    }

    Dessiner-Motif -g $g -taille $taille -proportion $proportion

    $dossier = Split-Path -Parent $chemin
    if (-not (Test-Path $dossier)) { New-Item -ItemType Directory -Force -Path $dossier | Out-Null }
    $bmp.Save($chemin, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    Write-Output ("  " + (Split-Path -Leaf $dossier) + " : " + $taille + " px")
}

# Densités Android. L'icône classique fait 48 dp, le premier plan adaptatif
# 108 dp, dont seuls les 72 dp centraux sont garantis visibles.
$densites = @(
    @{ nom = 'mdpi';    facteur = 1.0 },
    @{ nom = 'hdpi';    facteur = 1.5 },
    @{ nom = 'xhdpi';   facteur = 2.0 },
    @{ nom = 'xxhdpi';  facteur = 3.0 },
    @{ nom = 'xxxhdpi'; facteur = 4.0 }
)

Write-Output ''
Write-Output 'Icone classique'
foreach ($d in $densites) {
    $t = [int](48 * $d.facteur)
    Ecrire-Icone -chemin (Join-Path $res ("mipmap-" + $d.nom + "\ic_launcher.png")) `
                 -taille $t -avecFond $true -proportion 1.0
}

Write-Output ''
Write-Output 'Premier plan adaptatif'
foreach ($d in $densites) {
    $t = [int](108 * $d.facteur)
    Ecrire-Icone -chemin (Join-Path $res ("mipmap-" + $d.nom + "\ic_launcher_foreground.png")) `
                 -taille $t -avecFond $false -proportion 0.60
}

# Le fond de l'icône adaptative, et sa déclaration.
$valeurs = Join-Path $res 'values'
if (-not (Test-Path $valeurs)) { New-Item -ItemType Directory -Force -Path $valeurs | Out-Null }
@'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Le vert de la charte Yalla, celui du site. -->
    <color name="ic_launcher_background">#146B3A</color>
</resources>
'@ | Set-Content -Path (Join-Path $valeurs 'ic_launcher_background.xml') -Encoding UTF8

$anydpi = Join-Path $res 'mipmap-anydpi-v26'
if (-not (Test-Path $anydpi)) { New-Item -ItemType Directory -Force -Path $anydpi | Out-Null }
@'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
'@ | Set-Content -Path (Join-Path $anydpi 'ic_launcher.xml') -Encoding UTF8

Write-Output ''
Write-Output 'Icone adaptative declaree. Reconstruire l APK pour la voir.'
Write-Output ''
