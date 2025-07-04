#Requires -Version 5.1
<#
.SYNOPSIS
    Scoop auto updater installer.

.DESCRIPTION
    Installs and configures a daily scheduled task to update Scoop and its packages.
    This script can be run locally or directly from the web.

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
    # Run directly from the web
    iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/Xelofan/Scoop-Scheduled-Updates/master/Install-ScoopAutoUpdate.ps1'))

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

    # If running from memory (iex) or files are not found locally, download them
    Write-Status "Running from web or local files not found. Downloading required files..." -Type 'Info'
    $TempDir = Join-Path $env:TEMP "ScoopAutoUpdate_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
    
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $WebClient = New-Object System.Net.WebClient

        # Download Update-Scoop.ps1
        $RemoteUrl = "$DefaultRepoUrl/$UpdateScriptName"
        $LocalPath = Join-Path $TempDir $UpdateScriptName
        Write-Status "Downloading $UpdateScriptName..." -Type 'Info'
        $WebClient.DownloadFile($RemoteUrl, $LocalPath)

        # Download ScoopAutoUpdate.xml
        $RemoteUrl = "$DefaultRepoUrl/$TaskXmlName"
        $LocalPath = Join-Path $TempDir $TaskXmlName
        Write-Status "Downloading $TaskXmlName..." -Type 'Info'
        $WebClient.DownloadFile($RemoteUrl, $LocalPath)

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
        if ($ExistingTask) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Status "Scheduled task '$TaskName' removed successfully." -Type 'Success'
        }
        else { Write-Status "Scheduled task '$TaskName' not found." -Type 'Info' }
        if (Test-Path $InstallPath) {
            Remove-Item -Path $InstallPath -Recurse -Force
            Write-Status "Installation directory removed: $InstallPath" -Type 'Success'
        }
        else { Write-Status "Installation directory not found: $InstallPath" -Type 'Info' }
        Write-Status "Uninstallation completed successfully." -Type 'Success'
    } catch {
        Write-Status "Uninstallation failed: $($_.Exception.Message)" -Type 'Error'
    }
}

function Invoke-Installation {
    param([string]$SourcePath) # Takes the source path as a parameter now

    $UpdateScriptName = "Update-Scoop.ps1"
    $TaskXmlName = "ScoopAutoUpdate.xml"
    $LogPath = "$env:USERPROFILE\.scoop\logs"

    Write-Status "Starting installation..." -Type 'Info'
    try {
        # Create directories
        if (-not (Test-Path $InstallPath)) { New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null; Write-Status "Created installation directory: $InstallPath" -Type 'Success' }
        if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null; Write-Status "Created log directory: $LogPath" -Type 'Success' }
        
        # Copy Update-Scoop.ps1
        $SourceScript = Join-Path $SourcePath $UpdateScriptName
        $DestScript = Join-Path $InstallPath $UpdateScriptName
        Copy-Item -Path $SourceScript -Destination $DestScript -Force
        Write-Status "Copied $UpdateScriptName to installation directory." -Type 'Success'
        
        # --- THIS BLOCK IS NOW CORRECTED TO BE iex-SAFE ---
        # 1. Prepare the XML content in memory
        $TaskXmlPath = Join-Path $SourcePath $TaskXmlName
        $TaskXmlContent = Get-Content $TaskXmlPath -Raw
        $CurrentUserSID = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        
        $TaskXmlContent = $TaskXmlContent -replace "2025-01-01T03:00:00", "2025-01-01T$($ScheduleTime):00"
        $TaskXmlContent = $TaskXmlContent -replace "%USERPROFILE%\\Documents\\ScoopAutoUpdate", $InstallPath
        $TaskXmlContent = $TaskXmlContent -replace '##USER_SID##', $CurrentUserSID

        # 2. Save the content to a temporary file on disk
        $TempXmlPath = Join-Path $env:TEMP "ScoopAutoUpdate_Task.xml"
        $TaskXmlContent | Out-File -FilePath $TempXmlPath -Encoding UTF8 -Force
        
        # Remove existing task if it exists
        $ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($ExistingTask) { Write-Status "Removing existing task..."; Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false }
        
        # 3. Register the task by reading from the temp file
        Register-ScheduledTask -TaskName $TaskName -Xml (Get-Content -Path $TempXmlPath -Raw) | Out-Null
        
        # 4. Clean up the temp file
        Remove-Item -Path $TempXmlPath -Force

        Write-Status "Scheduled task '$TaskName' registered successfully." -Type 'Success'
        
        # Verify task registration
        $RegisteredTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($RegisteredTask) { 
            # Use NextRunTime if available, otherwise use the trigger's start boundary
            $NextRun = if ($RegisteredTask.NextRunTime -lt [datetime]::new(2002,1,1)) { $RegisteredTask.Triggers[0].StartBoundary } else { $RegisteredTask.NextRunTime }
            Write-Status "Task verification successful. Next run: $($NextRun)" -Type 'Success'
        }
        else { Write-Status "Task verification failed." -Type 'Warning' }
    } catch {
        Write-Status "Installation failed: $($_.Exception.Message)" -Type 'Error'
        # Clean up temp file on failure too
        if (Test-Path $TempXmlPath) { Remove-Item -Path $TempXmlPath -Force }
        throw
    }
}


# --- Main Execution Block ---
$ScriptRoot = $null
$IsTemp = $false

try {
    Write-Host "`n=== Scoop Auto-Update Installer ===" -ForegroundColor White -BackgroundColor DarkBlue
    
    if ($Uninstall) {
        Invoke-Uninstall
    }
    else {
        # This is the key change. We initialize the path first.
        $ScriptRoot = Initialize-SourcePath
        if (-not $ScriptRoot) { throw "Could not prepare source files. Aborting." }
        
        # Check if we are using a temporary directory
        if ($ScriptRoot.Contains($env:TEMP)) { $IsTemp = $true }

        # Check prerequisites
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
        if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "This script should not be run as Administrator." }
        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { throw "Scoop not found. Please install Scoop first: https://scoop.sh" }
        Write-Status "Prerequisites met." -Type 'Success'

        # Perform installation, passing the determined source path
        Invoke-Installation -SourcePath $ScriptRoot
        
        Write-Host ""
        Write-Status "=== Installation Summary ===" -Type 'Info'
        Write-Status "✓ Scripts installed to: $InstallPath" -Type 'Success'
        Write-Status "✓ Logs will be stored in: $env:USERPROFILE\.scoop\logs" -Type 'Success'
        Write-Status "✓ Scheduled task '$TaskName' created to run daily at $ScheduleTime" -Type 'Success'
        Write-Host ""
        Write-Status "Installation completed successfully!" -Type 'Success'
    }
}
catch {
    Write-Status "An error occurred: $($_.Exception.Message)" -Type 'Error'
    exit 1
}
finally {
    # Clean up the temporary directory if one was used
    if ($IsTemp -and $ScriptRoot -and (Test-Path $ScriptRoot)) {
        Write-Status "Cleaning up temporary files..." -Type 'Info'
        Remove-Item -Path $ScriptRoot -Recurse -Force
    }
}

exit 0