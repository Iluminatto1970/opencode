param(
  [Parameter(Position = 0)]
  [ValidateSet('update', 'backup', 'cleanup', 'restore', 'status')]
  [string]$Command,
  [switch]$Yes,
  [switch]$DryRun,
  [switch]$Json,
  [switch]$VerboseMode,
  [string]$From
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Version = '1.0.0'
$AppName = 'opencode'

function Log([string]$Message) {
  if (-not $Json) {
    Write-Host "[opencode-safe] $Message"
  }
}

function VLog([string]$Message) {
  if ($VerboseMode) {
    Log $Message
  }
}

function Fail([string]$Message) {
  if ($Json) {
    Write-Output ("{{`"ok`":false,`"error`":`"{0}`"}}" -f $Message.Replace('"', "'"))
  } else {
    Write-Error "[opencode-safe] ERROR: $Message"
  }
  exit 1
}

if (-not $Command) {
  Fail 'Missing command. Use: update | backup | cleanup | restore | status'
}

$LocalAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME 'AppData\Local' }
$AppData = if ($env:APPDATA) { $env:APPDATA } else { Join-Path $HOME 'AppData\Roaming' }

$DataDir = if ($env:OPENCODE_DATA_DIR) { $env:OPENCODE_DATA_DIR } else { Join-Path $LocalAppData $AppName }
$ConfigDir = if ($env:OPENCODE_CONFIG_DIR) { $env:OPENCODE_CONFIG_DIR } else { Join-Path $AppData $AppName }
$StateDir = if ($env:OPENCODE_STATE_DIR) { $env:OPENCODE_STATE_DIR } else { Join-Path $LocalAppData "$AppName\state" }
$BackupRoot = if ($env:OPENCODE_BACKUP_ROOT) { $env:OPENCODE_BACKUP_ROOT } else { Join-Path $HOME '.opencode-backups' }

