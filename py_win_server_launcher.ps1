####################################################################################################
# py_win_server_launcher.ps1
# Launch multiple Python servers in Windows Terminal with specific layouts and environments
#
# Author: mgua@tomware.it
# strong Contributions: Claude 3.5 sonnet
# Version: 1.1.0
# Last Modified: 29/12/2024
#
# Description:
#   This script manages multiple Python server instances in Windows Terminal.
#   Each server runs in its own virtual environment with customized window positions and color schemes.
#
# Features:
#   - Process monitoring and management
#   - Customizable window layouts and color schemes
#   - Virtual environment support
#   - Graceful shutdown handling
#
# Technical notes:
#   - Process Management: The script handles the complexity of Python processes running under
#     virtual environments, where each server actually spawns two Python processes (one from
#     the venv and one from the system Python).
#   - Windows Terminal Integration: Server processes are launched in separate Windows Terminal
#     tabs with specific positions and color schemes. When a server is terminated, its process
#     is killed cleanly but the terminal tab needs to be closed manually (Ctrl+D).
#   - Virtual Environments: Each server runs in its own virtual environment, properly activated
#     before server launch.
#
# Usage:
#   .\py_win_server_launcher.ps1 [-Force] [-IgnoreRunning] [-Help]
#
# Parameters:
#   -Force          : Skip confirmation prompts and force restart any running instances
#   -IgnoreRunning  : Start new instances even if servers are already running
#   -Help           : Show this help message
#
####################################################################################################


# Show help if requested
param(
    [Parameter()]
    [string]$ConfigFile = ".\py_win_server_launcher.json",
    
    [Parameter()]
    [switch]$Force,
    
    [Parameter()]
    [switch]$IgnoreRunning,
    
    [Parameter()]
    [switch]$Help
)


# Function to display script help
function Show-ScriptHelp {
    $helpText = @"
Python Servers Windows Terminal Launcher
Usage: .\py_win_server_launcher.ps1 [-ConfigFile <path>] [-Force] [-IgnoreRunning] [-Help]

Description:
    Launches and manages multiple Python servers in Windows Terminal windows.
    Each server runs in its own virtual environment with customized window positions and color schemes.

Parameters:
    -ConfigFile     : Path to configuration JSON file (default: .\py_win_server_launcher.json)
    -Force          : Skip confirmation prompts and force restart any running instances
    -IgnoreRunning  : Start new instances even if servers are already running
    -Help           : Show this help message

Configuration File:
    The JSON configuration file contains two main sections:
    1. 'config' - Global settings for logging, terminal, and process management
    2. 'servers' - Array of server configurations including:
       - Server name and title
       - Home folder and virtual environment paths
       - Window position and color scheme
       - Startup command

Examples:
    .\py_win_server_launcher.ps1
    .\py_win_server_launcher.ps1 -ConfigFile .\custom_config.json
    .\py_win_server_launcher.ps1 -Force
"@
    Write-Host $helpText
    exit
}

# Function to get initial user confirmation
function Get-InitialConfirmation {
    Write-Host @"

Python Servers Windows Terminal Launcher
--------------------------------------
This script will:
- Check for running server instances
- Launch servers in configured virtual environments
- Position Windows Terminal windows according to layout
- Each server will run in its own terminal window

Configuration file: $ConfigFile

"@ -ForegroundColor Cyan

    Write-Host "Do you want to proceed? [y/N]: " -ForegroundColor Yellow -NoNewline
    $response = Read-Host
    if ($response.ToLower() -ne 'y') {
        Write-Host "Operation cancelled by user." -ForegroundColor Yellow
        exit
    }
    Write-Host ""
}



# Display help if requested
if ($Help) {
    Show-ScriptHelp
}

# Error handling preference
$ErrorActionPreference = "Stop"



# Get user confirmation before proceeding
if (-not $Force) {
    Get-InitialConfirmation
}



# Function to initialize global configuration from JSON
function Initialize-Configuration {
    param(
        [PSCustomObject]$jsonConfig
    )
    
    # Convert JSON config to hashtable for easier access
    $Global:CONFIG = @{
        Logging = @{
            Enabled = $jsonConfig.logging.enabled
            Directory = $jsonConfig.logging.directory
            Filename = $jsonConfig.logging.filename
            MaxLogSize = $jsonConfig.logging.maxLogSize
            MaxLogFiles = $jsonConfig.logging.maxLogFiles
        }
        Terminal = @{
            LaunchDelay = $jsonConfig.terminal.launchDelay
            TitleLength = $jsonConfig.terminal.titleLength
        }
        Process = @{
            GracefulShutdownTimeout = $jsonConfig.process.gracefulShutdownTimeout
            CheckInterval = $jsonConfig.process.checkInterval
        }
        Defaults = @{
            Width = $jsonConfig.defaults.width
            Height = $jsonConfig.defaults.height
            ColorScheme = $jsonConfig.defaults.colorScheme
        }
        Layouts = @{
            TwoByTwo = $jsonConfig.layouts.twoByTwo
            Vertical = $jsonConfig.layouts.vertical
            Horizontal = $jsonConfig.layouts.horizontal
        }
    }
}




