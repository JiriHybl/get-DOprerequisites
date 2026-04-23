# get-DOprerequisites

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

A PowerShell script used as an **Intune Proactive Remediation detection script** that checks all prerequisites for **Delivery Optimization (DO)** on Windows machines.

---

## Description

`get-DOprerequisites.ps1` inspects key configuration points and service states that influence whether Delivery Optimization can function correctly on a Windows endpoint. It is designed to be deployed as the **detection script** of an Intune Proactive Remediation policy. Results are written to standard output as a comma-separated token string that can be used for reporting or remediation logic.

---

## What It Checks

| Check | Details |
|---|---|
| **DoSvc service** | Verifies the Delivery Optimization service is running |
| **DO download mode (cache)** | Reads the active download mode via `Get-DeliveryOptimizationStatus` |
| **DO download mode (PerfSnap)** | Reads aggregate download mode via `Get-DeliveryOptimizationPerfSnap` |
| **DO download mode (registry policy)** | Reads MDM/GPO registry policy for `DODownloadMode` |
| **Connected Cache (MCC) host** | Reports the configured MCC host name |
| **MCC TCP reachability** | Tests TCP reachability of the MCC host on port 80 |
| **Network profile type** | Detects Public network profiles, which block LAN peering |
| **WinHTTP proxy** | Reads static WinHTTP proxy configuration |
| **System/IE proxy** | Reads current-user Internet Explorer proxy settings |
| **Windows Update service** | Checks that `wuauserv` is running |
| **BITS service** | Checks that the Background Intelligent Transfer Service is running |
| **Windows build & edition** | Reports OS build number (UBR) and edition |
| **Free disk space (C:)** | Alerts if free space on C: falls below 5 GB |
| **DO cache size** | Reports `DOMaxCacheSize` and `DOMaxCacheAge` policy values |
| **Firewall – port 7680 (P2P)** | Checks for an enabled inbound rule referencing port 7680 |
| **Firewall – port 5353 (mDNS)** | Checks for an enabled inbound rule referencing port 5353 |
| **DO cloud endpoints** | Tests DNS resolution and HTTP reachability for geo, kv, cp, disc, and CDN endpoints |

---

## Output Format

The script writes a single comma-separated string to standard output, for example:

```
DOServiceRunning,DOmode:InternetAndLAN,DOmodePerfSnap:InternetAndLAN,DOmodePolicy:1,MCCHost:mcc.contoso.com,MCCReachable:OK,NetworkProfile:DomainAuthenticated,WinHTTPProxy:Direct,IEProxy:Direct,wuauserv:Running,BITS:Running,OSBuild:22621.3447,OSEdition:Enterprise,DiskOK,CacheSize:0GB,CacheAge:604800s,Firewall7680OK,Firewall5353OK,Reachable(200):geo.prod.do.dsp.mp.microsoft.com,...
```

Each token represents the result of one check. Tokens ending in `NotOK`, `NotRunning`, `Stopped`, `NotFound`, `DetectionFailed`, `DNSFail:`, `Unreachable(`, `GeneralException:`, or `MCCReachable:Failed` indicate a failed condition.

---

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | One or more prerequisites are **not met** — Intune will trigger the remediation script |
| `1` | All prerequisites appear to be **met** — no remediation needed |

> **Note:** This is intentionally reversed from typical shell conventions to match the Intune Proactive Remediation model where exit `0` signals a detected issue.

---

## Usage / Deployment

1. In the [Microsoft Intune admin center](https://intune.microsoft.com), navigate to **Devices > Remediations**.
2. Create a new Remediation policy.
3. Upload `get-DOprerequisites.ps1` as the **Detection script**.
4. Configure the script to run in the **SYSTEM** context (required for full WMI and registry access).
5. Set the schedule as appropriate (e.g., hourly or daily).
6. Optionally pair it with a remediation script to fix identified issues.

---

## Known Limitations

- **Firewall check**: Only verifies that an enabled inbound rule *references* the port; it does **not** verify the rule's Action (Allow vs. Block).
- **DO mode via `Get-DeliveryOptimizationStatus`**: May return `NotKnownCacheEmpty` on machines with no active DO cache, which is not necessarily an error.
- **MCC reachability**: Uses `Test-NetConnection`; the system default timeout applies (~5 s).
- **Proxy detection**: Reads static WinHTTP configuration; PAC/WPAD scripts are **not** evaluated.

---

## Requirements

- Windows 10 version 1709 (build 16299) or later
- PowerShell 5.1 or later
- Must run as **SYSTEM** (required for full registry, WMI, and firewall access)

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for information on how to contribute to this project.

## Security

Please review [SECURITY.md](SECURITY.md) for instructions on how to report security vulnerabilities responsibly.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
