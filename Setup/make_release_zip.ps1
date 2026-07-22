$ErrorActionPreference = 'Stop'

$packageName = 'Aul2MIRAI'
$pluginDir = 'C:\ProgramData\aviutl2\Plugin\Aul2MIRAI'
$workDir = Join-Path $PSScriptRoot $packageName
$zipFile = Join-Path $PSScriptRoot "$packageName.zip"

# Add future runtime files here. Destination is relative to the package root.
$packageFiles = @(
  @{
    Source = Join-Path $pluginDir 'Aul2MIRAI.aux2'
    Destination = 'Aul2MIRAI.aux2'
    Description = 'Aul2MIRAI plugin'
  }
)

foreach ($item in $packageFiles) {
  if (-not (Test-Path -LiteralPath $item.Source -PathType Leaf)) {
    Write-Host "$($item.Description) not found:"
    Write-Host "  $($item.Source)"
    Write-Host 'Build the Release configuration first, then run this batch again.'
    exit 1
  }
}

if (Test-Path -LiteralPath $workDir) {
  Remove-Item -LiteralPath $workDir -Recurse -Force
}

if (Test-Path -LiteralPath $zipFile) {
  Remove-Item -LiteralPath $zipFile -Force
}

try {
  New-Item -ItemType Directory -Path $workDir -Force | Out-Null

  foreach ($item in $packageFiles) {
    $destination = Join-Path $workDir $item.Destination
    $destinationDir = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $destinationDir)) {
      New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $item.Source -Destination $destination -Force
  }

  Compress-Archive -Path $workDir -DestinationPath $zipFile -Force
}
finally {
  if (Test-Path -LiteralPath $workDir) {
    Remove-Item -LiteralPath $workDir -Recurse -Force
  }
}

Write-Host 'Created:'
Write-Host "  $zipFile"
