<#
.SYNOPSIS
    Checks prerequisites for Delivery Optimization on a Windows machine.

.DESCRIPTION
    Verifies the following conditions required for Delivery Optimization to function correctly:
      - DoSvc service is running
      - Delivery Optimization download mode (via cache, PerfSnap, and registry policy)
      - Connected Cache (MCC) host configuration and reachability
      - Network profile type (Public profile blocks LAN peering)
      - Proxy configuration (WinHTTP and system/IE proxy)
      - Windows Update (wuauserv) and BITS service status
      - Windows build version and edition
      - Sufficient free disk space on drive C:
      - DO cache size configuration
      - Inbound firewall rules for ports 7680 and 5353
      - Reachability of required Microsoft DO cloud endpoints

    Results are concatenated into a comma-separated string and written to output.
    Intended for use as an Intune proactive remediation detection script.

.NOTES
    Author  : JiriHybl
    Version : 1.3
    Date    : 04-2026

    Exit codes:
      0 - One or more prerequisites are not met (triggers Intune remediation)
      1 - All prerequisites appear to be met

    Known limitations:
      - Firewall check only verifies that an enabled inbound rule references the port;
        it does NOT verify the rule Action (Allow vs. Block).
      - DO mode via Get-DeliveryOptimizationStatus may return "NotKnownCacheEmpty"
        on machines with no active DO cache, which is not necessarily an error.
      - MCC reachability test uses Test-NetConnection; system default timeout applies (~5s).
      - Proxy detection reads static WinHTTP config; PAC/WPAD scripts are not evaluated.
#>

# Initialize output variable -- results are appended as comma-separated tokens
$Output = ""

# Registry paths used by multiple checks below
$regMDM = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\DeliveryOptimization"
$regGPO = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"

# ---------------------------------------------------------------------------
# Check Delivery Optimization Service (DoSvc)
# ---------------------------------------------------------------------------
$service = Get-Service -Name "DoSvc" -ErrorAction SilentlyContinue
if ($service.Status -ne "Running") {
    $Output += "DOServiceNotRunning,"
}
else {
    $Output += "DOServiceRunning,"
}

# ---------------------------------------------------------------------------
# Check DO download mode via Get-DeliveryOptimizationStatus
# Uses the first cached item to determine the active download mode.
# NOTE: If the DO cache is empty, the cmdlet may throw and fall into the catch block.
# ---------------------------------------------------------------------------
try {
    $doStatus = Get-DeliveryOptimizationStatus | Select-Object -First 1 -ErrorAction Stop
    $Output += "DOmode:" + $doStatus.DownloadMode.ToString() + ","
}
catch {
    $Output += "DOmode:NotKnownCacheEmpty,"
}

# ---------------------------------------------------------------------------
# Check DO download mode via Get-DeliveryOptimizationPerfSnap
# PerfSnap provides aggregate statistics and is available even without active cache.
# ---------------------------------------------------------------------------
try {
    $doMode = Get-DeliveryOptimizationPerfSnap | Select-Object -ExpandProperty DownloadMode
    $Output += "DOmodePerfSnap:" + $doMode + ","
}
catch {
    $Output += "DOmodePerfSnap:DetectionFailed,"
}

# ---------------------------------------------------------------------------
# Check DO Download Mode from Registry (applied policy)
# Reads the effective configured value -- MDM (Intune) takes precedence over GPO.
# DownloadMode: 0=HTTP only, 1=LAN, 2=Group, 3=Internet, 99=Bypass, 100=Simple
# ---------------------------------------------------------------------------
$doModeRegValue  = $null
$doModeRegSource = $null

if (Test-Path $regMDM) {
    $doModeRegValue = (Get-ItemProperty $regMDM -Name "DODownloadMode" -ErrorAction SilentlyContinue).DODownloadMode
    if ($null -ne $doModeRegValue) { $doModeRegSource = "MDM" }
}
if ($null -eq $doModeRegValue -and (Test-Path $regGPO)) {
    $doModeRegValue = (Get-ItemProperty $regGPO -Name "DODownloadMode" -ErrorAction SilentlyContinue).DODownloadMode
    if ($null -ne $doModeRegValue) { $doModeRegSource = "GPO" }
}

