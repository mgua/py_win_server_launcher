# powershell script for launching 
# python servers in windows, each in its own environment
# using wt windows with specific colorschemes
# mgua@tomware.it and claude, 26 12 2024
#
#
[CmdletBinding()]
param(
    [Parameter()]
    [switch]$UseTemporarySettings,
    
    [Parameter()]
    [switch]$ModifyCurrentSettings,
    
    [Parameter()]
    [switch]$Force,
    
    [Parameter()]
    [switch]$IgnoreRunning
)

# Error handling preference
$ErrorActionPreference = "Stop"

# Function to get detailed process information
function Get-ServerProcessInfo {
    param(
        [System.Diagnostics.Process]$process
    )
    
    try {
        $cpuCounter = New-Object System.Diagnostics.CounterSample
        try {
            $cpu = (Get-Counter "\Process($($process.ProcessName)*)\% Processor Time" -ErrorAction SilentlyContinue).CounterSamples.CookedValue
        }
        catch {
            $cpu = "N/A"
        }
        
        return @{
            ProcessId = $process.Id
            CPU = if ($cpu -eq "N/A") { "N/A" } else { "{0:N1}%" -f $cpu }
            Memory = "{0:N2} MB" -f ($process.WorkingSet64 / 1MB)
            StartTime = $process.StartTime
            Runtime = (Get-Date) - $process.StartTime
            CommandLine = (Get-WmiObject Win32_Process -Filter "ProcessId = $($process.Id)").CommandLine
        }
    }
    catch {
        Write-Warning "Could not get full process information for PID $($process.Id): $_"
        return $null
    }
}

# Function to write to log file
function Write-ServerLog {
    param(
        [string]$Message,
        [string]$ServerName,
        [string]$Type = "INFO"
    )
    
    $logDir = ".\logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }
    
    $logFile = Join-Path $logDir "server_launcher.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Type] [$ServerName] $Message"
    
    Add-Content -Path $logFile -Value $logMessage
    
    # Also write to console with color based on type
    $color = switch ($Type) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host $logMessage -ForegroundColor $color
}

# Function to stop server process
function Stop-ServerProcess {
    param(
        [System.Diagnostics.Process]$process,
        [string]$serverName
    )
    
    try {
        Write-ServerLog -ServerName $serverName -Message "Attempting to stop process $($process.Id)..."
        
        # Try graceful shutdown first
        if (-not $process.HasExited) {
            $process.CloseMainWindow() | Out-Null
            if (-not $process.WaitForExit(5000)) {
                Write-ServerLog -ServerName $serverName -Message "Graceful shutdown failed, forcing termination..." -Type "WARNING"
                $process.Kill()
            }
        }
        
        Write-ServerLog -ServerName $serverName -Message "Process stopped successfully" -Type "SUCCESS"
        return $true
    }
    catch {
        Write-ServerLog -ServerName $serverName -Message "Failed to stop process: $_" -Type "ERROR"
        return $false
    }
}

# Function to check if a server process is running
function Test-ServerRunning {
    param(
        [string]$serverName,
        [string]$scriptPath
    )
    
    # Get all Python processes
    $pythonProcesses = Get-Process python -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and (Test-Path $_.Path)
    }
    
    $runningProcesses = @()
    
    foreach ($process in $pythonProcesses) {
        try {
            # Get command line arguments for the process
            $cmdLine = (Get-WmiObject Win32_Process -Filter "ProcessId = $($process.Id)").CommandLine
            
            # Check if this process is running our script
            if ($cmdLine -match [regex]::Escape($scriptPath)) {
                $processInfo = Get-ServerProcessInfo -process $process
                if ($processInfo) {
                    $runningProcesses += @{
                        Process = $process
                        Info = $processInfo
                    }
                }
            }
        }
        catch {
            Write-ServerLog -ServerName $serverName -Message "Could not check process $($process.Id): $_" -Type "WARNING"
        }
    }
    
    if ($runningProcesses.Count -gt 0) {
        Write-ServerLog -ServerName $serverName -Message "Found $($runningProcesses.Count) running instance(s)"
        
        foreach ($proc in $runningProcesses) {
            $info = $proc.Info
            Write-ServerLog -ServerName $serverName -Message @"
Process Details:
  PID: $($info.ProcessId)
  CPU: $($info.CPU)
  Memory: $($info.Memory)
  Running Time: $($info.Runtime)
  Start Time: $($info.StartTime)
"@
        }
        
        return $runningProcesses
    }
    
    Write-ServerLog -ServerName $serverName -Message "No running instances found"
    return $null
}

