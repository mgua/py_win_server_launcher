# Windows Terminal Server Launcher Manual

## Overview
The Windows Terminal Server Launcher is a PowerShell tool designed to manage multiple server processes in Windows Terminal. It supports various types of servers including Python applications, command-line tools, and environment-dependent executables.

## Features
- Launch multiple servers in separate Windows Terminal windows
- Custom window positioning and color schemes
- Virtual environment support for Python servers and environment-dependent commands
- Process monitoring and management
- Graceful shutdown handling
- Configurable logging
- Support for multiple server types (Python, command-line, environment-dependent)
- Multiple predefined window layouts
- Active/inactive server management

## Usage

### Basic Command
```powershell
.\py_win_server_launcher.ps1 [config_file] [-Force] [-IgnoreRunning] [-Help]
```

### Parameters
- `config_file`: Path to configuration JSON file (default: .\py_win_server_launcher.json)
- `-Force (-f)`: Skip confirmation prompts and force restart any running instances
- `-IgnoreRunning (-i)`: Start new instances even if servers are already running
- `-Help (-h, -?, --help)`: Show help message

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

### Python Server
```json
{
    "id": "flask-app",
    "title": "Flask Server",
    "description": "Flask web application server",
    "active": true,
    "type": "python",
    "command": "app.py",
    "workingDir": "C:\\Servers\\flask-app",
    "venv": "C:\\Servers\\venv_flask",
    "display": {
        "colorScheme": "Campbell Powershell",
        "position": {
            "x": 10,
            "y": 10,
            "width": 80,
            "height": 15
        }
    }
}
```

### Environment-Dependent Command
```json
{
    "id": "openwebui",
    "title": "OpenWebUI",
    "description": "LLM web interface",
    "active": true,
    "type": "venv-command",
    "command": "open-webui serve",
    "workingDir": "d:\\sw\\openwebui",
    "venv": "d:\\sw\\venv_openwebui",
    "display": {
        "colorScheme": "Solarized Light",
        "position": {
            "x": 900,
            "y": 10,
            "width": 80,
            "height": 15
        }
    }
}
```

### Simple Command (CMD Shell)
```json
{
    "id": "ping-test",
    "title": "Network Monitor",
    "description": "Continuous ping test",
    "active": true,
    "type": "command",
    "shell": "cmd",
    "command": "ping 1.1.1.1 -t",
    "workingDir": "C:\\Servers",
    "display": {
        "colorScheme": "Vintage",
        "position": {
            "x": 10,
            "y": 500,
            "width": 80,
            "height": 15
        }
    }
}
```

### PowerShell Command
```json
{
    "id": "process-monitor",
    "title": "Process Monitor",
    "description": "System process monitoring",
    "active": true,
    "type": "command",
    "shell": "powershell",
    "command": "Get-Process | Where-Object {$_.CPU -gt 10} | Watch-Object -Property CPU",
    "workingDir": "C:\\Servers\\monitoring",
    "display": {
        "colorScheme": "Solarized Dark",
        "position": {
            "x": 900,
            "y": 500,
            "width": 80,
            "height": 15
        }
    }
}
```

## Server Configuration Fields

| Field | Description | Required | Example |
|-------|-------------|----------|---------|
| id | Unique identifier for the server | Yes | "flask-app" |
| title | Display title in Windows Terminal | Yes | "Flask Server" |
| description | Server description | No | "Flask web application" |
| active | Whether the server should be started | No | true |
| type | Server type (python/command/venv-command) | Yes | "python" |
| shell | Shell type for command servers (cmd/powershell) | No | "cmd" |
| command | Command to start the server | Yes | "app.py" |
| workingDir | Working directory for the server | Yes | "C:\\Servers\\flask-app" |
| venv | Path to virtual environment | For python/venv-command | "C:\\Servers\\venv_flask" |
| display | Window display settings | Yes | See display object |

### Display Object Fields
| Field | Description | Required | Example |
|-------|-------------|----------|---------|
| colorScheme | Windows Terminal color scheme name | Yes | "Campbell Powershell" |
| position | Window position and size settings | Yes | See position object |

### Position Object Fields
| Field | Description | Type | Example |
|-------|-------------|------|---------|
| x | Window X position | number | 10 |
| y | Window Y position | number | 10 |
| width | Window width in characters | number | 80 |
| height | Window height in characters | number | 15 |

## Server Types
The launcher supports three types of servers:

1. **python**: Python scripts that require a virtual environment
   - Activates virtual environment before launching
   - Runs Python script with interpreter

2. **command**: Direct system commands
   - Can specify shell type (cmd/powershell)
   - No environment activation needed
   - Runs command directly or through specified shell

3. **venv-command**: Commands that require a Python environment
   - Activates virtual environment before launching
   - Runs command directly in activated environment
   - Useful for tools installed in environment's Scripts directory

## Process Management
The tool provides several options when a server is already running:
- **R**: Retry check for running instances
- **T**: Terminate existing and start new
- **S**: Start new instance anyway (not recommended)
- **K**: Keep existing (skip)

## Windows Terminal Integration
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
1. Use descriptive IDs and titles for each server
2. Set appropriate working directories
3. Choose the correct server type based on requirements
4. Use description field for documentation
5. Set active flag to false for temporarily disabled servers
6. Use distinct window positions to avoid overlap
7. Group related servers with similar color schemes
8. Use shell specification for command-type servers when needed