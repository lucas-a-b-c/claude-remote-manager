# Teste no Windows (usado pelo GitHub Actions): cria um remote de teste, abre o .exe em modo de teste
# (CRM_TESTE) e confere que a janela leu o estado sem erro e sem travar.
$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $raiz 'Claude Remote Manager.exe'
if (-not (Test-Path $exe)) { throw "Falta $exe" }
. (Join-Path $raiz 'app\Nucleo.ps1')
New-Item -ItemType Directory -Force 'C:\crm-teste' | Out-Null
Save-Remote (New-Remote 'Teste CI' '' 'C:\crm-teste')
Save-Remote (New-Remote 'Teste CI conta 2' (Join-Path $env:USERPROFILE '.claude-contas\teste-ci') 'C:\crm-teste')

# Pergunta "Enable Remote Control?": detecta no saida.log e responde no .claude.json da conta.
$rt = New-Remote 'Teste pergunta' (Join-Path $env:USERPROFILE '.claude-contas\teste-pergunta') 'C:\crm-teste'
New-Item -ItemType Directory -Force (Get-RcDir $rt) | Out-Null
[IO.File]::WriteAllText((Join-Path (Get-RcDir $rt) 'saida.log'), "Take this session with you...`r`nEnable Remote Control? (y/n) ")
if (-not (Test-PerguntaRC $rt)) { throw 'Test-PerguntaRC não viu a pergunta.' }
if (Test-RemoteAceito $rt.conta) { throw 'Test-RemoteAceito deveria ser falso numa conta nova.' }
Set-RemoteAceito $rt.conta
if (-not (Test-RemoteAceito $rt.conta)) { throw 'Set-RemoteAceito não gravou remoteDialogSeen.' }
Set-Confianca $rt.conta 'C:\crm-teste'
if (-not (Test-RemoteAceito $rt.conta)) { throw 'Set-Confianca apagou remoteDialogSeen.' }
Write-Host 'Pergunta Enable Remote Control: OK'

$saida = Join-Path $env:RUNNER_TEMP 'crm-resultado.txt'
$tela = Join-Path $env:RUNNER_TEMP 'crm-tela.png'
Remove-Item $saida -ErrorAction SilentlyContinue
$env:CRM_TESTE = $saida
$inicio = Get-Date
$p = Start-Process -FilePath $exe -WorkingDirectory $raiz -PassThru
while (-not (Test-Path $saida) -and ((Get-Date) - $inicio).TotalSeconds -lt 200) { Start-Sleep -Seconds 2 }
$seg = [int]((Get-Date) - $inicio).TotalSeconds
try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object Drawing.Bitmap($b.Width, $b.Height)
    [Drawing.Graphics]::FromImage($bmp).CopyFromScreen($b.Location, [Drawing.Point]::Empty, $b.Size)
    $bmp.Save($tela)
} catch { Write-Host "Sem captura de tela: $($_.Exception.Message)" }
Start-Sleep -Seconds 3
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
$falhou = Join-Path $env:USERPROFILE '.claude-remote-manager\exe-falhou.txt'
if (Test-Path $falhou) { Write-Host '--- exe-falhou.txt'; Get-Content $falhou }
if (-not (Test-Path $saida)) { throw "A janela não gravou o resultado em $seg s (travou ou fechou com erro)." }
$txt = Get-Content $saida -Raw
Write-Host "--- resultado em $seg s"
Write-Host $txt
if ($txt -notmatch 'RESULTADO: OK') { throw 'A leitura do estado não terminou bem.' }
if ($txt -notmatch 'LINHA: Teste CI') { throw 'A lista não mostrou o remote de teste.' }
if ($txt -match 'ERRO|aviso:') { throw 'Apareceu erro no registro.' }
if ($txt -match 'SUB: .*sem administrador') { throw 'Abriu sem administrador.' }
Write-Host 'OK'
