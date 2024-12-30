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
        
        # Get WMI process object for the main process
        $wmiProcess = Get-WmiObject Win32_Process -Filter "ProcessId = $($process.Id)"
        Write-ServerLog -ServerName $serverName -Message "Main process is: $($wmiProcess.Name)" -Type "DEBUG"
        
        $success = $true
        
        # Kill any child processes first
        Get-WmiObject Win32_Process | Where-Object { $_.ParentProcessId -eq $process.Id } | ForEach-Object {
            try {
                Write-ServerLog -ServerName $serverName -Message "Killing child process: $($_.ProcessId) ($($_.Name))" -Type "DEBUG"
                Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
                Write-ServerLog -ServerName $serverName -Message "Killed child process" -Type "SUCCESS"
            }
            catch {
                Write-ServerLog -ServerName $serverName -Message "Trying taskkill for child process..." -Type "DEBUG"
                taskkill /PID $_.ProcessId /F 2>$null
            }
        }
        
        # Small delay to ensure child processes are gone
        Start-Sleep -Milliseconds 100
        
        # Kill the main process
        if (-not $process.HasExited) {
            Write-ServerLog -ServerName $serverName -Message "Killing main process $($process.Id)" -Type "DEBUG"
            try {
                $process.Kill()
                Write-ServerLog -ServerName $serverName -Message "Killed main process" -Type "SUCCESS"
            }
            catch {
                Write-ServerLog -ServerName $serverName -Message "Trying taskkill for main process..." -Type "DEBUG"
                taskkill /PID $process.Id /F /T 2>$null
            }
        }
        
        # Find all related PowerShell processes
        $psProcessIds = @()
        
        # Add launcher script process
        $launcherPs = Get-WmiObject Win32_Process | Where-Object { 
            $_.Name -eq "powershell.exe" -and 
            $_.CommandLine -like "*ServerLauncher_$serverName\start_$serverName.ps1*"
        }
        $psProcessIds += $launcherPs | Select-Object -ExpandProperty ProcessId
        
        # Add parent PowerShell process
        $parentPs = Get-WmiObject Win32_Process | Where-Object {
            $_.Name -eq "powershell.exe" -and
            $_.ProcessId -eq $wmiProcess.ParentProcessId
        }
        $psProcessIds += $parentPs | Select-Object -ExpandProperty ProcessId
        
        # Remove duplicates and kill each process
        $psProcessIds = $psProcessIds | Select-Object -Unique
        foreach ($psId in $psProcessIds) {
            try {
                Write-ServerLog -ServerName $serverName -Message "Killing PowerShell process $psId" -Type "DEBUG"
                Stop-Process -Id $psId -Force -ErrorAction Stop
                Write-ServerLog -ServerName $serverName -Message "Killed PowerShell process" -Type "SUCCESS"
            }
            catch {
                Write-ServerLog -ServerName $serverName -Message "Trying taskkill for PowerShell process..." -Type "DEBUG"
                taskkill /PID $psId /F 2>$null
            }
        }
        
        Write-ServerLog -ServerName $serverName -Message "Note: You can close the terminal tab with Ctrl+D" -Type "INFO"
        return $true
    }
    catch {
        Write-ServerLog -ServerName $serverName -Message "Unexpected error in process cleanup: $_" -Type "ERROR"
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
    
    $runningProcesses = @()
    
    if ($venvPath -eq "not_needed") {
        # Extract the actual command being run for different shell types
        $shellCommand = ""
        $shellType = ""
        
        if ($scriptPath -like "cmd.exe*") {
            $shellType = "cmd"
            $shellCommand = $scriptPath -replace '^cmd\.exe\s+/c\s+', ''
        }
        elseif ($scriptPath -like "powershell.exe*") {
            $shellType = "powershell"
            $shellCommand = $scriptPath -replace '^powershell\.exe\s+(?:-Command\s+)?', ''
        }
        else {
            # Direct command without shell prefix
            $shellType = "direct"
            $shellCommand = $scriptPath
        }
        
        Write-ServerLog -ServerName $serverName -Message "Looking for $shellType command: $shellCommand" -Type "DEBUG"
            
        # Find processes based on shell type
        $processes = Get-WmiObject Win32_Process | Where-Object {
            if ($shellType -eq "cmd") {
                $_.Name -eq "cmd.exe" -and $_.CommandLine -like "*$shellCommand*"
            }
            elseif ($shellType -eq "powershell") {
                $_.Name -eq "powershell.exe" -and $_.CommandLine -like "*$shellCommand*" -and 
                # Exclude our launcher processes
                (-not ($_.CommandLine -like "*ServerLauncher_*\start_*.ps1*"))
            }
            else {
                $_.CommandLine -like "*$shellCommand*"
            }
        }
            
        foreach ($proc in $processes) {
            try {
                # Get both the shell process and its child processes
                $process = Get-Process -Id $proc.ProcessId
                $processInfo = Get-ServerProcessInfo -process $process
                if ($processInfo) {
                    # Get child processes
                    $childProcesses = Get-WmiObject Win32_Process | 
                        Where-Object { $_.ParentProcessId -eq $proc.ProcessId }
                    
                    $runningProcesses += @{
                        Process = $process
                        Info = $processInfo
                        CommandLine = $proc.CommandLine
                        ParentProcessId = $proc.ParentProcessId
                        ParentName = (Get-WmiObject Win32_Process -Filter "ProcessId = $($proc.ParentProcessId)").Name
                        ShellType = $shellType
                        ChildProcesses = $childProcesses
                    }
                    
                    Write-ServerLog -ServerName $serverName -Message "Found $shellType process with children:" -Type "DEBUG"
                    foreach ($child in $childProcesses) {
                        Write-ServerLog -ServerName $serverName -Message "Child process: $($child.ProcessId) - $($child.Name)" -Type "DEBUG"
                    }
                }
            }
            catch {
                Write-ServerLog -serverName $serverName -Message "Error accessing process $($proc.ProcessId): $_" -Type "WARNING"
            }
        }
    }
    else {
        # For Python servers
        $scriptName = Split-Path $scriptPath -Leaf
        
        # Get all Python processes
        $pythonProcesses = Get-WmiObject Win32_Process | 
            Where-Object { $_.Name -like "*python*" }
        
        foreach ($proc in $pythonProcesses) {
            if ($proc.CommandLine -like "*$scriptName*") {
                try {
                    $process = Get-Process -Id $proc.ProcessId
                    $processInfo = Get-ServerProcessInfo -process $process
                    if ($processInfo) {
                        $parent = Get-WmiObject Win32_Process -Filter "ProcessId = $($proc.ParentProcessId)"
                        $runningProcesses += @{
                            Process = $process
                            Info = $processInfo
                            CommandLine = $proc.CommandLine
                            ParentProcessId = $proc.ParentProcessId
                            ParentName = $parent.Name
                        }
                    }
                }
                catch {
                    Write-ServerLog -serverName $serverName -Message "Error accessing process $($proc.ProcessId): $_" -Type "WARNING"
                }
            }
        }
    }
    
    # Log process details
    if ($runningProcesses.Count -gt 0) {
        Write-ServerLog -ServerName $serverName -Message "Found $($runningProcesses.Count) related processes" -Type "WARNING"
        foreach ($proc in $runningProcesses) {
            $info = $proc.Info
            $shellInfo = if ($proc.ShellType) { " ($($proc.ShellType) process)" } else { "" }
            Write-ServerLog -ServerName $serverName -Message @"
Process Details:
  PID: $($info.ProcessId)$shellInfo
  Parent PID: $($proc.ParentProcessId)
  Parent Process: $($proc.ParentName)
  CPU: $($info.CPU)
  Memory: $($info.Memory)
  Running Time: $($info.Runtime)
  Start Time: $($info.StartTime)
  Command: $($proc.CommandLine)
"@ -Type "WARNING"

            if ($proc.ChildProcesses) {
                foreach ($child in $proc.ChildProcesses) {
                    Write-ServerLog -ServerName $serverName -Message "  Child Process: $($child.ProcessId) - $($child.Name)" -Type "DEBUG"
                }
            }
        }
        
        # For Python servers, return only the venv process if found
        if ($venvPath -ne "not_needed") {
            $mainProcess = $runningProcesses | Where-Object { $_.CommandLine -like "*$venvPath*" }
            if ($mainProcess) {
                return @($mainProcess)
            }
        }
        
        # Return the first process found
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
    
    # Skip check if virtual environment is marked as not needed
    if ($venvPath -eq "not_needed") {
        Write-ServerLog -ServerName $serverName -Message "No virtual environment required" -Type "INFO"
        return $true
    }
    
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



# Function to get startup script content
function Get-StartupScript {
    param(
        [hashtable]$config
    )
    
    if ($config.VenvPath -eq "not_needed") {
        # Simple script for non-Python servers
        return @"
# Server startup script for $($config.ServerName)
try {
    Write-Host "Changing to directory: $($config.HomeFolder)" -ForegroundColor Cyan
    Set-Location -Path '$($config.HomeFolder)'
    
    Write-Host "Starting server: $($config.StartupCmd)" -ForegroundColor Green
    $($config.StartupCmd)
}
catch {
    Write-Host "Error during startup: `$_" -ForegroundColor Red
    Write-Host "Press any key to exit..."
    `$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
"@
    }
    else {
        # Script with virtual environment activation for Python servers
        return @"
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
    }
}



# Function to launch a Windows Terminal instance
function Start-ServerWindow {
    param(
        [hashtable]$config
    )
    
    $pos = $config.Position
    $rmost = -$Global:CONFIG.Terminal.TitleLength  # Take rightmost N chars for title
    $scriptName = $config.StartupCmd -replace '^python\s+', ''  # Extract script name from command
    $windowTitle = -join ($config.Title, ": ", -join $scriptName[$rmost..-1])
    
    # Get appropriate startup script based on server type
    $startScript = Get-StartupScript -config $config
    
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
    
    # For non-Python servers, skip script file check
    if ($config.VenvPath -eq "not_needed") {
        return $true
    }
    
    # For Python servers, check for script file
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
    
    # Get the correct script path or command
    $scriptPath = if ($config.VenvPath -eq "not_needed") {
        $config.StartupCmd  # Use the full command for non-Python servers
    }
    else {
        Join-Path $config.HomeFolder "$($config.ServerName).py"  # Use .py file path for Python servers
    }
    
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


