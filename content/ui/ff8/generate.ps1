# Recreate the reference's simple gray gradient and bevel using geometric pixels.
# This is a procedural interpretation, not a pixel extraction of the screenshot.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$skinRoot = $PSScriptRoot
$canvasWidth = 1104
$canvasHeight = 120
$border = 5
$bitmap = New-Object System.Drawing.Bitmap($canvasWidth, $canvasHeight)
try {
    for ($y = 0; $y -lt $canvasHeight; $y++) {
        for ($x = 0; $x -lt $canvasWidth; $x++) {
            $edge = [Math]::Min([Math]::Min($x, $canvasWidth-1-$x), [Math]::Min($y, $canvasHeight-1-$y))
            $shade = [int](85 + 51 * $x / ($canvasWidth-1))
            if ($edge -eq 0) { $shade = 8 }
            elseif ($edge -lt $border) {
                $brightSide = [Math]::Min($x, $y) -le [Math]::Min($canvasWidth-1-$x, $canvasHeight-1-$y)
                if ($brightSide) { $shade = @(0, 196, 156, 137, 119)[$edge] }
                else { $shade = @(0, 40, 53, 65, 76)[$edge] }
            }
            $bitmap.SetPixel($x, $y, [Drawing.Color]::FromArgb(255, $shade, $shade, $shade))
        }
    }
    $pieces = @{
        'top-left' = @(0,0,$border,$border)
        'top-right' = @(($canvasWidth-$border),0,$border,$border)
        'bottom-left' = @(0,($canvasHeight-$border),$border,$border)
        'bottom-right' = @(($canvasWidth-$border),($canvasHeight-$border),$border,$border)
        'top' = @($border,0,($canvasWidth-2*$border),$border)
        'bottom' = @($border,($canvasHeight-$border),($canvasWidth-2*$border),$border)
        'left' = @(0,$border,$border,($canvasHeight-2*$border))
        'right' = @(($canvasWidth-$border),$border,$border,($canvasHeight-2*$border))
        'center' = @($border,$border,($canvasWidth-2*$border),($canvasHeight-2*$border))
    }
    foreach ($name in $pieces.Keys) {
        $r = $pieces[$name]
        $rectangle = New-Object Drawing.Rectangle($r[0],$r[1],$r[2],$r[3])
        $piece = $bitmap.Clone($rectangle, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try { $piece.Save((Join-Path $skinRoot ($name+'.png')), [Drawing.Imaging.ImageFormat]::Png) }
        finally { $piece.Dispose() }
    }
    $bitmap.Save((Join-Path $skinRoot 'preview.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally { $bitmap.Dispose() }
