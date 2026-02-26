Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# === Create the form ===
$form = New-Object System.Windows.Forms.Form
$form.Text = "DNS Query Utility"
$form.Size = New-Object System.Drawing.Size(650, 740)
$form.StartPosition = "CenterScreen"

# === Domain label and input box ===
$label = New-Object System.Windows.Forms.Label
$label.Text = "Domain:"
$label.Location = New-Object System.Drawing.Point(20, 20)
$form.Controls.Add($label)

$domainInput = New-Object System.Windows.Forms.TextBox
$domainInput.Size = New-Object System.Drawing.Size(300, 20)
$domainInput.Location = New-Object System.Drawing.Point(120, 20)
$form.Controls.Add($domainInput)

# === Record Categories ===
$categories = @{
    "Basic" = @("A", "AAAA", "MX", "NS", "CNAME")
    "TXT & Security" = @("TXT", "DMARC", "DKIM")
    "Advanced" = @("SOA", "SRV", "PTR")
}

$checkboxes = @{}

# Function to create a groupbox with checkboxes
function CreateCategoryGroupbox {
    param (
        [string]$name,
        [string[]]$records,
        [int]$x,
        [int]$y
    )

    $groupbox = New-Object System.Windows.Forms.GroupBox
    $groupbox.Text = $name
    $groupbox.Size = New-Object System.Drawing.Size(200, 130)
    $groupbox.Location = New-Object System.Drawing.Point($x, $y)
    $form.Controls.Add($groupbox)

    for ($i=0; $i -lt $records.Count; $i++) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = $records[$i]
        $cb.Location = New-Object System.Drawing.Point(10, (20 + ($i * 22)))
        $cb.AutoSize = $true
        $groupbox.Controls.Add($cb)
        $checkboxes[$records[$i]] = $cb
    }
}

# Create groupboxes for each category
CreateCategoryGroupbox -name "Basic Records" -records $categories["Basic"] -x 20 -y 60
CreateCategoryGroupbox -name "TXT & Security" -records $categories["TXT & Security"] -x 240 -y 60
CreateCategoryGroupbox -name "Advanced Records" -records $categories["Advanced"] -x 460 -y 60

# === Select All / Deselect All buttons ===
$selectAllBtn = New-Object System.Windows.Forms.Button
$selectAllBtn.Text = "Select All"
$selectAllBtn.Size = New-Object System.Drawing.Size(80, 25)
$selectAllBtn.Location = New-Object System.Drawing.Point(20, 200)
$form.Controls.Add($selectAllBtn)

$deselectAllBtn = New-Object System.Windows.Forms.Button
$deselectAllBtn.Text = "Deselect All"
$deselectAllBtn.Size = New-Object System.Drawing.Size(80, 25)
$deselectAllBtn.Location = New-Object System.Drawing.Point(110, 200)
$form.Controls.Add($deselectAllBtn)

$selectAllBtn.Add_Click({
    foreach ($cb in $checkboxes.Values) { $cb.Checked = $true }
})

$deselectAllBtn.Add_Click({
    foreach ($cb in $checkboxes.Values) { $cb.Checked = $false }
})

# === Export checkbox (optional export) ===
$exportCheck = New-Object System.Windows.Forms.CheckBox
$exportCheck.Text = "Enable Export"
$exportCheck.Location = New-Object System.Drawing.Point(20, 230)
$exportCheck.AutoSize = $true
$form.Controls.Add($exportCheck)

# === Export format radio buttons ===
$exportCsv = New-Object System.Windows.Forms.RadioButton
$exportCsv.Text = "CSV"
$exportCsv.Location = New-Object System.Drawing.Point(140, 230)
$exportCsv.Checked = $true
$form.Controls.Add($exportCsv)

$exportJson = New-Object System.Windows.Forms.RadioButton
$exportJson.Text = "JSON"
$exportJson.Location = New-Object System.Drawing.Point(200, 230)
$form.Controls.Add($exportJson)
$exportJson.BringToFront()

# === Output box ===
$outputBox = New-Object System.Windows.Forms.TextBox
$outputBox.Multiline = $true
$outputBox.ScrollBars = "Vertical"
$outputBox.ReadOnly = $true
$outputBox.Font = 'Consolas, 10'
$outputBox.Location = New-Object System.Drawing.Point(20, 270)
$outputBox.Size = New-Object System.Drawing.Size(600, 400)
$form.Controls.Add($outputBox)

# === Query button ===
$btn = New-Object System.Windows.Forms.Button
$btn.Text = "Query DNS"
$btn.Size = New-Object System.Drawing.Size(120, 35)
$btn.Location = New-Object System.Drawing.Point(460, 680)
$form.Controls.Add($btn)

# === SaveFileDialog ===
$saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
$saveFileDialog.InitialDirectory = [Environment]::GetFolderPath("Desktop")

# === Helper: Format output lines nicely ===
function Format-RecordLine {
    param($record)
    # Align Name, Type, and Data with padding
    $name = $record.Name.PadRight(30)
    $type = $record.QueryType.PadRight(6)
    $data = $null
    if ($record.IPAddress) {
        $data += $record.IPAddress
    } elseif ($record.NameHost) {
        $data += $record.NameHost
    } elseif ($record.Strings) {
        $data = ($record.Strings -join ", ")
    } elseif ($record.Text) {
        $data += $record.Text
    } else {
        $data = "[No data]"
    }
    return "$name $type -> $data"
}

