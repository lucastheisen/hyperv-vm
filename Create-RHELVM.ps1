#Requires -RunAsAdministrator

param(
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
    
    $isoFile = "$isoCache\$vmName.iso"
    if (-not (Test-Path -Path "$isoFile" -PathType Leaf)) {
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
        -NewVHDPath "$InstallDir\VMs\$vmName.vhdx" `
        -Path "$InstallDir\VMData" `
        -Generation 2 `
        -Switch "$VmSwitchName" `
        -ErrorAction Stop

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

# $vmDir = "${env:LOCALAPPDATA}\$VmName"
# $null = New-Item -Path "$vmDir" -Type Directory -Force
# 
# Write-Information "Import WSL distribution"
# $console = ([console]::OutputEncoding)
# [console]::OutputEncoding = New-Object System.Text.UnicodeEncoding
# $wslMatcher = (wsl --list --quiet | Select-String -Pattern "(?m)^$WslName$")
# [console]::OutputEncoding = $console
# if (-not $wslMatcher.Matches) {
#     Write-Information "WSL distribution $WslName not yet installed, installing"
#     $distroCache = "$InstallDir\distrocache"
#     $null = New-Item -Path "$distroCache" -Type Directory -Force
# 
#     $wslDir = "${env:LOCALAPPDATA}\$WslName"
#     $null = New-Item -Path "$wslDir" -Type Directory -Force
# 
#     $distroFile = "$distroCache\$WslName.tar.xz"
#     if (-not (Test-Path -Path "$distroFile" -PathType Leaf)) {
#         Start-BitsTransfer -Source "$DistroUrl" -Destination "$distroFile"
#     }
# 
#     $wslVolume = "$wslDir\volume"
#     wsl --import "$WslName" "$wslVolume" "$distroFile"
# 
#     Write-Information "Configure WSL $WslName"
#     wsl --distribution "$WslName" --user root --exec `
#         bash -c "
#             . /etc/os-release
#             if [[ `"`${ID_LIKE}`" =~ rhel ]]; then
#               dnf install --assumeyes systemd
#             fi
# 
#             cat > /etc/wsl.conf <<'EOF'
# [boot]
# systemd=true
# [user]
# default=$WslUsername
# EOF
#             chmod 0644 /etc/wsl.conf
#             "
#     # terminate to satisfy the 8 second rule (may need to switch to shutdown)
#     #   https://learn.microsoft.com/en-us/windows/wsl/wsl-config#the-8-second-rule
#     wsl --terminate "$WslName"
# }
# 
# Write-Information "WSL user $WslUsername"
# wsl --distribution "$WslName" --user root --exec `
#     bash -c "grep '$WslUsername' /etc/passwd"
# if (-not $?) {
#     Write-Information "$WslUsername does not exist, creating..."
#     wsl --distribution "$WslName" --user root --exec `
#         bash -c "
# useradd --create-home '$WslUsername' --shell /bin/bash
# dnf install --assumeyes sudo
# mkdir --parents /etc/sudoers.d
# echo '$WslUsername ALL=(ALL) NOPASSWD:ALL' > '/etc/sudoers.d/$WslUsername'
# chmod 0440 '/etc/sudoers.d/$WslUsername'
#         "
# }
# 
# Write-Information "Setup ansible"
# $configureAnsible = "$env:TEMP\ConfigureRemotingForAnsible.ps1"
# Start-BitsTransfer `
#     -Source "https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1" `
#     -Destination "$configureAnsible"
# Write-Information "Running $configureAnsible"
# powershell.exe -NoProfile -ExecutionPolicy ByPass -File "$configureAnsible" -DisableBasicAuth -EnableCredSSP
# winrm set winrm/config/Winrs '@{AllowRemoteShellAccess="true"}'
# Enable-WSManCredSSP -Role Server -Force
# 
# Write-Information "Link config inside wsl"
# $wslPathInstallDir = wsl --distribution "$WslName" --exec wslpath "$InstallDir"
# wsl --distribution "$WslName" --user "$WslUsername" --exec bash -c @"
# dir="$wslPathInstallDir"
# 
# mkdir --parents "`${dir}"
# config="`${dir}/config.yml"
# if [[ ! -f "`${config}" ]]; then
#   touch "`${config}"
# fi
# 
# wsl_config_dir="`${HOME}/.config/dev-bootstrap"
# mkdir --parents "`${wsl_config_dir}"
# wslconfig="`${wsl_config_dir}/config.yml"
# if [[ ! -e "`${wslconfig}" ]]; then
#   ln --symbolic "`${config}" "`${wslconfig}"
# fi
# "@
# 
# Write-Information "Switch to bash to complete the bootstrap"
# if ("$GitBranch" -eq "unversioned") {
#     Write-Information "Use local unversioned (from $PSScriptRoot)"
#     wsl --distribution "$WslName" --user "$WslUsername" --cd "$PSScriptRoot" --exec `
#         bash -c "GIT_BRANCH=$GitBranch ./bootstrap.sh"
# }
# else {
#     Write-Information "Use remote branch $GitBranch (from $PSScriptRoot)"
#     wsl --distribution "$WslName" --user "$WslUsername" --exec `
#         bash -c @"
# script="`$(mktemp)"
# curl "https://raw.githubusercontent.com/lucastheisen/dev-bootstrap/$GitBranch/bootstrap.sh" \
#     --output "`${script}"
# chmod 0700 "`${script}"
# GIT_BRANCH='$GitBranch' "`${script}"
# rm "`${script}"
# "@
# }
