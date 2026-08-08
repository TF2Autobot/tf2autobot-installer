$ErrorActionPreference = "Stop"

$waitForExit = $args -contains "-WaitForExit"

$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "The script needs admin rights, relaunching with UAC prompt" -ForegroundColor Yellow

    if ($PSCommandPath) {
        Start-Process powershell.exe -Verb RunAs -WorkingDirectory $PWD -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$PSCommandPath`"",
            "-WaitForExit"
        )
    }
    else {
        $url = "https://raw.githubusercontent.com/TF2Autobot/tf2autobot-installer/main/installer-windows.ps1"
        $temp = Join-Path $env:TEMP "installer-windows.ps1"

        Invoke-WebRequest $url -OutFile $temp

        Start-Process powershell.exe -Verb RunAs -WorkingDirectory $PWD -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$temp`"",
            "-WaitForExit"
        )
    }

    exit
}

function Write-Step($msg) {
    Write-Host ""
    Write-Host "> $msg" -ForegroundColor Cyan
}

function Refresh-Path {
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Select-InstallFolder {
    Add-Type -AssemblyName System.Windows.Forms

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Choose where to install TF2Autobot"
    $dialog.SelectedPath = $env:USERPROFILE

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        throw "Installation cancelled"
    }

    return Join-Path $dialog.SelectedPath "tf2autobot"
}

$scriptFailed = $false

try {
    Write-Step "Selecting install location"

    $installPath = Select-InstallFolder

    Write-Host "Installing to: $installPath"

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "Can't find winget on this machine. Install/update 'App Installer' from the Microsoft Store, then try again"
    }

    Write-Step "Installing Git"

    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host "Git already installed"
    }
    else {
        winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements

        if ($LASTEXITCODE -ne 0) {
            throw "Git install failed (exit code $LASTEXITCODE)"
        }
    }

    Write-Step "Installing Node.js (LTS)"

    if (Get-Command node -ErrorAction SilentlyContinue) {
        Write-Host "Node already installed"
    }
    else {
        $nodeMajor = 24

        $versionLines = winget show --id OpenJS.NodeJS.LTS -e --versions --accept-source-agreements

        $nodeVersion = $versionLines |
            Where-Object { $_ -match "^$nodeMajor\.\d+\.\d+$" } |
            Sort-Object { [Version]$_ } -Descending |
            Select-Object -First 1

        if (-not $nodeVersion) {
            throw "Couldn't find any Node.js $nodeMajor.x release via winget"
        }

        Write-Host "Installing Node.js $nodeVersion"

        winget install --id OpenJS.NodeJS.LTS -e --version $nodeVersion --silent --accept-package-agreements --accept-source-agreements

        if ($LASTEXITCODE -ne 0) {
            throw "Node install failed (exit code $LASTEXITCODE)"
        }
    }

    Refresh-Path

    foreach ($tool in @("git", "node", "npm")) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "'$tool' is not available after installation"
        }
    }

    Write-Host ""
    Write-Host "Git:  $(git --version)"
    Write-Host "Node: $(node --version)"
    Write-Host "npm:  $(npm --version)"
    Write-Host ""

    Write-Step "Cloning TF2Autobot"

    if (Test-Path $installPath) {
        throw "The selected folder already exists. Choose an empty folder"
    }

    git clone https://github.com/TF2Autobot/tf2autobot $installPath

    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed (exit code $LASTEXITCODE)"
    }

    Set-Location $installPath

    Write-Step "Installing TypeScript"

    npm install typescript@latest -g

    if ($LASTEXITCODE -ne 0) {
        throw "Installing TypeScript failed (exit code $LASTEXITCODE)"
    }

    Write-Step "Installing PM2"

    npm install pm2@latest -g

    if ($LASTEXITCODE -ne 0) {
        throw "Installing PM2 failed (exit code $LASTEXITCODE)"
    }

    Write-Step "Installing dependencies"

    npm ci --no-audit

    if ($LASTEXITCODE -ne 0) {
        throw "npm ci failed (exit code $LASTEXITCODE)"
    }

    Write-Step "Building TF2Autobot"

    npm run build

    if ($LASTEXITCODE -ne 0) {
        throw "Build failed (exit code $LASTEXITCODE)"
    }

    Write-Step "Creating ecosystem.json"

    Copy-Item ".\template.ecosystem.json" ".\ecosystem.json" -Force

    Write-Host "Created ecosystem.json"

    Write-Step "Done"

    Write-Host "TF2Autobot installed"
    Write-Host "Location: $installPath"
    Write-Host ""
    Write-Host "Edit ecosystem.json and add your bot credentials"
    Write-Host "Config guide:"
    Write-Host "https://github.com/TF2Autobot/tf2autobot/wiki/Configuring-the-bot"
    Write-Host ""
    Write-Host "Start your bot with: " -NoNewline
    Write-Host "pm2 start ecosystem.json" -ForegroundColor Cyan
}
catch {
    $scriptFailed = $true

    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($waitForExit) {
        Write-Host ""
        Write-Host "Press Enter to close this window..." -ForegroundColor DarkGray
        Read-Host
    }
}

if ($scriptFailed) {
    exit 1
}