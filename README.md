# Windows Update Service Dependency Checker

A PowerShell diagnostic script that audits the status and startup type of Windows Update and its dependency services across a fleet of remote Windows hosts. Results export to a timestamped CSV for cross-machine comparison.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell) ![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey?logo=windows) ![License](https://img.shields.io/badge/License-MIT-green)

## Background

When a large number of managed endpoints began failing Windows Update, this script was used to systematically identify the root cause. Running it against affected machines revealed that **BITS (Background Intelligent Transfer Service)** was either stopped or in a failed state on the problem hosts — preventing Windows Update from downloading patches. The CSV output allowed quick cross-fleet comparison to confirm the pattern before targeting remediation.

## Services Checked

| Service Name | Display Name | Role in Windows Update |
|---|---|---|
| `wuauserv` | Windows Update | Core update orchestration |
| `BITS` | Background Intelligent Transfer Service | Downloads update packages in the background |
| `RpcSS` | Remote Procedure Call | Required by virtually all Windows services |
| `RpcEptMapper` | RPC Endpoint Mapper | Routes RPC traffic to the correct endpoint |
| `CryptSvc` | Cryptographic Services | Validates update package signatures |

## Requirements

| Requirement | Detail |
|-------------|--------|
| PowerShell | 5.1 or later |
| Network | WMI/DCOM access to each target (TCP 135 + dynamic RPC), or WinRM |
| Permissions | Permission to query services on each remote host |
| Input | CSV file with a column named `FQDN` |

## Usage

```powershell
# Basic — reads .\computers.csv, writes a timestamped CSV to the current directory
.\Get-WUServiceStatus.ps1

# Specify input file
.\Get-WUServiceStatus.ps1 -ComputerListCsv "C:\Lists\servers.csv"

# Specify both input and output
.\Get-WUServiceStatus.ps1 -ComputerListCsv ".\servers.csv" -OutputCsv "C:\Reports\audit.csv"

# Check a custom set of services
.\Get-WUServiceStatus.ps1 -Services "wuauserv","BITS","Winmgmt"
```

### Input CSV format

```csv
FQDN
workstation01.corp.local
workstation02.corp.local
server01.corp.local
```

### Example Output (console)

```
Computer                  Service      DisplayName                              Status  StartupType
--------                  -------      -----------                              ------  -----------
workstation01.corp.local  wuauserv     Windows Update                          Running Manual
workstation01.corp.local  BITS         Background Intelligent Transfer Service  Stopped Disabled
workstation01.corp.local  RpcSS        Remote Procedure Call                   Running Automatic
workstation02.corp.local  wuauserv     Windows Update                          Running Manual
workstation02.corp.local  BITS         Background Intelligent Transfer Service  Running Manual
...

Results saved to: .\WUServiceStatus_20260621_143022.csv
10 records written (2 machine(s) x 5 service(s)).
```

## Bugs Fixed from Original Version

| # | Issue | Fix |
|---|-------|-----|
| 1 | `Get-WmiObject` is deprecated since PS 3.0 | Replaced with `Get-CimInstance` |
| 2 | WMI call lacked `-ErrorAction Stop` — null `.StartMode` would throw uncaught | Added `-ErrorAction Stop`; added null guard on CIM result |
| 3 | `$results += [PSCustomObject]` in a loop causes O(n²) array copies | Replaced with `[System.Collections.Generic.List]` |
| 4 | Hardcoded CSV input/output paths | Converted to `-ComputerListCsv` and `-OutputCsv` parameters |
| 5 | No check for missing input file | Added `Test-Path` guard with a clear error message |
| 6 | Catch block didn't distinguish "not found" from "host unreachable" | Split into typed catch blocks: `ServiceCommandException` vs general |
| 7 | Reruns silently overwrite the output CSV | Timestamp appended to output filename automatically |
| 8 | Missing `wuauserv` and `CryptSvc` from service list | Added both — they are direct Windows Update dependencies |

## License

MIT — see [LICENSE](LICENSE) for details.
