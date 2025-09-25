function Connect-TnGraphAppCertApiAccessToken {
    param (
        [string]$vault_api_creds_name,
        #[bool]$debugging = $script:debugging ?? $false
        [switch]$debugging
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

		# $certificate.GetType().FullName

	    # Make sure MSAL.PS is installed
	    if (-not (Get-Module -ListAvailable -Name MSAL.PS)) {
	        Install-Module MSAL.PS -Scope CurrentUser -Force
	    }

	    # Request token via MSAL.PS
	    $msal_token = Get-MsalToken `
	        -ClientId $client_id `
	        -TenantId $tenant_id `
	        -ClientCertificate $certificate `
	        -Scopes "https://graph.microsoft.com/.default" `
	        -ErrorAction Stop

		if ($debugging) {
			$msal_token | format-list *	
		}

	    return $msal_token.AccessToken

    }
    catch {
        Write-TnLogMessage "❌ Connect-MgGraph failed: $($_.Exception.Message)"
        # $Error[0] | Format-List * -Force
        throw
    }

}



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



function Get-TnRecentlyModifiedUsers {
    param (
        [int]$days,
        [string]$only_domain,
        [switch]$debugging
    )

    $since = (Get-Date).AddDays(-$days).ToString("o")

    $logs = Get-MgAuditLogDirectoryAudit -All -Filter "activityDateTime ge $since and (activityDisplayName eq 'Update user')"

    $changed_upns = @()

    foreach ($log in $logs) {
        foreach ($target in $log.TargetResources) {
            if ($target.UserPrincipalName -like "*$only_domain" -and
                $target.UserPrincipalName -notmatch '\d') {

                # Flatten ModifiedProperties into a friendlier structure
                $modProps = @()
                if ($target.ModifiedProperties) {
                    foreach ($prop in $target.ModifiedProperties) {
                        $modProps += [PSCustomObject]@{
                            Property   = $prop.DisplayName
                            OldValue   = $prop.OldValue
                            NewValue   = $prop.NewValue
                        }
                    }
                }

                $changed_upns += [PSCustomObject]@{
                    UserPrincipalName   = $target.UserPrincipalName
                    ActivityDateTime    = $log.ActivityDateTime
					ActivityDateTimeAEST = $(Convert-TnUTCtoAEST -UtcIsoDate (Get-Date $log.ActivityDateTime -Format "o"))
					ActivityDisplayName = $log.ActivityDisplayName
                    Category            = $log.Category
                    AdditionalDetails   = $log.AdditionalDetails -join ', '
                    ModifiedProperties  = $modProps
                }
            }
        }
    }

    if ($debugging) {
        $logs | Format-List
    }

    # Deduplicate by UPN, keep latest change
    $changed_upns = $changed_upns |
                    Sort-Object UserPrincipalName, ActivityDateTimeAEST, ActivityDateTime -Descending |
                    Group-Object UserPrincipalName |
                    ForEach-Object { $_.Group[0] }

    return $changed_upns
}

function Get-TnUserGroups {
    param (
        [string]$upn,
		[switch]$out_json
    )
	
	$user = Get-MgUser -UserId $upn
	$user_groups = (Get-MgUserMemberOf -UserId $user.Id) | Select-Object Id,@{n='DisplayName';e={ $_.AdditionalProperties['displayName'] }}
		
	if ($out_json){
		$user_groups | ConvertTo-Json -Depth 5 | Write-Host
	} else {
		$user_groups
	}
	
}

function Get-TnAllActiveGroups {
	param (
		[string]$filter_string
	)

    Write-TnLogMessage "🔄 Getting all active groups..."

	if ($filter_string){
		$all_groups = Get-MgGroup -All -ConsistencyLevel eventual -CountVariable count -Filter "$filter_string"		
	} else {
		$all_groups = Get-MgGroup -All -ConsistencyLevel eventual -CountVariable count
	}

	Write-TnLogMessage "✅ $($all_groups.Count) active groups returned."

	return $all_groups

}

function Get-TnFilterActiveGroupsByString {
    param(
		[object[]]$all_groups,
		[string]$search_string
	)

	$filtered_groups = $all_groups | Where-Object { $_.DisplayName -like $search_string }
	
	Write-TnLogMessage "Total groups (for search) returned after filtering: $($filtered_groups.Count)"

	return $filtered_groups
}


function Get-TnGroupMembers {
	param (
		[object[]]$groups
	)
	$group_members = @()
	foreach ($group in $groups) {
		$members = Get-MgGroupMember -GroupId $group.Id -All |
		    Select-Object Id,
		                  @{n="DisplayName";e={ $_.AdditionalProperties["displayName"] }},
		                  @{n="UserPrincipalName";e={ $_.AdditionalProperties["userPrincipalName"] }}
						  
		if ($members) { $group_members += $members }
	}
	$group_members = $group_members | Sort-Object id -Unique
	return $group_members
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

	#$caller_name = $caller = (Get-PSCallStack | Where-Object { $_.InvocationInfo.MyCommand.Path })[0].InvocationInfo.MyCommand.Path
	
	$callerFrame = (Get-PSCallStack | Where-Object { $_.InvocationInfo.MyCommand.Path }) | Select-Object -First 1
	if ($callerFrame) {
	    $caller_name = [System.IO.Path]::GetFileNameWithoutExtension($callerFrame.InvocationInfo.MyCommand.Path)
	} else {
	    $caller_name = $null
	}
	
	$caller_name = [System.IO.Path]::GetFileNameWithoutExtension($caller)
    
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

	if ($caller_name){
		$timestamped_msg = "$(Get-TnTimeStamp) <$caller_name> $message"		
	} else {
	    $timestamped_msg = "$(Get-TnTimeStamp) $message"
	}

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

function Convert-TnMACAddressFormat {
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

function Edit-TnTrimScreenRecording {
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

	if ($debugging){
		Write-TnLogMessage "This function requires in put in ISO8601 format (e.g. from AW)."		
	}
	
    $UtcIsoDate = $UtcIsoDate -replace '\sUTC$', ''

    if ($IsMacOS) {
        $utcDate = [DateTime]::Parse($UtcIsoDate, $null, [System.Globalization.DateTimeStyles]::AssumeUniversal)
        $localDate = $utcDate.ToLocalTime()
        return $localDate.ToString("yyyy-MM-dd HH:mm:ss 'AEST'")
    } else {
        Write-TnLogMessage "This function is intended to run on macOS with system timezone set to AEST."
    }
}


function Get-TnVideoFromURL {
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

function Send-TnPushoverNotification {
	
    param(
        [Parameter(Mandatory)][string]$token,
        [Parameter(Mandatory)][string]$user,
        [Parameter(Mandatory)][string]$message,
		[switch]$debugging
    )

    try {
        return Invoke-RestMethod -Uri "https://api.pushover.net/1/messages.json" -Method Post -Form @{
            token   = $token
            user    = $user
            message = $message
        } -ErrorAction Stop
    } catch {
        if ($_.Exception -and $_.ErrorDetails -and $_.ErrorDetails.Message) {
            return $_.ErrorDetails.Message
        } else {
            return @{ error = $_.Exception.Message }
        }
    }

}

function Start-TnScriptMenu {
    
	param(
        [Parameter(Mandatory)][string]$menu_name,
		[Parameter(Mandatory)][object[]]$menu_items,
		[switch]$debugging
    )
	
	
	# Input an indexed object
	Write-Host ""
	Write-Host ("-" * $menu_name.Length)
	Write-Host "$menu_name"
	Write-Host ("-" * $menu_name.Length)
	foreach ($item in $menu_items) {
		if ($item.display -eq $true){
			if ($item.id -eq $null -and $item.name -eq $null){
				Write-Host ""
			} else {
				Write-Host "$($item.id). $($item.name)"					
			}
		}
	}
	Write-Host ""
	return $menu_command = $( Read-Host "What task do you want to run? (enter menu item number or 'exit')" )
	
}




# ---------- JSON Save/Load ----------
# Relies on $global:script_datafile

function Write-TnObjectJSONFile {
    param(
        [Parameter(Mandatory)]$object
    )

    try {
        $json = $object | ConvertTo-Json -Depth 10
        $json | Out-File -FilePath "$global:script_datafile" -Encoding UTF8
        Write-TnLogMessage "💾 Data saved to `"$global:script_datafile`""
    }
    catch {
        Write-TnLogMessage "❌ Failed to save JSON: $_"
    }
}


function Get-TnObjectJSONFile {

    if (Test-Path $global:script_datafile) {
        try {
            $json = Get-Content -Path "$global:script_datafile" -Raw
            Write-TnLogMessage "✅ JSON loaded successfully."
            return $json | ConvertFrom-Json
        }
        catch {
            Write-TnLogMessage "❌ Failed to load JSON."
	        return $false
        }
    }
    else {
        Write-TnLogMessage "⚠️  No existing JSON file found at $global:script_datafile."
        return $false
    }
}
