# dream-team — установка MCP-версии для mahcode (Windows / PowerShell). install == update.
#
#   irm https://raw.githubusercontent.com/neoff/dream-team/main/install.ps1 | iex
#
# Запускать из корня проекта. Ставит .mahcode/skills, .mahcode/dream-team.yaml (если его нет),
# блок @dream-team в AGENTS.md, .mcp.json с сервером mahcode и выполняет `mahcode mcp trust`.
$ErrorActionPreference = 'Stop'
$Repo   = 'neoff/dream-team'
$Branch = if ($env:DREAM_TEAM_BRANCH) { $env:DREAM_TEAM_BRANCH } else { 'main' }
$Proj   = (Get-Location).Path
$Tmp    = Join-Path ([IO.Path]::GetTempPath()) ("dream-team-" + [guid]::NewGuid())

Write-Host "> Качаю $Repo@$Branch ..."
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
if (Test-Path $yaml) { Write-Host "ok dream-team.yaml уже есть — модели проекта не трогаю" }
else { Copy-Item (Join-Path $Src '.mahcode\dream-team.yaml') $yaml; Write-Host "ok создан .mahcode\dream-team.yaml (поправь модели под проект)" }

# AGENTS.md: блок-вход (идемпотентно, по маркерам)
$ag = Join-Path $Proj 'AGENTS.md'
$block = Get-Content -Raw (Join-Path $Src '.mahcode\templates\AGENTS.dream-team.md')
$text = if (Test-Path $ag) { Get-Content -Raw $ag } else { '' }
$text = [regex]::Replace($text, '(?s)\r?\n?<!-- >>> dream-team >>> -->.*?<!-- <<< dream-team <<< -->\r?\n?', '')
Set-Content -Path $ag -Value ($text.TrimEnd() + "`n`n" + $block) -NoNewline
Write-Host "ok AGENTS.md: вход @dream-team"

# .mcp.json: MCP mahcode для нативных сессий проекта
$mcp = Join-Path $Proj '.mcp.json'
if (-not (Test-Path $mcp)) {
  Set-Content -Path $mcp -Value '{ "mcpServers": { "mahcode": { "command": "mahcode", "args": ["mcp", "serve"] } } }'
} elseif (-not (Select-String -Path $mcp -Pattern '"mahcode"' -Quiet)) {
  Write-Warning ".mcp.json уже есть — добавь сервер mahcode (command: mahcode, args: [mcp, serve]) вручную"
}
if (Get-Command mahcode -ErrorAction SilentlyContinue) { mahcode mcp trust | Out-Null; Write-Host "ok mahcode mcp trust" }
Write-Warning "Чтобы менеджер/лиды работали на codex/claude/agy, зарегистрируй MCP mahcode в их конфигах (см. README)."
Remove-Item -Recurse -Force $Tmp
Write-Host "`nГотово. В сессии mahcode этого проекта: @dream-team new: <задача>"