if ($null -ne $doModeRegValue) {
    $Output += "DOmodeReg:$doModeRegValue($doModeRegSource),"
}
else {
    $Output += "DOmodeReg:NotConfigured,"
}

# ---------------------------------------------------------------------------
# Check Connected Cache (MCC) Host Configuration and Reachability
# Reads DOCacheHost from MDM or GPO registry path.
# If configured, tests TCP port 80 connectivity (DO uses HTTP to reach MCC).
# ---------------------------------------------------------------------------
$mccHost = $null

if (Test-Path $regMDM) {
    $mccHost = (Get-ItemProperty $regMDM -Name "DOCacheHost" -ErrorAction SilentlyContinue).DOCacheHost
}
if ([string]::IsNullOrEmpty($mccHost) -and (Test-Path $regGPO)) {
    $mccHost = (Get-ItemProperty $regGPO -Name "DOCacheHost" -ErrorAction SilentlyContinue).DOCacheHost
}

if ([string]::IsNullOrEmpty($mccHost)) {
    $Output += "MCCHost:NotConfigured,"
}
else {
    $Output += "MCCHost:$mccHost,"
    try {
        $mccTest = Test-NetConnection -ComputerName $mccHost -Port 80 `
            -InformationLevel Quiet -ErrorAction Stop -WarningAction SilentlyContinue
        if ($mccTest) {
            $Output += "MCCReachable:OK,"
        }
        else {
            $Output += "MCCReachable:Failed,"
        }
    }
    catch {
        $Output += "MCCReachable:TestException,"
    }
}

# ---------------------------------------------------------------------------
# Check Network Connection Profile
# DO LAN peering (mode 1/2) is blocked when the active profile is Public.
# NetworkCategory values: Public, Private, DomainAuthenticated
# Reports all connected profiles (multiple NICs may be active on hybrid clients).
# ---------------------------------------------------------------------------
try {
    $profiles = Get-NetConnectionProfile -ErrorAction Stop
    foreach ($profile in $profiles) {
        $Output += "NetProfile:$($profile.Name)-$($profile.NetworkCategory),"
    }
}
catch {
    $Output += "NetProfile:DetectionFailed,"
}

# ---------------------------------------------------------------------------
# Check Proxy Configuration
# DO uses the WinHTTP proxy for cloud endpoint traffic but bypasses it for
# LAN peering. Reports both WinHTTP (system/service-level) and WinInet
# (user-level / IE) proxy settings.
# NOTE: PAC/WPAD auto-detection is not evaluated here.
# ---------------------------------------------------------------------------
try {
    $winHttpProxy = netsh winhttp show proxy 2>&1 | Out-String
    if ($winHttpProxy -match "Direct access") {
        $Output += "WinHTTPProxy:Direct,"
    }
    elseif ($winHttpProxy -match "Proxy Server\(s\)\s*:\s*(.+)") {
        $proxyVal = $Matches[1].Trim()
        $Output += "WinHTTPProxy:$proxyVal,"
    }
    else {
        $Output += "WinHTTPProxy:Unknown,"
    }
}
catch {
    $Output += "WinHTTPProxy:DetectionFailed,"
}

$inetProxy = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" `
    -Name "ProxyServer" -ErrorAction SilentlyContinue).ProxyServer
if ([string]::IsNullOrEmpty($inetProxy)) {
    $Output += "SystemProxy:None,"
}
else {
    $Output += "SystemProxy:$inetProxy,"
}

# ---------------------------------------------------------------------------
# Check Windows Update (wuauserv) and BITS Service Status
# DO integrates with the Windows Update stack; both services must be functional
# for Windows Update content to be delivered via DO.
# ---------------------------------------------------------------------------
foreach ($svcName in @("wuauserv", "BITS")) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        $Output += "${svcName}:NotFound,"
    }
    elseif ($svc.Status -ne "Running") {
        $Output += "${svcName}:$($svc.Status),"
    }
    else {
        $Output += "${svcName}:Running,"
    }
}

