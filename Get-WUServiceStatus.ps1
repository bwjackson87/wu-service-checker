<#
.SYNOPSIS
    Audits Windows Update dependency services across multiple remote hosts.

.DESCRIPTION
    Queries the status and startup type of services that are prerequisites for
    Windows Update on a list of remote machines. Results are written to a
    timestamped CSV for trend analysis across remediation attempts.

    Background:
    When a large number of managed endpoints began failing Windows Update, this
    script was used to identify the root cause. Running it against affected
    machines revealed that BITS (Background Intelligent Transfer Service) was
    either stopped or in a failed state — preventing Windows Update from
    downloading patches. The CSV output allowed quick cross-fleet comparison
    to confirm the pattern before targeting remediation.

    Services checked:
      - wuauserv      Windows Update
      - BITS          Background Intelligent Transfer Service
      - RpcSS         Remote Procedure Call
      - RpcEptMapper  RPC Endpoint Mapper
      - CryptSvc      Cryptographic Services (required for update signing checks)

.PARAMETER ComputerListCsv
    Path to a CSV file with a column named "FQDN" containing the fully-qualified
    domain names of target machines.
    Default: ".\computers.csv"

.PARAMETER OutputCsv
    Path for the results CSV. A timestamp is appended to the base name
    automatically so reruns never overwrite previous results.
    Default: ".\WUServiceStatus_<timestamp>.csv"

.PARAMETER Services
    Override the default list of service names to check.

.EXAMPLE
    .\Get-WUServiceStatus.ps1 -ComputerListCsv ".\servers.csv"

.EXAMPLE
    .\Get-WUServiceStatus.ps1 -ComputerListCsv ".\servers.csv" `
                              -OutputCsv "C:\Reports\audit.csv"

.NOTES
    Requirements:
      - PowerShell 5.1 or later
      - WMI / DCOM access to each target (TCP 135 + dynamic RPC ports), OR
        WinRM access (Get-Service -ComputerName uses the Service Controller API
        over named pipes / RPC)
      - The running account must have permission to query services on each target
#>

[CmdletBinding()]
param (
    [string]   $ComputerListCsv = ".\computers.csv",

    [string]   $OutputCsv,

    [string[]] $Services = @(
        "wuauserv",     # Windows Update
        "BITS",         # Background Intelligent Transfer Service
        "RpcSS",        # Remote Procedure Call
        "RpcEptMapper", # RPC Endpoint Mapper
        "CryptSvc"      # Cryptographic Services
    )
)

# ---------------------------------------------------------------------------
# Validate input file
# ---------------------------------------------------------------------------

if (-not (Test-Path $ComputerListCsv)) {
    Write-Error "Computer list not found: $ComputerListCsv"
    exit 1
}

$computers = Import-Csv -Path $ComputerListCsv | Select-Object -ExpandProperty FQDN

if (-not $computers) {
    Write-Error "No entries found in '$ComputerListCsv'. Verify the file has a 'FQDN' column."
    exit 1
}

# ---------------------------------------------------------------------------
# Build output path with timestamp so reruns never overwrite prior results
# ---------------------------------------------------------------------------

if (-not $OutputCsv) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutputCsv = ".\WUServiceStatus_$timestamp.csv"
}

# ---------------------------------------------------------------------------
# Query each machine
# ---------------------------------------------------------------------------

# Use a generic List to avoid O(n²) array-copy overhead from repeated +=
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

$total   = $computers.Count
$current = 0

foreach ($computer in $computers) {
    $current++
    Write-Progress -Activity "Checking services" `
                   -Status "$computer ($current of $total)" `
                   -PercentComplete (($current / $total) * 100)

    foreach ($serviceName in $Services) {
        try {
            # Get-Service for status; Get-CimInstance for startup type.
            # Both calls are inside the same try so either failure is caught.
            # Get-WmiObject is deprecated since PS 3.0 — use Get-CimInstance instead.
            $svc = Get-Service -ComputerName $computer -Name $serviceName -ErrorAction Stop

            $cim = Get-CimInstance -ClassName Win32_Service `
                                   -ComputerName $computer `
                                   -Filter "Name='$serviceName'" `
                                   -ErrorAction Stop

            # Guard against a null CIM result (service found by SC but not WMI)
            $startupType = if ($cim) { $cim.StartMode } else { "Unknown" }

            $results.Add([PSCustomObject]@{
                Computer    = $computer
                Service     = $svc.Name
                DisplayName = $svc.DisplayName
                Status      = $svc.Status
                StartupType = $startupType
            })
        }
        catch [Microsoft.PowerShell.Commands.ServiceCommandException] {
            # Service name not found on this host
            $results.Add([PSCustomObject]@{
                Computer    = $computer
                Service     = $serviceName
                DisplayName = "N/A"
                Status      = "Not Found"
                StartupType = "N/A"
            })
        }
        catch {
            # Host unreachable, access denied, or other connectivity error
            $results.Add([PSCustomObject]@{
                Computer    = $computer
                Service     = $serviceName
                DisplayName = "N/A"
                Status      = "Inaccessible — $($_.Exception.Message)"
                StartupType = "N/A"
            })
        }
    }
}

Write-Progress -Activity "Checking services" -Completed

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

$results | Format-Table -AutoSize
$results | Export-Csv -Path $OutputCsv -NoTypeInformation

Write-Host "`nResults saved to: $OutputCsv" -ForegroundColor Green
Write-Host "$($results.Count) records written ($total machine(s) x $($Services.Count) service(s))."