# Function to validate a server configuration
function Test-ServerConfig {
    param(
        [PSCustomObject]$config,
        [string]$jsonPath
    )
    
    $requiredFields = @(
        'serverName',
        'homeFolder',
        'venvPath',
        'startupCmd',
        'title',
        'colorScheme',
        'position'
    )
    
    $positionFields = @(
        'x',
        'y',
        'width',
        'height'
    )
    
    # Check required fields
    foreach ($field in $requiredFields) {
        if (-not $config.$field) {
            Write-ServerLog -ServerName "Config" -Message "Missing required field '$field' in config from $jsonPath" -Type "ERROR"
            return $false
        }
    }
    
    # Check position fields
    foreach ($field in $positionFields) {
        if (-not $config.position.$field) {
            Write-ServerLog -ServerName "Config" -Message "Missing position field '$field' in config from $jsonPath" -Type "ERROR"
            return $false
        }
    }
    
    return $true
}


# Updated function to load server configurations from JSON
function Get-ServerConfigs {
    param(
        [string]$configPath = ".\py_win_server_launcher.json"
    )
    
    try {
        # Check if config file exists
        if (-not (Test-Path $configPath)) {
            Write-Error "Configuration file not found: $configPath"
            return $null
        }
        
        # Read and parse JSON
        $jsonContent = Get-Content $configPath -Raw
        $fullConfig = $jsonContent | ConvertFrom-Json
        
        # Initialize global configuration
        if ($fullConfig.config) {
            Initialize-Configuration -jsonConfig $fullConfig.config
        }
        else {
            Write-Error "No global configuration found in config file"
            return $null
        }
        
        # Continue with server configurations
        if (-not $fullConfig.servers) {
            Write-ServerLog -ServerName "Config" -Message "No 'servers' array found in config file" -Type "ERROR"
            return $null
        }
        
        # Validate each server configuration
        $validConfigs = @()
        foreach ($server in $fullConfig.servers) {
            if (Test-ServerConfig -config $server -jsonPath $configPath) {
                $serverConfig = @{
                    ServerName = $server.serverName
                    HomeFolder = $server.homeFolder
                    VenvPath = $server.venvPath
                    StartupCmd = $server.startupCmd
                    Title = $server.title
                    ColorScheme = $server.colorScheme
                    Position = @{
                        X = $server.position.x
                        Y = $server.position.y
                        Width = $server.position.width
                        Height = $server.position.height
                    }
                }
                $validConfigs += $serverConfig
            }
            else {
                Write-ServerLog -ServerName "Config" -Message "Invalid configuration for server '$($server.serverName)'" -Type "ERROR"
            }
        }
        
        if ($validConfigs.Count -eq 0) {
            Write-ServerLog -ServerName "Config" -Message "No valid server configurations found" -Type "ERROR"
            return $null
        }
        
        Write-ServerLog -ServerName "Config" -Message "Loaded $($validConfigs.Count) server configurations" -Type "SUCCESS"
        return $validConfigs
    }
    catch {
        Write-Error "Error loading configurations: $_"
        return $null
    }
}



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
	
	if (-not (Get-Variable -Name CONFIG -Scope Global -ErrorAction SilentlyContinue)) {
		Write-Error "Global configuration not initialized"
		return
	}
    
    if (-not $Global:CONFIG.Logging.Enabled) {
        return
    }
    
    $logDir = $Global:CONFIG.Logging.Directory
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }
    
    $logFile = Join-Path $logDir $Global:CONFIG.Logging.Filename
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Type] [$ServerName] $Message"
    
    Add-Content -Path $logFile -Value $logMessage
    Write-Host $logMessage -ForegroundColor $(
        switch ($Type) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            default { "White" }
        }
    )
}



