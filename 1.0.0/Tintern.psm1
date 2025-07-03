function Connect-TnGraphAppCert {
    param (
        [string]$vault_api_creds_name,
		[bool]$debugging = $script:debugging ?? $false
    )

    if (-not $vault_api_creds_name) {
        throw "❌ vault_api_creds_name is required. Specify the name of the 1Password item to retrieve credentials from."
    }

    Write-TnLogMessage "🔐 Connecting to Microsoft Graph using certificate credentials from 1Password item '$vault_api_creds_name'..."

    try {
        $secretItemJson = op item get $vault_api_creds_name --format json 2>$null
        if (-not $secretItemJson) {
            throw "❌ 1Password item '$vault_api_creds_name' not found or accessible."
        }

        $secretItem = $secretItemJson | ConvertFrom-Json
        $client_id   = $secretItem.fields | Where-Object { $_.label -eq "client_id" }   | Select-Object -ExpandProperty value
        $tenant_id   = $secretItem.fields | Where-Object { $_.label -eq "tenant_id" }   | Select-Object -ExpandProperty value
        $cert_base64 = $secretItem.fields | Where-Object { $_.label -eq "cert_base64" } | Select-Object -ExpandProperty value
        $cert_pass   = $secretItem.fields | Where-Object { $_.label -eq "cert_pass" }   | Select-Object -ExpandProperty value

        if (-not $client_id -or -not $tenant_id -or -not $cert_base64 -or [string]::IsNullOrWhiteSpace($cert_pass)) {
            throw "❌ Missing required field(s) in 1Password item '$vault_api_creds_name'. Required: client_id, tenant_id, cert_base64, cert_pass"
        }

        if ($debugging) {
            Write-TnLogMessage "🔎 client_id: $client_id"
            Write-TnLogMessage "🔎 tenant_id: $tenant_id"
        }

        # Convert PFX from base64
        $certBytes = [Convert]::FromBase64String($cert_base64)

        # Set key storage flags
        $certFlags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable -bor `
                     [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet

        # Load X509 certificate from byte array
        $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
            $certBytes,
            (ConvertTo-SecureString $cert_pass -AsPlainText -Force),
            $certFlags
        )


		if ($debugging) {
			write-host $certificate
		}


        # Connect using certificate
        Connect-MgGraph -ClientId $client_id -TenantId $tenant_id -Certificate $certificate -ErrorAction Stop -NoWelcome
        Write-TnLogMessage "✅ Connected to Microsoft Graph as app: $client_id (certificate)"
    }
    catch {
        Write-TnLogMessage "❌ Connect-MgGraph failed: $($_.Exception.Message)"
        # $Error[0] | Format-List * -Force
        throw
    }
}

function Connect-TnGraphAppSecret {
    param (
        [string]$vault_api_creds_name,
        [bool]$debugging = $script:debugging
    )

    if (-not $vault_api_creds_name) {
        throw "❌ vault_api_creds_name is required. Specify the name of the 1Password item to retrieve credentials from."
    }

    Write-TnLogMessage "🔐 Connecting to Microsoft Graph using 1Password item '$vault_api_creds_name'..."

    try {
        $secretItemJson = op item get $vault_api_creds_name --format json 2>$null
        if (-not $secretItemJson) {
            throw "❌ 1Password item '$vault_api_creds_name' not found or accessible."
        }

        $secretItem = $secretItemJson | ConvertFrom-Json
        $client_id = $secretItem.fields | Where-Object { $_.label -eq "client_id" } | Select-Object -ExpandProperty value
        $tenant_id = $secretItem.fields | Where-Object { $_.label -eq "tenant_id" } | Select-Object -ExpandProperty value

        if (-not $client_id -or -not $tenant_id) {
            throw "❌ Required fields (client_id, tenant_id) not found in 1Password item '$vault_api_creds_name'."
        }

        if ($debugging) {
            Write-TnLogMessage "🔎 client_id: $client_id"
            Write-TnLogMessage "🔎 tenant_id: $tenant_id"
        }

        $creds = [PSCredential]::new(
            $client_id,
            ($secretItem.fields | Where-Object { $_.label -eq "secret" } | Select-Object -ExpandProperty value | ConvertTo-SecureString -AsPlainText -Force)
        )

        Connect-MgGraph -TenantId $tenant_id -ClientSecretCredential $creds
        Write-TnLogMessage "✅ Connected to Microsoft Graph as app: $client_id"
    }
    catch {
        Write-TnLogMessage "$_"
        throw
    }
}

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

    if (-not ($($global:log_name))) {
        $global:log_name = "log"
    }

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
	Write-Host -NoNewline ": " -ForegroundColor Green
    Write-Host "$value" -ForegroundColor White
}

function New-TnListEntry {
    param (
        [string]$group_id,
        [string]$site_id,
        [string]$list_id,
        [string]$project_name,
        [string]$project_description
    )

	if (-not $list_id) { throw "Missing parameter: list_id" }
	if (-not $site_id) { throw "Missing parameter: site_id" }
	if (-not $group_id) { throw "Missing parameter: group_id" }
	if (-not $project_name) { throw "Missing parameter: project_name" }
	if (-not $project_description) { throw "Missing parameter: project_description" }

    $upn = (Get-MgContext).Account

    Write-TnLogMessage "Creating Planner Plan..."
	
	# Write-TnLogMessage "New-MgPlannerPlan -Owner $group_id -Title `"$($project_name) Tasks`""
    $plan = New-MgPlannerPlan -Owner $group_id -Title "$($project_name) Tasks"
	
	Write-TnLogMessage "New Task List Created at: https://tasks.office.com/$($upn.Split('@')[1])/Home/PlanViews/$($plan.Id)"
	$plan_url = "https://tasks.office.com/$($upn.Split('@')[1])/Home/PlanViews/$($plan.Id)"

    Write-TnLogMessage "Adding entry to SharePoint list..."
	
	# {[Description, Tasks], [Url, https://planner.cloud.microsoft/webui/plan/y_X8qBX5-Ea7cMyPWV3snMgAHsd4/view/board?tid=1e1659cd-21d7-4da0-a2e5-22666a880027]}


    $userInput = @{
		fields = @{
			"Project Lead" = "6"
			"Title"  = $project_name
			"Description"  = $project_description
	        ## "Planner"      = @{
	        ##     Description = "Tasks"
	        ##     Url         = "$plan_url"
	        ## }
    	}
	}

	# Get all columns from the list
	$columns = Get-MgSiteListColumn -SiteId $site_id -ListId $list_id

	# Create a hashtable mapping DisplayName -> Name
	$columnMap = @{}
	foreach ($col in $columns) {
	    $columnMap[$col.DisplayName] = $col.Name
	}
	
	$columnMap | format-table

	$fields = @{}
	foreach ($key in $userInput.fields.Keys) {
	    if ($key -eq "Title") {
	        $fields["Title"] = $userInput.fields[$key]
	    }
	    elseif ($columnMap.ContainsKey($key)) {
	        $internal = $columnMap[$key]
	        $fields[$internal] = $userInput.fields[$key]
	    }
	}	
	$userInput = @{ fields = $fields }

	$userInput | format-table
	
	$($userInput | ConvertTo-Json -Depth 5)

	Write-TnLogMessage "New-MgSiteListItem -SiteId $site_id -ListId $list_id -BodyParameter $userInput"
    New-MgSiteListItem -SiteId $site_id -ListId $list_id -BodyParameter $userInput -Debug

    Write-TnLogMessage "Project entry created successfully..."
}

function New-TnTemporaryPassword {
	
	$words   = "soda", "star", "sofa", "tree", "seed", "rose", "nest", "crow", "shoe", "nose", "tank", "book", "tent", "home", "soda", "moon", "bird", "dirt", "meat", "milk", "show", "room", "bike", "game", "heat", "mice", "hill", "rock", "mask", "road", "stew", "shop", "sink", "test", "crib"
	$colours = "red", "blue", "white", "green", "pink", "yellow", "mauve", "scarlet", "gray", "violet", "purple"
	$numbers = "1", "2", "3", "4", "5", "6", "7", "8", "9", "0"
	$symbols = "#", "$", "!", "@", "¶"
	$animals = "bird", "dog", "cat", "fish", "ant", "horse", "tiger", "leopard", "bear", "mouse","giraffe","pidgeon"

	$index1 = Get-Random -Maximum $words.Count
	$index2 = Get-Random -Maximum $colours.Count
	$index3 = Get-Random -Maximum $numbers.Count
	$index4 = Get-Random -Maximum $symbols.Count
	$index5 = Get-Random -Maximum $animals.Count

	$part1 = $words[$index1]
	$part2 = $colours[$index2]
	$part3 = $symbols[$index4]
	$part4 = $animals[$index4]
	$part5 = $numbers[$index3]

	$joined = "$part2$part1$part3$part4$part5"

	# Randomize capitalization
	$final = ($joined.ToCharArray() | ForEach-Object {
	    if (Get-Random -Minimum 0 -Maximum 2) { $_.ToString().ToUpper() } else { $_.ToString().ToLower() }
	}) -join ''

	Write-Output $final
	
}

function Get-TnVendorFromOui {
	
	param (
	    [Parameter(Mandatory=$true)][string]$mac
	)

	# Normalize the identifier
	if ($mac -match "^[0-9A-Fa-f]{2}([-:]?[0-9A-Fa-f]{2}){2}([-:]?[0-9A-Fa-f]{2}){0,3}$") {
    
	    $url = "https://api.macvendors.com/$mac"
	    $response = Invoke-RestMethod -Uri $url -Method Get

	    if ($response) {
	        Write-Output "$mac vendor is: $response"
	    } else {
	        Write-Output "$mac not found in database."
	    }
	} else {
	    Write-Output "Invalid MAC address or OUI format"
	    exit 1
	}
	
}

function ConvertTo-TnMACAddress {
    param (
        [Parameter(Mandatory = $true)]
        [string]$MAC,
        [switch]$OutHyphens,
        [switch]$OutSpaces
    )

    # Remove spaces, dashes, and colons
    $cleaned = $MAC -replace '[-:\s]', ''

    # Choose separator
    if ($OutSpaces) {
        $sep = ' '
    } elseif ($OutHyphens) {
        $sep = '-'
    } else {
        $sep = ':'
    }

    # Insert separator every 2 characters
    ($cleaned -split '(.{2})' | Where-Object { $_ }) -join $sep
}

function Trim-TnScreenRecording {
    param(
        [string]$path,
        [string]$startTime,
        [string]$endTime
    )

    if (-not $path)       { $path      = Read-Host "Enter full path to video" }
    if (-not $startTime -and -not $endTime) {
        Write-TnLogMessage "You must specify at least -startTime or -endTime"
        return
    }

    $ffmpeg = "/opt/homebrew/bin/ffmpeg"
    $dir = Split-Path $path
    $name = [System.IO.Path]::GetFileNameWithoutExtension($path)
    $ext = [System.IO.Path]::GetExtension($path)
    $output = Join-Path $dir "$name.trimmed$ext"

    # Trim before cut
    if ($startTime) {
        & $ffmpeg -i $path -ss 00:00:00 -to $startTime -c copy "$dir/part_before.mp4"
    }

    # Trim after cut
    if ($endTime) {
        & $ffmpeg -i $path -ss $endTime -c copy "$dir/part_after.mp4"
    }

    # Create concat file
    $fileList = @()
    if ($startTime) { $fileList += "file 'part_before.mp4'" }
    if ($endTime)   { $fileList += "file 'part_after.mp4'" }

    $fileList | Set-Content -Path "$dir/filelist.txt" -Encoding ascii

    # Combine parts
    Push-Location $dir
    & $ffmpeg -f concat -safe 0 -i "filelist.txt" -c copy "$output"
    Pop-Location

    # Cleanup
    if (Test-Path "$dir/part_before.mp4") { Remove-Item "$dir/part_before.mp4" }
    if (Test-Path "$dir/part_after.mp4")  { Remove-Item "$dir/part_after.mp4" }
    Remove-Item "$dir/filelist.txt"
}


function Get-TnConvertVideoToTargetSize {
    param (
        [string]$input
    )

    $ffmpeg = "/opt/homebrew/bin/ffmpeg"

    if (-not $input) {
        $input = Read-Host "Enter full path to input video"
    }

    $dir = Split-Path $input
    $name = [System.IO.Path]::GetFileNameWithoutExtension($input)
    $ext = [System.IO.Path]::GetExtension($input)
    $output = Join-Path $dir "$name.compressed$ext"

    $targetMB = Read-Host "Enter target file size in MB"
    $targetBytes = [int]$targetMB * 1024 * 1024

    # Get video duration in seconds
    $duration = & $ffmpeg -i $input 2>&1 | ForEach-Object {
        if ($_ -match "Duration: (\d{2}):(\d{2}):(\d{2})") {
            $h = [int]$matches[1]; $m = [int]$matches[2]; $s = [int]$matches[3]
            return ($h * 3600) + ($m * 60) + $s
        }
    }

    if (-not $duration) {
        Write-TnLogMessage "Could not determine video duration."
        return
    }

    # Total bitrate in bits/sec
	$adjustedTargetBytes = [math]::Floor($targetBytes * 0.92)
	$total_bitrate = [math]::Floor(($adjustedTargetBytes * 8) / $duration)
    $audio_bitrate = 128000  # 128 kbps
    $videon_bitrate = $total_bitrate - $audio_bitrate

    Write-TnLogMessage "Duration: $duration sec"
    Write-TnLogMessage "Target bitrate: $total_bitrate bps (video: $video_bitrate bps)"

    # 2-pass encode
    & $ffmpeg -y -i $input -c:v libx264 -b:v $video_bitrate -pass 1 -an -f mp4 /dev/null
    & $ffmpeg -i $input -c:v libx264 -b:v $video_bitrate -pass 2 -c:a aac -b:a 128k $output

    Write-TnLogMessage "Compressed video written to: $output"
}



function Convert-TnUTCtoAEST {
    param (
        [Parameter(Mandatory)]
        [string]$UtcIsoDate
    )

	Write-TnLogMessage "This function requires in put in ISO8601 format (e.g. from AW)."
    $UtcIsoDate = $UtcIsoDate -replace '\sUTC$', ''

    if ($IsMacOS) {
        $utcDate = [DateTime]::Parse($UtcIsoDate, $null, [System.Globalization.DateTimeStyles]::AssumeUniversal)
        $localDate = $utcDate.ToLocalTime()
        return $localDate.ToString("yyyy-MM-dd HH:mm:ss 'AEST'")
    } else {
        Write-TnLogMessage "This function is intended to run on macOS with system timezone set to AEST."
    }
}


function Download-TnVideo {
    param(
        [Parameter(Mandatory)]
        [string]$url,
        [switch]$keep_audio,
		[switch]$debugging
    )

	if ($debugging) {
		$global:tnDebug = $true
	}

	# Write-Output $global:tnDebug

    $yt_dlp = "/opt/homebrew/bin/yt-dlp"
    $ffmpeg = "/opt/homebrew/bin/ffmpeg"
    $output_dir = "/Users/Shared/downloaded-videos/yt_video_$date_$(Get-Random)"
	$date = Get-TnFSDate
	
	Write-TnLogMessage "$output_dir.%(ext)s"

    # Download best video+audio
    & "$yt_dlp" "-f" "bv*+ba/b" "--ffmpeg-location" "$ffmpeg" "$url" "-o" "$output_dir.%(ext)s"
	$downloaded_file = Get-ChildItem -Path "/Users/Shared/downloaded-videos" -Filter "$(Split-Path $output_dir -Leaf).*" | Select-Object -First 1
    Write-TnLogMessage "Video saved to $downloaded_file"

    # Convert to h264 + aac in a .mp4
	& "$ffmpeg" -i "$downloaded_file" -c:v libx264 -c:a aac -movflags +faststart "$($output_dir)_output.mp4"
    Write-TnLogMessage "Video converted to $output_dir.output.mp4"

    # Optionally extract audio
    if ($keep_audio) {
		& "$ffmpeg" -i "$output_dir.*"-vn -c:a aac -b:a 192k "$($output_dir)_output.m4a"
	}

}