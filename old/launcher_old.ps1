# this is a powershell launcher using wt windows terminal
# 
# working examples:
# start-Process "wt.exe" -Argumentlist "--pos 10,500", "--size 80,15", "--colorScheme `"Solarized Light`"", "powershell -NoExit -command ping 127.0.0.1 "
# 
#
# Define the path to the child scripts
$scriptPath01 = "c:/Users/mgua/psprofile/child01.ps1"
$scriptPath02 = "c:/Users/mgua/psprofile/child02.ps1"
$title01 = $scriptPath01
$title02 = $scriptPath02
$colorScheme01 = "Campbell Powershell"
$colorScheme01 = "Solarized Light"


# Function to launch a PowerShell window with specific settings
function Start-ChildWindow {
    param (
        [string]$pos,
        [string]$size,
        [string]$colorScheme,
        [string]$ScriptPath,
        [string]$Title,
        [string]$BackgroundColor,
        [string]$FontName,
        [int]$FontSize
    )
    # Create the command to start a new PowerShell window with specified parameters
    # @" is the beginning of a here string and "@ is its end
    # no doublequotes inside the $command since it goes in the startprocess line which is doublequote delimited
    #
    $command = @"
        powershell.exe -NoExit -Command {
            `$Host.UI.RawUI.BackgroundColor = '$BackgroundColor' ;
            `$Host.UI.RawUI.ForegroundColor = 'White' ;
            `$Host.UI.RawUI.WindowTitle = '$Title' ;
            `$Host.PrivateData.ConsolePaneBackground = [System.Windows.Media.Brushes]::$BackgroundColor ;
            `$Host.PrivateData.ConsolePaneForegroundColor = [System.Windows.Media.Brushes]::White ;
            `$Host.PrivateData.FontName = '$FontName' ;
            `$Host.PrivateData.FontSize = $FontSize ;
            '$ScriptPath'
        }
"@

    # Start the new PowerShell window asynchronously
    Start-Process "wt.exe" -ArgumentList "--pos $pos","--size $size","--colorScheme $colorScheme","powershell.exe -NoExit -Command $command"
    #Start-Process "wt.exe" -ArgumentList "--pos $pos","--size $size","--colorScheme $colorScheme","$command"
}

Start-ChildWindow -pos 010,010 -size 80,15 -colorScheme "Solarized Light" -ScriptPath $scriptPath01 -Title "$title01" -BackgroundColor "Blue" -FontName "Consolas" -FontSize 12
Start-ChildWindow -pos 010,500 -size 80,15 -colorSchema "Campbell Powershell" -ScriptPath $scriptPathi02 -Title "$title02" -BackgroundColor "Green" -FontName "Courier New" -FontSize 14