# Function to stop server process
function Stop-ServerProcess {
    param(
        [System.Diagnostics.Process]$process,
        [string]$serverName
    )
    
    try {
        Write-ServerLog -ServerName $serverName -Message "Attempting to stop process and cleanup for $($process.Id)..."
        
        # Kill the Python process
        if (-not $process.HasExited) {
            $process.Kill()
            Write-ServerLog -ServerName $serverName -Message "Killed Python process" -Type "SUCCESS"
        }
        
        # Find and kill the PowerShell process running our startup script
        $psProcesses = Get-WmiObject Win32_Process | 
            Where-Object { 
                $_.Name -eq "powershell.exe" -and 
                $_.CommandLine -like "*ServerLauncher_$serverName\start_$serverName.ps1*" 
            }
        
        foreach ($ps in $psProcesses) {
            try {
                $psProcess = Get-Process -Id $ps.ProcessId -ErrorAction SilentlyContinue
                if ($psProcess) {
                    $psProcess.Kill()
                    Write-ServerLog -ServerName $serverName -Message "Killed PowerShell host process" -Type "SUCCESS"
                    Write-ServerLog -ServerName $serverName -Message "Note: You can close the terminal tab with Ctrl+D" -Type "INFO"
                }
            }
            catch {
                Write-ServerLog -ServerName $serverName -Message "Error killing PowerShell: $_" -Type "WARNING"
            }
        }
        
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
        [string]$scriptPath,
        [string]$venvPath
    )
    
    Write-ServerLog -ServerName $serverName -Message "Checking for running instances..."
    
    # Extract the script name
    $scriptName = Split-Path $scriptPath -Leaf
    
    # Get all Python processes with parent process information
    $pythonProcesses = Get-WmiObject Win32_Process | 
        Where-Object { $_.Name -like "*python*" } |
        ForEach-Object {
            $parent = Get-WmiObject Win32_Process -Filter "ProcessId = $($_.ParentProcessId)"
            @{
                ProcessId = $_.ProcessId
                ParentProcessId = $_.ParentProcessId
                ParentName = $parent.Name
                CommandLine = $_.CommandLine
                Process = $_
            }
        }
    
    Write-ServerLog -ServerName $serverName -Message "Found $($pythonProcesses.Count) Python processes"
    
    # Log all found processes and their relationships
    foreach ($proc in $pythonProcesses) {
        Write-ServerLog -ServerName $serverName -Message @"
Python Process Details:
  PID: $($proc.ProcessId)
  Parent PID: $($proc.ParentProcessId)
  Parent Process: $($proc.ParentName)
  Command: $($proc.CommandLine)
"@ -Type "DEBUG"
    }
    
    # Filter processes - only consider those running our script
    $runningProcesses = @()
    foreach ($proc in $pythonProcesses) {
        if ($proc.CommandLine -like "*$scriptName*") {
            try {
                $process = Get-Process -Id $proc.ProcessId
                $processInfo = Get-ServerProcessInfo -process $process
                if ($processInfo) {
                    $runningProcesses += @{
                        Process = $process
                        Info = $processInfo
                        CommandLine = $proc.CommandLine
                        ParentProcessId = $proc.ParentProcessId
                        ParentName = $proc.ParentName
                    }
                }
            }
            catch {
                Write-ServerLog -ServerName $serverName -Message "Error accessing process $($proc.ProcessId): $_" -Type "WARNING"
            }
        }
    }
    
    if ($runningProcesses.Count -gt 0) {
        Write-ServerLog -ServerName $serverName -Message "Found $($runningProcesses.Count) related Python processes" -Type "WARNING"
        foreach ($proc in $runningProcesses) {
            $info = $proc.Info
            Write-ServerLog -ServerName $serverName -Message @"
Process Details:
  PID: $($info.ProcessId)
  Parent PID: $($proc.ParentProcessId)
  Parent Process: $($proc.ParentName)
  CPU: $($info.CPU)
  Memory: $($info.Memory)
  Running Time: $($info.Runtime)
  Start Time: $($info.StartTime)
  Command: $($proc.CommandLine)
"@ -Type "WARNING"
        }
        
        # Return only the main process (the one from venv)
        $mainProcess = $runningProcesses | Where-Object { $_.CommandLine -like "*$venvPath*" }
        if ($mainProcess) {
            return @($mainProcess)
        }
        return @($runningProcesses[0])
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

Server '$serverName' is already running in virtual environment:
"@ -ForegroundColor Yellow

    foreach ($proc in $runningProcesses) {
        $info = $proc.Info
        $uptime = $info.Runtime.ToString("hh\:mm\:ss")
        # Extract just the number from the memory string
        $memory = if ($info.Memory -match '(\d+\.?\d*)') {
            $matches[1]
        } else {
            "N/A"
        }
        
        Write-Host @"
Details of running instance:
  Process ID : $($info.ProcessId)
  Started at : $($info.StartTime)
  Up for     : $uptime
  Memory     : $memory MB
  Running as : $($proc.CommandLine)
"@ -ForegroundColor Cyan
    }

    Write-Host @"

Choose an action:
[R] Retry check for running instances
[T] Terminate existing and start new
[S] Start new instance anyway (not recommended)
[K] Keep existing (skip)
"@ -ForegroundColor Yellow
    
    do {
        $decision = Read-Host "[R/T/S/K]"
        switch ($decision.ToUpper()) {
            "R" { 
                Write-Host "Rechecking running instances..." -ForegroundColor Cyan
                return @{ Action = "RETRY"; StopExisting = $false } 
            }
            "T" { return @{ Action = "START"; StopExisting = $true } }
            "S" { 
                Write-Host "Warning: Starting a new instance while another is running may cause conflicts" -ForegroundColor Red
                return @{ Action = "START"; StopExisting = $false } 
            }
            "K" { return @{ Action = "SKIP"; StopExisting = $false } }
            default { Write-Host "Invalid choice. Please enter R, T, S, or K" -ForegroundColor Red }
        }
    } while ($true)
}


# Function to validate virtual environment
function Test-VirtualEnvironment {
    param(
        [string]$venvPath,
        [string]$serverName
    )
    
    $activateScript = Join-Path $venvPath "Scripts\activate.ps1"
    
    if (-not (Test-Path $venvPath)) {
        Write-ServerLog -ServerName $serverName -Message "Virtual environment directory not found: $venvPath" -Type "ERROR"
        return $false
    }
    
    if (-not (Test-Path $activateScript)) {
        Write-ServerLog -ServerName $serverName -Message "Activation script not found: $activateScript" -Type "ERROR"
        return $false
    }
    
    return $true
}



# Function to launch a Windows Terminal instance
function Start-ServerWindow {
    param(
        [hashtable]$config
    )
    
    $pos = $config.Position
    $rmost = -$Global:CONFIG.Terminal.TitleLength  # Take rightmost N chars for title
    $scriptName = $config.StartupCmd -replace '^python\s+', ''  # Extract script name from startup command
    $windowTitle = -join ($config.Title, ": ", -join $scriptName[$rmost..-1])
    
    # Create a PowerShell script block that will:
    # 1. Navigate to server directory
    # 2. Activate virtual environment
    # 3. Start the Python script
    $startScript = @"
# Server startup script for $($config.ServerName)
try {
    Write-Host "Changing to directory: $($config.HomeFolder)" -ForegroundColor Cyan
    Set-Location -Path '$($config.HomeFolder)'
    
    Write-Host "Activating virtual environment: $($config.VenvPath)" -ForegroundColor Cyan
    & '$($config.VenvPath)\Scripts\activate.ps1'
    
    Write-Host "Starting server: $($config.StartupCmd)" -ForegroundColor Green
    $($config.StartupCmd)
}
catch {
    Write-Host "Error during startup: `$_" -ForegroundColor Red
    Write-Host "Press any key to exit..."
    `$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
"@
    
    # Create a unique temporary directory for this server
    $tempDir = Join-Path $env:TEMP "ServerLauncher_$($config.ServerName)"
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }
    
    # Save the script to the temporary directory
    $tempScript = Join-Path $tempDir "start_$($config.ServerName).ps1"
    $startScript | Out-File -FilePath $tempScript -Force -Encoding UTF8
    
    # Create the Windows Terminal arguments
    $argumentList = @(
        "--pos $($pos.X),$($pos.Y)",
        "--size $($pos.Width),$($pos.Height)",
        "--title `"$windowTitle`"",
        "--colorScheme `"$($config.ColorScheme)`"",
        "powershell.exe -NoProfile -NoExit -Command `"& '$tempScript'`""
    )
    
    Write-ServerLog -ServerName $config.ServerName -Message "Launching with command: $($config.StartupCmd)"
    Start-Process "wt.exe" -ArgumentList $argumentList
    
    # Register a cleanup job that will run after a delay
    Start-Job -ScriptBlock {
        param($tempDir, $serverName)
        Start-Sleep -Seconds 10  # Give enough time for WT to start
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force
            Write-Host "Cleaned up temporary files for $serverName"
        }
    } -ArgumentList $tempDir, $config.ServerName | Out-Null
}



