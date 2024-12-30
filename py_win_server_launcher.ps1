####################################################################################################
#
# Windows Terminal Server Launcher
# (py_win_server_launcher.ps1)
#
# Purpose:
#   Launch and manage multiple server instances in Windows Terminal.
#   Each server (Python-based or command-based) runs in its own window
#   with customized positions and color schemes.
#
# Usage:
#   .\py_win_server_launcher.ps1 [options] [config_file]
#
# Parameters:
#   config_file          : Path to JSON configuration file (default: .\py_win_server_launcher.json)
#   -Force (-f)          : Skip confirmation prompts and force restart any running instances
#   -IgnoreRunning (-i)  : Start new instances even if servers are already running
#   -Help (-h, -?, --help): Show this help message
#
# Configuration File:
#   JSON file containing server definitions. Each server must specify:
#   - id: Unique identifier for the server
#   - type: Server type ("python" or "command")
#   - title: Display name
#   - command: Command to execute
#   - workingDir: Working directory
#   - display: Window position and appearance settings
#
# Examples:
#   .\py_win_server_launcher.ps1
#   .\py_win_server_launcher.ps1 .\my_config.json
#   .\py_win_server_launcher.ps1 -Force
#   .\py_win_server_launcher.ps1 -Help
#
# Author: mgua@tomware.it
# Version: 1.2.0
# Last Modified: 30/12/2024
#
####################################################################################################

# Show help if requested
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$ConfigFile = ".\\py_win_server_launcher.json",
    
    [Parameter()]
    [Alias('f')]
    [switch]$Force,
    
    [Parameter()]
    [Alias('i')]
    [switch]$IgnoreRunning,
    
    [Parameter()]
    [Alias('h', '?')]
    [switch]$Help
)

# Error handling preference
$ErrorActionPreference = "Stop"

# Check for help flags first
if ($Help -or $args -contains "--help" -or $args -contains "-h" -or $args -contains "-?") {
    Show-ScriptHelp
    exit
}

# Validate config file path
if (-not [System.IO.Path]::IsPathRooted($ConfigFile)) {
    $ConfigFile = Join-Path $PSScriptRoot $ConfigFile
}

if (-not (Test-Path $ConfigFile)) {
    Write-Host "Error: Configuration file not found: $ConfigFile" -ForegroundColor Red
    Write-Host "Usage: $($MyInvocation.MyCommand.Name) [config_file] [-Force] [-IgnoreRunning] [-Help]" -ForegroundColor Yellow
    exit 1
}

