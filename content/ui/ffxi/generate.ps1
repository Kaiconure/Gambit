# Normalize the retained center asset and rebuild the preview from runtime assets.
# No separate full-resolution source image is required.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$centerPath = Join-Path $PSScriptRoot 'center.png'
$source = [Drawing.Bitmap]::FromFile($centerPath)
$center = $null
$preview = $null
try {
    $resizeNeeded = $source.Width -ne 300 -or $source.Height -ne 400
    $center = New-Object Drawing.Bitmap(300,400)
    $graphics = [Drawing.Graphics]::FromImage($center)
    try {
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($source,[Drawing.Rectangle]::new(0,0,300,400),
            [Drawing.Rectangle]::new(0,0,$source.Width,$source.Height),[Drawing.GraphicsUnit]::Pixel)
    } finally { $graphics.Dispose() }
    $source.Dispose()
    $source = $null
    # Avoid rewriting already normalized artwork on repeated runs.
    if ($resizeNeeded) {
        $center.Save($centerPath,[Drawing.Imaging.ImageFormat]::Png)
    }
    $registry = Get-Content (Join-Path $PSScriptRoot '../themes.json') -Raw | ConvertFrom-Json
    $textureHeight = $registry.ffxi.texture_height
    $border = $registry.ffxi.border
    $pw=580; $ph=300
    $preview = New-Object Drawing.Bitmap($pw,$ph)
    $graphics = [Drawing.Graphics]::FromImage($preview)
    try {
        # Match the renderer: stretch across width, repeat at texture_height.
        for ($y=$border; $y -lt $ph-$border; $y+=$textureHeight) {
            $height=[Math]::Min($textureHeight,$ph-$border-$y)
            $graphics.DrawImage($center,[Drawing.Rectangle]::new(0,$y,$pw,$height),
                [Drawing.Rectangle]::new(0,0,$center.Width,[int]($center.Height*$height/$textureHeight)),
                [Drawing.GraphicsUnit]::Pixel)
        }
        foreach ($edge in @('top','bottom')) {
            $edgeImage=[Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot ($edge+'.png')))
            try {
                $y=0
                if ($edge -eq 'bottom') { $y=$ph-$border }
                $graphics.DrawImage($edgeImage,[Drawing.Rectangle]::new(0,$y,$pw,$border),
                    [Drawing.Rectangle]::new(0,0,$edgeImage.Width,$edgeImage.Height),[Drawing.GraphicsUnit]::Pixel)
            } finally { $edgeImage.Dispose() }
        }
    } finally { $graphics.Dispose() }
    $preview.Save((Join-Path $PSScriptRoot 'preview.png'),[Drawing.Imaging.ImageFormat]::Png)
    "FFXI center: 300x400; rebuilt ${pw}x${ph} preview from retained assets."
} finally {
    if ($preview) { $preview.Dispose() }
    if ($center) { $center.Dispose() }
    if ($source) { $source.Dispose() }
}