# Function to validate server paths and environment
function Test-ServerEnvironment {
    param(
        [hashtable]$config
    )
    
    # Check server directory
    if (-not (Test-Path $config.HomeFolder)) {
        Write-ServerLog -ServerName $config.ServerName -Message "Server directory not found: $($config.HomeFolder)" -Type "ERROR"
        return $false
    }
    
    # Check virtual environment
    if (-not (Test-VirtualEnvironment -venvPath $config.VenvPath -serverName $config.ServerName)) {
        return $false
    }
    
    # Check server script
    $scriptPath = Join-Path $config.HomeFolder "$($config.ServerName).py"
    if (-not (Test-Path $scriptPath)) {
        Write-ServerLog -ServerName $config.ServerName -Message "Server script not found: $scriptPath" -Type "ERROR"
        return $false
    }
    
    return $true
}

# Function to handle server process management
function Start-ServerProcessManagement {
    param(
        [hashtable]$config
    )
    
    $scriptPath = Join-Path $config.HomeFolder "$($config.ServerName).py"
    $keepChecking = $true
    
    while ($keepChecking) {
        $runningProcesses = Test-ServerRunning -serverName $config.ServerName -scriptPath $scriptPath -venvPath $config.VenvPath
        
        if ($runningProcesses) {
            $decision = Get-ServerStartDecision -serverName $config.ServerName -runningProcesses $runningProcesses
            
            switch ($decision.Action) {
                "RETRY" { 
                    Write-ServerLog -ServerName $config.ServerName -Message "Retrying process check..."
                    continue
                }
                "START" {
                    if ($decision.StopExisting) {
                        if (-not (Stop-ExistingProcesses -config $config -processes $runningProcesses)) {
                            Write-Host "Some processes could not be stopped. Retry? (Y/N)" -ForegroundColor Yellow
                            if ((Read-Host) -eq 'Y') {
                                continue
                            }
                        }
                    }
                    $keepChecking = $false
                    return $true
                }
                "SKIP" {
                    $keepChecking = $false
                    Write-ServerLog -ServerName $config.ServerName -Message "Skipping server launch (user choice)"
                    return $false
                }
            }
        }
        else {
            $keepChecking = $false
            return $true
        }
    }
}

