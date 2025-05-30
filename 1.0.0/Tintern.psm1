function Get-TnPlatform {
    # Returns 1 = Windows, 2 = macOS, 3 = Linux
    if ($IsWindows) { return 1 }
    elseif ($IsMacOS) { return 2 }
    elseif ($IsLinux) { return 3 }
    else { return 0 } # Unknown
}

function Get-TnTimeStamp {
    # Returns date and time in format: [2020-02-18 12:12:57]
    return "[{0:dd/MM/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

function Get-TnFSDate {
    # Returns date in format: 2020-02-18
    return "{0:yyyy-MM-dd}" -f (Get-Date)
}

function Write-TnLogMessage {
    param (
        [string]$message
    )

    $platform = Get-TnPlatform

    switch ($platform) {
        1 { $log_filepath = "C:\Logs\$($global:log_name)" }
        2 { $log_filepath = "/Users/Shared/pwsh_logs/$($global:log_name)" }
        3 { $log_filepath = "/pwsh_logs/$($global:log_name)" }
        default { throw "Unknown platform. Cannot determine log path." }
    }

    $log_filepath += "_$(Get-TnFSDate).log"

    $log_dir = Split-Path $log_filepath
    if (-not (Test-Path $log_dir)) {
        New-Item -ItemType Directory -Path $log_dir -Force | Out-Null
    }

    $timestamped_msg = "$(Get-TnTimeStamp) $message"
    $timestamped_msg | Out-File -FilePath $log_filepath -Append

    if ($global:tnDebug) {
        Write-Host $timestamped_msg -ForegroundColor Yellow
    } else {
        Write-Host $timestamped_msg
    }
}

function Write-TnField {
    param (
        [string]$title,
        [string]$value
    )

    Write-Host -NoNewline "$title" -ForegroundColor Green
    Write-Host "$value" -ForegroundColor White
}