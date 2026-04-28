Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$env:TZ = if ($env:TZ) { $env:TZ } else { "Asia/Seoul" }

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
$repoRoot = $repoRoot.Path

$defaultCodexBin = Join-Path $env:USERPROFILE ".vscode\extensions\openai.chatgpt-26.422.30944-win32-x64\bin\windows-x86_64\codex.exe"
$codexBin = if ($env:CODEX_BIN) { $env:CODEX_BIN } elseif (Test-Path $defaultCodexBin) { $defaultCodexBin } else { "codex" }
$promptFile = if ($env:CODEX_PROMPT_FILE) { $env:CODEX_PROMPT_FILE } else { Join-Path $repoRoot "docs\codex_cron_daily_tv_monitor.md" }
$model = if ($env:CODEX_MODEL) { $env:CODEX_MODEL } else { "gpt-5.4" }
$codexSandbox = if ($env:CODEX_SANDBOX_MODE) { $env:CODEX_SANDBOX_MODE } else { "workspace-write" }
$logDir = if ($env:CODEX_LOG_DIR) { $env:CODEX_LOG_DIR } else { Join-Path $repoRoot "logs\cron" }
$remoteUrl = if ($env:REMOTE_URL) { $env:REMOTE_URL } else { "https://github.com/DoramiLab/daily-tv-monitor.git" }
$branch = if ($env:BRANCH) { $env:BRANCH } else { "main" }
$authFile = if ($env:GITHUB_AUTH_FILE) { $env:GITHUB_AUTH_FILE } else { Join-Path $repoRoot ".github-auth.local" }
$gitBin = if ($env:GIT_BIN) { $env:GIT_BIN } elseif (Test-Path "C:\Program Files\Git\cmd\git.exe") { "C:\Program Files\Git\cmd\git.exe" } else { "git" }
$tempRoot = [System.IO.Path]::GetTempPath()

New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$runLog = Join-Path $logDir "run_$timestamp.log"
$lastMessage = Join-Path $logDir "last_message_$timestamp.txt"
$lockFile = Join-Path $tempRoot "daily-tv-monitor-cron.lock"
$instance = "{0}-{1}" -f ([DateTimeOffset]::Now.ToUnixTimeSeconds()), $PID
$gitDir = if ($env:TV_AI_DAILY_GIT_DIR) { $env:TV_AI_DAILY_GIT_DIR } else { Join-Path $tempRoot "tv-ai-daily-git-$instance" }
$workDir = if ($env:TV_AI_DAILY_WORK_DIR) { $env:TV_AI_DAILY_WORK_DIR } else { Join-Path $tempRoot "tv-ai-daily-worktree-$instance" }
$askpassScript = $null

function Write-RunLog {
    param([string]$Message)
    $Message | Tee-Object -FilePath $runLog -Append | Out-Null
}

function Test-TransientNetworkError {
    param([string]$Output)
    $text = $Output.ToLowerInvariant()
    return $text.Contains("could not resolve host") -or
        $text.Contains("failed to connect") -or
        $text.Contains("operation timed out") -or
        $text.Contains("connection timed out") -or
        $text.Contains("connection reset") -or
        $text.Contains("the remote end hung up unexpectedly") -or
        $text.Contains("http 5")
}

function Invoke-WithRetry {
    param(
        [string]$Label,
        [scriptblock]$Command
    )

    $delays = @(0, 5, 15, 45, 90)
    $attempt = 1
    $lastExit = 0

    foreach ($delay in $delays) {
        if ($delay -gt 0) {
            Start-Sleep -Seconds $delay
        }

        $output = & $Command 2>&1 | Out-String
        $lastExit = if ($LASTEXITCODE -ne $null) { $LASTEXITCODE } else { 0 }

        if ($lastExit -eq 0) {
            if ($output.Trim().Length -gt 0) {
                Write-RunLog $output.TrimEnd()
            }
            return
        }

        Write-RunLog ("{0} attempt {1} failed: {2}" -f $Label, $attempt, $output.TrimEnd())
        if (-not (Test-TransientNetworkError $output)) {
            throw "$Label failed with exit code $lastExit"
        }

        $attempt++
    }

    throw "$Label failed with exit code $lastExit"
}