# Function to get user decision about running server
function Get-ServerStartDecision {
    param(
        [string]$serverName,
        [array]$runningProcesses
    )
    
    if ($Force) {
        return @{ Action = "START"; StopExisting = $true }
    }
    
    Write-Host @"
    
Server $serverName is already running. Choose an action:
[S] Start new instance anyway
[T] Terminate existing and start new
[K] Keep existing (skip)
"@
    
    do {
        $decision = Read-Host "[S/T/K]"
        switch ($decision.ToUpper()) {
            "S" { return @{ Action = "START"; StopExisting = $false } }
            "T" { return @{ Action = "START"; StopExisting = $true } }
            "K" { return @{ Action = "SKIP"; StopExisting = $false } }
            default { Write-Host "Invalid choice. Please enter S, T, or K" }
        }
    } while ($true)
}

# Function to acquire a lock with timeout
function Get-SettingsLock {
    param(
        [int]$timeoutSeconds = 30
    )
    
    $startTime = Get-Date
    $locked = $false
    
    while (-not $locked) {
        try {
            $lockStream = [System.IO.File]::Open($wtSettingsLockFile, 
                [System.IO.FileMode]::CreateNew, 
                [System.IO.FileAccess]::ReadWrite, 
                [System.IO.FileShare]::None)
            $locked = $true
            return $lockStream
        }
        catch {
            if ((Get-Date).Subtract($startTime).TotalSeconds -gt $timeoutSeconds) {
                throw "Failed to acquire lock on settings file after $timeoutSeconds seconds. Another process may be using it."
            }
            Start-Sleep -Milliseconds 100
        }
    }
}

# Function to safely read settings with retry
function Read-SettingsWithRetry {
    param(
        [string]$Path,
        [int]$maxRetries = 3,
        [int]$retryDelayMs = 500
    )
    
    for ($i = 0; $i -lt $maxRetries; $i++) {
        try {
            $content = $null
            $fileStream = [System.IO.File]::Open($Path, 
                [System.IO.FileMode]::Open, 
                [System.IO.FileAccess]::Read, 
                [System.IO.FileShare]::Read)
            
            try {
                $reader = New-Object System.IO.StreamReader($fileStream)
                $content = $reader.ReadToEnd()
            }
            finally {
                if ($reader) { $reader.Dispose() }
                if ($fileStream) { $fileStream.Dispose() }
            }
            
            return $content | ConvertFrom-Json
        }
        catch {
            if ($i -eq $maxRetries - 1) {
                throw "Failed to read settings file after $maxRetries attempts: $_"
            }
            Start-Sleep -Milliseconds $retryDelayMs
        }
    }
}

