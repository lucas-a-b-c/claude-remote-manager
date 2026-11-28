# Claude Remote Manager - atualização automática pelo site CruzVerbenaGroup.
# Com a janela aberta, pergunta ao site qual é a versão publicada (ao abrir e a cada 10 min). Se for mais nova,
# mostra um aviso com o botão Atualizar agora, que baixa o pacote, instala por cima desta pasta e reabre o programa.
# O login do site fica salvo por usuário do Windows (criptografado com DPAPI) em
# %USERPROFILE%\.claude-remote-manager\site-login.xml. Sem internet ou com o site fora do ar, segue sem atualizar.

$script:AtuApp      = 'claude-remote-manager'
$script:AtuRaiz     = Split-Path $PSScriptRoot -Parent
$script:AtuVersao   = Join-Path $PSScriptRoot 'versao.txt'
$script:AtuSiteJson = Join-Path $PSScriptRoot 'site.json'
$script:AtuLogin    = Join-Path (Join-Path $env:USERPROFILE '.claude-remote-manager') 'site-login.xml'

function Get-VersaoLocal {
    try { return [version]((Get-Content $script:AtuVersao -Raw).Trim()) } catch { return [version]'0.0.0' }
}

function Get-SiteUrl {
    try { return ((Get-Content $script:AtuSiteJson -Raw -Encoding UTF8 | ConvertFrom-Json).url).TrimEnd('/') } catch { return $null }
}

function Get-LoginSite([switch]$Pedir) {
    if (-not $Pedir -and (Test-Path $script:AtuLogin)) {
        try { return Import-Clixml $script:AtuLogin } catch { }
    }
    if (-not $Pedir) { return $null }
    return (Show-LoginSite)
}

# Pede o login do site numa janelinha (sem depender do console do PowerShell).
function Show-LoginSite {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $d = New-Object Windows.Forms.Form
    $d.Text = 'Login do site CruzVerbenaGroup'
    $d.Size = New-Object Drawing.Size(420, 230); $d.FormBorderStyle = 'FixedDialog'; $d.StartPosition = 'CenterScreen'
    $d.MaximizeBox = $false; $d.MinimizeBox = $false; $d.TopMost = $true
    $d.Font = New-Object Drawing.Font('Segoe UI', 9.5)
    $l = New-Object Windows.Forms.Label; $l.Text = 'Para o programa se atualizar sozinho, entre com o login do site (só uma vez neste PC).'
    $l.Location = New-Object Drawing.Point(14, 12); $l.Size = New-Object Drawing.Size(380, 40); $d.Controls.Add($l)
    $l1 = New-Object Windows.Forms.Label; $l1.Text = 'Login'; $l1.Location = New-Object Drawing.Point(14, 62); $l1.AutoSize = $true; $d.Controls.Add($l1)
    $tU = New-Object Windows.Forms.TextBox; $tU.Location = New-Object Drawing.Point(90, 59); $tU.Width = 300; $d.Controls.Add($tU)
    $l2 = New-Object Windows.Forms.Label; $l2.Text = 'Senha'; $l2.Location = New-Object Drawing.Point(14, 96); $l2.AutoSize = $true; $d.Controls.Add($l2)
    $tS = New-Object Windows.Forms.TextBox; $tS.Location = New-Object Drawing.Point(90, 93); $tS.Width = 300; $tS.UseSystemPasswordChar = $true; $d.Controls.Add($tS)
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Entrar'; $ok.Location = New-Object Drawing.Point(204, 140); $ok.Width = 90; $ok.DialogResult = 'OK'
    $ca = New-Object Windows.Forms.Button; $ca.Text = 'Agora não'; $ca.Location = New-Object Drawing.Point(300, 140); $ca.Width = 90; $ca.DialogResult = 'Cancel'
    $d.Controls.Add($ok); $d.Controls.Add($ca); $d.AcceptButton = $ok; $d.CancelButton = $ca
    if ($d.ShowDialog() -ne 'OK' -or -not $tU.Text -or -not $tS.Text) { return $null }
    $sec = ConvertTo-SecureString $tS.Text -AsPlainText -Force
    return (New-Object Management.Automation.PSCredential($tU.Text.Trim(), $sec))
}