function Import-GitHubAuth {
    if (-not (Test-Path $authFile)) {
        return
    }

    foreach ($line in Get-Content $authFile) {
        if ($line -match "^\s*$" -or $line -match "^\s*#") {
            continue
        }
        $parts = $line -split "=", 2
        if ($parts.Count -ne 2) {
            continue
        }
        $name = $parts[0].Trim()
        $value = $parts[1].Trim()
        if ($name) {
            Set-Item -Path "Env:$name" -Value $value
        }
    }

    if (-not $env:GITHUB_ID) {
        if ($env:GITHUB_USER) {
            $env:GITHUB_ID = $env:GITHUB_USER
        } elseif ($env:GITHUB_USERNAME) {
            $env:GITHUB_ID = $env:GITHUB_USERNAME
        } else {
            $env:GITHUB_ID = "x-access-token"
        }
    }

    if (-not $env:GITHUB_PAT -and $env:GITHUB_TOKEN) {
        $env:GITHUB_PAT = $env:GITHUB_TOKEN
    }

    if (-not $env:GITHUB_PAT) {
        Write-RunLog "GitHub auth file exists but no token was found in $authFile"
        return
    }

    $askpassScript = Join-Path $tempRoot "tv-ai-daily-askpass-$($PID).cmd"
    Set-Content -Path $askpassScript -Encoding ASCII -Value @(
        "@echo off",
        "echo %1 | findstr /I Username >nul",
        "if %ERRORLEVEL%==0 (echo %GITHUB_ID%& exit /b 0)",
        "echo %1 | findstr /I Password >nul",
        "if %ERRORLEVEL%==0 (echo %GITHUB_PAT%& exit /b 0)",
        "echo."
    )
    $script:askpassScript = $askpassScript
    $env:GIT_ASKPASS = $askpassScript
    $env:GIT_TERMINAL_PROMPT = "0"
    $env:GCM_INTERACTIVE = "Never"
}

function Invoke-Git {
    & $gitBin @args
}

