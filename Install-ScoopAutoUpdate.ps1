#Requires -Version 5.1
<#
.SYNOPSIS
    Scoop auto updater installer.

.DESCRIPTION
    Installs and configures a daily scheduled task to update Scoop and its packages.
    Requires all three script files to be downloaded and present in the same directory.

.PARAMETER InstallPath
    Path where the Update-Scoop.ps1 script will be installed.
    Default: %USERPROFILE%\Documents\ScoopAutoUpdate

.PARAMETER TaskName
    Name of the scheduled task. Default: ScoopAutoUpdate

.PARAMETER ScheduleTime
    Time when the task should run daily (24-hour format). Default: 03:00

.PARAMETER Uninstall
    Delete the scheduled task and installation directory.

.EXAMPLE
    # Run the installer from a local file
    .\Install-ScoopAutoUpdate.ps1

.EXAMPLE
    # Install with a custom schedule time
    .\Install-ScoopAutoUpdate.ps1 -ScheduleTime "02:30"

.EXAMPLE
    # Uninstall the components
    .\Install-ScoopAutoUpdate.ps1 -Uninstall
#>

param(
    [string]$InstallPath = "$env:USERPROFILE\Documents\ScoopAutoUpdate",
    [string]$TaskName = "ScoopAutoUpdate",
    [string]$ScheduleTime = "03:00",
    [switch]$Uninstall
)

# --- Define script variables ---
$ScriptRoot = $PSScriptRoot
$UpdateScriptName = "Update-Scoop.ps1"
$TaskXmlName = "ScoopAutoUpdate.xml"
$LogPath = "$env:USERPROFILE\.scoop\logs"

# --- Helper function for colored output ---
function Write-Status {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Type = 'Info'
    )
    $Colors = @{ 'Info' = 'Cyan'; 'Success' = 'Green'; 'Warning' = 'Yellow'; 'Error' = 'Red' }
    $Prefix = switch ($Type) { 'Info' { "[INFO]" }; 'Success' { "[SUCCESS]" }; 'Warning' { "[WARNING]" }; 'Error' { "[ERROR]" } }
    Write-Host "$Prefix $Message" -ForegroundColor $Colors[$Type]
}

# --- Installation and Uninstallation functions ---

function Invoke-Uninstall {
    Write-Status "Starting uninstallation..." -Type 'Info'
    try {
        $ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($ExistingTask) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false; Write-Status "Scheduled task '$TaskName' removed." -Type 'Success' }
        else { Write-Status "Scheduled task '$TaskName' not found." -Type 'Info' }
        if (Test-Path $InstallPath) { Remove-Item -Path $InstallPath -Recurse -Force; Write-Status "Installation directory removed: $InstallPath" -Type 'Success' }
        else { Write-Status "Installation directory not found: $InstallPath" -Type 'Info' }
    } catch {
        Write-Status "Uninstallation failed: $($_.Exception.Message)" -Type 'Error'
    }
}

function Invoke-Installation {
    $TempXmlPath = $null
    try {
        if (-not (Test-Path $InstallPath)) { New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null; Write-Status "Created install directory: $InstallPath" -Type 'Success' }
        if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null; Write-Status "Created log directory: $LogPath" -Type 'Success' }
        
        Copy-Item -Path (Join-Path $ScriptRoot $UpdateScriptName) -Destination (Join-Path $InstallPath $UpdateScriptName) -Force
        
        $TaskXmlContent = Get-Content (Join-Path $ScriptRoot $TaskXmlName) -Raw
        $CurrentUserSID = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        
        $TaskXmlContent = $TaskXmlContent -replace "2025-01-01T03:00:00", "2025-01-01T$($ScheduleTime):00"
        $TaskXmlContent = $TaskXmlContent -replace "%USERPROFILE%\\Documents\\ScoopAutoUpdate", $InstallPath
        $TaskXmlContent = $TaskXmlContent -replace '##USER_SID##', $CurrentUserSID

        $TempXmlPath = Join-Path $env:TEMP "ScoopAutoUpdate_Task.xml"
        $TaskXmlContent | Out-File -FilePath $TempXmlPath -Encoding UTF8 -Force
        
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false }
        
        Register-ScheduledTask -TaskName $TaskName -Xml (Get-Content -Path $TempXmlPath -Raw) | Out-Null
        
        Remove-Item -Path $TempXmlPath -Force; $TempXmlPath = $null

        $RegisteredTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($RegisteredTask) { 
            $NextRun = if ($RegisteredTask.NextRunTime -lt [datetime]::new(2002,1,1)) { $RegisteredTask.Triggers[0].StartBoundary } else { $RegisteredTask.NextRunTime }
            Write-Status "Task '$TaskName' registered successfully. Next run: $($NextRun)" -Type 'Success'
        }
        else { Write-Status "Task verification failed." -Type 'Warning' }
    } catch {
        Write-Status "Installation failed: $($_.Exception.Message)" -Type 'Error'
        if ($TempXmlPath -and (Test-Path $TempXmlPath)) { Remove-Item -Path $TempXmlPath -Force }
        throw
    }
}

# --- Main Execution Block ---
try {
    Write-Host "`n=== Scoop Auto-Update Installer ===" -ForegroundColor White -BackgroundColor DarkBlue
    
    if ($Uninstall) { Invoke-Uninstall }
    else {
        # Check that required files exist in the same directory
        if (-not ((Test-Path (Join-Path $ScriptRoot $UpdateScriptName)) -and (Test-Path (Join-Path $ScriptRoot $TaskXmlName)))) {
            throw "Required files 'Update-Scoop.ps1' and 'ScoopAutoUpdate.xml' not found. Please ensure all three files are in the same directory."
        }

        # Check prerequisites
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
        if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "This script should not be run as Administrator." }
        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { throw "Scoop not found. Please install Scoop first: https://scoop.sh" }
        Write-Status "Prerequisites met." -Type 'Success'

        Invoke-Installation
        
        Write-Host ""
        Write-Status "Installation completed successfully!" -Type 'Success'
    }
}
catch {
    Write-Status "An error occurred: $($_.Exception.Message)" -Type 'Error'
    exit 1
}

exit 0