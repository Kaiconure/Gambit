# Extract nine slices from the existing FFVII asset without modifying it.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$sourcePath = Join-Path $PSScriptRoot '../../ffvii-narrow.png'
$source = [Drawing.Bitmap]::FromFile([IO.Path]::GetFullPath($sourcePath))
$frame = $null
try {
    $left=$source.Width; $top=$source.Height; $right=0; $bottom=0
    for ($y=0; $y -lt $source.Height; $y++) {
        for ($x=0; $x -lt $source.Width; $x++) {
            if ($source.GetPixel($x,$y).A -gt 0) {
                $left=[Math]::Min($left,$x); $top=[Math]::Min($top,$y)
                $right=[Math]::Max($right,$x); $bottom=[Math]::Max($bottom,$y)
            }
        }
    }
    $bounds=New-Object Drawing.Rectangle($left,$top,($right-$left+1),($bottom-$top+1))
    $frame=$source.Clone($bounds,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $w=$frame.Width; $h=$frame.Height; $b=10
    $pieces=@{
        'top-left'=@(0,0,$b,$b); 'top-right'=@(($w-$b),0,$b,$b)
        'bottom-left'=@(0,($h-$b),$b,$b); 'bottom-right'=@(($w-$b),($h-$b),$b,$b)
        'top'=@($b,0,($w-2*$b),$b); 'bottom'=@($b,($h-$b),($w-2*$b),$b)
        'left'=@(0,$b,$b,($h-2*$b)); 'right'=@(($w-$b),$b,$b,($h-2*$b))
        'center'=@($b,$b,($w-2*$b),($h-2*$b))
    }
    foreach ($name in $pieces.Keys) {
        $r=$pieces[$name]
        $rectangle=New-Object Drawing.Rectangle($r[0],$r[1],$r[2],$r[3])
        $piece=$frame.Clone($rectangle,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try { $piece.Save((Join-Path $PSScriptRoot ($name+'.png')),[Drawing.Imaging.ImageFormat]::Png) }
        finally { $piece.Dispose() }
    }
    $frame.Save((Join-Path $PSScriptRoot 'preview.png'),[Drawing.Imaging.ImageFormat]::Png)
    "Extracted FF7 skin: $w x $h, $b-pixel corners; source unchanged."
} finally {
    if ($frame) { $frame.Dispose() }
    $source.Dispose()
}