function ConvertTo-CommandLineArg {
    param([string]$Value)
    if ($Value -notmatch '[\s"]') {
        return $Value
    }
    return '"' + ($Value -replace '\\(?=\\*")', '$0\' -replace '"', '\"') + '"'
}

function Invoke-CodexExec {
    param([string]$Prompt)

    $arguments = @(
        "--search",
        "--ask-for-approval", "never",
        "--sandbox", $codexSandbox,
        "exec",
        "-C", $repoRoot,
        "-m", $model,
        "--color", "never",
        "-o", $lastMessage,
        "-"
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $codexBin
    $psi.Arguments = ($arguments | ForEach-Object { ConvertTo-CommandLineArg $_ }) -join " "
    $psi.WorkingDirectory = $repoRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $promptBytes = [System.Text.Encoding]::UTF8.GetBytes($Prompt)
    $process.StandardInput.BaseStream.Write($promptBytes, 0, $promptBytes.Length)
    $process.StandardInput.BaseStream.Flush()
    $process.StandardInput.Close()
    $process.WaitForExit()

    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    if ($stdout.Trim().Length -gt 0) {
        Write-RunLog $stdout.TrimEnd()
    }
    if ($stderr.Trim().Length -gt 0) {
        Write-RunLog $stderr.TrimEnd()
    }

    return $process.ExitCode
}

function Publish-Reports {
    $commitMessage = "Daily TV monitor: $(Get-Date -Format yyyy-MM-dd)"

    New-Item -ItemType Directory -Force -Path $gitDir, $workDir | Out-Null
    Import-GitHubAuth

    if (-not (Test-Path (Join-Path $gitDir "HEAD"))) {
        Invoke-Git "--git-dir=$gitDir" init -q
        if ($LASTEXITCODE -ne 0) { throw "git init failed" }
    }

    Invoke-Git "--git-dir=$gitDir" remote get-url origin *> $null
    if ($LASTEXITCODE -ne 0) {
        Invoke-Git "--git-dir=$gitDir" remote add origin $remoteUrl
    } else {
        Invoke-Git "--git-dir=$gitDir" remote set-url origin $remoteUrl
    }
    if ($LASTEXITCODE -ne 0) { throw "git remote setup failed" }

    Invoke-Git "--git-dir=$gitDir" config user.name *> $null
    if ($LASTEXITCODE -ne 0) {
        Invoke-Git "--git-dir=$gitDir" config user.name "codex-automation"
    }
    Invoke-Git "--git-dir=$gitDir" config user.email *> $null
    if ($LASTEXITCODE -ne 0) {
        Invoke-Git "--git-dir=$gitDir" config user.email "codex-automation@users.noreply.github.com"
    }
    Invoke-Git "--git-dir=$gitDir" config credential.helper ""

    Write-RunLog ("[{0}] Publishing updated reports." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss K"))
    Invoke-WithRetry "git fetch" { Invoke-Git "--git-dir=$gitDir" fetch origin $branch -q }

    Invoke-Git "--git-dir=$gitDir" update-ref "refs/heads/$branch" "refs/remotes/origin/$branch"
    Invoke-Git "--git-dir=$gitDir" symbolic-ref HEAD "refs/heads/$branch"
    Invoke-Git "--git-dir=$gitDir" "--work-tree=$workDir" reset --hard "origin/$branch" -q
    if ($LASTEXITCODE -ne 0) { throw "git reset failed" }

    $reportDest = Join-Path $workDir "new_features"
    New-Item -ItemType Directory -Force -Path $reportDest | Out-Null
    $reportFiles = Get-ChildItem -Path (Join-Path $repoRoot "new_features") -Filter "*.md"
    if ($reportFiles.Count -eq 0) {
        throw "No report files found under $repoRoot\new_features."
    }
    Copy-Item -Path $reportFiles.FullName -Destination $reportDest -Force

    Push-Location $workDir
    try {
        Invoke-Git "--git-dir=$gitDir" "--work-tree=$workDir" add "new_features/*.md"
        if ($LASTEXITCODE -ne 0) { throw "git add failed" }
    } finally {
        Pop-Location
    }

    Invoke-Git "--git-dir=$gitDir" "--work-tree=$workDir" diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-RunLog ("[{0}] No report changes to publish." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss K"))
        return
    }

    Invoke-Git "--git-dir=$gitDir" "--work-tree=$workDir" commit -m $commitMessage -q
    if ($LASTEXITCODE -ne 0) { throw "git commit failed" }

    Invoke-WithRetry "git push" { Invoke-Git "--git-dir=$gitDir" "--work-tree=$workDir" push origin $branch }
    Write-RunLog ("[{0}] Publish completed." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss K"))
}

function Sync-LocalCheckoutIfOnlyReportsChanged {
    Invoke-Git -C $repoRoot rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) {
        return
    }

    $currentBranch = (& $gitBin -C $repoRoot branch --show-current 2>$null).Trim()
    if ($currentBranch -ne $branch) {
        Write-RunLog ("[{0}] Skipping local checkout sync; current branch is {1}, expected {2}." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss K"), $(if ($currentBranch) { $currentBranch } else { "detached" }), $branch)
        return
    }

    $statusLines = & $gitBin -C $repoRoot status --porcelain=v1 --untracked-files=all
    $hasNonReportChange = $false
    foreach ($line in $statusLines) {
        if (-not $line) { continue }
        $path = $line.Substring(3)
        if (-not $path.StartsWith("new_features/") -and -not $path.StartsWith("new_features\")) {
            $hasNonReportChange = $true
            break
        }
    }

    if ($hasNonReportChange) {
        Write-RunLog ("[{0}] Skipping local checkout sync; non-report changes are present." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss K"))
        return
    }

    Invoke-Git -C $repoRoot diff --quiet
    $diffClean = $LASTEXITCODE -eq 0
    Invoke-Git -C $repoRoot diff --cached --quiet
    $cachedClean = $LASTEXITCODE -eq 0
    $untrackedReports = & $gitBin -C $repoRoot ls-files --others --exclude-standard -- new_features
    if ($diffClean -and $cachedClean -and -not $untrackedReports) {
        return
    }

    Write-RunLog ("[{0}] Syncing local checkout after report publish." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss K"))
    Invoke-WithRetry "local git fetch" { Invoke-Git -C $repoRoot fetch origin $branch -q }

    Invoke-Git -C $repoRoot merge-base --is-ancestor HEAD "origin/$branch"
    if ($LASTEXITCODE -ne 0) {
        Write-RunLog ("[{0}] Skipping local checkout sync; local HEAD is not an ancestor of origin/{1}." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss K"), $branch)
        return
    }

    Invoke-Git -C $repoRoot clean -fd -- new_features | Tee-Object -FilePath $runLog -Append
    Invoke-Git -C $repoRoot reset --hard "origin/$branch" -q
    if ($LASTEXITCODE -ne 0) { throw "local checkout reset failed" }
    Write-RunLog ("[{0}] Local checkout synced to origin/{1}." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss K"), $branch)
}

if (Test-Path $lockFile) {
    Write-RunLog ("[{0}] Another run is already in progress. Exiting." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss K"))
    exit 0
}

try {
    New-Item -ItemType File -Path $lockFile -Force | Out-Null

    if (-not (Get-Command $codexBin -ErrorAction SilentlyContinue)) {
        throw "Codex binary not found or not executable: $codexBin"
    }
    if (-not (Test-Path $promptFile)) {
        throw "Prompt file not found: $promptFile"
    }
    if (-not (Test-Path (Join-Path $repoRoot "new_features"))) {
        throw "Report output directory not found: $repoRoot\new_features"
    }

    Write-RunLog ("[{0}] Starting daily TV monitor run." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss K"))
    Write-RunLog "repo_root=$repoRoot"
    Write-RunLog "prompt_file=$promptFile"
    Write-RunLog "model=$model"
    Write-RunLog "sandbox=$codexSandbox"

    $prompt = Get-Content -Path $promptFile -Raw -Encoding UTF8
    $cmdStatus = Invoke-CodexExec -Prompt $prompt

    Write-RunLog ("[{0}] Finished with exit code {1}." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss K"), $cmdStatus)
    if ($cmdStatus -ne 0) {
        exit $cmdStatus
    }

    Publish-Reports
    Sync-LocalCheckoutIfOnlyReportsChanged
    exit 0
} catch {
    Write-RunLog ("[{0}] Failed: {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss K"), $_.Exception.Message)
    exit 1
} finally {
    Remove-Item -Path $gitDir, $workDir -Recurse -Force -ErrorAction SilentlyContinue
    if ($askpassScript) {
        Remove-Item -Path $askpassScript -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
}
