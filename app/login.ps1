# Janela de login de uma conta do Claude Code (aberta pelo Claude Remote Manager).
param([string]$Conta, [string]$Nome, [string]$Email, [string]$Claude)

$Host.UI.RawUI.WindowTitle = "Login do Claude - $Nome"
if ($Conta -and $Conta -ne 'padrao') { $env:CLAUDE_CONFIG_DIR = $Conta } else { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }

Write-Host ''
Write-Host "  Login da conta do remote `"$Nome`"" -ForegroundColor Cyan
Write-Host ''
Write-Host '  O navegador vai abrir na página de login do Claude.'
Write-Host '  Entre com a conta certa para este remote.'
Write-Host '  Se o navegador já estiver logado em outra conta, saia dela'
Write-Host '  ou aperte C aqui para copiar o link e cole numa janela anônima.'
Write-Host ''

$a = @('auth', 'login')
if ($Email -and $Email -ne '-') { $a += @('--email', $Email) }
& $Claude @a

Write-Host ''
Write-Host '  Pronto. Esta janela fecha sozinha.' -ForegroundColor Green
Start-Sleep -Seconds 3
