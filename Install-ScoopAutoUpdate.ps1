#Requires -Version 5.1
<#
.SYNOPSIS
    Scoop auto updater installer.

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
    .\Install-ScoopAutoUpdate.ps1
    Install with default settings

.EXAMPLE
    .\Install-ScoopAutoUpdate.ps1 -ScheduleTime "02:30"
    Install with custom schedule time

.EXAMPLE
    .\Install-ScoopAutoUpdate.ps1 -Uninstall
    Delete the installation
#>

param(
    [string]$InstallPath = "$env:USERPROFILE\Documents\ScoopAutoUpdate",
    [string]$TaskName = "ScoopAutoUpdate",
    [string]$ScheduleTime = "03:00",
    [switch]$Uninstall
)

# Initialize variables
$ScriptRoot = $PSScriptRoot
$UpdateScriptName = "Update-Scoop.ps1"
$TaskXmlName = "ScoopAutoUpdate.xml"
$LogPath = "$env:USERPROFILE\.scoop\logs"

# Helper function for colored output
function Write-Status {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Type = 'Info'
    )
    
    $Colors = @{
        'Info' = 'Cyan'
        'Success' = 'Green'
        'Warning' = 'Yellow'
        'Error' = 'Red'
    }
    
    $Prefix = switch ($Type) {
        'Info' { "[INFO]" }
        'Success' { "[SUCCESS]" }
        'Warning' { "[WARNING]" }
        'Error' { "[ERROR]" }
    }
    
    Write-Host "$Prefix $Message" -ForegroundColor $Colors[$Type]
}

# Validate prerequisites
function Test-Prerequisites {
    Write-Status "Checking prerequisites..." -Type 'Info'
    
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Status "PowerShell 5.1 or higher is required. Current version: $($PSVersionTable.PSVersion)" -Type 'Error'
        return $false
    }
    
    # Check if Scoop is installed
    try {
        $ScoopPath = Get-Command scoop -ErrorAction Stop
        Write-Status "Scoop found at: $($ScoopPath.Source)" -Type 'Success'
    }
    catch {
        Write-Status "Scoop not found. Please install Scoop first: https://scoop.sh" -Type 'Error'
        return $false
    }
    
    # Check if running as administrator (we don't want this)
    $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($CurrentUser)
    if ($Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Status "This script should NOT be run as Administrator. Please run as regular user." -Type 'Error'
        return $false
    }
    
    Write-Status "All prerequisites met." -Type 'Success'
    return $true
}

# Download required files from GitHub
function Get-RequiredFiles {
    param(
        [string]$BaseUrl = "https://raw.githubusercontent.com/Xelofan/Scoop-Scheduled-Updates/refs/heads/master"
    )
    
    $FilesToDownload = @{
        $UpdateScriptName = "$BaseUrl/Update-Scoop.ps1"
        $TaskXmlName = "$BaseUrl/ScoopAutoUpdate.xml"
    }
    
    Write-Status "Downloading required files from remote repository..." -Type 'Info'
    
    # Create temp directory for downloads
    $TempDir = Join-Path $env:TEMP "ScoopAutoUpdate_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
    
    try {
        # Set TLS 1.2 for older PowerShell versions
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        foreach ($File in $FilesToDownload.GetEnumerator()) {
            $LocalPath = Join-Path $TempDir $File.Key
            $RemoteUrl = $File.Value
            
            Write-Status "Downloading $($File.Key)..." -Type 'Info'
            
            try {
                $WebClient = New-Object System.Net.WebClient
                $WebClient.DownloadFile($RemoteUrl, $LocalPath)
                
                if (Test-Path $LocalPath) {
                    Write-Status "Downloaded $($File.Key) successfully." -Type 'Success'
                }
                else {
                    throw "File not found after download"
                }
            }
            catch {
                Write-Status "Failed to download $($File.Key): $($_.Exception.Message)" -Type 'Error'
                return $false
            }
            finally {
                if ($WebClient) { $WebClient.Dispose() }
            }
        }
        
        # Update ScriptRoot to point to temp directory
        $script:ScriptRoot = $TempDir
        Write-Status "All required files downloaded successfully." -Type 'Success'
        return $true
    }
    catch {
        Write-Status "Failed to download files: $($_.Exception.Message)" -Type 'Error'
        return $false
    }
}

# Check if required files exist (local or remote)
function Test-RequiredFiles {
    # If PSScriptRoot is not set, we are running from memory (e.g. iex).
    # We must skip the local file check and go directly to download.
    if (-not $PSScriptRoot) {
        Write-Status "Running in memory, must download required files..." -Type 'Info'
        return Get-RequiredFilesFromDefaultUrl
    }

    # First check if files exist locally
    $UpdateScriptPath = Join-Path $ScriptRoot $UpdateScriptName
    $TaskXmlPath = Join-Path $ScriptRoot $TaskXmlName
    
    if ((Test-Path $UpdateScriptPath) -and (Test-Path $TaskXmlPath)) {
        Write-Status "Required files found locally." -Type 'Success'
        return $true
    }
    
    # If not found locally, try to download from remote
    Write-Status "Local files not found. Attempting remote download..." -Type 'Info'
    return Get-RequiredFilesFromDefaultUrl
}