# Function to display script help
function Show-ScriptHelp {
    $helpText = @"
Python Servers Windows Terminal Launcher
Usage: .\py_win_server_launcher.ps1 [-ConfigFile <path>] [-Force] [-IgnoreRunning] [-Help]

Description:
    Launches and manages multiple server instances in Windows Terminal windows.
    Each server runs in its own environment with customized window positions and color schemes.

Parameters:
    -ConfigFile     : Path to configuration JSON file (default: .\py_win_server_launcher.json)
    -Force          : Skip confirmation prompts and force restart any running instances
    -IgnoreRunning  : Start new instances even if servers are already running
    -Help           : Show this help message

Configuration File:
    The JSON configuration file contains settings for servers including:
    - Server ID and title
    - Working directory and virtual environment paths
    - Window position and color scheme
    - Startup command and type (python/command)
"@
    Write-Host $helpText
    exit
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

# Function to write to log file
function Write-ServerLog {
    param(
        [string]$Message,
        [string]$ServerId,
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
    $logMessage = "[$timestamp] [$Type] [$ServerId] $Message"
    
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

# Function to validate server configuration
function Test-ServerConfig {
    param(
        [PSCustomObject]$config,
        [string]$jsonPath
    )
    
    $requiredFields = @(
        'id',
        'title',
        'type',
        'command',
        'workingDir',
        'display'
    )
    
    $displayFields = @(
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
            Write-ServerLog -ServerId "Config" -Message "Missing required field '$field' in config from $jsonPath" -Type "ERROR"
            return $false
        }
    }
    
    # Check display fields
    foreach ($field in $displayFields) {
        if (-not $config.display.$field) {
            Write-ServerLog -ServerId "Config" -Message "Missing display field '$field' in config from $jsonPath" -Type "ERROR"
            return $false
        }
    }
    
    # Check position fields
    foreach ($field in $positionFields) {
        if (-not $config.display.position.$field) {
            Write-ServerLog -ServerId "Config" -Message "Missing position field '$field' in config from $jsonPath" -Type "ERROR"
            return $false
        }
    }

	# Add to Test-ServerConfig function
	if ($config.type -notin @('python', 'command', 'venv-command')) {
		Write-ServerLog -ServerId "Config" -Message "Invalid server type '$($config.type)' for server '$($config.id)'. Must be 'python', 'command', or 'venv-command'" -Type "ERROR"
		return $false
	}

	# Check Python and venv-command specific requirements
	if (($config.type -eq "python" -or $config.type -eq "venv-command") -and -not $config.venv) {
		Write-ServerLog -ServerId "Config" -Message "Server '$($config.id)' requires venv path for type '$($config.type)'" -Type "ERROR"
		return $false
	}    

    
    return $true
}

# Function to validate virtual environment
function Test-VirtualEnvironment {
    param(
        [string]$venvPath,
        [string]$serverId
    )
    
    $activateScript = Join-Path $venvPath "Scripts\activate.ps1"
    
    if (-not (Test-Path $venvPath)) {
        Write-ServerLog -ServerId $serverId -Message "Virtual environment directory not found: $venvPath" -Type "ERROR"
        return $false
    }
    
    if (-not (Test-Path $activateScript)) {
        Write-ServerLog -ServerId $serverId -Message "Activation script not found: $activateScript" -Type "ERROR"
        return $false
    }
    
    return $true
}

# Function to get server configurations from JSON
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
            Write-ServerLog -ServerId "Config" -Message "No 'servers' array found in config file" -Type "ERROR"
            return $null
        }
        
        # Validate each server configuration
        $validConfigs = @()
        foreach ($server in $fullConfig.servers) {
            # Skip inactive servers
            if ($server.PSObject.Properties.Name -contains "active" -and -not $server.active) {
                Write-ServerLog -ServerId $server.id -Message "Server is marked as inactive, skipping" -Type "INFO"
                continue
            }
            
            if (Test-ServerConfig -config $server -jsonPath $configPath) {
                $serverConfig = @{
                    Id = $server.id
                    Title = $server.title
                    Description = $server.description
                    Type = $server.type
                    Command = $server.command
                    Shell = $server.shell
                    WorkingDir = $server.workingDir
                    Venv = $server.venv
                    Display = @{
                        ColorScheme = $server.display.colorScheme
                        Position = @{
                            X = $server.display.position.x
                            Y = $server.display.position.y
                            Width = $server.display.position.width
                            Height = $server.display.position.height
                        }
                    }
                }
                $validConfigs += $serverConfig
            }
        }
        
        if ($validConfigs.Count -eq 0) {
            Write-ServerLog -ServerId "Config" -Message "No valid server configurations found" -Type "ERROR"
            return $null
        }
        
        Write-ServerLog -ServerId "Config" -Message "Loaded $($validConfigs.Count) server configurations" -Type "SUCCESS"
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

# Function to check if a server process is running
function Test-ServerRunning {
    param(
        [string]$serverId,
        [hashtable]$config
    )
    
    Write-ServerLog -ServerId $serverId -Message "Checking for running instances..."
    
    $runningProcesses = @()
    
    if ($config.Type -eq "command") {
        # Extract the command being run
        $shellCommand = $config.Command
        $shellType = $config.Shell
        
        Write-ServerLog -ServerId $serverId -Message "Looking for $shellType command: $shellCommand" -Type "DEBUG"
        
        # Find processes based on shell type
        $processes = Get-WmiObject Win32_Process | Where-Object {
            if ($shellType -eq "cmd") {
                $_.Name -eq "cmd.exe" -and $_.CommandLine -like "*$shellCommand*"
            }
            elseif ($shellType -eq "powershell") {
                $_.Name -eq "powershell.exe" -and $_.CommandLine -like "*$shellCommand*" -and 
                (-not ($_.CommandLine -like "*ServerLauncher_*\start_*.ps1*"))
            }
            else {
                $_.CommandLine -like "*$shellCommand*"
            }
        }
    }
    else {
        # For Python servers
        $scriptName = $config.Command
        
        # Get all Python processes
        $processes = Get-WmiObject Win32_Process | 
            Where-Object { $_.Name -like "*python*" -and $_.CommandLine -like "*$scriptName*" }
    }
    
    foreach ($proc in $processes) {
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
            Write-ServerLog -ServerId $serverId -Message "Error accessing process $($proc.ProcessId): $_" -Type "WARNING"
        }
    }
    
    if ($runningProcesses.Count -gt 0) {
        Write-ServerLog -ServerId $serverId -Message "Found $($runningProcesses.Count) related processes" -Type "WARNING"
        return $runningProcesses
    }
    
    Write-ServerLog -ServerId $serverId -Message "No running instances found"
    return $null
}

