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

function Say([string]$m) {
    if ($script:OnLog) { & $script:OnLog $m } else { Write-Host $m }
}

function Wait-Um([int]$ms = 300) {
    if ($script:OnEspera) { & $script:OnEspera }
    Start-Sleep -Milliseconds $ms
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

# Abre uma janela de terminal visível com o login da conta e espera o usuário terminar.
# A janela é um .cmd (não depende de PowerShell nem do terminal padrão do Windows) e só fecha
# sozinha quando o login dá certo; se falhar, mostra o erro e espera uma tecla.
# A espera não confia no processo da janela (o Terminal do Windows 11 pode trocar de processo):
# termina quando o .cmd grava o arquivo de fim, quando a conta aparece logada, ou em 15 min.
function Start-Login($r) {
    if (-not $script:PodeLogar) { Say "  Login necessário em '$($r.nome)': abra o programa neste PC e clique em Entrar na conta."; return $false }
    $dir = Get-RcDir $r
    New-Item -ItemType Directory -Force $dir | Out-Null
    if ($r.conta) { New-Item -ItemType Directory -Force $r.conta | Out-Null }
    $cmd = Join-Path $dir 'login.cmd'
    $fim = Join-Path $dir 'login-fim.txt'
    Remove-Item $fim -Force -ErrorAction SilentlyContinue
    $exe = Get-ClaudeExe
    if (-not $exe -or -not (Test-Path $exe)) { Say '  ERRO: não achei o claude.exe neste PC. Instale o Claude Code e tente de novo.'; return $false }
    $setConta = if ($r.conta) { "set `"CLAUDE_CONFIG_DIR=$($r.conta)`"" } else { 'set "CLAUDE_CONFIG_DIR="' }
    $emailArg = if ($r.email) { " --email `"$($r.email)`"" } else { '' }
    $t = @"
@echo off
title Login do Claude - $($r.nome)
$setConta
echo.
echo   Login da conta do remote "$($r.nome)"
echo.
echo   O navegador vai abrir na pagina de login do Claude.
echo   Entre com a conta certa para este remote.
echo   Se o navegador ja estiver logado em outra conta, saia dela
echo   ou aperte C aqui para copiar o link e cole numa janela anonima.
echo.
"$exe" auth login$emailArg
set "RC=%errorlevel%"
echo %RC%> "$fim"
echo.
if "%RC%"=="0" (
  echo   Pronto. Esta janela fecha sozinha.
  timeout /t 3 >nul
) else (
  echo   O login falhou ^(codigo %RC%^). Veja a mensagem acima.
  echo   Aperte uma tecla para fechar.
  pause >nul
)
"@
    [IO.File]::WriteAllText($cmd, ($t -replace "`r?`n", "`r`n"), (Get-Oem))
    Say "  Abrindo o login da conta de '$($r.nome)' numa janela de terminal. Entre no navegador; o programa espera."
    try {
        Start-Process -FilePath $env:ComSpec -ArgumentList @('/c', "`"$cmd`"") -WindowStyle Normal | Out-Null
    } catch {
        Say "  ERRO ao abrir a janela de login: $($_.Exception.Message)"
        return $false
    }
    $inicio = Get-Date
    $ultimaChecagem = Get-Date
    while (((Get-Date) - $inicio).TotalMinutes -lt 15) {
        if (Test-Path $fim) { break }
        if (((Get-Date) - $ultimaChecagem).TotalSeconds -ge 5) {
            $ultimaChecagem = Get-Date
            if ((Get-Login $r.conta).logado) { break }
        }
        Wait-Um 400
    }
    $l = Get-Login $r.conta
    if ($l.logado) { Say "  Logado como $($l.email)."; return $true }
    if (Test-Path $fim) {
        $rc = (Get-Content $fim -Raw -ErrorAction SilentlyContinue)
        if ($rc) { $rc = $rc.Trim() }
        Say "  O login não foi concluído (o claude auth login terminou com código $rc). A mensagem de erro ficou na janela de login."
    } else {
        Say '  O login não foi concluído em 15 minutos.'
    }
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
"$exe" remote-control --spawn $($r.spawn) --name "$($r.nome)" --debug-file "%DBG%" > nul 2> "%LOG%"
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
    if (-not $f -or -not (Test-Path $f)) { return 'sem log' }
    $idade = (Get-Date) - (Get-Item $f).LastWriteTime
    $txt = @(Get-Content $f -Tail 400 -ErrorAction SilentlyContinue)
    $iReg = -1; $iRuim = -1
    for ($i = 0; $i -lt $txt.Count; $i++) {
        if ($txt[$i] -match 'Registered, server environmentId|work/poll -> 200|heartbeat -> 200') { $iReg = $i }
        elseif ($txt[$i] -match 'giving up|Registration failed') { $iRuim = $i }
    }
    if ($iRuim -gt $iReg) { return 'com erro' }
    if ($idade.TotalMinutes -gt 15) { return "sem sinal há $([int]$idade.TotalMinutes) min" }
    return 'conectado'
}

function Get-Estado($r, $procs) {
    $p = Find-Processo $r $procs
    $login = Get-Login $r.conta
    $falha = Join-Path (Get-RcDir $r) 'FALHA-LOGIN.txt'
    $problemas = @()
    if (-not (Test-Path $r.pasta)) { $problemas += 'a pasta de trabalho não existe' }
    if (-not $login.logado) { $problemas += 'a conta não está logada' }
    elseif ((Test-Path $falha) -and -not $p) { $problemas += 'o login expirou (o Remote Control não consegue subir)' }
    $problemas += @(Test-Tarefa $r)
    if (-not (Test-Lancador $r)) { $problemas += 'o lançador precisa ser criado ou atualizado' }
    if ((Test-Path $r.pasta) -and -not (Test-Confianca $r.conta $r.pasta)) { $problemas += 'a pasta não está marcada como confiável nesta conta' }
    if (-not $p) { $problemas += 'o Remote Control não está rodando' }
    $nomeAntigo = [bool]($p -and -not (Test-TemTexto $p.CommandLine "--name `"$($r.nome)`""))
    return [pscustomobject]@{
        processo = $p; login = $login; problemas = $problemas; conexao = (Get-Conexao $p)
        sessoes = (Get-Sessoes $p); nomeAntigo = $nomeAntigo
    }
}

# ---------------------------------------------------------------- ações

function Wait-Registro($r, [int]$segundos = 90) {
    $dbg = Join-Path (Get-RcDir $r) 'debug.log'
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
        if ((Test-Path $dbg) -and (Get-Item $dbg).LastWriteTime -ge $inicio.AddSeconds(-5)) {
            if (Select-String -Path $dbg -Pattern 'Registered, server environmentId' -Quiet) { return 'ok' }
        }
        if ((Test-Path $falha) -and (Get-Item $falha).LastWriteTime -ge $inicio) { return 'login' }
    }
    return 'tempo'
}

function Start-Remote($r) {
    Start-ScheduledTask -TaskName $r.tarefa -ErrorAction Stop
    Say '  Tarefa iniciada; esperando o Remote Control registrar no claude.ai...'
    switch (Wait-Registro $r) {
        'ok'    { Say "  OK: '$($r.nome)' subiu e está conectado."; return $true }
        'login' { Say '  O Remote Control não subiu por falta de login.'; return $false }
        default { Say '  Não vi o registro em 90 s. Veja remote-control.log na pasta de logs.'; return $false }
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
