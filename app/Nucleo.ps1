# Claude Remote Manager - núcleo: remotes, contas (CLAUDE_CONFIG_DIR), tarefas agendadas, login e testes.
# Usado pela janela (Janela.ps1) e pelo modo sem janela (-ConsertarTudo).

Add-Type -AssemblyName System.Web.Extensions

$script:Base      = Join-Path $env:USERPROFILE '.claude-remote-manager'
$script:Arquivo   = Join-Path $script:Base 'remotes.json'
$script:ContasDir = Join-Path $env:USERPROFILE '.claude-contas'
$script:AppDir    = $PSScriptRoot
$script:Modelos   = Join-Path $PSScriptRoot 'modelos.json'
$script:OnLog     = $null      # scriptblock que recebe cada linha de log (a janela define)
$script:OnEspera  = $null      # scriptblock chamado durante esperas (a janela processa eventos)
$script:PodeLogar = $true      # false no modo automático: nunca abre janela de login

$script:PadraoMarcador = 'padrao'

# Passo atual da leitura em segundo plano (a janela mostra se demorar).
function Set-Passo([string]$t) { if ($global:PassoFundo) { $global:PassoFundo['p'] = $t } }

function Say([string]$m) {
    if ($script:OnLog) { & $script:OnLog $m } else { Write-Host $m }
}

# Espera sem travar a janela: dorme em pedaços curtos e deixa a janela responder entre eles.
function Wait-Um([int]$ms = 300) {
    $fim = (Get-Date).AddMilliseconds($ms)
    do {
        if ($script:OnEspera) { & $script:OnEspera }
        Start-Sleep -Milliseconds 40
    } while ((Get-Date) -lt $fim)
}

# Mostra no registro as últimas linhas do log do Remote Control (para saber por que não subiu).
function Show-FimDoLog($r, [int]$linhas = 8) {
    $dir = Get-RcDir $r
    $achou = $false
    foreach ($nome in 'saida.log', 'remote-control.log', 'debug.log') {
        $log = Join-Path $dir $nome
        if (-not (Test-Path $log)) { continue }
        $achou = $true
        $t = @(Get-Content $log -Tail 60 -ErrorAction SilentlyContinue | ForEach-Object { ($_ -replace '\x1b\[[0-9;?]*[A-Za-z]', '' -replace '\x1b\][^\x07]*\x07', '').Trim() } | Where-Object { $_ })
        if (-not $t.Count) { Say "  ($nome está vazio)"; continue }
        Say "  Últimas linhas do ${nome}:"
        foreach ($l in ($t | Select-Object -Last $linhas)) { Say "    $l" }
    }
    if (-not $achou) { Say "  (nenhum log em ${dir}: o Windows não chegou a rodar o lançador)" }
}

function Test-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ClaudeExe {
    $p = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
    if (Test-Path $p) { return $p }
    $c = Get-Command claude.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    throw 'Não achei o claude.exe. Instale o Claude Code neste PC primeiro.'
}

function Get-ClaudeVersao {
    try { return ((& (Get-ClaudeExe) --version 2>$null) -join ' ').Trim() } catch { return '?' }
}

function ConvertTo-Slug([string]$s) {
    $n = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $n.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne 'NonSpacingMark') { [void]$sb.Append($ch) }
    }
    $r = ($sb.ToString().ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if (-not $r) { $r = 'remote' }
    return $r
}