# Function to safely write settings with retry
function Write-SettingsWithRetry {
    param(
        [string]$Path,
        $Settings,
        [int]$maxRetries = 3,
        [int]$retryDelayMs = 500
    )
    
    $tempPath = "$Path.tmp"
    $content = $Settings | ConvertTo-Json -Depth 10
    
    for ($i = 0; $i -lt $maxRetries; $i++) {
        try {
            # Write to temp file first
            [System.IO.File]::WriteAllText($tempPath, $content)
            
            # Verify the temp file is valid JSON
            $null = Get-Content $tempPath -Raw | ConvertFrom-Json
            
            # Replace the original file
            Move-Item -Path $tempPath -Destination $Path -Force
            return
        }
        catch {
            if ($i -eq $maxRetries - 1) {
                throw "Failed to write settings file after $maxRetries attempts: $_"
            }
            Start-Sleep -Milliseconds $retryDelayMs
        }
        finally {
            if (Test-Path $tempPath) {
                Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# Function to create Windows Terminal command for each window
function Get-WTCommand {
    param(
        [hashtable]$config
    )
    
    $pos = $config.Position
    return "new-tab --profile `"$($config.ProfileName)`" ``
        --title `"$($config.Title)`" ``
        --pos ${pos.X}x${pos.Y} ``
        --size ${pos.Width}x${pos.Height} ``
        powershell.exe -NoExit -Command ``
        `"Set-Location '$($config.HomeFolder)'; ``
        & '$($config.VenvPath)\Scripts\activate.ps1'; ``
        $($config.StartupCmd)`""
}

# Server configurations
$configurations = @(
    @{
        ServerName = "s01"
        HomeFolder = "C:\Servers\s01"
        VenvPath = "C:\Servers\venv_s01"
        StartupCmd = "python s01.py"
        Title = "Server 01"
        ProfileName = "Server01"
        Position = @{
            X = 0
            Y = 0
            Width = 80
            Height = 25
        }
    },
    @{
        ServerName = "s02"
        HomeFolder = "C:\Servers\s02"
        VenvPath = "C:\Servers\venv_s02"
        StartupCmd = "python s02.py"
        Title = "Server 02"
        ProfileName = "Server02"
        Position = @{
            X = 82
            Y = 0
            Width = 80
            Height = 25
        }
    },
    @{
        ServerName = "s03"
        HomeFolder = "C:\Servers\s03"
        VenvPath = "C:\Servers\venv_s03"
        StartupCmd = "python s03.py"
        Title = "Server 03"
        ProfileName = "Server03"
        Position = @{
            X = 0
            Y = 27
            Width = 80
            Height = 25
        }
    },
    @{
        ServerName = "s04"
        HomeFolder = "C:\Servers\s04"
        VenvPath = "C:\Servers\venv_s04"
        StartupCmd = "python s04.py"
        Title = "Server 04"
        ProfileName = "Server04"
        Position = @{
            X = 82
            Y = 27
            Width = 80
            Height = 25
        }
    }
)


# Windows Terminal settings paths
$wtSettingsDir = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
$wtSettingsPath = Join-Path $wtSettingsDir "settings.json"
$wtSettingsBackupPath = Join-Path $wtSettingsDir "settings.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$wtSettingsLockFile = Join-Path $wtSettingsDir "settings.lock"
$sourceSettingsPath = ".\wt-settings.json"

# Main execution block
$lockStream = $null
try {
    if ($UseTemporarySettings -or $ModifyCurrentSettings) {
        Write-Host "Acquiring lock on settings file..."
        $lockStream = Get-SettingsLock
        
        # Ensure settings directory exists
        if (-not (Test-Path $wtSettingsDir)) {
            New-Item -ItemType Directory -Path $wtSettingsDir -Force
        }
        
        # Create backup with retry
        if (Test-Path $wtSettingsPath) {
            Write-Host "Creating backup of current settings..."
            Copy-Item -Path $wtSettingsPath -Destination $wtSettingsBackupPath -Force -ErrorAction Stop
            Write-Host "Created backup at: $wtSettingsBackupPath"
        }
        
        # Load settings
        Write-Host "Loading current settings..."
        $currentSettings = Read-SettingsWithRetry $wtSettingsPath
        $newSettings = Get-TerminalSettings $sourceSettingsPath
        
        if (-not $currentSettings -or -not $newSettings) {
            throw "Failed to load required settings files"
        }
        
        # Check for profile conflicts
        $conflicts = Test-ProfileConflicts $currentSettings $newSettings.profiles.list
        if ($conflicts -and -not $Force) {
            Write-Host "The following profiles already exist in your settings:"
            $conflicts | ForEach-Object { Write-Host "- $_" }
            
            $confirmation = Read-Host "Do you want to overwrite these profiles? (Y/N)"
            if ($confirmation -ne 'Y') {
                Write-Host "Operation cancelled by user."
                exit
            }
        }
        
        # Apply settings changes
        if ($UseTemporarySettings) {
            Write-Host "Applying temporary settings..."
            $tempSettingsPath = Join-Path $wtSettingsDir "settings.temp.json"
            $mergedSettings = Merge-Profiles -CurrentSettings $currentSettings -NewProfiles $newSettings.profiles.list -RemoveExisting
            Write-SettingsWithRetry -Path $tempSettingsPath -Settings $mergedSettings
            
            Move-Item $wtSettingsPath "$wtSettingsPath.original" -Force
            Move-Item $tempSettingsPath $wtSettingsPath -Force
        }
        elseif ($ModifyCurrentSettings) {
            Write-Host "Updating current settings..."
            $mergedSettings = Merge-Profiles -CurrentSettings $currentSettings -NewProfiles $newSettings.profiles.list -RemoveExisting
            Write-SettingsWithRetry -Path $wtSettingsPath -Settings $mergedSettings
            Write-Host "Successfully updated Windows Terminal settings"
        }
    }
    
    # Check running servers and build command
    Write-ServerLog -ServerName "Launcher" -Message "Starting server checks..."
    $wtCommand = "wt"
    $serversToLaunch = @()
    
    foreach ($config in $configurations) {
        $scriptPath = Join-Path $config.HomeFolder "$($config.ServerName).py"
        $runningProcesses = Test-ServerRunning -serverName $config.ServerName -scriptPath $scriptPath
        
        if ($runningProcesses) {
            $decision = Get-ServerStartDecision -serverName $config.ServerName -runningProcesses $runningProcesses
            
            if ($decision.StopExisting) {
                Write-ServerLog -ServerName $config.ServerName -Message "Stopping existing processes..."
                foreach ($proc in $runningProcesses) {
                    $stopped = Stop-ServerProcess -process $proc.Process -serverName $config.ServerName
                    if (-not $stopped) {
                        Write-ServerLog -ServerName $config.ServerName -Message "Failed to stop process, skipping restart" -Type "ERROR"
                        continue
                    }
                }
            }
            
            if ($decision.Action -eq "SKIP") {
                Write-ServerLog -ServerName $config.ServerName -Message "Skipping server launch (user choice)"
                continue
            }
        }
        
        $serversToLaunch += $config
        if ($serversToLaunch.Count -eq 1) {
            $wtCommand += " "  # First tab doesn't need new-tab
        } else {
            $wtCommand += "; new-tab "
        }
        $wtCommand += Get-WTCommand -config $config
        Write-ServerLog -ServerName $config.ServerName -Message "Added to launch queue"
    }
    
    if ($serversToLaunch.Count -eq 0) {
        Write-ServerLog -ServerName "Launcher" -Message "No servers to launch. All servers are either running or launch was cancelled."
        exit
    }
    
    Write-ServerLog -ServerName "Launcher" -Message "Launching $($serversToLaunch.Count) server(s)..."
    
    # Split the command into parts and join with proper delays
    $wtParts = $wtCommand -split '; new-tab'
    $finalCommand = $wtParts[0]  # First part (wt)
    for ($i = 1; $i -lt $wtParts.Count; $i++) {
        $finalCommand += "; sleep 1; new-tab" + $wtParts[$i]
    }
    
    # Launch the Windows Terminal with all configurations
    Write-ServerLog -ServerName "Launcher" -Message "Executing Windows Terminal command..."
    Invoke-Expression $finalCommand
    
    if ($UseTemporarySettings) {
        Write-Host "Press any key to restore original settings..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    
    if ($UseTemporarySettings -and (Test-Path "$wtSettingsPath.original")) {
        Write-Host "Attempting to restore original settings..." -ForegroundColor Yellow
        Move-Item "$wtSettingsPath.original" $wtSettingsPath -Force
    }
}
finally {
    if ($lockStream) {
        $lockStream.Dispose()
        if (Test-Path $wtSettingsLockFile) {
            Remove-Item $wtSettingsLockFile -Force
        }
    }
}






