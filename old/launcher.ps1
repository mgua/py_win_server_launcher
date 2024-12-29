# this is a powershell launcher using wt windows terminal
# mgua@tomware.it 26.12.2024
# 
# working examples:
# Start-Process "wt.exe" -Argumentlist "--pos 10,500", "--size 80,15", "--colorScheme `"Solarized Light`"", "powershell -NoExit -command ping 127.0.0.1 "
# Start-Process "wt.exe" -ArgumentList "--pos 010,010","--size 040,020","--colorScheme `"Solarized Light`"","cmd"
#
# Define the path to the child scripts
$script01 = "c:/Users/mgua/psprofile/child01.ps1"
$script02 = "c:/Users/mgua/psprofile/child02.ps1"
$script03 = "c:/Users/mgua/psprofile/child03.ps1"
$script04 = "c:/Users/mgua/psprofile/child04.ps1"
$title01 = "Title 02"
$title02 = "Title 02"
$title03 = "Title 03"
$title04 = "Title 04"
#
# prepare suitable titles given windows title limitations
$rmost = -22
$t01 = -join ("$title01", ": ", -join $script01[$rmost..-1])  # take the rightmost $rmost chars of script name
$t02 = -join ("$title02", ": ", -join $script02[$rmost..-1])
$t03 = -join ("$title03", ": ", -join $script03[$rmost..-1])
$t04 = -join ("$title04", ": ", -join $script04[$rmost..-1])

$color01 = "Campbell Powershell"
$color02 = "Solarized Light"
$color03 = "Solarized Dark"
$color04 = "One Half Dark"

Start-Process "wt.exe" -ArgumentList "--pos 010,010","--size 080,015","--title `"$t01`"","--colorScheme `"$color01`"","powershell -NoExit -Command $script01"
Start-Process "wt.exe" -ArgumentList "--pos 010,500","--size 080,015","--title `"$t02`"","--colorScheme `"$color02`"","powershell -NoExit -Command $script02"
Start-Process "wt.exe" -ArgumentList "--pos 900,010","--size 080,015","--title `"$t03`"","--colorScheme `"$color03`"","powershell -NoExit -Command $script03"
Start-Process "wt.exe" -ArgumentList "--pos 900,500","--size 080,015","--title `"$t04`"","--colorScheme `"$color04`"","powershell -NoExit -Command $script04"


