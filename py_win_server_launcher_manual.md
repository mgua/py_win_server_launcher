# Python/Windows Server Launcher Manual

## Overview
The Python/Windows Server Launcher is a PowerShell tool designed to manage multiple server processes in Windows Terminal. While originally designed for Python servers running in virtual environments, it can handle any type of long-running process or server.

## Features
- Launch multiple servers in separate Windows Terminal windows
- Custom window positioning and color schemes
- Virtual environment support for Python servers
- Process monitoring and management
- Graceful shutdown handling
- Configurable logging
- Support for Python and non-Python servers
- Multiple predefined window layouts

## Usage

### Basic Command
```powershell
.\py_win_server_launcher.ps1 [-ConfigFile <path>] [-Force] [-IgnoreRunning] [-Help]
```

### Parameters
- `-ConfigFile`: Path to configuration JSON file (default: .\py_win_server_launcher.json)
- `-Force`: Skip confirmation prompts and force restart any running instances
- `-IgnoreRunning`: Start new instances even if servers are already running
- `-Help`: Show help message

## Configuration File Structure

The configuration file is a JSON document with two main sections:
1. `config`: Global settings
2. `servers`: Array of server configurations

### Global Configuration
```json
{
    "config": {
        "logging": {
            "enabled": true,
            "directory": ".\\logs",
            "filename": "py_win_server_launcher.log",
            "maxLogSize": "10MB",
            "maxLogFiles": 5
        },
        "terminal": {
            "launchDelay": 500,
            "titleLength": 22
        },
        "process": {
            "gracefulShutdownTimeout": 5000,
            "checkInterval": 1000
        },
        "defaults": {
            "width": 80,
            "height": 15,
            "colorScheme": "Campbell Powershell"
        },
        "layouts": {
            "twoByTwo": [
                { "x": 10, "y": 10, "width": 80, "height": 15 },
                { "x": 10, "y": 500, "width": 80, "height": 15 },
                { "x": 900, "y": 10, "width": 80, "height": 15 },
                { "x": 900, "y": 500, "width": 80, "height": 15 }
            ]
        }
    }
}
```

## Server Configuration Examples

### Python Server with Virtual Environment
```json
{
    "serverName": "flask-app",
    "homeFolder": "C:\\Servers\\flask-app",
    "venvPath": "C:\\Servers\\venv_flask",
    "startupCmd": "python app.py",
    "title": "Flask Server",
    "colorScheme": "Campbell Powershell",
    "position": {
        "x": 10,
        "y": 10,
        "width": 80,
        "height": 15
    }
}
```

### Node.js Server (No Virtual Environment)
```json
{
    "serverName": "node-server",
    "homeFolder": "C:\\Servers\\node-app",
    "venvPath": "not_needed",
    "startupCmd": "node server.js",
    "title": "Node Server",
    "colorScheme": "One Half Dark",
    "position": {
        "x": 900,
        "y": 10,
        "width": 80,
        "height": 15
    }
}
```

### Command-Line Tool (Using CMD)
```json
{
    "serverName": "network-monitor",
    "homeFolder": "C:\\Servers",
    "venvPath": "not_needed",
    "startupCmd": "cmd.exe /c ping 1.1.1.1 -t",
    "title": "Network Monitor",
    "colorScheme": "Vintage",
    "position": {
        "x": 10,
        "y": 500,
        "width": 80,
        "height": 15
    }
}
```

### PowerShell Command
```json
{
    "serverName": "process-monitor",
    "homeFolder": "C:\\Servers\\monitoring",
    "venvPath": "not_needed",
    "startupCmd": "powershell.exe -Command Get-Process | Where-Object {$_.CPU -gt 10} | Watch-Object -Property CPU",
    "title": "Process Monitor",
    "colorScheme": "Solarized Dark",
    "position": {
        "x": 900,
        "y": 500,
        "width": 80,
        "height": 15
    }
}
```

## Server Configuration Fields

| Field | Description | Required | Example |
|-------|-------------|----------|---------|
| serverName | Unique identifier for the server | Yes | "flask-app" |
| homeFolder | Working directory for the server | Yes | "C:\\Servers\\flask-app" |
| venvPath | Path to virtual environment or "not_needed" | Yes | "C:\\Servers\\venv_flask" |
| startupCmd | Command to start the server | Yes | "python app.py" |
| title | Display title in Windows Terminal | Yes | "Flask Server" |
| colorScheme | Windows Terminal color scheme name | Yes | "Campbell Powershell" |
| position | Window position and size settings | Yes | See position object |

### Position Object Fields
| Field | Description | Type | Example |
|-------|-------------|------|---------|
| x | Window X position | number | 10 |
| y | Window Y position | number | 10 |
| width | Window width in characters | number | 80 |
| height | Window height in characters | number | 15 |

## Process Management
The tool provides several options when a server is already running:
- **R**: Retry check for running instances
- **T**: Terminate existing and start new
- **S**: Start new instance anyway (not recommended)
- **K**: Keep existing (skip)

## Window Terminal Integration
- Each server runs in its own Windows Terminal window
- Windows are positioned according to configuration
- Custom color schemes are supported
- When terminating servers, use Ctrl+D to close the terminal tabs

## Logging
- All operations are logged to the configured log file
- Log rotation is supported based on file size
- Different log levels: INFO, WARNING, ERROR, SUCCESS
- Debug information available for process management

## Best Practices
1. Use unique serverName values for each server
2. Set appropriate working directories in homeFolder
3. Use "not_needed" for venvPath when running non-Python servers
4. Choose distinct window positions to avoid overlap
5. Use meaningful titles for better process management
