# dream-team — install the MCP version for mahcode (Windows / PowerShell). install == update.
#
#   irm https://raw.githubusercontent.com/neoff/dream-team/main/install.ps1 | iex
#
# Run from the project root. Installs .mahcode/skills, .mahcode/dream-team.yaml (if missing),
# the @dream-team block in AGENTS.md, .mcp.json with the mahcode server and runs `mahcode mcp trust`.
$ErrorActionPreference = 'Stop'
$Repo   = 'neoff/dream-team'
$Branch = if ($env:DREAM_TEAM_BRANCH) { $env:DREAM_TEAM_BRANCH } else { 'main' }
$Proj   = (Get-Location).Path
$Tmp    = Join-Path ([IO.Path]::GetTempPath()) ("dream-team-" + [guid]::NewGuid())

Write-Host "> Fetching $Repo@$Branch ..."
New-Item -ItemType Directory -Path $Tmp | Out-Null
$zip = Join-Path $Tmp 'src.zip'
Invoke-WebRequest "https://codeload.github.com/$Repo/zip/refs/heads/$Branch" -OutFile $zip
Expand-Archive $zip -DestinationPath $Tmp
$Src = Join-Path $Tmp "dream-team-$Branch"

$Dst = Join-Path $Proj '.mahcode'
New-Item -ItemType Directory -Force -Path (Join-Path $Dst 'skills') | Out-Null
foreach ($s in 'dream-team','agent-planner','agent-critic','agent-coder','agent-reviewer','agent-tester','agent-debugger') {
  $t = Join-Path $Dst "skills\$s"
  if (Test-Path $t) { Remove-Item -Recurse -Force $t }
  Copy-Item -Recurse (Join-Path $Src ".mahcode\skills\$s") $t
}
$yaml = Join-Path $Dst 'dream-team.yaml'
if (Test-Path $yaml) { Write-Host "ok dream-team.yaml already exists — leaving the project's models alone" }
else { Copy-Item (Join-Path $Src '.mahcode\dream-team.yaml') $yaml; Write-Host "ok created .mahcode\dream-team.yaml (adjust the models for the project)" }

# AGENTS.md: entry block (idempotent, by markers)
$ag = Join-Path $Proj 'AGENTS.md'
$block = Get-Content -Raw (Join-Path $Src '.mahcode\templates\AGENTS.dream-team.md')
$text = if (Test-Path $ag) { Get-Content -Raw $ag } else { '' }
$text = [regex]::Replace($text, '(?s)\r?\n?<!-- >>> dream-team >>> -->.*?<!-- <<< dream-team <<< -->\r?\n?', '')
Set-Content -Path $ag -Value ($text.TrimEnd() + "`n`n" + $block) -NoNewline
Write-Host "ok AGENTS.md: @dream-team entry"

# .mcp.json: mahcode MCP for the project's native sessions
$mcp = Join-Path $Proj '.mcp.json'
if (-not (Test-Path $mcp)) {
  Set-Content -Path $mcp -Value '{ "mcpServers": { "mahcode": { "command": "mahcode", "args": ["mcp", "serve"] } } }'
} elseif (-not (Select-String -Path $mcp -Pattern '"mahcode"' -Quiet)) {
  Write-Warning ".mcp.json already exists — add the mahcode server (command: mahcode, args: [mcp, serve]) manually"
}
if (Get-Command mahcode -ErrorAction SilentlyContinue) { mahcode mcp trust | Out-Null; Write-Host "ok mahcode mcp trust" }
Write-Warning "For the manager/leads to work on codex/claude/agy, register the mahcode MCP in their configs (see README)."
Remove-Item -Recurse -Force $Tmp
Write-Host "`nDone. In a mahcode session of this project: @dream-team new: <task>"
