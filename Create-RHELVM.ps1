#Requires -RunAsAdministrator

param(
    [string]$IsoName=$env:ISO_NAME,
    [string]$IsoUrl=$env:ISO_URL,
    [string]$InstallDir=$env:INSTALL_DIR,
    [string]$NetAdapterName=$env:NET_ADAPTER,
    [uint64]$VmDiskSizeBytes=$env:VM_DISK_SIZE_BYTES,
    [uint64]$VmMemorySizeBytes=$env:VM_MEMORY_SIZE_BYTES,
    [string]$VmName=$env:VM_NAME,
    [string]$VmSwitchName=$env:VM_SWITCH
)

if (-not "$InstallDir") {
    $InstallDir = "${env:LOCALAPPDATA}\create-rhelvm"
}
if (-not "$IsoUrl") {
    # CODE_REVIEW_CATCH_ME:
    # these urls are only valid for a short period of time
    #   https://superuser.com/a/1549862
    # gonna need to show user link to developer site
    #    https://developers.redhat.com/products/rhel/getting-started
    # from which they can obtain a temp url and provide to this script via
    # env var or param.
    $IsoUrl = "https://access.cdn.redhat.com/content/origin/files/sha256/a1/a18bf014e2cb5b6b9cee3ea09ccfd7bc2a84e68e09487bb119a98aa0e3563ac2/rhel-9.2-x86_64-dvd.iso?_auth_=1698607846_386a4268bece18e4b5127d8b9667ade8"
}
if (-not "$IsoName") {
    $IsoName = ([System.Uri]$IsoUrl).Segments | Select-Object -Last 1
}
if (-not "$NetAdapterName") {
    $NetAdapterName = "Ethernet"
}
if (-not $VmMemorySizeBytes) {
    $VmMemorySizeBytes = 4GB
    Write-Debug "Using default VM memory size $VmMemorySizeBytes"
}
if (-not $VmDiskSizeBytes) {
    $VmDiskSizeBytes = 100GB
    Write-Debug "Using default VM disk size $VmDiskSizeBytes"
}
if (-not "$VmName") {
    $VmName = "rhel-9"
}
if (-not "$VmSwitchName") {
    $VmSwitchName = "External Switch"
}

Write-Debug "Check for Hyper-V"
if ((Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All).State -eq "Enabled") {
    Write-Information "Hyper-V already enabled"
}
else {
    Write-Information "Enabling Hyper-V"
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All

    Write-Information "Restart required.  Please restart, then run this script again"
    exit
}


if (Get-VM -Name $VmName -ErrorAction Ignore) {
    Write-Information "VM named $VmName already exists"
    exit 0
}
else {
    Write-Information "Creating VM named $VmName"
    $isoCache = "$InstallDir\isocache"
    $null = New-Item -Path "$isoCache" -Type Directory -Force
    
    $isoFile = "$isoCache\$IsoName"
    if (-not (Test-Path -Path "$isoFile" -PathType Leaf)) {
        Write-Error "EXIT EARLY <$isoFile>" -ErrorAction Stop
        Write-Information "did i get here?"
        exit 1
        Write-Information "ISO not downloaded yet, downloading"
        Start-BitsTransfer -Source "$IsoUrl" -Destination "$isoFile.TEMP"
        Move-Item -Path "$isoFile.TEMP" -Destination "$isoFile"
    }
    
    if (-not (Get-VMSwitch -Name $VmSwitchName -ErrorAction Ignore)) {
        $adapter = Get-NetAdapter -Name $NetAdapterName -ErrorAction Stop
        # this caused dhcp to renew which triggered a new IP for me... could be bad to automate
        New-VMSwitch -Name "$VmSwitchName" -NetAdapterName $adapter.Name -ErrorAction Stop
    }

    New-VM `
        -Name $VmName `
        -MemoryStartupBytes $VmMemorySizeBytes `
        -NewVHDSizeBytes $VmDiskSizeBytes `
        -BootDevice VHD `
        -NewVHDPath "$InstallDir\VMs\$VmName.vhdx" `
        -Path "$InstallDir\VMData" `
        -Generation 2 `
        -SwitchName "$VmSwitchName" `
        -ErrorAction Stop

    # automatic checkpoints are not cleaned up upon exit as they were supposed
    # to be, and any checkpoint has a performance pentalty, so we just dont
    # want them created on each boot.
    Set-VM -Name $VmName -AutomaticCheckpointsEnabled $false

    Add-VMDvdDrive -VMName "$VmName" -Path "$isoFile" -ErrorAction Stop
    Set-VMFirmware `
        -VMName "$VmName" `
        -BootOrder `
            $(Get-VMDvdDrive -VMName "$VmName"), `
            $(Get-VMHardDiskDrive -VMName "$VmName"), `
            $(Get-VMNetworkAdapter -VMName "$VmName") `
        -SecureBootTemplate "MicrosoftUEFICertificateAuthority" `
        -ErrorAction Stop

    Start-VM -Name "$VmName"
}