function EnsureDir([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Copy-IfExists([string]$Source, [string]$Destination) {
  if (Test-Path -LiteralPath $Source) {
    $Parent = Split-Path -Parent $Destination
    if ($Parent) {
      EnsureDir $Parent
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
    VLog "Copied $Source -> $Destination"
  } else {
    VLog "Skipped missing: $Source"
  }
}

function Confirm-OrFail([string]$Action) {
  if (-not $Yes) {
    Fail "$Action requires -Yes"
  }
}

function Backup-Now {
  EnsureDir $BackupRoot
  $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
  $target = Join-Path $BackupRoot $ts
  $archive = Join-Path $BackupRoot ("$ts.zip")

  if (Test-Path -LiteralPath $target) {
    Fail "Backup folder already exists: $target"
  }

  EnsureDir $target
  EnsureDir (Join-Path $target 'data')
  EnsureDir (Join-Path $target 'config')
  EnsureDir (Join-Path $target 'state')

  Copy-IfExists (Join-Path $DataDir 'opencode.db') (Join-Path $target 'data\opencode.db')
  Copy-IfExists (Join-Path $DataDir 'opencode.db-wal') (Join-Path $target 'data\opencode.db-wal')
  Copy-IfExists (Join-Path $DataDir 'opencode.db-shm') (Join-Path $target 'data\opencode.db-shm')
  Copy-IfExists (Join-Path $DataDir 'storage') (Join-Path $target 'data\storage')
  Copy-IfExists (Join-Path $DataDir 'auth.json') (Join-Path $target 'data\auth.json')
  Copy-IfExists $ConfigDir (Join-Path $target 'config\opencode')
  Copy-IfExists $StateDir (Join-Path $target 'state\opencode')

  @(
    "version=$Version"
    "created_at=$ts"
    "source_data_dir=$DataDir"
    "source_config_dir=$ConfigDir"
    "source_state_dir=$StateDir"
  ) | Set-Content -Path (Join-Path $target 'metadata.txt') -Encoding utf8

  Compress-Archive -Path (Join-Path $target '*') -DestinationPath $archive -Force

  if ($Json) {
    Write-Output ("{{`"ok`":true,`"action`":`"backup`",`"folder`":`"{0}`",`"archive`":`"{1}`"}}" -f $target, $archive)
  } else {
    Log 'Backup complete'
    Log "Folder: $target"
    Log "Archive: $archive"
  }
}

function Cleanup-Now {
  $targets = @(
    (Join-Path $env:LOCALAPPDATA 'Temp\opencode'),
    (Join-Path $DataDir 'log'),
    (Join-Path $DataDir 'tool-output'),
    (Join-Path $DataDir 'worktree')
  )

  if ($DryRun) {
    Log 'Dry-run cleanup'
    foreach ($path in $targets) {
      if (Test-Path -LiteralPath $path) {
        Log "Would remove: $path"
      }
    }
    return
  }

  Confirm-OrFail 'cleanup'
  foreach ($path in $targets) {
    if (Test-Path -LiteralPath $path) {
      Remove-Item -LiteralPath $path -Recurse -Force
      VLog "Removed: $path"
    }
  }
  Log 'Cleanup complete'
}

function Resolve-RestoreSource([string]$InputPath) {
  if (Test-Path -LiteralPath $InputPath -PathType Container) {
    return $InputPath
  }

  if (Test-Path -LiteralPath $InputPath -PathType Leaf) {
    $tmp = Join-Path $env:TEMP ("opencode-restore-" + [guid]::NewGuid().ToString())
    EnsureDir $tmp
    Expand-Archive -Path $InputPath -DestinationPath $tmp -Force
    $dirs = Get-ChildItem -Path $tmp -Directory
    if ($dirs.Count -ne 1) {
      Fail 'Archive must contain exactly one folder'
    }
    return $dirs[0].FullName
  }

  Fail "Restore source not found: $InputPath"
}

function Restore-Now {
  if (-not $From) {
    Fail 'restore requires -From <path>'
  }
  Confirm-OrFail 'restore'

  $src = Resolve-RestoreSource $From
  $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
  $snapshot = Join-Path $BackupRoot ("pre-restore-$ts")
  EnsureDir $snapshot

  Copy-IfExists (Join-Path $DataDir 'opencode.db') (Join-Path $snapshot 'opencode.db')
  Copy-IfExists (Join-Path $DataDir 'opencode.db-wal') (Join-Path $snapshot 'opencode.db-wal')
  Copy-IfExists (Join-Path $DataDir 'opencode.db-shm') (Join-Path $snapshot 'opencode.db-shm')
  Copy-IfExists (Join-Path $DataDir 'storage') (Join-Path $snapshot 'storage')
  Copy-IfExists (Join-Path $DataDir 'auth.json') (Join-Path $snapshot 'auth.json')
  Copy-IfExists $ConfigDir (Join-Path $snapshot 'config')
  Copy-IfExists $StateDir (Join-Path $snapshot 'state')

  EnsureDir $DataDir
  EnsureDir $ConfigDir
  EnsureDir $StateDir

  if (Test-Path -LiteralPath (Join-Path $DataDir 'storage')) {
    Remove-Item -LiteralPath (Join-Path $DataDir 'storage') -Recurse -Force
  }
  if (Test-Path -LiteralPath $ConfigDir) {
    Remove-Item -LiteralPath $ConfigDir -Recurse -Force
  }
  if (Test-Path -LiteralPath $StateDir) {
    Remove-Item -LiteralPath $StateDir -Recurse -Force
  }

  EnsureDir $DataDir

  Copy-IfExists (Join-Path $src 'data\opencode.db') (Join-Path $DataDir 'opencode.db')
  Copy-IfExists (Join-Path $src 'data\opencode.db-wal') (Join-Path $DataDir 'opencode.db-wal')
  Copy-IfExists (Join-Path $src 'data\opencode.db-shm') (Join-Path $DataDir 'opencode.db-shm')
  Copy-IfExists (Join-Path $src 'data\storage') (Join-Path $DataDir 'storage')
  Copy-IfExists (Join-Path $src 'data\auth.json') (Join-Path $DataDir 'auth.json')
  Copy-IfExists (Join-Path $src 'config\opencode') $ConfigDir
  Copy-IfExists (Join-Path $src 'state\opencode') $StateDir

  if ($Json) {
    Write-Output ("{{`"ok`":true,`"action`":`"restore`",`"source`":`"{0}`",`"snapshot`":`"{1}`"}}" -f $From, $snapshot)
  } else {
    Log 'Restore complete'
    Log "Safety snapshot: $snapshot"
  }
}

function Status-Now {
  $db = Test-Path -LiteralPath (Join-Path $DataDir 'opencode.db')
  $auth = Test-Path -LiteralPath (Join-Path $DataDir 'auth.json')
  $cfg = Test-Path -LiteralPath $ConfigDir
  $storage = Test-Path -LiteralPath (Join-Path $DataDir 'storage')

  if ($Json) {
    Write-Output ("{{`"ok`":true,`"data_dir`":`"{0}`",`"config_dir`":`"{1}`",`"state_dir`":`"{2}`",`"db`":{3},`"auth`":{4},`"config`":{5},`"storage`":{6}}}" -f $DataDir, $ConfigDir, $StateDir, $db.ToString().ToLower(), $auth.ToString().ToLower(), $cfg.ToString().ToLower(), $storage.ToString().ToLower())
  } else {
    Log "Version: $Version"
    Log "Data dir: $DataDir"
    Log "Config dir: $ConfigDir"
    Log "State dir: $StateDir"
    Log "Found opencode.db: $db"
    Log "Found auth.json: $auth"
    Log "Found config dir: $cfg"
    Log "Found storage dir: $storage"
  }
}

switch ($Command) {
  'backup' { Backup-Now }
  'cleanup' { Cleanup-Now }
  'restore' { Restore-Now }
  'status' { Status-Now }
  'update' {
    Backup-Now
    if ($DryRun) {
      Cleanup-Now
    } else {
      $DryRun = $true
      Cleanup-Now
      $DryRun = $false
      Cleanup-Now
    }
  }
  default { Fail "Unknown command: $Command" }
}
