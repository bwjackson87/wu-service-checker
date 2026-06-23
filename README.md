# Windows Update Service Dependency Checker

## Overview
A PowerShell diagnostic script that audits the status and startup type of Windows Update and its core dependency services across a fleet of remote Windows hosts. Results export to a timestamped CSV for cross-machine comparison, enabling rapid identification of which service is broken and on which machines.

## Problem It Solves
When Windows Update fails across multiple endpoints simultaneously, the root cause is rarely the update service itself — it's almost always a dependency (BITS, CryptSvc, RPC) that is stopped, disabled, or in a failed state. Checking each machine manually through the GUI or even `services.msc` remotely is not scalable. This script was used to diagnose a fleet-wide update failure: running it revealed that **BITS was stopped or disabled on all affected machines**, enabling targeted remediation instead of a trial-and-error approach.

## Key Features
- Audits 5 Windows Update dependency services per host: `wuauserv`, `BITS`, `RpcSS`, `RpcEptMapper`, `CryptSvc`
- Accepts a custom service list via parameter for ad-hoc audits
- Remote query via CIM (WMI) — no WinRM required
- Timestamped output CSV — reruns never overwrite prior results
- Graceful error handling per host — one unreachable machine does not abort the batch
- Parameterized input/output paths — portable across environments

## Technologies Used
- PowerShell 5.1+
- `Get-CimInstance Win32_Service` (WMI/DCOM transport)
- CSV input/output via `Import-Csv` / `Export-Csv`

## Example Use Case
A wave of SCCM compliance alerts shows Windows Update failing on 40+ workstations in a remote office. Running this script against the affected machine list returns a CSV showing BITS is `Stopped / Disabled` on every affected host. A follow-up SCCM script re-enables and starts BITS fleet-wide — update failures stop within the hour, with no need to touch each machine individually.

## How to Run

```powershell
# Default — reads .\computers.csv, writes timestamped CSV to current directory
.\Get-WUServiceStatus.ps1

# Specify input CSV
.\Get-WUServiceStatus.ps1 -ComputerListCsv "C:\Lists\servers.csv"

# Specify both input and output
.\Get-WUServiceStatus.ps1 -ComputerListCsv ".\servers.csv" -OutputCsv "C:\Reports\wu_audit.csv"

# Check a custom service list
.\Get-WUServiceStatus.ps1 -Services "wuauserv","BITS","Winmgmt"
```

**Input CSV format** (`computers.csv` template included in repo):

```csv
FQDN
workstation01.corp.local
server01.corp.local
```

## Example Output

**Console:**
```
Computer                  Service  DisplayName                              Status   StartupType
--------                  -------  -----------                              ------   -----------
workstation01.corp.local  wuauserv Windows Update                          Running  Manual
workstation01.corp.local  BITS     Background Intelligent Transfer Service  Stopped  Disabled
workstation01.corp.local  CryptSvc Cryptographic Services                  Running  Automatic

Results saved to: .\WUServiceStatus_20260621_143022.csv
15 records written (3 machine(s) x 5 service(s)).
```

## Security Notes
- Requires **local administrator rights** on each target host for WMI service queries
- Uses WMI/DCOM (TCP 135 + dynamic RPC) — ensure firewall rules allow this on the target network segment
- Read-only — does not start, stop, or modify any services
- Authorized use only — run only against systems you are authorized to administer

## Lessons Learned
- `Get-WmiObject` is deprecated and should be replaced with `Get-CimInstance` — it is faster, supports WSMan transport, and handles null results more predictably
- Building a `List<T>` instead of using `+=` on an array in a loop eliminates O(n²) memory copying, which becomes significant at 500+ machine × 5 service rows
- Typed catch blocks (`ServiceCommandException` vs general `Exception`) provide meaningful error messages instead of a generic "the RPC server is unavailable" swallowing the real cause
- Including `StartupType` alongside `Status` is critical — a service set to `Disabled` will return `Stopped`, but the fix is different: you must re-enable it, not just start it
