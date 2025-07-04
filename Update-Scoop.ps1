#Requires -Version 5.1
<#
.SYNOPSIS
    Automated Scoop package updater with logging and error handling.

.DESCRIPTION
    This script updates Scoop itself and all installed packages, cleans old versions
    and cache, and maintains rotating logs. Designed for scheduled execution.

.PARAMETER LogPath
    Path to store log files. Defaults to %USERPROFILE%\.scoop\logs

.PARAMETER MaxLogAge
    Maximum age of log files in days before rotation. Default is 7 days.

.PARAMETER Quiet
    Suppress console output (useful for scheduled tasks).

.EXAMPLE
    .\Update-Scoop.ps1
    Run with default settings

.EXAMPLE
    .\Update-Scoop.ps1 -LogPath "C:\Logs\Scoop" -MaxLogAge 14
    Run with custom log path and 14-day retention

.NOTES
    Author: Scoop Auto-Update Solution
    Version: 1.0
    Created: 2025
    Requires: Scoop package manager
#>

param(
    [string]$LogPath = "$env:USERPROFILE\.scoop\logs",
    [int]$MaxLogAge = 7,
    [switch]$Quiet
)

# Initialize script variables
$ScriptName = "Update-Scoop"
$StartTime = Get-Date
$LogFile = Join-Path $LogPath "$ScriptName-$(Get-Date -Format 'yyyy-MM-dd').log"
$ErrorCount = 0
$WarningCount = 0
$UpdateCount = 0

# Ensure log directory exists
if (-not (Test-Path $LogPath)) {
    try {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
        Write-Host "Created log directory: $LogPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to create log directory: $LogPath. Error: $($_.Exception.Message)"
        exit 1
    }
}

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO',
        [switch]$NoConsole
    )
    
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $LogEntry = "[$Timestamp] [$Level] $Message"
    
    try {
        Add-Content -Path $LogFile -Value $LogEntry -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to write to log file: $($_.Exception.Message)"
    }
    
    if (-not $NoConsole -and -not $Quiet) {
        switch ($Level) {
            'INFO' { Write-Host $LogEntry -ForegroundColor Cyan }
            'WARN' { Write-Host $LogEntry -ForegroundColor Yellow }
            'ERROR' { Write-Host $LogEntry -ForegroundColor Red }
            'SUCCESS' { Write-Host $LogEntry -ForegroundColor Green }
        }
    }
    
    # Update counters
    switch ($Level) {
        'ERROR' { $script:ErrorCount++ }
        'WARN' { $script:WarningCount++ }
    }
}

# Log rotation function
function Invoke-LogRotation {
    param([string]$LogDirectory, [int]$MaxDays)
    
    try {
        $CutoffDate = (Get-Date).AddDays(-$MaxDays)
        $OldLogs = Get-ChildItem -Path $LogDirectory -Filter "$ScriptName-*.log" | 
                   Where-Object { $_.LastWriteTime -lt $CutoffDate }
        
        foreach ($Log in $OldLogs) {
            Remove-Item -Path $Log.FullName -Force
            Write-Log "Rotated old log file: $($Log.Name)" -Level 'INFO'
        }
        
        if ($OldLogs.Count -eq 0) {
            Write-Log "No old log files to rotate" -Level 'INFO'
        }
    }
    catch {
        Write-Log "Failed to rotate logs: $($_.Exception.Message)" -Level 'ERROR'
    }
}

# Scoop command wrapper with error handling
function Invoke-ScoopCommand {
    param(
        [string]$Command,
        [string]$Arguments = "",
        [string]$Description
    )
    
    Write-Log "Executing: $Description" -Level 'INFO'
    
    try {
        $FullCommand = "scoop $Command $Arguments"
        Write-Log "Running: $FullCommand" -Level 'INFO'
        
        $Output = Invoke-Expression $FullCommand 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "$Description completed successfully" -Level 'SUCCESS'
            if ($Output) {
                Write-Log "Output: $($Output -join '; ')" -Level 'INFO'
            }
            return $true
        }
        else {
            Write-Log "$Description failed with exit code: $LASTEXITCODE" -Level 'ERROR'
            Write-Log "Error output: $($Output -join '; ')" -Level 'ERROR'
            return $false
        }
    }
    catch {
        Write-Log "$Description failed with exception: $($_.Exception.Message)" -Level 'ERROR'
        return $false
    }
}

# Check if Scoop is installed and accessible
function Test-ScoopInstallation {
    try {
        $ScoopPath = Get-Command scoop -ErrorAction Stop
        Write-Log "Scoop found at: $($ScoopPath.Source)" -Level 'INFO'
        return $true
    }
    catch {
        Write-Log "Scoop not found in PATH. Please ensure Scoop is properly installed." -Level 'ERROR'
        return $false
    }
}

