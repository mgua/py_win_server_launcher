# this powershell script launches all the tailor.wizh.it ai services on this machine
# mgua@tomware.it 13 december 2024
# 19 12 2024: added email_engine processing (g2)
#
# $SWROOT is the folder where the repos of the different parts are cloned and pulled
# each components has a corresponding venv_folder_name
# the nvidia drivers with cuda support up to 12.6 are expected
# the ollama components have to independently setup
# the ollama models are to be downloaded in an independent folder, as 
# pointed by the system env variable OLLAMA_MODELS
# the script ollama_fetch_models updates all the required models in the relevant
# folder 
# 
#
# all the services are scripts that open their own environment and execute the required commands
# ollama server launches the ollama listener
# this script take the name of the current folder, appent to that the venv_ prefix and activate the environment
# Start-Process starts process with its own window
#

$SWROOT = "d:\sw\"
# mailnode is where we run the mail processor
$MAILNODE = "WIZWKS01"


function Start-CustomPSWindow {
    param(
        [string]$Title,
        [string]$BackgroundColor,
        [string]$ForegroundColor,
        [string]$FontFamily = "Consolas",
        [int]$FontSize = 10,
        [scriptblock]$Command
    )
    
    $customization = @"
        `$Host.UI.RawUI.WindowTitle = '$Title';
        `$Host.UI.RawUI.BackgroundColor = '$BackgroundColor';
        `$Host.UI.RawUI.ForegroundColor = '$ForegroundColor';
        `$Host.UI.RawUI.FontFamily = '$FontFamily';
        `$Host.UI.RawUI.FontSize = $FontSize;
        Clear-Host;
        $Command
"@
    
    Start-Process powershell -ArgumentList '-NoExit', '-Command', $customization
}

#Start-CustomPSWindow -Title "Process 1" -BackgroundColor "DarkBlue" -ForegroundColor "White" -Command {
#    Write-Host "Running Process 1"
#    # Your actual commands here
#}


# ollama network server -----------------------------------------------------
Get-WmiObject Win32_Process | 
Select-Object ProcessId, Name, CommandLine | 
Where-Object {$_.Name -like "*ollama*" -and $_.Commandline -like "*serve"} |
ForEach-Object { 
	Write-Host "Killing process $($_.ProcessId): $($_.CommandLine)"
	$confirmation = Read-Host "Are you sure you want to kill this process? (y/n)"
	if($confirmation -eq 'y') {
        Stop-Process -Id $_.ProcessId -Force
    }
}

Write-Host "Spawning ollama server..."
$ollama_command = "Set-Item env:OLLAMA_HOST '0.0.0.0:11434'; ollama serve"
#Start-CustomPSWindow -Title "Process 1" -BackgroundColor "DarkBlue" -ForegroundColor "White" -Command "$ollama_command"
Start-Process powershell -ArgumentList "-NoExit", "-Command", $ollama_command
# ---------------------------------------------------------------------------



# tailor frontend server ----------------------------------------------------
Get-WmiObject Win32_Process | 
Select-Object ProcessId, Name, CommandLine | 
Where-Object {$_.Name -like "*ython*" -and $_.Commandline -like "*tailor_server*"} |
ForEach-Object { 
	Write-Host "Killing process $($_.ProcessId): $($_.CommandLine)"
	$confirmation = Read-Host "Are you sure you want to kill this process? (y/n)"
	if($confirmation -eq 'y') {
        Stop-Process -Id $_.ProcessId -Force
    }
}

Write-Host "Spawning tailor web frontend..."
Set-Location $SWROOT
# environment folder will become tailor_webfe
Set-Location "ollama_web_assistant"
$current_folder_name = Split-Path -Path (Get-Location) -Leaf
Write-Host "  current_folder_name=$current_folder_name"
$venv_folder_name = "venv_" + $current_folder_name
Write-Host "  webfoldername=$venv_folder_name"
$venv_activate = "..\$venv_folder_name\Scripts\Activate.ps1"
Write-Host "  venv_activate=$venv_activate"
$tailor_fe_command = ". $venv_activate; python ./tailor_server.py"
Write-Host "  command=$tailor_fe_command"
#Start-CustomPSWindow -Title "Tailor_User_WebFrontEnd" -BackgroundColor "DarkRed" -ForegroundColor "White" -Command "$tailor_fe_command"
Start-Process powershell -ArgumentList "-NoExit", "-Command", $tailor_fe_command
# ---------------------------------------------------------------------------



# gufo frontend server ----------------------------------------------------
Get-WmiObject Win32_Process | 
Select-Object ProcessId, Name, CommandLine | 
Where-Object {$_.Name -like "*ython*" -and $_.Commandline -like "*gufo_server*"} |
ForEach-Object { 
	Write-Host "Killing process $($_.ProcessId): $($_.CommandLine)"
	$confirmation = Read-Host "Are you sure you want to kill this process? (y/n)"
	if($confirmation -eq 'y') {
        Stop-Process -Id $_.ProcessId -Force
    }
}

Write-Host "Spawning Gufo web frontend..."
Set-Location $SWROOT
Set-Location "gufo"
$current_folder_name = Split-Path -Path (Get-Location) -Leaf
Write-Host "  current_folder_name=$current_folder_name"
$venv_folder_name = "venv_" + $current_folder_name
Write-Host "  webfoldername=$venv_folder_name"
$venv_activate = "..\$venv_folder_name\Scripts\Activate.ps1"
Write-Host "  venv_activate=$venv_activate"
$gufo_command = ". $venv_activate; python ./gufo_server.py"
Write-Host "  command=$gufo_command"
#Start-CustomPSWindow -Title "Gufo_WebFrontEnd" -BackgroundC#olor "DarkGreen" -ForegroundColor "White" -Command "$gufo_command"
Start-Process powershell -ArgumentList "-NoExit", "-Command", $gufo_command
# ---------------------------------------------------------------------------
#
#
function Launch_Mail_Processor {
    # mail processor server -(this should run on a single server ----------------------------
    Get-WmiObject Win32_Process | 
    Select-Object ProcessId, Name, CommandLine | 
    Where-Object {$_.Name -like "*ython*" -and $_.Commandline -like "*process_email*"} |
    ForEach-Object { 
	Write-Host "Killing process $($_.ProcessId): $($_.CommandLine)"
	$confirmation = Read-Host "Are you sure you want to kill this process? (y/n)"
	if($confirmation -eq 'y') {
        Stop-Process -Id $_.ProcessId -Force
        }
    }
    
    Write-Host "Spawning headless email processor server..."
    Set-Location $SWROOT
    # environment folder will become tailor_webfe
    Set-Location "ollama_web_assistant"
    $current_folder_name = Split-Path -Path (Get-Location) -Leaf
    Write-Host "  current_folder_name=$current_folder_name"
    $venv_folder_name = "venv_" + $current_folder_name
    Write-Host "  webfoldername=$venv_folder_name"
    $venv_activate = "..\$venv_folder_name\Scripts\Activate.ps1"
    Write-Host "  venv_activate=$venv_activate"
    $mail_processor_command = ". $venv_activate; python ./email_engine_g2/process_emails4.py"
    Write-Host "  command=$mail_processor_command"
    #Start-CustomPSWindow -Title "Mail_processor_server" -BackgroundColor "DarkRed" -ForegroundColor "White" -Command "$mail_processor_command"
    Start-Process powershell -ArgumentList "-NoExit", "-Command", $mail_processor_command
}
# ---------------------------------------------------------------------------



Write-Host "Current hostname: $env:COMPUTERNAME"
Write-Host "Running mail processor only on $MAILNODE"

if ($env:COMPUTERNAME -ieq "$MAILNODE") {
    Write-Host "Spawning mail processor"
    Launch_Mail_Processor
}

#
