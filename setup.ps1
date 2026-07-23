Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
trap {
    Write-Output "ERROR: $_"
    Write-Output (($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1')
    Write-Output (($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1')
    Exit 1
}

# wrap the choco command (to make sure this script aborts when it fails).
function Start-Choco([string[]]$Arguments, [int[]]$SuccessExitCodes=@(0)) {
    $command, $commandArguments = $Arguments
    if ($command -eq 'install') {
        $Arguments = @($command, '--no-progress') + $commandArguments
    }
    for ($n = 0; $n -lt 10; ++$n) {
        if ($n) {
            # NB sometimes choco fails with "The package was not found with the source(s) listed."
            #    but normally its just really a transient "network" error.
            Write-Host "Retrying choco install..."
            Start-Sleep -Seconds 3
        }
        &C:\ProgramData\chocolatey\bin\choco.exe @Arguments
        if ($SuccessExitCodes -Contains $LASTEXITCODE) {
            return
        }
    }
    throw "$(@('choco')+$Arguments | ConvertTo-Json -Compress) failed with exit code $LASTEXITCODE (0x$($LASTEXITCODE.ToString('X8')))"
}
function choco {
    Start-Choco $Args
}

# install other useful applications and dependencies.
choco install -y nssm
choco install -y carbon
choco install -y --ignore-checksums procexp
choco install -y notepad3
choco install -y --allow-empty-checksums dependencywalker
choco install -y git --params '/GitOnlyOnPath /NoAutoCrlf'
choco install -y gitextensions
choco install -y meld

# update $env:PATH with the recently installed Chocolatey packages.
Import-Module C:\ProgramData\chocolatey\helpers\chocolateyInstaller.psm1
Update-SessionEnvironment

# configure git.
# see http://stackoverflow.com/a/12492094/477532
git config --global user.name 'Rui Lopes'
git config --global user.email 'rgl@ruilopes.com'
git config --global push.default simple
git config --global diff.guitool meld
git config --global difftool.meld.path 'C:/Program Files (x86)/Meld/Meld.exe'
git config --global difftool.meld.cmd '\"C:/Program Files (x86)/Meld/Meld.exe\" \"$LOCAL\" \"$REMOTE\"'
git config --global merge.tool meld
git config --global mergetool.meld.path 'C:/Program Files (x86)/Meld/Meld.exe'
git config --global mergetool.meld.cmd '\"C:/Program Files (x86)/Meld/Meld.exe\" --diff \"$LOCAL\" \"$BASE\" \"$REMOTE\" --output \"$MERGED\"'
#git config --list --show-origin

# install msys2.
choco install -y msys2 --params '/NoPath'

# configure the msys2 launcher to let the shell inherit the PATH.
$msys2BasePath = 'C:\tools\msys64'
@(
    'msys2.ini'
    'mingw64.ini'
) | ForEach-Object {
    $msys2ConfigPath = "$msys2BasePath\$_"
    [IO.File]::WriteAllText(
        $msys2ConfigPath,
        ([IO.File]::ReadAllText($msys2ConfigPath) `
            -replace '#?(MSYS2_PATH_TYPE=).+','$1inherit')
    )
}

# configure msys2 to mount C:\Users at /home.
[IO.File]::WriteAllText(
    "$msys2BasePath\etc\nsswitch.conf",
    ([IO.File]::ReadAllText("$msys2BasePath\etc\nsswitch.conf") `
        -replace '(db_home: ).+','$1windows')
)
Write-Output 'C:\Users /home' | Out-File -Encoding ASCII -Append "$msys2BasePath\etc\fstab"

# define a function for easing the execution of bash scripts.
$bashPath = "$msys2BasePath\usr\bin\bash.exe"
function Bash($script) {
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # we also redirect the stderr to stdout because PowerShell
        # oddly interleaves them.
        # see https://www.gnu.org/software/bash/manual/bash.html#The-Set-Builtin
        echo 'exec 2>&1;set -eu;export PATH="/usr/bin:$PATH";export HOME=$USERPROFILE;' $script | &$bashPath
        if ($LASTEXITCODE) {
            throw "bash execution failed with exit code $LASTEXITCODE (0x$($LASTEXITCODE.ToString('X8')))"
        }
    } finally {
        $ErrorActionPreference = $eap
    }
}

# register msys2 bash in the windows explorer context menu.
reg import /vagrant/MSYS2-Bash-Here.reg
if ($LASTEXITCODE) {
    throw "reg import failed with exit code $LASTEXITCODE (0x$($LASTEXITCODE.ToString('X8')))"
}

# install the remaining dependencies.
Bash 'pacman --noconfirm -Sy make zip unzip tar dos2unix'

# configure the shell.
Bash @'
pacman --noconfirm -Sy vim

cat>~/.bash_history<<"EOF"
EOF

cat>~/.bashrc<<"EOF"
# If not running interactively, don't do anything
[[ "$-" != *i* ]] && return

export EDITOR=vim
export PAGER=less

alias l='ls -lF --color'
alias ll='l -a'
alias h='history 25'
alias j='jobs -l'
EOF

cat>~/.inputrc<<"EOF"
"\e[A": history-search-backward
"\e[B": history-search-forward
"\eOD": backward-word
"\eOC": forward-word
set show-all-if-ambiguous on
set completion-ignore-case on
EOF

cat>~/.vimrc<<"EOF"
syntax on
set background=dark
set esckeys
set ruler
set laststatus=2
set nobackup

autocmd BufNewFile,BufRead Vagrantfile set ft=ruby
autocmd BufNewFile,BufRead *.config set ft=xml

" Usefull setting for working with Ruby files.
autocmd FileType ruby set tabstop=2 shiftwidth=2 smarttab expandtab softtabstop=2 autoindent
autocmd FileType ruby set smartindent cinwords=if,elsif,else,for,while,try,rescue,ensure,def,class,module

" Usefull setting for working with Python files.
autocmd FileType python set tabstop=4 shiftwidth=4 smarttab expandtab softtabstop=4 autoindent
" Automatically indent a line that starts with the following words (after we press ENTER).
autocmd FileType python set smartindent cinwords=if,elif,else,for,while,try,except,finally,def,class

" Usefull setting for working with Go files.
autocmd FileType go set tabstop=4 shiftwidth=4 smarttab expandtab softtabstop=4 autoindent
" Automatically indent a line that starts with the following words (after we press ENTER).
autocmd FileType go set smartindent cinwords=if,else,switch,for,func
EOF
'@

# remove the default desktop shortcuts.
del C:\Users\Public\Desktop\*.lnk

# add MINGW64 shortcut to the Desktop and Start Menu.
Install-ChocolateyShortcut `
  -ShortcutFilePath "$env:USERPROFILE\Desktop\MINGW64 Bash.lnk" `
  -TargetPath 'C:\tools\msys64\mingw64.exe' `
  -WorkingDirectory $env:USERPROFILE
Install-ChocolateyShortcut `
  -ShortcutFilePath "C:\Users\All Users\Microsoft\Windows\Start Menu\Programs\MINGW64 Bash.lnk" `
  -TargetPath 'C:\tools\msys64\mingw64.exe' `
  -WorkingDirectory $env:USERPROFILE

# enable show window content while dragging.
Set-ItemProperty -Path 'HKCU:Control Panel\Desktop' -Name DragFullWindows -Value 1

# show hidden files.
Set-ItemProperty -Path HKCU:Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name Hidden -Value 1

# show protected operating system files.
Set-ItemProperty -Path HKCU:Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name ShowSuperHidden -Value 1

# show file extensions.
Set-ItemProperty -Path HKCU:Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name HideFileExt -Value 0

# display full path in the title bar.
New-Item -Path HKCU:Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState -Force `
    | New-ItemProperty -Name FullPath -Value 1 -PropertyType DWORD `
    | Out-Null

# never combine the taskbar buttons.
#
# possible values:
#   0: always combine and hide labels (default)
#   1: combine when taskbar is full
#   2: never combine
Set-ItemProperty -Path HKCU:Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarGlomLevel -Value 2

# set keyboard layout.
# NB you can get the name from the list:
#      [Globalization.CultureInfo]::GetCultures('InstalledWin32Cultures') | Out-GridView
Set-WinUserLanguageList pt-PT -Force

# set the date format, number format, etc.
Set-Culture pt-PT

# set the timezone.
# tzutil /l lists all available timezone ids
& $env:windir\system32\tzutil /s "GMT Standard Time"