# Function to get user decision about running server
function Get-ServerStartDecision {
    param(
        [string]$serverId,
        [array]$runningProcesses
    )
    
    if ($Force) {
        return @{ Action = "START"; StopExisting = $true }
    }
    
    Write-Host @"

Server '$serverId' is already running:
"@ -ForegroundColor Yellow

    foreach ($proc in $runningProcesses) {
        $info = $proc.Info
        $uptime = $info.Runtime.ToString("hh\:mm\:ss")
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

# Function to stop server process
function Stop-ServerProcess {
    param(
        [System.Diagnostics.Process]$process,
        [string]$serverId
    )
    
    try {
        Write-ServerLog -ServerId $serverId -Message "Attempting to stop process and cleanup for $($process.Id)..."
        
        # Get WMI process object for the main process
        $wmiProcess = Get-WmiObject Win32_Process -Filter "ProcessId = $($process.Id)"
        Write-ServerLog -ServerId $serverId -Message "Main process is: $($wmiProcess.Name)" -Type "DEBUG"
        
        # Kill any child processes first
        Get-WmiObject Win32_Process | Where-Object { $_.ParentProcessId -eq $process.Id } | ForEach-Object {
            try {
                Write-ServerLog -ServerId $serverId -Message "Killing child process: $($_.ProcessId) ($($_.Name))" -Type "DEBUG"
                Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
                Write-ServerLog -ServerId $serverId -Message "Killed child process" -Type "SUCCESS"
            }
            catch {
                Write-ServerLog -ServerId $serverId -Message "Trying taskkill for child process..." -Type "DEBUG"
                taskkill /PID $_.ProcessId /F 2>$null
            }
        }
        
        # Small delay to ensure child processes are gone
        Start-Sleep -Milliseconds 100
        
        # Kill the main process
        if (-not $process.HasExited) {
            Write-ServerLog -ServerId $serverId -Message "Killing main process $($process.Id)" -Type "DEBUG"
            try {
                $process.Kill()
                Write-ServerLog -ServerId $serverId -Message "Killed main process" -Type "SUCCESS"
            }
            catch {
                Write-ServerLog -ServerId $serverId -Message "Trying taskkill for main process..." -Type "DEBUG"
                taskkill /PID $process.Id /F /T 2>$null
            }
        }
        
        # Find and kill related PowerShell processes
        $psProcessIds = @()
        
        # Add launcher script process
        $launcherPs = Get-WmiObject Win32_Process | Where-Object { 
            $_.Name -eq "powershell.exe" -and 
            $_.CommandLine -like "*ServerLauncher_$serverId\start_$serverId.ps1*"
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
                Write-ServerLog -ServerId $serverId -Message "Killing PowerShell process $psId" -Type "DEBUG"
                Stop-Process -Id $psId -Force -ErrorAction Stop
                Write-ServerLog -ServerId $serverId -Message "Killed PowerShell process" -Type "SUCCESS"
            }
            catch {
                Write-ServerLog -ServerId $serverId -Message "Trying taskkill for PowerShell process..." -Type "DEBUG"
                taskkill /PID $psId /F 2>$null
            }
        }
        
        Write-ServerLog -ServerId $serverId -Message "Note: You can close the terminal tab with Ctrl+D" -Type "INFO"
        return $true
    }
    catch {
        Write-ServerLog -ServerId $serverId -Message "Unexpected error in process cleanup: $_" -Type "ERROR"
        return $false
    }
}


function Get-StartupScript {
    param(
        [hashtable]$config
    )
    
    $baseScript = @"
# Server startup script for $($config.Id)
try {
    Write-Host "Changing to directory: $($config.WorkingDir)" -ForegroundColor Cyan
    Set-Location -Path '$($config.WorkingDir)'
    
"@

    switch ($config.Type) {
        "python" {
            # Python server with virtual environment
            $baseScript += @"
    Write-Host "Activating virtual environment: $($config.Venv)" -ForegroundColor Cyan
    & '$($config.Venv)\Scripts\activate.ps1'
    
    Write-Host "Starting Python server: $($config.Command)" -ForegroundColor Green
    python $($config.Command)
"@
        }
        "venv-command" {
            # Command that needs virtual environment
            $baseScript += @"
    Write-Host "Activating virtual environment: $($config.Venv)" -ForegroundColor Cyan
    & '$($config.Venv)\Scripts\activate.ps1'
    
    Write-Host "Starting command: $($config.Command)" -ForegroundColor Green
    $($config.Command)
"@
        }
        "command" {
            # Regular command-based server
            $shellPrefix = if ($config.Shell -eq "cmd") {
                "cmd.exe /c "
            }
            elseif ($config.Shell -eq "powershell") {
                "powershell.exe -Command "
            }
            else {
                ""
            }
            
            $baseScript += @"
    Write-Host "Starting command: $($config.Command)" -ForegroundColor Green
    $shellPrefix$($config.Command)
"@
        }
    }
    
    $baseScript += @"

}
catch {
    Write-Host "Error during startup: `$_" -ForegroundColor Red
    Write-Host "Press any key to exit..."
    `$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
"@

    return $baseScript
}





# Function to launch a Windows Terminal instance
function Start-ServerWindow {
    param(
        [hashtable]$config
    )
    
    $pos = $config.Display.Position
    $rmost = -$Global:CONFIG.Terminal.TitleLength
    $windowTitle = $config.Title
    
    $startScript = Get-StartupScript -config $config
    
    # Create a unique temporary directory for this server
    $tempDir = Join-Path $env:TEMP "ServerLauncher_$($config.Id)"
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }
    
    # Save the script to the temporary directory
    $tempScript = Join-Path $tempDir "start_$($config.Id).ps1"
    $startScript | Out-File -FilePath $tempScript -Force -Encoding UTF8
    
    # Create the Windows Terminal arguments
    $argumentList = @(
        "--pos $($pos.X),$($pos.Y)",
        "--size $($pos.Width),$($pos.Height)",
        "--title `"$windowTitle`"",
        "--colorScheme `"$($config.Display.ColorScheme)`"",
        "powershell.exe -NoProfile -NoExit -Command `"& '$tempScript'`""
    )
    
    Write-ServerLog -ServerId $config.Id -Message "Launching with command: $($config.Command)"
    Start-Process "wt.exe" -ArgumentList $argumentList
    
    # Register cleanup job
    Start-Job -ScriptBlock {
        param($tempDir, $serverId)
        Start-Sleep -Seconds 10
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force
            Write-Host "Cleaned up temporary files for $serverId"
        }
    } -ArgumentList $tempDir, $config.Id | Out-Null
}