# This is a new helper function. I've separated the download logic
# so it can be called from multiple places without code duplication.
function Get-RequiredFilesFromDefaultUrl {
    # Auto-detect GitHub URL if running from remote
    $RemoteUrl = $null
    try {
        # Check if we're running from a remote URL
        $InvocationUri = [System.Uri]$MyInvocation.MyCommand.Path
        if ($InvocationUri.Scheme -eq 'https' -and $InvocationUri.Host -eq 'raw.githubusercontent.com') {
            # Extract base URL from current execution
            $PathParts = $InvocationUri.AbsolutePath.Split('/')
            if ($PathParts.Length -ge 4) {
                # Combine the first three parts of the path after the host
                $RemoteUrl = "https://raw.githubusercontent.com/$($PathParts[1])/$($PathParts[2])/$($PathParts[3])"
            }
        }
    }
    catch {
        # Ignore errors in URL detection
    }
    
    # Use detected URL or default
    if (-not $RemoteUrl) {
        $RemoteUrl = "https://raw.githubusercontent.com/Xelofan/Scoop-Scheduled-Updates/refs/heads/master"
        Write-Status "Using default repository URL." -Type 'Warning'
    }
    
    return Get-RequiredFiles -BaseUrl $RemoteUrl
}

# Uninstall function
function Invoke-Uninstall {
    Write-Status "Starting uninstallation..." -Type 'Info'
    
    try {
        # Remove scheduled task
        $ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($ExistingTask) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Status "Scheduled task '$TaskName' removed successfully." -Type 'Success'
        }
        else {
            Write-Status "Scheduled task '$TaskName' not found." -Type 'Info'
        }
        
        # Remove installation directory
        if (Test-Path $InstallPath) {
            Remove-Item -Path $InstallPath -Recurse -Force
            Write-Status "Installation directory removed: $InstallPath" -Type 'Success'
        }
        else {
            Write-Status "Installation directory not found: $InstallPath" -Type 'Info'
        }
        
        Write-Status "Uninstallation completed successfully." -Type 'Success'
        return $true
    }
    catch {
        Write-Status "Uninstallation failed: $($_.Exception.Message)" -Type 'Error'
        return $false
    }
}

# Main installation function
function Invoke-Installation {
    Write-Status "Starting installation..." -Type 'Info'
    
    try {
        # Create installation directory
        if (-not (Test-Path $InstallPath)) {
            New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null
            Write-Status "Created installation directory: $InstallPath" -Type 'Success'
        }
        else {
            Write-Status "Installation directory already exists: $InstallPath" -Type 'Info'
        }
        
        # Create log directory
        if (-not (Test-Path $LogPath)) {
            New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
            Write-Status "Created log directory: $LogPath" -Type 'Success'
        }
        else {
            Write-Status "Log directory already exists: $LogPath" -Type 'Info'
        }
        
        # Copy Update-Scoop.ps1 to installation directory
        $SourceScript = Join-Path $ScriptRoot $UpdateScriptName
        $DestScript = Join-Path $InstallPath $UpdateScriptName
        Copy-Item -Path $SourceScript -Destination $DestScript -Force
        Write-Status "Copied $UpdateScriptName to installation directory." -Type 'Success'
        
        # Prepare task XML with custom schedule time
        $TaskXmlPath = Join-Path $ScriptRoot $TaskXmlName
        $TaskXmlContent = Get-Content $TaskXmlPath -Raw

        # <<< ADD THIS LINE: Get the Security ID (SID) of the current user >>>
        $CurrentUserSID = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        
        # Update the start time in the XML
        $NewStartTime = "2025-01-01T$($ScheduleTime):00"
        $TaskXmlContent = $TaskXmlContent -replace "2025-01-01T03:00:00", $NewStartTime
        
        # Update the working directory and script path
        $TaskXmlContent = $TaskXmlContent -replace "%USERPROFILE%\\Documents\\ScoopAutoUpdate", $InstallPath

        # <<< ADD THIS LINE: Replace the UserId placeholder with the current user's SID >>>
        $TaskXmlContent = $TaskXmlContent -replace '##USER_SID##', $CurrentUserSID
        
        # Save modified XML to temp file
        $TempXmlPath = Join-Path $env:TEMP "ScoopAutoUpdate_temp.xml"
        $TaskXmlContent | Out-File -FilePath $TempXmlPath -Encoding UTF8
        
        # Remove existing task if it exists
        $ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($ExistingTask) {
            Write-Status "Removing existing scheduled task..." -Type 'Info'
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }
        
        # Register the scheduled task
        Register-ScheduledTask -TaskName $TaskName -Xml (Get-Content $TempXmlPath -Raw) | Out-Null
        
        # Clean up temp file
        Remove-Item -Path $TempXmlPath -Force
        
        Write-Status "Scheduled task '$TaskName' registered successfully." -Type 'Success'
        
        # Verify task registration
        $RegisteredTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($RegisteredTask) {
            Write-Status "Task verification successful. Next run: $($RegisteredTask.Triggers[0].StartBoundary)" -Type 'Success'
        }
        else {
            Write-Status "Task verification failed." -Type 'Warning'
        }
        
        return $true
    }
    catch {
        Write-Status "Installation failed: $($_.Exception.Message)" -Type 'Error'
        return $false
    }
}

