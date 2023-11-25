#Requires -RunAsAdministrator

param(
    [string]$InstallDir=$env:INSTALL_DIR,
    [string]$NetAdapterName=$env:NET_ADAPTER,
    [Parameter(Position=0,mandatory=$true)]
    [string]$VmName=$env:VM_NAME,
    [string]$VmSwitchName=$env:VM_SWITCH
)

if (-not "$InstallDir") {
    $InstallDir = "${env:LOCALAPPDATA}\create-rhelvm"
}
if (-not "$NetAdapterName") {
    $NetAdapterName = "Ethernet"
}
if (-not "$VmSwitchName") {
    $VmSwitchName = "External Switch"
}

# CODE_REVIEW_CATCH_ME, may wanna see about dropping the swithc if not used by
# any other vm...  since it gets created as needed by the create-rhelvm
if (Get-VM -Name $VmName -ErrorAction Ignore) {
    Stop-VM -Name "$VmName" -Force -ErrorAction SilentlyContinue
    Remove-VM -Name "$VmName" -Force
    Write-Information "VM named $VmName already exists"
    exit 0
}
else {
    Write-Information "No VM named $VmName exists"
}

# if snapshotting was enabled a snapshot disk may exist
$diffDisk = (Get-VHD "$InstallDir\VMs\${VmName}_*.avhdx").Path
if (Test-Path -PathType Leaf -Path "$diffDisk") {
    Dismount-DiskImage -ImagePath "$diffDisk" -ErrorAction Continue
    Remove-Item -Path "$diffDisk" -Force -ErrorAction Continue
}

Dismount-DiskImage -ImagePath "$InstallDir\VMs\$VmName.vhdx" -ErrorAction Continue
Remove-Item "$InstallDir\VMs\$VmName.vhdx" -Force -ErrorAction Continue

Remove-Item "$InstallDir\VMData\$VmName" -Recurse -Force -ErrorAction Continue
