# Prints how much of a process's GPU memory is in VRAM ("dedicated") and in system memory ("shared").
# Usage: powershell -File vram-residency.ps1 [-Name llama-cli] [-Seconds 60] [-Interval 5]
param(
    [string]$Name = "llama-cli",
    [int]$Seconds = 60,
    [int]$Interval = 5
)

$deadline = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $deadline) {
    $proc = Get-Process -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) {
        Write-Host "$Name is not running"
    } else {
        $id = $proc.Id
        $samples = (Get-Counter "\GPU Process Memory(pid_${id}*)\Dedicated Usage", "\GPU Process Memory(pid_${id}*)\Shared Usage" -ErrorAction SilentlyContinue).CounterSamples
        $dedicated = ($samples | Where-Object { $_.Path -like "*dedicated usage" } | Measure-Object CookedValue -Sum).Sum
        $shared = ($samples | Where-Object { $_.Path -like "*shared usage" } | Measure-Object CookedValue -Sum).Sum
        "{0:HH:mm:ss}  pid={1}  dedicated={2,6} MiB  shared={3,6} MiB" -f (Get-Date), $id, [math]::Round($dedicated / 1MB), [math]::Round($shared / 1MB)
    }
    Start-Sleep -Seconds $Interval
}
