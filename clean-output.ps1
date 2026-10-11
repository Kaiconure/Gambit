$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'settings')).Path.TrimEnd('\')
$prefix = $root + '\'

$folders = Get-ChildItem -LiteralPath $root -Directory -Force -Recurse -Filter '.output' |
Where-Object { $_.FullName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) } |
Sort-Object { $_.FullName.Length } -Descending

$folders | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Recurse -Force -WhatIf
    # Remove-Item -LiteralPath $_.FullName -Recurse -Force
}