# Function to validate server environment
function Test-ServerEnvironment {
    param(
        [hashtable]$config
    )
    
    # Check server directory
    if (-not (Test-Path $config.WorkingDir)) {
        Write-ServerLog -ServerId $config.Id -Message "Server directory not found: $($config.WorkingDir)" -Type "ERROR"
        return $false
    }

    # For Python servers, check virtual environment and script
	if ($config.Type -eq "python" -or $config.Type -eq "venv-command") {
		if (-not (Test-VirtualEnvironment -venvPath $config.Venv -serverId $config.Id)) {
			return $false
		}
    
		# Only check for Python script if it's a python type
		if ($config.Type -eq "python") {
			$scriptPath = Join-Path $config.WorkingDir $config.Command
			if (-not (Test-Path $scriptPath)) {
				Write-ServerLog -ServerId $config.Id -Message "Server script not found: $scriptPath" -Type "ERROR"
				return $false
			}
		}
	}

    return $true
}

# Function to handle server process management
function Start-ServerProcessManagement {
    param(
        [hashtable]$config
    )
    
    $keepChecking = $true
    
    while ($keepChecking) {
        $runningProcesses = Test-ServerRunning -serverId $config.Id -config $config
        
        if ($runningProcesses) {
            $decision = Get-ServerStartDecision -serverId $config.Id -runningProcesses $runningProcesses
            
            switch ($decision.Action) {
                "RETRY" { 
                    Write-ServerLog -ServerId $config.Id -Message "Retrying process check..."
                    continue
                }
                "START" {
                    if ($decision.StopExisting) {
                        foreach ($proc in $runningProcesses) {
                            if (-not (Stop-ServerProcess -process $proc.Process -serverId $config.Id)) {
                                Write-Host "Some processes could not be stopped. Retry? (Y/N)" -ForegroundColor Yellow
                                if ((Read-Host) -eq 'Y') {
                                    continue
                                }
                            }
                        }
                    }
                    $keepChecking = $false
                    return $true
                }
                "SKIP" {
                    $keepChecking = $false
                    Write-ServerLog -ServerId $config.Id -Message "Skipping server launch (user choice)"
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

# Function to get initial user confirmation
function Get-InitialConfirmation {
    Write-Host @"

Python Servers Windows Terminal Launcher
--------------------------------------
This script will:
- Check for running server instances
- Launch servers in configured environments
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

# Main execution block
function Start-ServerLauncher {
    try {
        # Load server configurations
        $configs = Get-ServerConfigs -configPath $ConfigFile
        if (-not $configs) {
            Write-ServerLog -ServerId "Launcher" -Message "Failed to load server configurations. Exiting." -Type "ERROR"
            return
        }
        
        Write-ServerLog -ServerId "Launcher" -Message "Starting server checks..."
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
                Write-ServerLog -ServerId $config.Id -Message "Added to launch queue"
            }
        }
        
        # Launch servers
        if ($serversToLaunch.Count -eq 0) {
            Write-ServerLog -ServerId "Launcher" -Message "No servers to launch. All servers are either running or launch was cancelled."
            return
        }
        
        Write-ServerLog -ServerId "Launcher" -Message "Launching $($serversToLaunch.Count) server(s)..."
        
        foreach ($config in $serversToLaunch) {
            Write-ServerLog -ServerId $config.Id -Message "Launching server window..."
            Start-ServerWindow -config $config
            Start-Sleep -Milliseconds $Global:CONFIG.Terminal.LaunchDelay
        }
    }
    catch {
        Write-ServerLog -ServerId "Launcher" -Message "Error in launcher: $_" -Type "ERROR"
        Write-ServerLog -ServerId "Launcher" -Message "Stack Trace: $($_.ScriptStackTrace)" -Type "ERROR"
    }
}

# Display help if requested
if ($Help) {
    Show-ScriptHelp
}

# Get user confirmation before proceeding
if (-not $Force) {
    Get-InitialConfirmation
}

# Start the launcher
Start-ServerLauncher