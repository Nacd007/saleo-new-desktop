$ErrorActionPreference = 'Stop'
$saleoProjectRoot = 'C:\Users\wim\Desktop\Saleo_New_Desktop'
$saleoBuildOutput = Join-Path $saleoProjectRoot 'build\windows\x64\runner\Release'
$saleoCurrentPackage = Join-Path $saleoProjectRoot 'App'
$saleoPreparedPackage = Join-Path $saleoProjectRoot 'App-update-ready'
$saleoPreviousPackage = Join-Path $saleoProjectRoot 'App-previous-1.0.5-before-session-revocation'
foreach ($saleoTarget in @($saleoBuildOutput,$saleoCurrentPackage,$saleoPreparedPackage,$saleoPreviousPackage)) {
    $saleoAbsoluteTarget = [IO.Path]::GetFullPath($saleoTarget)
    if (-not $saleoAbsoluteTarget.StartsWith($saleoProjectRoot + '\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Package target is outside the Windows project.'
    }
}
if (Get-Process -Name Saleo_New_Desktop -ErrorAction SilentlyContinue) { throw 'Close Saleo before installing this update.' }
if ((Test-Path -LiteralPath $saleoPreparedPackage) -or (Test-Path -LiteralPath $saleoPreviousPackage)) { throw 'An update/rollback directory already exists; inspect before replacing it.' }
if (-not (Test-Path -LiteralPath (Join-Path $saleoBuildOutput 'Saleo_New_Desktop.exe'))) { throw 'New Windows executable is missing.' }
New-Item -ItemType Directory -Path $saleoPreparedPackage | Out-Null
foreach ($saleoBuildFile in Get-ChildItem -LiteralPath $saleoBuildOutput) {
    Copy-Item -LiteralPath $saleoBuildFile.FullName -Destination $saleoPreparedPackage -Recurse
}
$saleoSourceExe = Join-Path $saleoBuildOutput 'Saleo_New_Desktop.exe'
$saleoPreparedExe = Join-Path $saleoPreparedPackage 'Saleo_New_Desktop.exe'
function Assert-PackageMatches($source, $destination) {
    $sourceFiles = @(Get-ChildItem -LiteralPath $source -Recurse -File)
    $destinationFiles = @(Get-ChildItem -LiteralPath $destination -Recurse -File)
    if ($sourceFiles.Count -ne $destinationFiles.Count) { throw 'Package file counts do not match.' }
    foreach ($file in $sourceFiles) {
        $relative = $file.FullName.Substring($source.Length).TrimStart('\')
        $copied = Join-Path $destination $relative
        if (-not (Test-Path -LiteralPath $copied -PathType Leaf)) { throw ('Missing package file: ' + $relative) }
        if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $copied).Hash) { throw ('Package checksum mismatch: ' + $relative) }
    }
}
Assert-PackageMatches $saleoBuildOutput $saleoPreparedPackage
if (Get-Process -Name Saleo_New_Desktop -ErrorAction SilentlyContinue) { throw 'Close Saleo before installing this update.' }
Move-Item -LiteralPath $saleoCurrentPackage -Destination $saleoPreviousPackage
try {
    Move-Item -LiteralPath $saleoPreparedPackage -Destination $saleoCurrentPackage
} catch {
    Move-Item -LiteralPath $saleoPreviousPackage -Destination $saleoCurrentPackage
    throw
}
Assert-PackageMatches $saleoBuildOutput $saleoCurrentPackage
Write-Output 'Windows app updated; previous package kept as App-previous-1.0.5-before-session-revocation. Local company databases were not accessed.'
Get-Item -LiteralPath (Join-Path $saleoCurrentPackage 'Saleo_New_Desktop.exe') | ForEach-Object { Write-Output ('Executable version: ' + $_.VersionInfo.FileVersion) }