# Function to stop existing processes
function Stop-ExistingProcesses {
    param(
        [hashtable]$config,
        [array]$processes
    )
    
    Write-ServerLog -ServerName $config.ServerName -Message "Stopping existing processes..."
    $allStopped = $true
    
    foreach ($proc in $processes) {
        $stopped = Stop-ServerProcess -process $proc.Process -serverName $config.ServerName
        if (-not $stopped) {
            Write-ServerLog -ServerName $config.ServerName -Message "Failed to stop process $($proc.Process.Id)" -Type "ERROR"
            $allStopped = $false
        }
    }
    
    return $allStopped
}


# Main execution block
function Start-ServerLauncher {
    try {
        # Load server configurations
        $configs = Get-ServerConfigs -configPath $ConfigFile
        if (-not $configs) {
            Write-ServerLog -ServerName "Launcher" -Message "Failed to load server configurations. Exiting." -Type "ERROR"
            return
        }
        
        Write-ServerLog -ServerName "Launcher" -Message "Starting server checks..."
        $serversToLaunch = @()
        
        # Process each server configuration
        foreach ($config in $configs) {
            # Validate environment
            if (-not (Test-ServerEnvironment -config $config)) {
                continue
            }
            
            # Handle process management
            if (Start-ServerProcessManagement -config $config) {
                $serversToLaunch += $config
                Write-ServerLog -ServerName $config.ServerName -Message "Added to launch queue"
            }
        }
        
        # Launch servers
        if ($serversToLaunch.Count -eq 0) {
            Write-ServerLog -ServerName "Launcher" -Message "No servers to launch. All servers are either running or launch was cancelled."
            return
        }
        
        Write-ServerLog -ServerName "Launcher" -Message "Launching $($serversToLaunch.Count) server(s)..."
        
        foreach ($config in $serversToLaunch) {
            Write-ServerLog -ServerName $config.ServerName -Message "Launching server window..."
            Start-ServerWindow -config $config
            Start-Sleep -Milliseconds $Global:CONFIG.Terminal.LaunchDelay
        }
    }
    catch {
        Write-ServerLog -ServerName "Launcher" -Message "Error in launcher: $_" -Type "ERROR"
        Write-ServerLog -ServerName "Launcher" -Message "Stack Trace: $($_.ScriptStackTrace)" -Type "ERROR"
    }
}


# Start the launcher
Start-ServerLauncher


