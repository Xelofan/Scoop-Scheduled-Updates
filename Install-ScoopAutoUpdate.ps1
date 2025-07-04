#Requires -Version 5.1
<#
.SYNOPSIS
    Scoop auto updater installer.

.DESCRIPTION
    Installs and configures a daily scheduled task to update Scoop and its packages.
    This script can be run locally or directly from the web using the recommended one-liner.

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
    # Run directly from the web (Recommended Method)
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-Command -ScriptBlock ([ScriptBlock]::Create((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/Xelofan/Scoop-Scheduled-Updates/master/Install-ScoopAutoUpdate.ps1')))
#>

param(
    [string]$InstallPath = "$env:USERPROFILE\Documents\ScoopAutoUpdate",
    [string]$TaskName = "ScoopAutoUpdate",
    [string]$ScheduleTime = "03:00",
    [switch]$Uninstall
)

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

# --- This function now determines the source path for the other script files ---
function Initialize-SourcePath {
    $UpdateScriptName = "Update-Scoop.ps1"
    $TaskXmlName = "ScoopAutoUpdate.xml"
    $DefaultRepoUrl = "https://raw.githubusercontent.com/Xelofan/Scoop-Scheduled-Updates/master"

    # If the script is run as a local file, check for the other files in its directory
    if ($PSScriptRoot) {
        if ((Test-Path (Join-Path $PSScriptRoot $UpdateScriptName)) -and (Test-Path (Join-Path $PSScriptRoot $TaskXmlName))) {
            Write-Status "Required files found locally in '$PSScriptRoot'." -Type 'Success'
            return $PSScriptRoot
        }
    }

    # If running from memory or files are not found locally, download them
    Write-Status "Running from web or local files not found. Downloading required files..." -Type 'Info'
    $TempDir = Join-Path $env:TEMP "ScoopAutoUpdate_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
    
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $WebClient = New-Object System.Net.WebClient

        $WebClient.DownloadFile("$DefaultRepoUrl/$UpdateScriptName", (Join-Path $TempDir $UpdateScriptName))
        Write-Status "Downloaded $UpdateScriptName..." -Type 'Info'

        $WebClient.DownloadFile("$DefaultRepoUrl/$TaskXmlName", (Join-Path $TempDir $TaskXmlName))
        Write-Status "Downloaded $TaskXmlName..." -Type 'Info'
        
        Write-Status "Files downloaded successfully to temporary directory." -Type 'Success'
        return $TempDir
    }
    catch {
        Write-Status "Failed to download required files: $($_.Exception.Message)" -Type 'Error'
        if (Test-Path $TempDir) { Remove-Item -Path $TempDir -Recurse -Force }
        return $null
    }
    finally {
        if ($WebClient) { $WebClient.Dispose() }
    }
}

# --- Installation, Uninstallation, and other functions ---

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
    param([string]$SourcePath)

    $UpdateScriptName = "Update-Scoop.ps1"
    $TaskXmlName = "ScoopAutoUpdate.xml"
    $LogPath = "$env:USERPROFILE\.scoop\logs"
    $TempXmlPath = $null

    try {
        if (-not (Test-Path $InstallPath)) { New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null; Write-Status "Created install directory: $InstallPath" -Type 'Success' }
        if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null; Write-Status "Created log directory: $LogPath" -Type 'Success' }
        
        Copy-Item -Path (Join-Path $SourcePath $UpdateScriptName) -Destination (Join-Path $InstallPath $UpdateScriptName) -Force
        
        $TaskXmlContent = Get-Content (Join-Path $SourcePath $TaskXmlName) -Raw
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
$ScriptRoot = $null
$IsTemp = $false

try {
    Write-Host "`n=== Scoop Auto-Update Installer ===" -ForegroundColor White -BackgroundColor DarkBlue
    
    if ($Uninstall) { Invoke-Uninstall }
    else {
        $ScriptRoot = Initialize-SourcePath
        if (-not $ScriptRoot) { throw "Could not prepare source files. Aborting." }
        if ($ScriptRoot.Contains($env:TEMP)) { $IsTemp = $true }

        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
        if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "This script should not be run as Administrator." }
        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { throw "Scoop not found. Please install Scoop first: https://scoop.sh" }
        Write-Status "Prerequisites met." -Type 'Success'

        Invoke-Installation -SourcePath $ScriptRoot
        
        Write-Host ""
        Write-Status "Installation completed successfully!" -Type 'Success'
    }
}
catch {
    Write-Status "An error occurred: $($_.Exception.Message)" -Type 'Error'
    exit 1
}
finally {
    if ($IsTemp -and $ScriptRoot -and (Test-Path $ScriptRoot)) {
        Write-Status "Cleaning up temporary files..." -Type 'Info'
        Remove-Item -Path $ScriptRoot -Recurse -Force
    }
}

exit 0