# ---------------------------------------------------------------------------
# Check Windows Build Version and Edition
# MCC support requires Windows 10 build 1709 (16299) or later.
# Reports CurrentBuildNumber.UBR and EditionID for diagnostic purposes.
# ---------------------------------------------------------------------------
try {
    $osReg       = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
    $buildNumber = $osReg.CurrentBuildNumber
    $ubr         = $osReg.UBR
    $edition     = $osReg.EditionID
    $Output += "OSBuild:$buildNumber.$ubr,"
    $Output += "OSEdition:$edition,"
}
catch {
    $Output += "OSBuild:DetectionFailed,"
}

# ---------------------------------------------------------------------------
# Check Free Disk Space on drive C:
# DO requires sufficient disk space for its cache.
# Threshold: 5 GB (5GB PowerShell literal = 5 * 1073741824 bytes)
# ---------------------------------------------------------------------------
$disk = Get-PSDrive -Name C
if ($disk.Free -lt 5GB) {
    $Output += "DiskLow5GB,"
}
else {
    $Output += "DiskOK,"
}

# ---------------------------------------------------------------------------
# Check DO Cache Size Configuration
# If the cache limit is set to 0 or very low via policy, DO will not store
# content effectively. DOMaxCacheSize is in GB; DOMaxCacheAge is in seconds.
# A value of 0 for DOMaxCacheSize means "no limit" (Windows default behaviour).
# ---------------------------------------------------------------------------
$doCacheSize = $null
$doCacheAge  = $null

if (Test-Path $regMDM) {
    $doCacheSize = (Get-ItemProperty $regMDM -Name "DOMaxCacheSize" -ErrorAction SilentlyContinue).DOMaxCacheSize
    $doCacheAge  = (Get-ItemProperty $regMDM -Name "DOMaxCacheAge"  -ErrorAction SilentlyContinue).DOMaxCacheAge
}
if ($null -eq $doCacheSize -and (Test-Path $regGPO)) {
    $doCacheSize = (Get-ItemProperty $regGPO -Name "DOMaxCacheSize" -ErrorAction SilentlyContinue).DOMaxCacheSize
    $doCacheAge  = (Get-ItemProperty $regGPO -Name "DOMaxCacheAge"  -ErrorAction SilentlyContinue).DOMaxCacheAge
}

if ($null -ne $doCacheSize) {
    $Output += "DOMaxCacheSize:${doCacheSize}GB,"
}
else {
    $Output += "DOMaxCacheSize:NotConfigured,"
}

if ($null -ne $doCacheAge) {
    $Output += "DOMaxCacheAge:${doCacheAge}s,"
}
else {
    $Output += "DOMaxCacheAge:NotConfigured,"
}

# ---------------------------------------------------------------------------
# Check Inbound Firewall Rule for DO peer-to-peer port TCP/UDP 7680
# NOTE: This only checks whether an enabled inbound rule references port 7680.
#       It does NOT distinguish between Allow and Block rules.
#       A Block rule would also satisfy Count -gt 0 and incorrectly report OK.
# ---------------------------------------------------------------------------
$port = 7680
$firewallRules = Get-NetFirewallRule |
    Where-Object { $_.Direction -eq 'Inbound' -and $_.Enabled -eq 'True' } |
    Get-NetFirewallPortFilter |
    Where-Object { $_.LocalPort -eq $port }

if ($firewallRules.Count -eq 0) {
    $Output += "Firewall7680NotOK,"
}
else {
    $Output += "Firewall7680OK,"
}

# ---------------------------------------------------------------------------
# Check Inbound Firewall Rule for mDNS port UDP 5353
# Used by DO for peer discovery on the local network.
# NOTE: Same limitation as above -- Action (Allow/Block) is not verified.
# ---------------------------------------------------------------------------
$port = 5353
$firewallRules = Get-NetFirewallRule |
    Where-Object { $_.Direction -eq 'Inbound' -and $_.Enabled -eq 'True' } |
    Get-NetFirewallPortFilter |
    Where-Object { $_.LocalPort -eq $port }