function Save-LoginSite($cred) {
    $dir = Split-Path $script:AtuLogin -Parent
    New-Item -ItemType Directory -Force $dir | Out-Null
    $cred | Export-Clixml $script:AtuLogin
}

function New-ClienteSite($cred) {
    $wc = New-Object Net.WebClient
    $par = $cred.UserName + ':' + $cred.GetNetworkCredential().Password
    $wc.Headers['Authorization'] = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($par))
    $wc.Headers['User-Agent'] = 'claude-remote-manager'
    $wc.Encoding = [Text.Encoding]::UTF8
    return $wc
}

# Devolve o objeto da versão publicada, $null se não deu para consultar.
function Get-VersaoSite([switch]$PodePedirLogin) {
    $url = Get-SiteUrl
    if (-not $url) { return $null }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $cred = Get-LoginSite
    for ($tentativa = 0; $tentativa -lt 3; $tentativa++) {
        if (-not $cred) {
            if (-not $PodePedirLogin) { return $null }
            $cred = Get-LoginSite -Pedir
            if (-not $cred) { return $null }
        }
        try {
            $par = $cred.UserName + ':' + $cred.GetNetworkCredential().Password
            $cab = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($par)) }
            $info = Invoke-RestMethod -Uri "$url/api/versao/$($script:AtuApp)" -Headers $cab -UseBasicParsing -TimeoutSec 10 -UserAgent 'claude-remote-manager'
            Save-LoginSite $cred
            $info | Add-Member -NotePropertyName Credencial -NotePropertyValue $cred -Force
            $info | Add-Member -NotePropertyName Site -NotePropertyValue $url -Force
            return $info
        } catch [Net.WebException] {
            $r = $_.Exception.Response
            if ($r -and [int]$r.StatusCode -eq 401) {
                if (Test-Path $script:AtuLogin) { Remove-Item $script:AtuLogin -Force -ErrorAction SilentlyContinue }
                $cred = $null
                continue
            }
            return $null
        } catch { return $null }
    }
    return $null
}

# Devolve as informações da versão publicada se ela for mais nova que a deste PC; senão $null.
function Get-AtualizacaoDisponivel([switch]$PodePedirLogin) {
    $info = Get-VersaoSite -PodePedirLogin:$PodePedirLogin
    if (-not $info -or -not $info.versao) { return $null }
    try { $nova = [version]$info.versao } catch { return $null }
    if ($nova -le (Get-VersaoLocal)) { return $null }
    return $info
}

# Baixa e instala por cima desta pasta. Devolve $true quando instalou (quem chamou deve reabrir o programa).
function Install-Atualizacao($info) {
    $tmp = Join-Path $env:TEMP ("crm-atualizacao-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $tmp | Out-Null
    try {
        $zip = Join-Path $tmp 'pacote.zip'
        $wc = New-ClienteSite $info.Credencial
        $wc.DownloadFile($info.Site + $info.url, $zip)
        $dest = Join-Path $tmp 'pacote'
        Expand-Archive -Path $zip -DestinationPath $dest -Force
        # Confere que o pacote tem a cara do programa antes de copiar por cima.
        if (-not (Test-Path (Join-Path $dest 'app\Janela.ps1'))) { return $false }
        # Atualiza a pasta app inteira. Arquivos soltos na raiz (o .bat, o README) só são atualizados
        # se ainda existem: se você apagou, a atualização não traz de volta.
        Copy-Item -Path (Join-Path $dest 'app\*') -Destination $PSScriptRoot -Recurse -Force
        foreach ($f in Get-ChildItem $dest -File) {
            $alvo = Join-Path $script:AtuRaiz $f.Name
            if (Test-Path $alvo) { Copy-Item $f.FullName $alvo -Force }
        }
        return $true
    } catch {
        return $false
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Abre o programa de novo (já atualizado) num processo novo.
function Start-ProgramaDeNovo {
    $janela = Join-Path $PSScriptRoot 'Janela.ps1'
    # Abre pelo PowerShell, que refaz o .exe se o código dele mudou e passa para ele.
    Remove-Item Env:CRM_EXE -ErrorAction SilentlyContinue
    Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-STA', '-File', "`"$janela`"")
}
