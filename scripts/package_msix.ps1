param(
    [Parameter(Mandatory)][string]$Bundle,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][int]$BuildNumber,
    [Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string]$Arch,
    [Parameter(Mandatory)][string]$Destination
)
$ErrorActionPreference = 'Stop'
$bundlePath = (Resolve-Path $Bundle).Path
$outputPath = [IO.Path]::GetFullPath($Destination)
$tempBase = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$stage = Join-Path $tempBase "haneoka-msix-$Arch"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage, $outputPath -Force | Out-Null
Copy-Item "$bundlePath/*" $stage -Recurse -Force
$root = Split-Path $PSScriptRoot -Parent
Copy-Item (Join-Path $root 'LICENSE') $stage

# Produce package identity artwork from the existing brand asset.
Add-Type -AssemblyName System.Drawing
$assets = Join-Path $stage 'Assets'
New-Item -ItemType Directory -Path $assets -Force | Out-Null
$source = [Drawing.Image]::FromFile((Join-Path $root 'assets/brand/android-chrome-512x512.png'))
try {
    foreach ($size in @(44, 50, 150)) {
        $bitmap = [Drawing.Bitmap]::new($size, $size)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.DrawImage($source, 0, 0, $size, $size)
            $bitmap.Save((Join-Path $assets "Logo$size.png"), [Drawing.Imaging.ImageFormat]::Png)
        } finally { $graphics.Dispose(); $bitmap.Dispose() }
    }
} finally { $source.Dispose() }

$publisher = if ($env:WINDOWS_MSIX_PUBLISHER) { $env:WINDOWS_MSIX_PUBLISHER } else { 'CN=Haneoka' }
$escapedPublisher = [Security.SecurityElement]::Escape($publisher)
$components = @($Version.Split('.') | ForEach-Object { [int]$_ })
if ($components.Count -ne 3 -or $BuildNumber -lt 0 -or $BuildNumber -gt 65535 -or
    ($components | Where-Object { $_ -lt 0 -or $_ -gt 65535 })) {
    throw 'MSIX requires three version components and a build number in 0..65535.'
}
$packageVersion = "$Version.$BuildNumber"
$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
 xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
 xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
 IgnorableNamespaces="uap rescap">
 <Identity Name="Haneoka.Haneoka" Publisher="$escapedPublisher" Version="$packageVersion" ProcessorArchitecture="$Arch" />
 <Properties><DisplayName>Haneoka</DisplayName><PublisherDisplayName>Haneoka contributors</PublisherDisplayName><Logo>Assets\Logo50.png</Logo></Properties>
 <Resources><Resource Language="en-us" /></Resources>
 <Dependencies><TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17763.0" MaxVersionTested="10.0.26100.0" /></Dependencies>
 <Applications><Application Id="Haneoka" Executable="haneoka.exe" EntryPoint="Windows.FullTrustApplication">
  <uap:VisualElements DisplayName="Haneoka" Description="Our Notes catalogue and save reader" Square150x150Logo="Assets\Logo150.png" Square44x44Logo="Assets\Logo44.png" BackgroundColor="transparent" />
  <Extensions>
   <uap:Extension Category="windows.fileTypeAssociation"><uap:FileTypeAssociation Name="haneokasave"><uap:DisplayName>Our Notes Save</uap:DisplayName><uap:SupportedFileTypes><uap:FileType>.haneoka-save</uap:FileType><uap:FileType>.onpkg</uap:FileType><uap:FileType>.imazingapp</uap:FileType></uap:SupportedFileTypes></uap:FileTypeAssociation></uap:Extension>
   <uap:Extension Category="windows.protocol"><uap:Protocol Name="haneoka"><uap:DisplayName>Haneoka</uap:DisplayName></uap:Protocol></uap:Extension>
  </Extensions>
 </Application></Applications>
 <Capabilities><rescap:Capability Name="runFullTrust" /></Capabilities>
</Package>
"@
[IO.File]::WriteAllText((Join-Path $stage 'AppxManifest.xml'), $manifest, [Text.UTF8Encoding]::new($false))
$sdk = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
$tools = Get-ChildItem $sdk -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'x64/makeappx.exe') } |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (!$tools) { throw 'Windows SDK MakeAppx is required.' }
$unsigned = Join-Path $outputPath "haneoka-windows-$Arch-unsigned.msix"
& (Join-Path $tools.FullName 'x64/makeappx.exe') pack /d $stage /p $unsigned /o
if ($LASTEXITCODE -ne 0) { throw 'MSIX packaging failed' }
if ($env:WINDOWS_SIGNING_THUMBPRINT) {
    $signTool = Join-Path $tools.FullName 'x64/signtool.exe'
    & $signTool sign /sha1 $env:WINDOWS_SIGNING_THUMBPRINT /s My /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 $unsigned
    if ($LASTEXITCODE -ne 0) { throw 'MSIX signing failed' }
    & $signTool verify /pa $unsigned
    if ($LASTEXITCODE -ne 0) { throw 'MSIX signature verification failed' }
    Move-Item $unsigned (Join-Path $outputPath "haneoka-windows-$Arch.msix") -Force
    $certificate = Get-Item "Cert:/CurrentUser/My/$env:WINDOWS_SIGNING_THUMBPRINT"
    Export-Certificate -Cert $certificate -FilePath (Join-Path $outputPath 'haneoka-windows-signing.cer') -Force | Out-Null
} else {
    Write-Host 'Produced unsigned MSIX for signing. It cannot be installed until it is signed.'
}
Remove-Item $stage -Recurse -Force