if ($firewallRules.Count -eq 0) {
    $Output += "Firewall5353NotOK,"
}
else {
    $Output += "Firewall5353OK,"
}

# ---------------------------------------------------------------------------
# Check Reachability of Required Delivery Optimization Cloud Endpoints
#
# Endpoints are tested per service category using specific instances
# (wildcards are not testable directly). Source: Microsoft Learn
# https://learn.microsoft.com/en-us/windows/deployment/do/delivery-optimization-workflow
#
# Two-stage test per endpoint:
#   1. DNS resolution — distinguishes "hostname unknown" from HTTP-level failures.
#      If DNS fails, HTTP is skipped and DNSFail is reported.
#   2. HTTP request — any HTTP response (including 4xx) means the server was reached
#      and is considered reachable. Only network-level failures with no HTTP response
#      (timeout, connection refused) are reported as unreachable.
#
# Service categories and their purpose:
#   Geo      (geo*.prod.do.dsp.mp.microsoft.com)  — device location / datacenter routing
#   KeyValue (kv*.prod.do.dsp.mp.microsoft.com)   — bootstrap, provides all other endpoints
#   Content  (cp*.prod.do.dsp.mp.microsoft.com)   — content policy and metadata URLs
#   Discovery(disc*.prod.do.dsp.mp.microsoft.com) — peer matching / discovery
#   CDN      (dl.delivery.mp.microsoft.com)        — content metadata file hosting
# ---------------------------------------------------------------------------
$requiredUrls = @(
    "https://geo.prod.do.dsp.mp.microsoft.com",       # Geo
    "https://kv101.prod.do.dsp.mp.microsoft.com",     # KeyValue
    "https://cp901.prod.do.dsp.mp.microsoft.com",     # Content Policy
    "https://disc101.prod.do.dsp.mp.microsoft.com",   # Discovery
    "http://dl.delivery.mp.microsoft.com/"            # CDN metadata (HTTP/80)
)

foreach ($url in $requiredUrls) {
    # Extract hostname from URL for DNS pre-check
    $hostname = ([System.Uri]$url).Host

    # Stage 1: DNS resolution
    try {
        $null = [System.Net.Dns]::GetHostAddresses($hostname)
    }
    catch {
        $Output += "DNSFail:$hostname,"
        continue
    }

    # Stage 2: HTTP reachability — any HTTP response means the server was reached
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
        $Output += "Reachable($($response.StatusCode)):$hostname,"
    }
    catch [System.Net.WebException] {
        if ($null -ne $_.Exception.Response) {
            # HTTP error response (4xx/5xx) — server was reached
            $httpStatus = [int]$_.Exception.Response.StatusCode
            $Output += "Reachable($httpStatus):$hostname,"
        }
        else {
            # DNS resolved but no HTTP response — TCP/TLS level failure
            $Output += "Unreachable($($_.Exception.Status)):$hostname,"
        }
    }
    catch {
        $Output += "Unreachable(Exception):$hostname,"
    }
}

# ---------------------------------------------------------------------------
# Evaluate Results and Exit
# Scan $Output for known failure tokens to determine overall health.
# Exit 0 -- one or more prerequisites are not met (triggers Intune remediation)
# Exit 1 -- all prerequisites appear to be met
# ---------------------------------------------------------------------------
$issuePatterns = @(
    "DOServiceNotRunning",
    ":NotRunning",
    ":Stopped",
    ":NotFound",
    ":DetectionFailed",
    "MCCReachable:Failed",
    "MCCReachable:TestException",
    "DiskLow5GB",
    "Firewall7680NotOK",
    "Firewall5353NotOK",
    "Unreachable(",
    "DNSFail:",
    "GeneralException:"
)

$hasIssues = $false
foreach ($pattern in $issuePatterns) {
    if ($Output -like "*$pattern*") {
        $hasIssues = $true
        break
    }
}

Write-Output $Output

if ($hasIssues) {
    exit 0   # Prerequisites NOT met -- remediation required
}
else {
    exit 1   # Prerequisites met -- no action needed
}