function Test-TemTexto($texto, $parte) {
    if (-not $texto -or -not $parte) { return $false }
    return $texto.IndexOf($parte, [StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Test-MesmaPasta($a, $b) {
    if (-not $a -or -not $b) { return $false }
    return [string]::Equals($a.TrimEnd('\'), $b.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
}

# ---------------------------------------------------------------- contas

# Uma conta é uma pasta de configuração do Claude Code. '' = a padrão do Windows (%USERPROFILE%\.claude).
function Get-ContaDir($conta) {
    if ([string]::IsNullOrEmpty($conta)) { return (Join-Path $env:USERPROFILE '.claude') }
    return $conta
}

function Get-ContaJson($conta) {
    if ([string]::IsNullOrEmpty($conta)) { return (Join-Path $env:USERPROFILE '.claude.json') }
    return (Join-Path $conta '.claude.json')
}

function Get-ContaRotulo($conta) {
    if ([string]::IsNullOrEmpty($conta)) { return 'padrão do Windows (.claude)' }
    return (Split-Path $conta -Leaf)
}

function Get-ContasConhecidas {
    $l = @('')
    if (Test-Path $script:ContasDir) {
        $l += @(Get-ChildItem $script:ContasDir -Directory | ForEach-Object { $_.FullName })
    }
    foreach ($r in Read-Remotes) { if ($r.conta -and ($l -notcontains $r.conta)) { $l += $r.conta } }
    return $l
}

function Invoke-Claude($conta, [string[]]$argumentos) {
    $ErrorActionPreference = 'Continue'
    $antigo = $env:CLAUDE_CONFIG_DIR
    $enc = [Console]::OutputEncoding
    try {
        try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
        if ($conta) { $env:CLAUDE_CONFIG_DIR = $conta } else { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
        $saida = & (Get-ClaudeExe) @argumentos 2>$null
        return (@($saida) -join "`n")
    } finally {
        try { [Console]::OutputEncoding = $enc } catch {}
        if ($antigo) { $env:CLAUDE_CONFIG_DIR = $antigo } else { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
    }
}

function Get-Login($conta) {
    $txt = Invoke-Claude $conta @('auth', 'status', '--json')
    try { $j = $txt | ConvertFrom-Json } catch { $j = $null }
    if (-not $j) { return [pscustomobject]@{ logado = $false; email = ''; plano = ''; expira = ''; erro = $txt } }
    return [pscustomobject]@{
        logado = [bool]$j.loggedIn; email = [string]$j.email; plano = [string]$j.subscriptionType
        expira = [string]$j.loginExpiresAt; erro = ''
    }
}

# ---------------------------------------------------------------- login pelo próprio programa
# O "claude auth login" roda escondido (sem terminal). O programa pega o link de login, abre no
# navegador (de preferência numa janela anônima, para não usar a conta já logada no navegador)
# e tem uma caixa para colar o código que o site mostra. O código vai limpo para o processo.
# Se o navegador completar o login sozinho (sem código), o programa percebe e fecha.

function Find-NavegadorAnonimo {
    $edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")
    $chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")
    foreach ($e in $edge) { if ($e -and (Test-Path $e)) { return @{ exe = $e; arg = '--inprivate'; nome = 'Edge (InPrivate)' } } }
    foreach ($c in $chrome) { if ($c -and (Test-Path $c)) { return @{ exe = $c; arg = '--incognito'; nome = 'Chrome (anônima)' } } }
    return $null
}

# Abre a URL numa janela anônima. Nunca espera o navegador (esperar travava a janela de login).
function Open-Anonimo([string]$url) {
    $n = Find-NavegadorAnonimo
    try {
        if ($n) { Start-Process -FilePath $n.exe -ArgumentList @($n.arg, "`"$url`"") | Out-Null }
        else { Start-Process $url | Out-Null }
    } catch {
        Say "  Não consegui abrir o navegador: $($_.Exception.Message). Use Copiar link."
    }
}

function Read-Compartilhado([string]$arq) {
    if (-not (Test-Path $arq)) { return '' }
    try {
        $fs = [IO.File]::Open($arq, 'Open', 'Read', 'ReadWrite')
        try { $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8); return $sr.ReadToEnd() } finally { $fs.Dispose() }
    } catch { return '' }
}

# Processos "claude auth login" ainda vivos. O claude.exe pode passar o trabalho para outro processo
# (ex.: quando se atualiza sozinho) e terminar; por isso não dá para confiar só no processo que abrimos.
function Get-ProcessosLogin {
    return @(Get-CimInstance Win32_Process -Filter "Name='claude.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match '\sauth\s+login(\s|$)' })
}

function Stop-Arvore($p) {
    if ($p -and -not $p.HasExited) { & taskkill.exe /PID $p.Id /T /F 2>$null | Out-Null }
    foreach ($w in Get-ProcessosLogin) { & taskkill.exe /PID $w.ProcessId /T /F 2>$null | Out-Null }
}

function Start-ProcessoLogin($r, [string]$saida) {
    Remove-Item $saida -Force -ErrorAction SilentlyContinue
    $exe = Get-ClaudeExe
    $emailArg = if ($r.email) { " --email `"$($r.email)`"" } else { '' }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $env:ComSpec
    $psi.Arguments = "/d /s /c `"`"$exe`" auth login$emailArg > `"$saida`" 2>&1`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    # O claude abre o navegador sozinho (na janela normal, que pode estar logada na conta errada).
    # Ele usa o programa da variável BROWSER: apontamos para um que não faz nada (where.exe só
    # procura um arquivo e sai). O navegador só abre quando a pessoa clica no botão.
    $psi.EnvironmentVariables['BROWSER'] = Join-Path $env:WINDIR 'System32\where.exe'
    if ($r.conta) { $psi.EnvironmentVariables['CLAUDE_CONFIG_DIR'] = $r.conta }
    elseif ($psi.EnvironmentVariables.ContainsKey('CLAUDE_CONFIG_DIR')) { $psi.EnvironmentVariables.Remove('CLAUDE_CONFIG_DIR') }
    return [Diagnostics.Process]::Start($psi)
}

# Abre a janela de login da conta e espera o usuário terminar. Devolve $true se a conta ficou logada.
function Start-Login($r) {
    if (-not $script:PodeLogar) { Say "  Login necessário em '$($r.nome)': abra o programa neste PC e clique em Entrar na conta."; return $false }
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $dir = Get-RcDir $r
    New-Item -ItemType Directory -Force $dir | Out-Null
    if ($r.conta) { New-Item -ItemType Directory -Force $r.conta | Out-Null }
    $saida = Join-Path $dir 'login-saida.txt'
    $nav = Find-NavegadorAnonimo
    Say "  Abrindo o login da conta de '$($r.nome)'."

    $st = @{ p = $null; url = ''; enviado = $false; ok = $false; checagem = (Get-Date); conta = (Get-Date) }
    $fonteL = New-Object Drawing.Font('Segoe UI', 10)
    $d = New-Object Windows.Forms.Form
    $d.Text = "Entrar na conta - $($r.nome)"
    $d.Size = New-Object Drawing.Size(620, 430); $d.FormBorderStyle = 'FixedDialog'; $d.StartPosition = 'CenterScreen'
    $d.MaximizeBox = $false; $d.MinimizeBox = $false; $d.Font = $fonteL; $d.TopMost = $true

    function New-Rotulo($texto, $y, $alt = 22, $negrito = $false) {
        $l = New-Object Windows.Forms.Label; $l.Text = $texto; $l.AutoSize = $false
        $l.Location = New-Object Drawing.Point(16, $y); $l.Size = New-Object Drawing.Size(575, $alt)
        if ($negrito) { $l.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold) }
        $d.Controls.Add($l); return $l
    }
    [void](New-Rotulo "1. Abra o login e entre com a conta certa para '$($r.nome)'." 14 22 $true)
    $nomeNav = if ($nav) { "Abrir em janela anônima ($($nav.nome))" } else { 'Abrir no navegador' }
    [void](New-Rotulo 'A janela anônima evita entrar sem querer com a conta que já está logada no navegador. Se mesmo assim abrir sozinha uma aba comum do Claude, feche essa aba.' 38 40)
    $bAbrir = New-Object Windows.Forms.Button; $bAbrir.Text = $nomeNav; $bAbrir.Location = New-Object Drawing.Point(16, 84); $bAbrir.Size = New-Object Drawing.Size(330, 34); $bAbrir.Enabled = $false
    $bCopiar = New-Object Windows.Forms.Button; $bCopiar.Text = 'Copiar link'; $bCopiar.Location = New-Object Drawing.Point(356, 84); $bCopiar.Size = New-Object Drawing.Size(120, 34); $bCopiar.Enabled = $false
    $d.Controls.Add($bAbrir); $d.Controls.Add($bCopiar)
    [void](New-Rotulo '2. Depois de entrar e autorizar, o site mostra um código. Copie e cole aqui:' 136 22 $true)
    $tCodigo = New-Object Windows.Forms.TextBox; $tCodigo.Location = New-Object Drawing.Point(16, 164); $tCodigo.Size = New-Object Drawing.Size(460, 28); $tCodigo.Enabled = $false
    $bEntrar = New-Object Windows.Forms.Button; $bEntrar.Text = 'Entrar'; $bEntrar.Location = New-Object Drawing.Point(486, 162); $bEntrar.Size = New-Object Drawing.Size(105, 32); $bEntrar.Enabled = $false
    $bEntrar.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
    $d.Controls.Add($tCodigo); $d.Controls.Add($bEntrar); $d.AcceptButton = $bEntrar
    $lStatus = New-Rotulo 'Preparando o login...' 214 110
    $bNovo = New-Object Windows.Forms.Button; $bNovo.Text = 'Gerar novo link'; $bNovo.Location = New-Object Drawing.Point(16, 340); $bNovo.Size = New-Object Drawing.Size(150, 32); $bNovo.Visible = $false
    $bFechar = New-Object Windows.Forms.Button; $bFechar.Text = 'Cancelar'; $bFechar.Location = New-Object Drawing.Point(486, 340); $bFechar.Size = New-Object Drawing.Size(105, 32); $bFechar.DialogResult = 'Cancel'
    $d.Controls.Add($bNovo); $d.Controls.Add($bFechar); $d.CancelButton = $bFechar

    $iniciar = {
        Stop-Arvore $st.p
        $st.url = ''; $st.enviado = $false; $st.checagem = Get-Date
        $bAbrir.Enabled = $false; $bCopiar.Enabled = $false; $tCodigo.Enabled = $false; $bEntrar.Enabled = $false; $bNovo.Visible = $false
        $tCodigo.Text = ''
        $lStatus.ForeColor = [Drawing.SystemColors]::ControlText
        $lStatus.Text = 'Preparando o login...'
        try { $st.p = Start-ProcessoLogin $r $saida }
        catch { $lStatus.ForeColor = [Drawing.Color]::Firebrick; $lStatus.Text = "Não consegui iniciar o login: $($_.Exception.Message)"; $bNovo.Visible = $true }
    }

    $relogioL = New-Object Windows.Forms.Timer
    $relogioL.Interval = 500
    $relogioL.Add_Tick({
        $txt = Read-Compartilhado $saida
        if (-not $st.url -and $txt -match '(https://[^\s\x1b\x07"]+/oauth/authorize[^\s\x1b\x07"]*)') {
            $st.url = $Matches[1]
            $bAbrir.Enabled = $true; $bCopiar.Enabled = $true; $tCodigo.Enabled = $true; $bEntrar.Enabled = $true
            $lStatus.Text = 'Pronto. Clique no botão do passo 1.'
        }
        if ($txt -match 'Login successful') { $relogioL.Stop(); $st.ok = $true; $d.DialogResult = 'OK'; $d.Close(); return }
        $falhou = $txt -match "Couldn't log in"
        $agora = Get-Date
        if (-not $falhou -and $st.p -and $st.p.HasExited -and (($agora - $st.checagem).TotalSeconds -ge 3)) {
            # O processo que abrimos terminou: só é falha se nenhum "claude auth login" continua rodando.
            $st.checagem = $agora
            if (-not (Get-ProcessosLogin)) { $falhou = $true }
        }
        if (-not $falhou -and $st.enviado -and (($agora - $st.conta).TotalSeconds -ge 5)) {
            $st.conta = $agora
            if ((Get-Login $r.conta).logado) { $relogioL.Stop(); $st.ok = $true; $d.DialogResult = 'OK'; $d.Close(); return }
        }
        if ($falhou) {
            $relogioL.Stop()
            if ((Get-Login $r.conta).logado) { $st.ok = $true; $d.DialogResult = 'OK'; $d.Close(); return }
            $linhas = @($txt -split "`r?`n" | ForEach-Object { ($_ -replace '\x1b\[[0-9;]*[A-Za-z]', '' -replace '\x1b\][^\x07\x1b]*(\x07|\x1b\\)', '').Trim() } | Where-Object { $_ })
            $erro = @($linhas | Where-Object { $_ -match "Couldn't log in|error|failed" }) | Select-Object -Last 1
            if ($erro -match "wasn't accepted|incomplete|expired|already used") {
                $erro = 'O código não foi aceito. Ele pode ter sido copiado pela metade, já ter sido usado, ou ser de uma tentativa anterior. Clique em Gerar novo link e faça de novo, usando o link novo.'
            } elseif (-not $erro) {
                $cod = '?'
                try { $cod = $st.p.ExitCode } catch { }
                $erro = "O login do Claude fechou sozinho (código $cod) sem dizer o motivo. A saída ficou em $saida."
            }
            $lStatus.ForeColor = [Drawing.Color]::Firebrick
            $lStatus.Text = "Não deu certo. $erro"
            $bAbrir.Enabled = $false; $bCopiar.Enabled = $false; $tCodigo.Enabled = $false; $bEntrar.Enabled = $false
            $bNovo.Visible = $true
        }
    })

    $bAbrir.Add_Click({ if ($st.url) { Open-Anonimo $st.url; $lStatus.Text = 'Entre no navegador com a conta certa e autorize. Depois cole o código no passo 2. Se o navegador não abriu, use Copiar link e cole numa janela anônima.'; [void]$tCodigo.Focus() } })
    $bCopiar.Add_Click({ if ($st.url) { [Windows.Forms.Clipboard]::SetText($st.url); $lStatus.Text = 'Link copiado. Cole numa janela anônima do navegador.' } })
    $bEntrar.Add_Click({
        $c = ($tCodigo.Text -replace '\s', '').Trim('"', "'", '`')
        if (-not $c) { $lStatus.Text = 'Cole o código que o site mostrou.'; return }
        if (-not $st.p) { return }
        try {
            $st.p.StandardInput.WriteLine($c)
            $st.p.StandardInput.Flush()
            $st.enviado = $true
            $bEntrar.Enabled = $false; $tCodigo.Enabled = $false
            $lStatus.ForeColor = [Drawing.SystemColors]::ControlText
            $lStatus.Text = 'Conferindo o código...'
        } catch { $lStatus.Text = "Não consegui enviar o código: $($_.Exception.Message)" }
    })
    $bNovo.Add_Click({ & $iniciar; $relogioL.Start() })
    $d.Add_Shown({ & $iniciar; $relogioL.Start() })

    [void]$d.ShowDialog()
    $relogioL.Stop()
    Stop-Arvore $st.p

    $l = Get-Login $r.conta
    if ($l.logado) {
        Say "  Logado como $($l.email)."
        # Login novo: a marca de falha antiga não vale mais (senão o programa pediria login de novo).
        foreach ($f in 'FALHA-LOGIN.txt', 'falha-desde.txt') { Remove-Item (Join-Path $dir $f) -Force -ErrorAction SilentlyContinue }
        return $true
    }
    Say '  O login não foi concluído.'
    return $false
}

# ---------------------------------------------------------------- confiança na pasta e config inicial

function New-Serializador {
    $s = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $s.MaxJsonLength = [int]::MaxValue
    $s.RecursionLimit = 1000
    return $s
}

function Get-ChaveProjeto([string]$pasta) { return (($pasta -replace '\\', '/').TrimEnd('/')) }

function Test-Confianca($conta, $pasta) {
    $f = Get-ContaJson $conta
    if (-not (Test-Path $f)) { return $false }
    try { $d = (New-Serializador).DeserializeObject([IO.File]::ReadAllText($f)) } catch { return $false }
    if (-not $d -or -not $d.ContainsKey('projects')) { return $false }
    $p = $d['projects']
    $chave = Get-ChaveProjeto $pasta
    # A confiança numa pasta vale para as subpastas.
    while ($chave) {
        foreach ($k in $p.Keys) {
            if ([string]::Equals($k, $chave, [StringComparison]::OrdinalIgnoreCase) -and $p[$k] -is [Collections.IDictionary] -and $p[$k]['hasTrustDialogAccepted'] -eq $true) { return $true }
        }
        $i = $chave.LastIndexOf('/')
        if ($i -lt 3) { break }
        $chave = $chave.Substring(0, $i)
    }
    return $false
}

function Set-Confianca($conta, $pasta) {
    $f = Get-ContaJson $conta
    $s = New-Serializador
    $d = $null
    if (Test-Path $f) {
        $d = $s.DeserializeObject([IO.File]::ReadAllText($f))
        Copy-Item $f "$f.antes-remote-manager" -Force
    }
    if (-not $d) { $d = [System.Collections.Generic.Dictionary[string,object]]::new() }
    if (-not $d.ContainsKey('projects')) { $d['projects'] = [System.Collections.Generic.Dictionary[string,object]]::new() }
    $p = $d['projects']
    $chave = Get-ChaveProjeto $pasta
    if (-not $p.ContainsKey($chave)) { $p[$chave] = [System.Collections.Generic.Dictionary[string,object]]::new() }
    $p[$chave]['hasTrustDialogAccepted'] = $true
    if (-not $d.ContainsKey('hasCompletedOnboarding')) { $d['hasCompletedOnboarding'] = $true }
    New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
    [IO.File]::WriteAllText($f, $s.Serialize($d), (New-Object Text.UTF8Encoding $false))
}

# Conta nova: copia o settings.json da conta padrão (preferências, sem login).
function Initialize-Conta($conta) {
    if (-not $conta) { return }
    New-Item -ItemType Directory -Force $conta | Out-Null
    $origem = Join-Path $env:USERPROFILE '.claude\settings.json'
    $destino = Join-Path $conta 'settings.json'
    if ((Test-Path $origem) -and -not (Test-Path $destino)) {
        Copy-Item $origem $destino
        Say '  Copiei as preferências (settings.json) da conta padrão.'
    }
}

# ---------------------------------------------------------------- remotes salvos

function Read-Remotes {
    if (-not (Test-Path $script:Arquivo)) { return @() }
    $j = [IO.File]::ReadAllText($script:Arquivo) | ConvertFrom-Json
    return @($j.remotes | Where-Object { $_ })
}

function Save-Remotes($lista) {
    New-Item -ItemType Directory -Force $script:Base | Out-Null
    $tmp = "$($script:Arquivo).tmp"
    $json = [pscustomobject]@{ versao = 1; remotes = @($lista) } | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding $false))
    Move-Item $tmp $script:Arquivo -Force
}

function New-Remote([string]$nome, [string]$conta, [string]$pasta, [string]$spawn = 'same-dir', [string]$tarefa = '') {
    $id = ConvertTo-Slug $nome
    $ids = @(Read-Remotes | ForEach-Object { $_.id })
    $base = $id; $n = 2
    while ($ids -contains $id) { $id = "$base-$n"; $n++ }
    if (-not $tarefa) { $tarefa = "Claude Remote Control - $nome" }
    return [pscustomobject]@{
        id = $id; nome = $nome; conta = $conta; pasta = $pasta; spawn = $spawn; tarefa = $tarefa
        email = ''; nomesAntigos = @()
    }
}

function Save-Remote($r) {
    $l = @(Read-Remotes | Where-Object { $_.id -ne $r.id })
    $l += $r
    Save-Remotes $l
}

function Remove-RemoteSalvo($r) { Save-Remotes @(Read-Remotes | Where-Object { $_.id -ne $r.id }) }

function Get-Oem { return [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) }

function Test-NomeValido([string]$nome) {
    if (-not $nome -or -not $nome.Trim()) { return 'Dê um nome ao remote.' }
    if ($nome -match '["%^!<>|&]') { return 'O nome não pode ter " % ^ ! < > | &' }
    $oem = Get-Oem
    if ($oem.GetString($oem.GetBytes($nome)) -ne $nome) { return 'O nome tem um caractere que o Windows não aceita no script.' }
    return ''
}

function Get-RcDir($r) { return (Join-Path $script:Base "rc\$($r.id)") }
function Get-Lancador($r) { return (Join-Path (Get-RcDir $r) 'iniciar.cmd') }

# ---------------------------------------------------------------- lançador (.cmd) e tarefa agendada

function Get-LancadorTexto($r) {
    $dir = Get-RcDir $r
    $exe = Get-ClaudeExe
    $setConta = if ($r.conta) { "set `"CLAUDE_CONFIG_DIR=$($r.conta)`"" } else { 'set "CLAUDE_CONFIG_DIR="' }
    $contaTxt = Get-ContaRotulo $r.conta
    $t = @"
@echo off
rem Gerado pelo Claude Remote Manager. Nao edite a mao: use o programa (Gerenciar Remote Control.bat).
rem Remote: $($r.nome) / conta: $contaTxt
rem A tarefa agendada "$($r.tarefa)" roda este script no boot, sem login no Windows e sem janela, e o reinicia se ele terminar.
cd /d "$($r.pasta)"
$setConta
set "DIR=$dir"
set "LOG=%DIR%\remote-control.log"
set "DBG=%DIR%\debug.log"
set "FALHA=%DIR%\FALHA-LOGIN.txt"
if exist "%LOG%" move /y "%LOG%" "%LOG%.old" >nul
if exist "%DBG%" move /y "%DBG%" "%DBG%.old" >nul
forfiles /p "%DIR%" /m bridge-transcript-*.jsonl /d -7 /c "cmd /c del @path" >nul 2>&1
forfiles /p "%DIR%" /m debug-cse_*.log* /d -7 /c "cmd /c del @path" >nul 2>&1
echo %date% %time%> "%DIR%\ultimo-inicio.txt"
"$exe" remote-control --spawn $($r.spawn) --name "$($r.nome)" --debug-file "%DBG%" > "%DIR%\saida.log" 2> "%LOG%"
set "RC=%errorlevel%"
findstr /i /c:"logged in" /c:"auth login" /c:"401" /c:"expired" /c:"unauthorized" "%LOG%" >nul
if %errorlevel%==0 goto falhou
if exist "%FALHA%" del /q "%FALHA%"
if exist "%DIR%\falha-desde.txt" del /q "%DIR%\falha-desde.txt"
exit /b %RC%

:falhou
if not exist "%DIR%\falha-desde.txt" echo %date% %time%> "%DIR%\falha-desde.txt"
set /p DESDE=<"%DIR%\falha-desde.txt"
(
  echo FALHA DE LOGIN DO CLAUDE - o Remote Control "$($r.nome)" nao sobe.
  echo Correcao: abrir o Claude Remote Manager neste PC e clicar em Entrar na conta.
  echo Primeira falha: %DESDE%
  echo Ultima tentativa: %date% %time% ^(codigo %RC%^)
  echo.
  type "%LOG%"
) > "%FALHA%"
exit /b %RC%
"@
    return ($t -replace "`r?`n", "`r`n")
}

function Test-Lancador($r) {
    $f = Get-Lancador $r
    if (-not (Test-Path $f)) { return $false }
    return ([IO.File]::ReadAllText($f, (Get-Oem)) -eq (Get-LancadorTexto $r))
}

function Write-Lancador($r) {
    New-Item -ItemType Directory -Force (Get-RcDir $r) | Out-Null
    [IO.File]::WriteAllText((Get-Lancador $r), (Get-LancadorTexto $r), (Get-Oem))
}

function Get-TarefaXml($r) {
    $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $desc = [Security.SecurityElement]::Escape("Claude Remote Manager: Remote Control '$($r.nome)' (conta $(Get-ContaRotulo $r.conta)) na pasta $($r.pasta).")
    $argumentos = [Security.SecurityElement]::Escape("/c `"$(Get-Lancador $r)`"")
    $pasta = [Security.SecurityElement]::Escape($r.pasta)
    return @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>$desc</Description>
  </RegistrationInfo>
  <Principals>
    <Principal id="Author">
      <UserId>$sid</UserId>
      <LogonType>S4U</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <RestartOnFailure>
      <Count>999</Count>
      <Interval>PT1M</Interval>
    </RestartOnFailure>
    <StartWhenAvailable>true</StartWhenAvailable>
    <Enabled>true</Enabled>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
  </Settings>
  <Triggers>
    <BootTrigger>
      <Delay>PT30S</Delay>
    </BootTrigger>
    <TimeTrigger>
      <StartBoundary>2026-01-01T00:00:00</StartBoundary>
      <Repetition>
        <Interval>PT5M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
    </TimeTrigger>
    <EventTrigger>
      <Delay>PT30S</Delay>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
  </Triggers>
  <Actions Context="Author">
    <Exec>
      <Command>cmd.exe</Command>
      <Arguments>$argumentos</Arguments>
      <WorkingDirectory>$pasta</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@
}

# Lista o que está diferente do esperado na tarefa agendada (vazio = tarefa certa).
function Test-Tarefa($r) {
    $t = Get-ScheduledTask -TaskName $r.tarefa -ErrorAction SilentlyContinue
    if (-not $t) { return @('a tarefa agendada não existe') }
    $p = @()
    try { $x = [xml](Export-ScheduledTask -TaskName $r.tarefa) } catch { return @('não consegui ler a tarefa agendada') }
    $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $pr = $x.Task.Principals.Principal
    if ($pr.LogonType -ne 'S4U') { $p += 'a tarefa não roda sem login (S4U)' }
    if ($pr.UserId -ne $sid -and $pr.UserId -notlike "*\$env:USERNAME" -and $pr.UserId -ne $env:USERNAME) { $p += 'a tarefa roda com outro usuário' }
    $ex = @($x.Task.Actions.Exec)
    if ($ex.Count -ne 1 -or $ex[0].Command -ne 'cmd.exe' -or -not (Test-TemTexto $ex[0].Arguments (Get-Lancador $r))) { $p += 'a tarefa não chama o lançador deste remote' }
    elseif (-not (Test-MesmaPasta $ex[0].WorkingDirectory $r.pasta)) { $p += 'a tarefa está em outra pasta' }
    if (-not $x.Task.Triggers.BootTrigger) { $p += 'a tarefa não sobe com o Windows' }
    if ($x.Task.Triggers.TimeTrigger.Repetition.Interval -ne 'PT5M') { $p += 'a tarefa não confere a cada 5 minutos' }
    $s = $x.Task.Settings
    if ($s.Enabled -eq 'false' -or $t.State -eq 'Disabled') { $p += 'a tarefa está desativada' }
    if ($s.ExecutionTimeLimit -ne 'PT0S') { $p += 'a tarefa tem limite de tempo' }
    if (-not $s.RestartOnFailure) { $p += 'a tarefa não reinicia se cair' }
    if ($s.MultipleInstancesPolicy -ne 'IgnoreNew') { $p += 'a tarefa pode abrir duas cópias' }
    return $p
}

# Atualizar a tarefa não derruba o processo que ela já iniciou (testado).
function Register-Tarefa($r) {
    Register-ScheduledTask -TaskName $r.tarefa -Xml (Get-TarefaXml $r) -Force -ErrorAction Stop | Out-Null
}

# ---------------------------------------------------------------- processos e estado

function Get-ProcessosRC {
    return @(Get-CimInstance Win32_Process -Filter "Name='claude.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match '\sremote-control(\s|$)' })
}

function Find-Processo($r, $procs) {
    $dbg = Join-Path (Get-RcDir $r) 'debug.log'
    foreach ($p in $procs) { if (Test-TemTexto $p.CommandLine $dbg) { return $p } }
    $nomes = @($r.nome) + @($r.nomesAntigos)
    foreach ($p in $procs) {
        foreach ($n in $nomes) { if ($n -and (Test-TemTexto $p.CommandLine "--name `"$n`"")) { return $p } }
    }
    return $null
}

function Get-DebugDoProcesso($p) {
    if ($p -and $p.CommandLine -match '--debug-file\s+"([^"]+)"') { return $Matches[1] }
    if ($p -and $p.CommandLine -match '--debug-file\s+(\S+)') { return $Matches[1] }
    return $null
}

function Get-Sessoes($p) {
    if (-not $p) { return 0 }
    return @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.ProcessId) AND Name='claude.exe'" -ErrorAction SilentlyContinue).Count
}

# Lê o fim do log de depuração e diz se o remote está registrado no claude.ai.
function Get-Conexao($p) {
    if (-not $p) { return 'parado' }
    $f = Get-DebugDoProcesso $p
    $novo = $false
    try { if ($p.CreationDate) { $novo = (((Get-Date) - [datetime]$p.CreationDate).TotalMinutes -lt 3) } } catch { }
    if (-not $f -or -not (Test-Path $f)) { if ($novo) { return 'iniciando' } else { return 'sem log' } }
    $txt = @(Get-Content $f -Tail 400 -ErrorAction SilentlyContinue)
    # O Windows nem sempre atualiza a data de um arquivo que continua aberto: usa também a hora escrita na última linha.
    $quando = (Get-Item $f).LastWriteTime
    for ($i = $txt.Count - 1; $i -ge 0 -and $i -ge $txt.Count - 30; $i--) {
        if ($txt[$i] -match '(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z)') {
            try { $h = ([DateTimeOffset]::Parse($Matches[1])).LocalDateTime; if ($h -gt $quando) { $quando = $h } } catch { }
            break
        }
    }
    $idade = (Get-Date) - $quando
    $iReg = -1; $iRuim = -1
    for ($i = 0; $i -lt $txt.Count; $i++) {
        if ($txt[$i] -match 'Registered, server environmentId|work/poll -> 200|heartbeat -> 200') { $iReg = $i }
        elseif ($txt[$i] -match 'giving up|Registration failed') { $iRuim = $i }
    }
    if ($iRuim -gt $iReg) { return 'com erro' }
    if ($iReg -lt 0 -and $novo) { return 'iniciando' }
    if ($idade.TotalMinutes -gt 15) { return "sem sinal há $([int]$idade.TotalMinutes) min" }
    return 'conectado'
}

function Get-Estado($r, $procs) {
    Set-Passo "'$($r.nome)': processo"
    $p = Find-Processo $r $procs
    Set-Passo "'$($r.nome)': login da conta (claude auth status)"
    $login = Get-Login $r.conta
    Set-Passo "'$($r.nome)': tarefa, lançador e pasta"
    $falha = Join-Path (Get-RcDir $r) 'FALHA-LOGIN.txt'
    $problemas = @()
    if (-not (Test-Path $r.pasta)) { $problemas += 'a pasta de trabalho não existe' }
    if (-not $login.logado) { $problemas += 'a conta não está logada' }
    elseif ((Test-Path $falha) -and -not $p) { $problemas += 'o login expirou (o Remote Control não consegue subir)' }
    $problemas += @(Test-Tarefa $r)
    if (-not (Test-Lancador $r)) { $problemas += 'o lançador precisa ser criado ou atualizado' }
    if ((Test-Path $r.pasta) -and -not (Test-Confianca $r.conta $r.pasta)) { $problemas += 'a pasta não está marcada como confiável nesta conta' }
    if (-not $p) { $problemas += 'o Remote Control não está rodando' }
    Set-Passo "'$($r.nome)': conexão (debug.log)"
    $conexao = Get-Conexao $p
    if ($p -and $conexao -eq 'iniciando') { $problemas += 'o Remote Control acabou de subir e ainda está registrando no claude.ai (leva até uns 3 minutos)' }
    elseif ($p -and $conexao -ne 'conectado') { $problemas += "o Remote Control está rodando, mas não conectou no claude.ai (conexão: $conexao)" }
    $nomeAntigo = [bool]($p -and -not (Test-TemTexto $p.CommandLine "--name `"$($r.nome)`""))
    return [pscustomobject]@{
        processo = $p; login = $login; problemas = $problemas; conexao = $conexao
        sessoes = $(Set-Passo "'$($r.nome)': sessões"; Get-Sessoes $p); nomeAntigo = $nomeAntigo
    }
}

# ---------------------------------------------------------------- ações

# O remote registrou no claude.ai? Olha o log do processo que está rodando agora (o lançador zera o
# debug.log a cada início). Lê o arquivo mesmo aberto pelo claude e não confia na data dele.
function Test-Registrou($r) {
    $p = Find-Processo $r (Get-ProcessosRC)
    if (-not $p) { return $false }
    $f = Get-DebugDoProcesso $p
    if (-not $f) { $f = Join-Path (Get-RcDir $r) 'debug.log' }
    return ((Read-Compartilhado $f) -match 'Registered, server environmentId|work/poll -> 200|heartbeat -> 200')
}

function Wait-Registro($r, [int]$segundos = 90) {
    $falha = Join-Path (Get-RcDir $r) 'FALHA-LOGIN.txt'
    $marca = Join-Path (Get-RcDir $r) 'ultimo-inicio.txt'
    $inicio = Get-Date
    $reenviado = $false
    while (((Get-Date) - $inicio).TotalSeconds -lt $segundos) {
        Wait-Um 1000
        # Se o Windows não executou o lançador em 20 s, pede de novo uma vez.
        if (-not $reenviado -and ((Get-Date) - $inicio).TotalSeconds -gt 20 -and
            -not ((Test-Path $marca) -and (Get-Item $marca).LastWriteTime -ge $inicio.AddSeconds(-5))) {
            $reenviado = $true
            Stop-ScheduledTask -TaskName $r.tarefa -ErrorAction SilentlyContinue
            Start-ScheduledTask -TaskName $r.tarefa -ErrorAction SilentlyContinue
        }
        if (((Get-Date) - $inicio).TotalSeconds -ge 4 -and (Test-Registrou $r)) { return 'ok' }
        if ((Test-Path $falha) -and (Get-Item $falha).LastWriteTime -ge $inicio) { return 'login' }
    }
    return 'tempo'
}

function Start-Remote($r) {
    Start-ScheduledTask -TaskName $r.tarefa -ErrorAction Stop
    Say '  Tarefa iniciada; esperando o Remote Control registrar no claude.ai...'
    switch (Wait-Registro $r) {
        'ok'    { Say "  OK: '$($r.nome)' subiu e está conectado."; return $true }
        'login' { Say '  O Remote Control não subiu: o Claude diz que a conta não está logada.'; Show-FimDoLog $r; return $false }
        default {
            if (Find-Processo $r (Get-ProcessosRC)) {
                Say '  Está rodando, mas em 90 s ainda não confirmou o registro no claude.ai. A lista continua conferindo sozinha a cada minuto.'
            } else { Say '  Não subiu em 90 s.' }
            Show-FimDoLog $r; return $false
        }
    }
}

function Stop-Remote($r) {
    $p = Find-Processo $r (Get-ProcessosRC)
    Stop-ScheduledTask -TaskName $r.tarefa -ErrorAction SilentlyContinue
    if ($p) { & taskkill.exe /PID $p.ProcessId /T /F | Out-Null }
    for ($i = 0; $i -lt 20; $i++) {
        $t = Get-ScheduledTask -TaskName $r.tarefa -ErrorAction SilentlyContinue
        if (-not $t -or $t.State -ne 'Running') { break }
        Wait-Um 500
    }
}

function Restart-Remote($r) {
    Say "Reiniciando '$($r.nome)'..."
    Stop-Remote $r
    Wait-Um 1500
    return (Start-Remote $r)
}

# Testa: se está rodando, olha o log; se não, sobe e espera registrar.
function Test-Remote($r) {
    Say "Testando '$($r.nome)'..."
    $e = Get-Estado $r (Get-ProcessosRC)
    if ($e.processo) {
        Say "  Rodando (PID $($e.processo.ProcessId)), $($e.sessoes) sessão(ões), conexão: $($e.conexao)."
        if ($e.nomeAntigo) { Say '  Ainda está com o nome antigo: o nome novo vale depois de reiniciar.' }
        return ($e.conexao -eq 'conectado')
    }
    if (@(Test-Tarefa $r).Count -or -not (Test-Lancador $r)) { Say '  A tarefa não está pronta: use Conferir e consertar.'; return $false }
    return (Start-Remote $r)
}

# Confere tudo e conserta o que der. Nunca derruba um Remote Control que está rodando.
function Repair-Remote($r) {
    Say "Conferindo '$($r.nome)'..."
    if (-not (Test-Path $r.pasta)) { Say "  ERRO: a pasta $($r.pasta) não existe. Edite o remote."; return $false }
    Initialize-Conta $r.conta

    if (-not (Test-Confianca $r.conta $r.pasta)) {
        Set-Confianca $r.conta $r.pasta
        Say '  Marquei a pasta como confiável nesta conta.'
    }
    if (-not (Test-Lancador $r)) { Write-Lancador $r; Say '  Lançador criado/atualizado.' }
    $pt = @(Test-Tarefa $r)
    if ($pt.Count) {
        Say "  Tarefa: $($pt -join '; '). Ajustando..."
        Register-Tarefa $r
        $pt = @(Test-Tarefa $r)
        if ($pt.Count) { Say "  ERRO: a tarefa continua errada: $($pt -join '; ')"; return $false }
        Say '  Tarefa agendada OK (sobe com o Windows, sem login e sem janela).'
    }

    $login = Get-Login $r.conta
    $falha = Join-Path (Get-RcDir $r) 'FALHA-LOGIN.txt'
    $p = Find-Processo $r (Get-ProcessosRC)
    if (-not $login.logado -or ((Test-Path $falha) -and -not $p)) {
        Say '  A conta precisa entrar (login).'
        if (-not (Start-Login $r)) { return $false }
        $login = Get-Login $r.conta
    }
    if ($login.email) {
        $outro = Read-Remotes | Where-Object { $_.id -ne $r.id -and $_.conta -ne $r.conta -and $_.email -and $_.email -eq $login.email } | Select-Object -First 1
        if ($outro) { Say "  ATENÇÃO: esta conta está logada com o mesmo e-mail de '$($outro.nome)' ($($login.email)). Use Entrar na conta para trocar." }
        if ($r.email -ne $login.email) { $r.email = $login.email; Save-Remote $r }
    }

    if ($p) {
        Say "  Já está rodando (PID $($p.ProcessId)); não reiniciei para não derrubar as sessões."
        if (-not (Test-TemTexto $p.CommandLine "--name `"$($r.nome)`"")) { Say '  O nome novo vale depois de clicar em Reiniciar (ou no próximo boot).' }
        Say "  Conexão: $(Get-Conexao $p)."
        return $true
    }
    if (Test-Path $falha) { Remove-Item $falha -Force -ErrorAction SilentlyContinue }
    return (Start-Remote $r)
}

# ---------------------------------------------------------------- tarefas antigas e modelos

# Acha tarefas agendadas que rodam "claude remote-control" e não são gerenciadas por este programa.
function Find-TarefasSoltas {
    $nossas = @(Read-Remotes | ForEach-Object { $_.tarefa })
    $achadas = @()
    foreach ($t in Get-ScheduledTask -ErrorAction SilentlyContinue) {
        if ($nossas -contains $t.TaskName) { continue }
        foreach ($a in @($t.Actions)) {
            $linha = "$($a.Execute) $($a.Arguments)"
            $conteudo = ''
            foreach ($m in [regex]::Matches($linha, '([A-Za-z]:\\[^"]+?\.(cmd|bat|ps1|vbs))')) {
                if (Test-Path $m.Value) { $conteudo += [IO.File]::ReadAllText($m.Value) + "`n" }
            }
            $tudo = "$linha`n$conteudo"
            if ($tudo -notmatch 'remote-control') { continue }
            $nome = if ($tudo -match '--name\s+"([^"]+)"') { $Matches[1] } else { '' }
            $pasta = if ($conteudo -match '(?m)^\s*cd\s+/d\s+"?([^"\r\n]+?)"?\s*$') { $Matches[1] } elseif ($a.WorkingDirectory) { $a.WorkingDirectory } else { '' }
            $conta = if ($tudo -match 'CLAUDE_CONFIG_DIR=([^"\r\n]+)') { $Matches[1].Trim() } else { '' }
            $achadas += [pscustomobject]@{ tarefa = $t.TaskName; nome = $nome; pasta = $pasta; conta = $conta; estado = [string]$t.State }
            break
        }
    }
    return $achadas
}

# Transforma uma tarefa antiga em remote gerenciado, mantendo o nome da tarefa (o processo rodando não cai).
function Convert-TarefaSolta($solta, [string]$nomeNovo = '') {
    $nome = if ($nomeNovo) { $nomeNovo } elseif ($solta.nome) { $solta.nome } else { $solta.tarefa }
    $r = New-Remote $nome $solta.conta $solta.pasta 'same-dir' $solta.tarefa
    if ($solta.nome -and $solta.nome -ne $nome) { $r.nomesAntigos = @($solta.nome) }
    Save-Remote $r
    return $r
}

function Get-ContaDeModelo($m) {
    if (-not $m.conta -or $m.conta -eq $script:PadraoMarcador) { return '' }
    return (Join-Path $script:ContasDir (ConvertTo-Slug $m.conta))
}

function Read-Modelos {
    if (-not (Test-Path $script:Modelos)) { return $null }
    return ([IO.File]::ReadAllText($script:Modelos) | ConvertFrom-Json)
}

# Modelos (modelos.json) que ainda não existem neste PC.
function Get-ModelosPendentes {
    $j = Read-Modelos
    if (-not $j) { return @() }
    $rs = @(Read-Remotes)
    $ocultos = @(Read-Ocultos)
    return @(@($j.remotes) | Where-Object { $n = $_.nome; ($ocultos -notcontains $n) -and -not ($rs | Where-Object { $_.nome -eq $n }) })
}

function Get-PastaPadrao {
    $j = Read-Modelos
    if ($j -and $j.pastaPadrao) { return $j.pastaPadrao }
    return 'C:\Projetos'
}

# Cria o remote de um modelo; se já existe uma tarefa antiga da mesma conta e pasta, adota ela.
function New-RemoteDeModelo($m) {
    $conta = Get-ContaDeModelo $m
    $pasta = if ($m.pasta) { $m.pasta } else { Get-PastaPadrao }
    $solta = Find-TarefasSoltas | Where-Object { $_.conta -eq $conta -and (Test-MesmaPasta $_.pasta $pasta) } | Select-Object -First 1
    if ($solta) {
        Say "  Achei a tarefa antiga '$($solta.tarefa)' da mesma conta e pasta: vou adotá-la como '$($m.nome)'."
        return (Convert-TarefaSolta $solta $m.nome)
    }
    $r = New-Remote $m.nome $conta $pasta 'same-dir'
    Save-Remote $r
    return $r
}

function Remove-Remote($r) {
    Say "Removendo '$($r.nome)'..."
    Stop-Remote $r
    Unregister-ScheduledTask -TaskName $r.tarefa -Confirm:$false -ErrorAction SilentlyContinue
    Remove-RemoteSalvo $r
    Say '  Removido (a pasta da conta e o login foram mantidos).'
}

# Sugestões (modelos.json) que o usuário removeu neste PC.
$script:OcultosArq = Join-Path $script:Base 'sugestoes-removidas.json'

function Read-Ocultos {
    if (-not (Test-Path $script:OcultosArq)) { return @() }
    try { return @([IO.File]::ReadAllText($script:OcultosArq) | ConvertFrom-Json) } catch { return @() }
}

function Hide-Modelo($m) {
    New-Item -ItemType Directory -Force $script:Base | Out-Null
    $l = @(Read-Ocultos) + @($m.nome) | Select-Object -Unique
    [IO.File]::WriteAllText($script:OcultosArq, (ConvertTo-Json @($l)), (New-Object Text.UTF8Encoding($false)))
    Say "Sugestão '$($m.nome)' removida deste PC (para voltar, apague $script:OcultosArq)."
}

# Processo de uma tarefa que o programa não gerencia (pelo --name ou pela pasta de debug do lançador).
function Find-ProcessoSolta($s, $procs) {
    foreach ($p in $procs) { if ($s.nome -and (Test-TemTexto $p.CommandLine "--name `"$($s.nome)`"")) { return $p } }
    return $null
}

# Para e apaga uma tarefa de Remote Control feita fora do programa. O lançador e o login da conta ficam.
function Remove-TarefaSolta($s) {
    $rotulo = if ($s.nome) { $s.nome } else { $s.tarefa }
    Say "Removendo '$rotulo' (tarefa '$($s.tarefa)')..."
    Stop-ScheduledTask -TaskName $s.tarefa -ErrorAction SilentlyContinue
    $p = Find-ProcessoSolta $s (Get-ProcessosRC)
    if ($p) { & taskkill.exe /PID $p.ProcessId /T /F | Out-Null }
    for ($i = 0; $i -lt 20; $i++) {
        $t = Get-ScheduledTask -TaskName $s.tarefa -ErrorAction SilentlyContinue
        if (-not $t -or $t.State -ne 'Running') { break }
        Wait-Um 500
    }
    Unregister-ScheduledTask -TaskName $s.tarefa -Confirm:$false -ErrorAction Stop
    Say '  Removido (o login da conta foi mantido).'
}