# Test the installation
function Test-Installation {
    Write-Status "Testing installation..." -Type 'Info'
    
    try {
        # Test script execution
        $TestScriptPath = Join-Path $InstallPath $UpdateScriptName
        
        Write-Status "Running test execution of Update-Scoop.ps1..." -Type 'Info'
        $TestResult = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $TestScriptPath -Quiet
        
        if ($LASTEXITCODE -eq 0) {
            Write-Status "Test execution completed successfully." -Type 'Success'
        }
        else {
            Write-Status "Test execution completed with warnings. Check logs for details." -Type 'Warning'
        }
        
        # Check if log file was created
        $LogFiles = Get-ChildItem -Path $LogPath -Filter "Update-Scoop-*.log" -ErrorAction SilentlyContinue
        if ($LogFiles) {
            Write-Status "Log files found: $($LogFiles.Count) files in $LogPath" -Type 'Success'
        }
        else {
            Write-Status "No log files found. This may indicate an issue." -Type 'Warning'
        }
        
        return $true
    }
    catch {
        Write-Status "Installation test failed: $($_.Exception.Message)" -Type 'Error'
        return $false
    }
}

# Main execution
try {
    Write-Host ""
    Write-Host "=== Scoop Auto-Update Installer ===" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host ""
    
    if ($Uninstall) {
        Write-Status "Uninstall mode selected." -Type 'Info'
        $Success = Invoke-Uninstall
        
        if ($Success) {
            Write-Host ""
            Write-Status "Scoop Auto-Update has been uninstalled successfully." -Type 'Success'
        }
        else {
            Write-Host ""
            Write-Status "Uninstallation failed. Please check the errors above." -Type 'Error'
            exit 1
        }
    }
    else {
        # Installation mode
        Write-Status "Installation mode selected." -Type 'Info'
        Write-Status "Install path: $InstallPath" -Type 'Info'
        Write-Status "Task name: $TaskName" -Type 'Info'
        Write-Status "Schedule time: $ScheduleTime daily" -Type 'Info'
        Write-Host ""
        
        # Check prerequisites
        if (-not (Test-Prerequisites)) {
            Write-Status "Prerequisites check failed. Installation aborted." -Type 'Error'
            exit 1
        }
        
        # Check required files
        if (-not (Test-RequiredFiles)) {
            Write-Status "Required files check failed. Installation aborted." -Type 'Error'
            exit 1
        }
        
        # Perform installation
        if (-not (Invoke-Installation)) {
            Write-Status "Installation failed. Please check the errors above." -Type 'Error'
            exit 1
        }
        
        # Test installation
        Test-Installation | Out-Null
        
        Write-Host ""
        Write-Status "=== Installation Summary ===" -Type 'Info'
        Write-Status "✓ Scripts installed to: $InstallPath" -Type 'Success'
        Write-Status "✓ Logs will be stored in: $LogPath" -Type 'Success'
        Write-Status "✓ Scheduled task '$TaskName' created" -Type 'Success'
        Write-Status "✓ Daily execution at: $ScheduleTime" -Type 'Success'
        Write-Host ""
        Write-Status "You can manually run the task using:" -Type 'Info'
        Write-Host "  Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
        Write-Host ""
        Write-Status "To view task status:" -Type 'Info'
        Write-Host "  Get-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
        Write-Host ""
        Write-Status "To uninstall, run this script with -Uninstall parameter." -Type 'Info'
        Write-Host ""
        Write-Status "Installation completed successfully!" -Type 'Success'
    }
    
    exit 0
}
finally {
    # Clean up temporary files if they were downloaded
    if ($ScriptRoot -and $ScriptRoot.Contains($env:TEMP)) {
        try {
            Remove-Item -Path $ScriptRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            # Ignore cleanup errors
        }
    }
}
catch {
    Write-Status "Unexpected error: $($_.Exception.Message)" -Type 'Error'
    Write-Status "Stack trace: $($_.Exception.StackTrace)" -Type 'Error'
    exit 1
}