# Publica uma versão nova do Claude Remote Manager no site CruzVerbenaGroup.
# Uso (na pasta do claude-remote-manager):
#   powershell -ExecutionPolicy Bypass -File ferramentas\Publicar-Versao.ps1 -Versao 1.0.1 -Notas "O que mudou" -Site C:\Projetos\CruzVerbenaGroup
# Grava app\versao.txt, gera <Site>\downloads\claude-remote-manager.zip e atualiza <Site>\versoes.json.
# Depois: commit e push nos dois repositórios. Os PCs se atualizam ao abrir o programa.
param(
    [Parameter(Mandatory = $true)][string]$Versao,
    [string]$Notas = '',
    [Parameter(Mandatory = $true)][string]$Site
)
$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent
$nova = [version]$Versao
$atualTxt = Join-Path $raiz 'app\versao.txt'
$atual = [version]((Get-Content $atualTxt -Raw).Trim())
if ($nova -le $atual) { throw "A versão $Versao precisa ser maior que a atual ($atual)." }
$jsonSite = Join-Path $Site 'versoes.json'
if (-not (Test-Path $jsonSite)) { throw "Não achei $jsonSite. -Site deve ser a pasta do repositório CruzVerbenaGroup." }

[IO.File]::WriteAllText($atualTxt, "$Versao`r`n", (New-Object Text.UTF8Encoding($false)))

$downloads = Join-Path $Site 'downloads'
New-Item -ItemType Directory -Force $downloads | Out-Null
$zip = Join-Path $downloads 'claude-remote-manager.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
# O pacote leva a pasta app e o "Claude Remote Manager.exe" pronto (gerado por ferramentas/Gerar-Exe.sh,
# ou o que estiver na raiz). Basta extrair e abrir o .exe.
$exePronto = Join-Path $raiz 'Claude Remote Manager.exe'
if (-not (Test-Path $exePronto)) { throw "Falta $exePronto (gere com ferramentas/Gerar-Exe.sh ou abra o programa uma vez)." }
$itens = @((Join-Path $raiz 'app'), $exePronto)
Compress-Archive -Path $itens -DestinationPath $zip

$todos = Get-Content $jsonSite -Raw -Encoding UTF8 | ConvertFrom-Json
$entrada = [ordered]@{
    nome    = 'Claude Remote Manager'
    versao  = $Versao
    arquivo = 'claude-remote-manager.zip'
    notas   = $Notas
    data    = (Get-Date -Format 'yyyy-MM-dd')
}
$todos | Add-Member -NotePropertyName 'claude-remote-manager' -NotePropertyValue ([pscustomobject]$entrada) -Force
[IO.File]::WriteAllText($jsonSite, ($todos | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))

Write-Host "Versão $Versao pronta em $zip."
Write-Host 'Agora faça commit e push nos dois repositórios (claude-remote-manager e CruzVerbenaGroup).'
