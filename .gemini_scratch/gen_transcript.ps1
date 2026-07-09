$path = "C:\Users\Administrator\.gemini\antigravity-ide\brain\ef1f2370-b315-43bb-8275-82da84653508\.system_generated\logs\transcript.jsonl"
$outPath = "C:\Users\Administrator\.gemini\antigravity-ide\brain\ef1f2370-b315-43bb-8275-82da84653508\conversation_transcript.md"

$lines = Get-Content $path -Encoding UTF8
$md = "# GDrive Player - Full Conversation Transcript`n`n"
$userCount = 0

foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try {
        $obj = ConvertFrom-Json $line
        if ($obj.type -eq "USER_INPUT" -and $obj.content) {
            $userCount++
            $content = $obj.content
            if ($content.Length -gt 2000) { $content = $content.Substring(0, 2000) + "..." }
            $md += "---`n`n## User Message #$userCount`n`n$content`n`n"
        }
        elseif ($obj.type -eq "PLANNER_RESPONSE" -and $obj.content) {
            $content = $obj.content
            if ($content.Length -gt 3000) { $content = $content.Substring(0, 3000) + "..." }
            $md += "## Assistant Response`n`n$content`n`n"
        }
    } catch {
        # skip malformed lines
    }
}

$md | Out-File -FilePath $outPath -Encoding UTF8
Write-Host "Done. Total user messages: $userCount"