# Get list of installed packages
function Get-InstalledPackages {
    try {
        $Output = scoop list 2>&1
        if ($LASTEXITCODE -eq 0) {
            # Parse scoop list output to count packages
            $PackageLines = $Output | Where-Object { $_ -match '^\s*\w+' -and $_ -notmatch 'Installed|Name|----' }
            $PackageCount = $PackageLines.Count
            Write-Log "Found $PackageCount installed packages" -Level 'INFO'
            return $PackageCount
        }
        else {
            Write-Log "Failed to get package list: $($Output -join '; ')" -Level 'WARN'
            return 0
        }
    }
    catch {
        Write-Log "Exception getting package list: $($_.Exception.Message)" -Level 'ERROR'
        return 0
    }
}

# Main execution
try {
    Write-Log "=== Scoop Auto-Update Started ===" -Level 'INFO'
    Write-Log "Script: $($MyInvocation.MyCommand.Path)" -Level 'INFO'
    Write-Log "Log file: $LogFile" -Level 'INFO'
    Write-Log "PowerShell version: $($PSVersionTable.PSVersion)" -Level 'INFO'
    
    # Rotate old logs
    Invoke-LogRotation -LogDirectory $LogPath -MaxDays $MaxLogAge
    
    # Verify Scoop installation
    if (-not (Test-ScoopInstallation)) {
        Write-Log "Scoop installation check failed. Exiting." -Level 'ERROR'
        exit 1
    }
    
    # Get initial package count
    $InitialPackageCount = Get-InstalledPackages
    
    # Update Scoop itself
    Write-Log "--- Updating Scoop ---" -Level 'INFO'
    if (Invoke-ScoopCommand -Command "update" -Description "Scoop self-update") {
        Write-Log "Scoop self-update completed" -Level 'SUCCESS'
    }
    else {
        Write-Log "Scoop self-update failed" -Level 'ERROR'
    }
    
    # Update all installed packages
    Write-Log "--- Updating All Packages ---" -Level 'INFO'
    if (Invoke-ScoopCommand -Command "update" -Arguments "*" -Description "Update all packages") {
        Write-Log "Package updates completed" -Level 'SUCCESS'
        $script:UpdateCount++
    }
    else {
        Write-Log "Package updates failed" -Level 'ERROR'
    }
    
    # Clean old versions
    Write-Log "--- Cleaning Old Versions ---" -Level 'INFO'
    if (Invoke-ScoopCommand -Command "cleanup" -Arguments "*" -Description "Clean old package versions") {
        Write-Log "Cleanup completed" -Level 'SUCCESS'
    }
    else {
        Write-Log "Cleanup failed" -Level 'WARN'
    }
    
    # Clear cache
    Write-Log "--- Clearing Cache ---" -Level 'INFO'
    if (Invoke-ScoopCommand -Command "cache" -Arguments "rm *" -Description "Clear package cache") {
        Write-Log "Cache cleared" -Level 'SUCCESS'
    }
    else {
        Write-Log "Cache clearing failed" -Level 'WARN'
    }
    
    # Get final package count
    $FinalPackageCount = Get-InstalledPackages
    
    # Generate summary
    $EndTime = Get-Date
    $Duration = $EndTime - $StartTime
    
    Write-Log "=== Scoop Auto-Update Completed ===" -Level 'INFO'
    Write-Log "Duration: $($Duration.TotalMinutes.ToString('F2')) minutes" -Level 'INFO'
    Write-Log "Packages: $InitialPackageCount -> $FinalPackageCount" -Level 'INFO'
    Write-Log "Updates performed: $UpdateCount" -Level 'INFO'
    Write-Log "Warnings: $WarningCount" -Level 'INFO'
    Write-Log "Errors: $ErrorCount" -Level 'INFO'
    
    if ($ErrorCount -eq 0) {
        Write-Log "All operations completed successfully!" -Level 'SUCCESS'
        exit 0
    }
    else {
        Write-Log "Completed with $ErrorCount errors. Check log for details." -Level 'WARN'
        exit 1
    }
}
catch {
    Write-Log "Unexpected error in main execution: $($_.Exception.Message)" -Level 'ERROR'
    Write-Log "Stack trace: $($_.Exception.StackTrace)" -Level 'ERROR'
    exit 1
}
finally {
    # Ensure we always log completion
    if (-not $ErrorCount) { $ErrorCount = 0 }
    Write-Log "Script execution finished with $ErrorCount errors" -Level 'INFO'
}