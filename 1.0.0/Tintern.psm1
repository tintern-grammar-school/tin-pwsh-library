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

    Write-TNLogMessage "Creating Planner Plan..."
	
	# Write-TNLogMessage "New-MgPlannerPlan -Owner $group_id -Title `"$($project_name) Tasks`""
    $plan = New-MgPlannerPlan -Owner $group_id -Title "$($project_name) Tasks"
	
	Write-TNLogMessage "New Task List Created at: https://tasks.office.com/$($upn.Split('@')[1])/Home/PlanViews/$($plan.Id)"
	$plan_url = "https://tasks.office.com/$($upn.Split('@')[1])/Home/PlanViews/$($plan.Id)"

    Write-TNLogMessage "Adding entry to SharePoint list..."
	
	# {[Description, Tasks], [Url, https://planner.cloud.microsoft/webui/plan/y_X8qBX5-Ea7cMyPWV3snMgAHsd4/view/board?tid=1e1659cd-21d7-4da0-a2e5-22666a880027]}


    $userInput = @{
		fields = @{
			## "Project Lead" = $upn
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

	## $fields = @{}
	## foreach ($key in $userInput.fields.Keys) {
	##     if ($key -eq "Title") {
	##         $fields["Title"] = $userInput.fields[$key]
	##     }
	##     elseif ($columnMap.ContainsKey($key)) {
	##         $internal = $columnMap[$key]
	##         $fields[$internal] = $userInput.fields[$key]
	##     }
	## }	
	## $userInput = @{ fields = $fields }

	$userInput | format-table
	
	$($userInput | ConvertTo-Json -Depth 5)

	Write-TNLogMessage "New-MgSiteListItem -SiteId $site_id -ListId $list_id -BodyParameter $userInput"
    New-MgSiteListItem -SiteId $site_id -ListId $list_id -BodyParameter $userInput -Debug

    Write-TNLogMessage "Project entry created successfully..."
}