# === Query Logic ===
$btn.Add_Click({
    $outputBox.Clear()
    $results = @()
    $domain = $domainInput.Text.Trim()

    if (-not $domain) {
        [System.Windows.Forms.MessageBox]::Show("Please enter a domain.", "Missing Input", "OK", "Warning")
        return
    }

# === Get all selected DNS record types from checkboxes ===
$selectedTypes = $checkboxes.GetEnumerator() |
    Where-Object { $_.Value.Checked } |
    ForEach-Object { $_.Key }

if (-not $selectedTypes) {
    [System.Windows.Forms.MessageBox]::Show("Please select at least one DNS record type.", "No Record Types Selected", "OK", "Warning")
    return
}

$results = @()  # Initialize results array

foreach ($rtype in $selectedTypes) {

    # === Determine which name(s) to query ===
    $queryNames = switch ($rtype) {
        "DMARC" { "_dmarc.$domain" }
        "DKIM"  { @("default._domainkey.$domain", "selector1._domainkey.$domain", "selector2._domainkey.$domain") }
        "SRV"   { @("_sip._tcp.$domain", "_autodiscover._tcp.$domain") }
        "PTR" {
            try {
                $aRec = Resolve-DnsName -Name $domain -Type A -ErrorAction Stop | Select-Object -First 1
                if ($aRec) {
                    $ipParts = $aRec.IPAddress -split '\.'
                    if ($ipParts.Count -eq 4) {
                        "$($ipParts[3]).$($ipParts[2]).$($ipParts[1]).$($ipParts[0]).in-addr.arpa"
                    }
                }
            } catch { @() }
        }
        default { $domain }
    }

    $queryNames = @($queryNames)  # Ensure it's an array

    # === Determine the actual query type for Resolve-DnsName ===
    $actualType = switch ($rtype) {
        "DMARC" { "TXT" }
        "DKIM"  { "TXT" }
        default { $rtype }
    }

    foreach ($query in $queryNames) {
        try {
            $response = Resolve-DnsName -Name $query -Type $actualType -ErrorAction Stop

            foreach ($record in $response) {
                switch ($record.QueryType) {

                    "MX" {
                        # MX record: preference + exchange hostname
                        $preference = $record.Preference
                        $exchange = $record.NameExchange
                        # Optionally resolve IPs of MX hostname
                        $mxIPs = Resolve-DnsName -Name $exchange -Type A -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IPAddress
                        $ipList = if ($mxIPs) { " (IPs: $($mxIPs -join ', '))" } else { "" }
                        $line = "MX Preference: $preference, Exchange: $exchange$ipList"
                        $data = "Preference=$preference; Exchange=$exchange"
                    }

                    "SOA" {
                        # SOA record: show key SOA fields
                        $soa = $record
                        $line = "SOA Record - MName: $($soa.MName), RName: $($soa.RName), Serial: $($soa.SerialNumber), Refresh: $($soa.Refresh), Retry: $($soa.Retry), Expire: $($soa.Expire), MinimumTTL: $($soa.MinimumTTL)"
                        $data = $line
                    }

                    "SRV" {
                        # SRV record: priority, weight, port, target
                        $srv = $record
                        $line = "SRV Priority: $($srv.Priority), Weight: $($srv.Weight), Port: $($srv.Port), Target: $($srv.NameTarget)"
                        $data = $line
                    }

                    "PTR" {
                        # PTR record: target hostname
                        $line = "PTR Target: $($record.NameHost)"
                        $data = $record.NameHost
                    }

                    "TXT" {
                        # TXT record: join strings if multiple
                        $txtStrings = $record.Strings -join " "
                        $line = "TXT Data: $txtStrings"
                        $data = $txtStrings
                    }

                    "A" {
                        # A record: IP address
                        $line = "A Record IP: $($record.IPAddress)"
                        $data = $record.IPAddress
                    }

                    "AAAA" {
                        # AAAA record: IPv6 address
                        $line = "AAAA Record IP: $($record.IPAddress)"
                        $data = $record.IPAddress
                    }

                    "CNAME" {
                        # CNAME record: canonical name target
                        $line = "CNAME Target: $($record.NameHost)"
                        $data = $record.NameHost
                    }

                    "NS" {
                        # NS record: nameserver
                        $line = "NS Target: $($record.NameHost)"
                        $data = $record.NameHost
                    }

                    default {
                        # For any other types, attempt generic display
                        $data = if ($record.IPAddress) { $record.IPAddress }
                                elseif ($record.NameHost) { $record.NameHost }
                                elseif ($record.Strings) { ($record.Strings -join ", ") }
                                elseif ($record.Text) { $record.Text }
                                else { "[No data]" }
                        $line = "$($record.Name) [$($record.QueryType)] : $data"
                    }
                }

                $outputBox.AppendText("$line`r`n")

                $results += [pscustomobject]@{
                    Name = $record.Name
                    Type = $record.QueryType
                    Data = $data
                }
            }

        } catch {
            $outputBox.AppendText("$query [$rtype] -> Record not found or failed.`r`n")
        }
    }
}


    if ($exportCheck.Checked -and $results.Count -gt 0) {
        $saveFileDialog.Filter = if ($exportCsv.Checked) { "CSV Files (*.csv)|*.csv" } else { "JSON Files (*.json)|*.json" }
        $saveFileDialog.Title = "Export DNS Records"

        if ($saveFileDialog.ShowDialog() -eq 'OK') {
            $filePath = $saveFileDialog.FileName
            if ($exportCsv.Checked) {
                $results | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8
            } else {
                $results | ConvertTo-Json -Depth 3 | Set-Content -Path $filePath -Encoding UTF8
            }
            [System.Windows.Forms.MessageBox]::Show("Exported to:`n$filePath", "Export Complete")
        }
    }
    elseif ($exportCheck.Checked -and $results.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No records found to export.", "Export Skipped", "OK", "Information")
    }
})

# === Show the form ===
[void]$form.ShowDialog()
