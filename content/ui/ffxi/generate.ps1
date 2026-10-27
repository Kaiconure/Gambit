# Build a nine-slice frame from the cleaned artwork. The source is never modified.
# Its horizontal silver trim supplies the profile for all four sides.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$source = [Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'cleaned-background.png'))
$frame = $null
$preview = $null
try {
    $b = 6
    $trim = 24
    $w = $source.Width
    $h = $source.Height - 2*$trim + 2*$b
    $frame = New-Object Drawing.Bitmap($w,$h)
    $graphics = [Drawing.Graphics]::FromImage($frame)
    try {
        $graphics.DrawImage($source, [Drawing.Rectangle]::new(0,0,$w,$h),
            [Drawing.Rectangle]::new(0,$trim,$source.Width,($source.Height-2*$trim)),
            [Drawing.GraphicsUnit]::Pixel)
    } finally { $graphics.Dispose() }

    # Rounded outer corners with one-pixel alpha coverage. At the inside of the
    # frame, retain the texture already drawn underneath the silver profile.
    for ($y=0; $y -lt $h; $y++) {
        for ($x=0; $x -lt $w; $x++) {
            $dx = [Math]::Min($x,$w-1-$x)
            $dy = [Math]::Min($y,$h-1-$y)
            if ($dx -ge $b -and $dy -ge $b) { continue }
            $depth = [double][Math]::Min($dx,$dy)
            if ($dx -lt $b -and $dy -lt $b) {
                $depth = $b - [Math]::Sqrt([Math]::Pow($b-$dx-0.5,2) + [Math]::Pow($b-$dy-0.5,2))
            }
            if ($depth -lt -0.5) {
                $frame.SetPixel($x,$y,[Drawing.Color]::Transparent)
            } else {
                $sampleY = [int][Math]::Round([Math]::Max(0,$depth)*($trim-1)/($b-1))
                $sampleY = [Math]::Min($trim-1,$sampleY)
                $color = $source.GetPixel([int]($source.Width/2),$sampleY)
                $alpha = [int](255*[Math]::Min(1,[Math]::Max(0,$depth+0.5)))
                $frame.SetPixel($x,$y,[Drawing.Color]::FromArgb($alpha,$color.R,$color.G,$color.B))
            }
        }
    }
    $pieces = @{
        'top-left'=@(0,0,$b,$b); 'top-right'=@(($w-$b),0,$b,$b)
        'bottom-left'=@(0,($h-$b),$b,$b); 'bottom-right'=@(($w-$b),($h-$b),$b,$b)
        'top'=@($b,0,($w-2*$b),$b); 'bottom'=@($b,($h-$b),($w-2*$b),$b)
        'left'=@(0,$b,$b,($h-2*$b)); 'right'=@(($w-$b),$b,$b,($h-2*$b))
        'center'=@($b,$b,($w-2*$b),($h-2*$b))
    }
    # Assemble a preview using the same fixed corners and stretched edges as Lua.
    $pw=580; $ph=300
    $preview=New-Object Drawing.Bitmap($pw,$ph)
    $graphics=[Drawing.Graphics]::FromImage($preview)
    try {
        foreach ($name in $pieces.Keys) {
            # FFXI uses only horizontal trim; no side or corner assets.
            if ($name -match 'left|right') { continue }
            $r=$pieces[$name]
            $piece=$frame.Clone([Drawing.Rectangle]::new($r[0],$r[1],$r[2],$r[3]),
                [Drawing.Imaging.PixelFormat]::Format32bppArgb)
            try {
                $piece.Save((Join-Path $PSScriptRoot ($name+'.png')),[Drawing.Imaging.ImageFormat]::Png)
                $px=0; $py=$b; $width=$pw; $height=$ph-2*$b
                if ($name -match 'left') { $px=0; $width=$b }
                if ($name -match 'right') { $px=$pw-$b; $width=$b }
                if ($name -match 'top') { $py=0; $height=$b }
                if ($name -match 'bottom') { $py=$ph-$b; $height=$b }
                $sampleHeight=$piece.Height
                if ($name -eq 'center') { $sampleHeight=[int]($piece.Height*$height/400) }
                $graphics.DrawImage($piece,[Drawing.Rectangle]::new($px,$py,$width,$height),
                    [Drawing.Rectangle]::new(0,0,$piece.Width,$sampleHeight),[Drawing.GraphicsUnit]::Pixel)
            } finally { $piece.Dispose() }
        }
    } finally { $graphics.Dispose() }
    $preview.Save((Join-Path $PSScriptRoot 'preview.png'),[Drawing.Imaging.ImageFormat]::Png)
    "Generated FFXI skin: center and horizontal trim, $b-pixel borders, ${pw}x${ph} preview."
} finally {
    if ($preview) { $preview.Dispose() }
    if ($frame) { $frame.Dispose() }
    $source.Dispose()
}
