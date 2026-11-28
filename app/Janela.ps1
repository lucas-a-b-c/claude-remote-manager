# Claude Remote Manager - janela. Mostra os Remote Control deste PC e permite criar, conferir, consertar, logar e testar.
# -ConsertarTudo: sem janela, confere e conserta todos os remotes (e cria os sugeridos que faltam).
# -SemLogin: no modo sem janela, nunca abre login (só avisa).
# -Captura <png>: abre, lê o estado, salva uma imagem da janela e fecha (para conferência).
param([switch]$ConsertarTudo, [switch]$SemLogin, [string]$Captura)

. (Join-Path $PSScriptRoot 'Nucleo.ps1')

if ($ConsertarTudo) {
    if ($SemLogin) { $script:PodeLogar = $false }
    if (-not (Test-Admin)) { Write-Host 'Rode como administrador (o .bat já pede isso).'; exit 1 }
    foreach ($m in Get-ModelosPendentes) { Say "Criando '$($m.nome)' (sugerido)..."; [void](New-RemoteDeModelo $m) }
    $ok = $true
    foreach ($r in Read-Remotes) { if (-not (Repair-Remote $r)) { $ok = $false } }
    if ($ok) { Say 'Tudo certo.' } else { Say 'Alguns itens precisam de atenção (veja acima).' }
    exit ([int](-not $ok))
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

# Atualização: o aviso e o botão ficam na faixa amarela no topo (veja Test-Atualizacao, mais abaixo).
. (Join-Path $PSScriptRoot 'Atualizacao.ps1')

# Aberto pelo PowerShell (o .bat ou uma atualização)? Gera o "Claude Remote Manager.exe" se preciso e passa para ele.
. (Join-Path $PSScriptRoot 'Executavel.ps1')
if (-not $Captura -and (Switch-ParaExecutavel)) { exit }

$fonte = New-Object Drawing.Font('Segoe UI', 9.5)
$form = New-Object Windows.Forms.Form
$form.Text = "Claude Remote Manager v$(Get-VersaoLocal) - $env:COMPUTERNAME"
$form.Size = New-Object Drawing.Size(1180, 680)
$form.MinimumSize = New-Object Drawing.Size(900, 500)
$form.StartPosition = 'CenterScreen'
if ($env:CRM_EXE) { try { $form.Icon = [Drawing.Icon]::ExtractAssociatedIcon($env:CRM_EXE) } catch { } }
$form.Font = $fonte

$topo = New-Object Windows.Forms.Label
$topo.Dock = 'Top'; $topo.Height = 28; $topo.Font = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Bold); $topo.Padding = New-Object Windows.Forms.Padding(8, 6, 0, 0)

$faixa = New-Object Windows.Forms.Panel
$faixa.Dock = 'Top'; $faixa.Height = 40; $faixa.BackColor = [Drawing.Color]::FromArgb(255, 236, 160); $faixa.Visible = $false
$faixaTexto = New-Object Windows.Forms.Label
$faixaTexto.AutoSize = $false; $faixaTexto.Dock = 'Fill'; $faixaTexto.TextAlign = 'MiddleLeft'; $faixaTexto.Padding = New-Object Windows.Forms.Padding(10, 0, 0, 0)
$faixaTexto.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
$bAtualizarApp = New-Object Windows.Forms.Button
$bAtualizarApp.Text = 'Atualizar agora'; $bAtualizarApp.Dock = 'Right'; $bAtualizarApp.Width = 150
$bAtualizarApp.Font = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Bold)
$faixa.Controls.Add($faixaTexto); $faixa.Controls.Add($bAtualizarApp)
$faixaTexto.BringToFront()

$lista = New-Object Windows.Forms.ListView
$lista.View = 'Details'; $lista.FullRowSelect = $true; $lista.MultiSelect = $false; $lista.HideSelection = $false
$lista.Dock = 'Fill'
foreach ($c in @(@('Remote', 190), @('Estado', 100), @('Conta', 280), @('Sessões abertas', 110), @('Pasta', 150), @('O que fazer', 330))) {
    [void]$lista.Columns.Add($c[0], $c[1])
}

$detalhe = New-Object Windows.Forms.TextBox
$detalhe.Multiline = $true; $detalhe.ReadOnly = $true; $detalhe.ScrollBars = 'Vertical'
$detalhe.Dock = 'Bottom'; $detalhe.Height = 170; $detalhe.Font = New-Object Drawing.Font('Consolas', 9)

$painel = New-Object Windows.Forms.FlowLayoutPanel
$painel.Dock = 'Right'; $painel.Width = 200; $painel.FlowDirection = 'TopDown'; $painel.Padding = New-Object Windows.Forms.Padding(6)

$dicas = New-Object Windows.Forms.ToolTip
$botoes = @{}
function Add-Botao($chave, $texto, $dica) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $texto; $b.Width = 182; $b.Height = 34
    $dicas.SetToolTip($b, $dica)
    $painel.Controls.Add($b)
    $botoes[$chave] = $b
    return $b
}

$titulo = New-Object Windows.Forms.Label
$titulo.Text = 'Selecione uma linha e escolha:'; $titulo.AutoSize = $true; $titulo.Margin = New-Object Windows.Forms.Padding(0, 4, 0, 6)
$painel.Controls.Add($titulo)
$bCriar     = Add-Botao 'criar'     'Criar' 'Cria o remote que ainda não existe, ou passa a gerenciar uma tarefa feita fora do programa (sem derrubar).'
$bCriar.Font = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Bold)
$bRemover   = Add-Botao 'remover'   'Remover...' 'Para o Remote Control e apaga a tarefa do Windows (pede confirmação; o login da conta fica guardado).'
$bRemover.ForeColor = [Drawing.Color]::Firebrick
$bLogin     = Add-Botao 'login'     'Entrar na conta' 'Abre o login da conta do remote selecionado.'
$bConsertar = Add-Botao 'consertar' 'Conferir e consertar' 'Confere o remote selecionado e conserta o que estiver errado. Não derruba o que está rodando.'
$bTestar    = Add-Botao 'testar'    'Testar conexão' 'Se está rodando, confere a conexão; se não, sobe e espera conectar.'
$bReiniciar = Add-Botao 'reiniciar' 'Reiniciar' 'Derruba e sobe de novo (as sessões desse remote caem).'
$bEditar    = Add-Botao 'editar'    'Editar...' 'Muda nome, conta, pasta ou modo.'
$bLogs      = Add-Botao 'logs'      'Abrir pasta de logs' 'Abre a pasta com os logs do remote selecionado.'
$sep = New-Object Windows.Forms.Label; $sep.Text = 'Geral:'; $sep.AutoSize = $true; $sep.Margin = New-Object Windows.Forms.Padding(0, 14, 0, 6)
$painel.Controls.Add($sep)
$bNovo      = Add-Botao 'novo'      'Novo remote...' 'Cria um Remote Control novo (nome, conta e pasta).'
$bTudo      = Add-Botao 'tudo'      'Criar e conferir todos' 'Cria os que ainda não existem e confere/conserta todos.'
$bAtualizar = Add-Botao 'atualizar' 'Recarregar lista' 'Lê de novo o estado de tudo.'
$bVerificar = Add-Botao 'verificar' 'Verificar atualização' 'Confere agora no site se há versão nova do programa.'

$form.Controls.Add($lista)
$form.Controls.Add($painel)
$form.Controls.Add($detalhe)
$form.Controls.Add($topo)
$form.Controls.Add($faixa)
$lista.BringToFront()   # a lista ocupa só o espaço que sobra; o painel de botões fica sempre visível
$painel.AutoScroll = $true

$script:OnLog = {
    param($m)
    $detalhe.AppendText("[$(Get-Date -Format HH:mm:ss)] $m`r`n")
    [Windows.Forms.Application]::DoEvents()
}
$script:OnEspera = { [Windows.Forms.Application]::DoEvents() }

$script:Estados = @{}

function Get-Selecionado {
    if ($lista.SelectedItems.Count -eq 0) { return $null }
    return $lista.SelectedItems[0].Tag
}

function Update-Botoes {
    $s = Get-Selecionado
    $gerenciado = [bool]($s -and $s.tipo -eq 'remote')
    $bCriar.Enabled = [bool]($s -and $s.tipo -ne 'remote')
    $bCriar.Text = if ($s -and $s.tipo -eq 'solta') { 'Gerenciar pelo programa' } else { 'Criar' }
    $bRemover.Enabled = [bool]$s
    foreach ($k in 'consertar', 'login', 'testar', 'reiniciar', 'editar', 'logs') { $botoes[$k].Enabled = $gerenciado }
}

function Set-Ocupado([bool]$o) {
    foreach ($b in $botoes.Values) { $b.Enabled = -not $o }
    $form.UseWaitCursor = $o
    if (-not $o) { Update-Botoes }
    [Windows.Forms.Application]::DoEvents()
}

function Add-Linha($tag, [string[]]$cols, $cor) {
    $it = New-Object Windows.Forms.ListViewItem($cols[0])
    for ($i = 1; $i -lt $cols.Count; $i++) { [void]$it.SubItems.Add($cols[$i]) }
    $it.Tag = $tag
    if ($cor) { $it.ForeColor = $cor }
    [void]$lista.Items.Add($it)
}

function Show-Detalhe {
    $s = Get-Selecionado
    if (-not $s -or $s.tipo -ne 'remote') { return }
    $e = $script:Estados[$s.r.id]
    if (-not $e) { return }
    $l = @("Detalhes de '$($s.r.nome)' (linha selecionada)   conta: $(Get-ContaDir $s.r.conta)")
    if ($e.problemas.Count) { $l += @($e.problemas | ForEach-Object { "  - $_" }) } else { $l += "  '$($s.r.nome)' está funcionando." }
    $detalhe.AppendText(($l -join "`r`n") + "`r`n")
}

# Nome amigável da conta (pasta de configuração).
function Get-ContaNome($conta) {
    if ([string]::IsNullOrEmpty($conta)) { return 'conta principal' }
    return "conta $(Split-Path $conta -Leaf)"
}

function Get-ContaTexto($conta, $login) {
    $quem = if ($login.logado) { $login.email } else { 'não logada' }
    return "$quem ($(Get-ContaNome $conta))"
}

# Estado em uma palavra: Ativo, Parado, Sem login ou Erro, com cor e o que fazer.
function Get-EstadoSimples($e) {
    $semLogin = (-not $e.login.logado) -or ($e.problemas | Where-Object { $_ -like '*login expirou*' })
    $outros = @($e.problemas | Where-Object { $_ -notlike '*não está rodando*' })
    if ($semLogin) { return @{ texto = 'Sem login'; cor = [Drawing.Color]::Firebrick; dica = 'Clique em Entrar na conta.' } }
    if ($e.processo -and $e.conexao -eq 'conectado') {
        if ($outros.Count) { return @{ texto = 'Ativo'; cor = [Drawing.Color]::DarkOrange; dica = "Funcionando, mas: $($outros[0]). Clique em Conferir e consertar." } }
        return @{ texto = 'Ativo'; cor = [Drawing.Color]::DarkGreen; dica = 'Tudo certo.' }
    }
    if ($e.processo) { return @{ texto = 'Erro'; cor = [Drawing.Color]::Firebrick; dica = "Rodando, mas $($e.conexao). Clique em Testar conexão ou Reiniciar." } }
    return @{ texto = 'Parado'; cor = [Drawing.Color]::DarkOrange; dica = 'Clique em Conferir e consertar para subir.' }
}

function Update-Lista {
    $sel = Get-Selecionado
    $selId = if ($sel) { $sel.chave } else { '' }
    $script:Lendo = $true
    $topo.Text = 'Lendo o estado...'
    [Windows.Forms.Application]::DoEvents()
    $lista.BeginUpdate()
    $lista.Items.Clear()
    $procs = Get-ProcessosRC
    $pendentes = @()
    foreach ($r in Read-Remotes) {
        $e = Get-Estado $r $procs
        $script:Estados[$r.id] = $e
        $est = Get-EstadoSimples $e
        $conta = Get-ContaTexto $r.conta $e.login
        $sessoes = if ($e.processo) { [string]$e.sessoes } else { '-' }
        $nome = if ($e.nomeAntigo) { "$($r.nome) (reinicie para trocar o nome)" } else { $r.nome }
        Add-Linha ([pscustomobject]@{ tipo = 'remote'; chave = "r:$($r.id)"; r = $r }) @($nome, $est.texto, $conta, $sessoes, $r.pasta, $est.dica) $est.cor
        if ($est.texto -ne 'Ativo' -or $est.cor -ne [Drawing.Color]::DarkGreen) { $pendentes += "$($r.nome) ($($est.texto))" }
    }
    foreach ($m in Get-ModelosPendentes) {
        $pasta = if ($m.pasta) { $m.pasta } else { Get-PastaPadrao }
        $conta = Get-ContaNome (Get-ContaDeModelo $m)
        Add-Linha ([pscustomobject]@{ tipo = 'modelo'; chave = "m:$($m.nome)"; m = $m }) @($m.nome, 'Não criado', $conta, '-', $pasta, 'Clique em Criar (ou Remover, se não quiser neste PC).') ([Drawing.Color]::SteelBlue)
        $pendentes += "$($m.nome) (Não criado)"
    }
    foreach ($s in Find-TarefasSoltas) {
        $p = Find-ProcessoSolta $s $procs
        $txt = if ($p) { 'Ativo' } else { 'Parado' }
        $cor = if ($p) { [Drawing.Color]::DarkGreen } else { [Drawing.Color]::DarkOrange }
        $sessoes = if ($p) { [string](Get-Sessoes $p) } else { '-' }
        $nome = if ($s.nome) { $s.nome } else { $s.tarefa }
        Add-Linha ([pscustomobject]@{ tipo = 'solta'; chave = "s:$($s.tarefa)"; s = $s }) @($nome, $txt, (Get-ContaNome $s.conta), $sessoes, $s.pasta, 'Feito fora do programa: Gerenciar pelo programa, ou Remover.') $cor
        if (-not $p) { $pendentes += "$nome (Parado)" }
    }
    $lista.EndUpdate()
    foreach ($it in $lista.Items) { if ($it.Tag.chave -eq $selId) { $it.Selected = $true } }
    if ($lista.SelectedItems.Count -eq 0 -and $lista.Items.Count) { $lista.Items[0].Selected = $true }
    $adm = if (Test-Admin) { '' } else { '   ATENÇÃO: aberto sem administrador, consertar vai falhar.' }
    if ($pendentes.Count) {
        $resumo = if ($pendentes.Count -eq 1) { "1 precisa de atenção: $($pendentes[0])" } else { "$($pendentes.Count) precisam de atenção: $($pendentes -join ', ')" }
        $topo.ForeColor = [Drawing.Color]::Firebrick
    } elseif ($lista.Items.Count) {
        $resumo = 'Tudo certo: todos os remotes estão ativos.'
        $topo.ForeColor = [Drawing.Color]::DarkGreen
    } else {
        $resumo = 'Nenhum remote neste PC. Clique em Novo remote.'
        $topo.ForeColor = [Drawing.SystemColors]::ControlText
    }
    $topo.Text = "$resumo   |   PC $env:COMPUTERNAME   |   $(Get-ClaudeVersao)   |   atualizado às $(Get-Date -Format HH:mm:ss)$adm"
    $script:Lendo = $false
    Say "Resumo: $resumo"
    Update-Botoes
    Show-Detalhe
}

function Invoke-Acao([scriptblock]$acao) {
    Set-Ocupado $true
    try { & $acao } catch { Say "ERRO: $($_.Exception.Message)" }
    finally { Set-Ocupado $false }
    Update-Lista
}

# ---------------------------------------------------------------- diálogo de remote (novo / editar)

function Show-DialogoRemote($r) {
    $d = New-Object Windows.Forms.Form
    $d.Text = if ($r) { "Editar $($r.nome)" } else { 'Novo Remote Control' }
    $d.Size = New-Object Drawing.Size(560, 300); $d.FormBorderStyle = 'FixedDialog'; $d.StartPosition = 'CenterParent'
    $d.MaximizeBox = $false; $d.MinimizeBox = $false; $d.Font = $fonte

    $novo = @()
    function Add-Campo($texto, $y, $controle, $largura = 390) {
        $l = New-Object Windows.Forms.Label; $l.Text = $texto; $l.AutoSize = $true
        $l.Location = New-Object Drawing.Point(14, ($y + 3)); $d.Controls.Add($l)
        $controle.Location = New-Object Drawing.Point(130, $y); $controle.Width = $largura; $d.Controls.Add($controle)
    }

    $tNome = New-Object Windows.Forms.TextBox
    Add-Campo 'Nome' 18 $tNome
    $cConta = New-Object Windows.Forms.ComboBox; $cConta.DropDownStyle = 'DropDownList'
    $contas = @(Get-ContasConhecidas)
    foreach ($c in $contas) { [void]$cConta.Items.Add((Get-ContaRotulo $c)) }
    [void]$cConta.Items.Add('Nova conta separada...')
    Add-Campo 'Conta' 56 $cConta
    $tPasta = New-Object Windows.Forms.TextBox
    Add-Campo 'Pasta' 94 $tPasta 300
    $bPasta = New-Object Windows.Forms.Button; $bPasta.Text = 'Procurar'; $bPasta.Location = New-Object Drawing.Point(436, 93); $bPasta.Width = 84; $d.Controls.Add($bPasta)
    $cModo = New-Object Windows.Forms.ComboBox; $cModo.DropDownStyle = 'DropDownList'
    foreach ($m in 'same-dir', 'worktree', 'session') { [void]$cModo.Items.Add($m) }
    Add-Campo 'Modo' 132 $cModo

    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Salvar'; $ok.Location = New-Object Drawing.Point(330, 190); $ok.Width = 90
    $cancel = New-Object Windows.Forms.Button; $cancel.Text = 'Cancelar'; $cancel.Location = New-Object Drawing.Point(430, 190); $cancel.Width = 90; $cancel.DialogResult = 'Cancel'
    $d.Controls.Add($ok); $d.Controls.Add($cancel); $d.AcceptButton = $ok; $d.CancelButton = $cancel

    if ($r) {
        $tNome.Text = $r.nome; $tPasta.Text = $r.pasta; $cModo.SelectedItem = $r.spawn
        $i = [array]::IndexOf($contas, [string]$r.conta); $cConta.SelectedIndex = [Math]::Max(0, $i)
    } else {
        $tPasta.Text = Get-PastaPadrao; $cModo.SelectedItem = 'same-dir'; $cConta.SelectedIndex = $cConta.Items.Count - 1
    }

    $bPasta.Add_Click({
        $f = New-Object Windows.Forms.FolderBrowserDialog
        $f.SelectedPath = $tPasta.Text
        if ($f.ShowDialog($d) -eq 'OK') { $tPasta.Text = $f.SelectedPath }
    })
    $ok.Add_Click({
        $erro = Test-NomeValido $tNome.Text
        if (-not $erro -and -not (Test-Path $tPasta.Text)) { $erro = 'A pasta não existe.' }
        $outro = Read-Remotes | Where-Object { $_.nome -eq $tNome.Text.Trim() -and (-not $r -or $_.id -ne $r.id) }
        if (-not $erro -and $outro) { $erro = 'Já existe um remote com esse nome.' }
        if ($erro) { [void][Windows.Forms.MessageBox]::Show($d, $erro, 'Remote'); return }
        $d.DialogResult = 'OK'; $d.Close()
    })

    if ($d.ShowDialog($form) -ne 'OK') { return $null }
    $nome = $tNome.Text.Trim()
    if ($cConta.SelectedIndex -eq $cConta.Items.Count - 1) {
        $conta = Join-Path $script:ContasDir (ConvertTo-Slug ($nome -replace '^Claude\s+', ''))
    } else { $conta = $contas[$cConta.SelectedIndex] }
    if ($r) {
        if ($r.nome -ne $nome -and (@($r.nomesAntigos) -notcontains $r.nome)) { $r.nomesAntigos = @($r.nomesAntigos) + @($r.nome) }
        if ($r.conta -ne $conta) { $r.email = '' }
        $r.nome = $nome; $r.conta = $conta; $r.pasta = $tPasta.Text.Trim(); $r.spawn = [string]$cModo.SelectedItem
        Save-Remote $r
        return $r
    }
    $n = New-Remote $nome $conta $tPasta.Text.Trim() ([string]$cModo.SelectedItem)
    Save-Remote $n
    return $n
}

# ---------------------------------------------------------------- eventos

$lista.Add_SelectedIndexChanged({ Update-Botoes; if ($lista.SelectedItems.Count -and -not $script:Lendo) { Show-Detalhe } })
$lista.Add_DoubleClick({ Show-Detalhe })
$bAtualizar.Add_Click({ Invoke-Acao { } })
$bNovo.Add_Click({
    $r = Show-DialogoRemote $null
    if ($r) { Invoke-Acao { Say "Criado '$($r.nome)'."; [void](Repair-Remote $r) } }
})
$bCriar.Add_Click({
    $s = Get-Selecionado
    if (-not $s) { return }
    Invoke-Acao {
        if ($s.tipo -eq 'modelo') { $r = New-RemoteDeModelo $s.m }
        else { $r = Convert-TarefaSolta $s.s; Say "Tarefa '$($s.s.tarefa)' adotada como '$($r.nome)'." }
        [void](Repair-Remote $r)
    }
})
$bConsertar.Add_Click({ $s = Get-Selecionado; Invoke-Acao { [void](Repair-Remote $s.r) } })
$bTudo.Add_Click({
    Invoke-Acao {
        foreach ($m in Get-ModelosPendentes) { Say "Criando '$($m.nome)' (sugerido)..."; [void](New-RemoteDeModelo $m) }
        foreach ($r in Read-Remotes) { [void](Repair-Remote $r) }
        Say 'Fim da conferência.'
    }
})
$bLogin.Add_Click({
    $s = Get-Selecionado
    Invoke-Acao {
        Initialize-Conta $s.r.conta
        if (Start-Login $s.r) {
            $l = Get-Login $s.r.conta
            $s.r.email = $l.email; Save-Remote $s.r
            if (-not (Find-Processo $s.r (Get-ProcessosRC))) { [void](Repair-Remote $s.r) }
        }
    }
})
$bTestar.Add_Click({ $s = Get-Selecionado; Invoke-Acao { [void](Test-Remote $s.r) } })
$bReiniciar.Add_Click({
    $s = Get-Selecionado
    $e = $script:Estados[$s.r.id]
    if ($e -and $e.sessoes -gt 0) {
        $q = [Windows.Forms.MessageBox]::Show($form, "'$($s.r.nome)' tem $($e.sessoes) sessão(ões) abertas. Reiniciar derruba essas sessões (inclusive um Claude que esteja trabalhando nelas). Continuar?", 'Reiniciar', 'YesNo', 'Warning')
        if ($q -ne 'Yes') { return }
    }
    Invoke-Acao { [void](Restart-Remote $s.r) }
})
$bEditar.Add_Click({
    $s = Get-Selecionado
    $r = Show-DialogoRemote $s.r
    if ($r) { Invoke-Acao { Say "Salvei '$($r.nome)'."; [void](Repair-Remote $r) } }
})
$bRemover.Add_Click({
    $s = Get-Selecionado
    if (-not $s) { return }
    switch ($s.tipo) {
        'remote' {
            $e = $script:Estados[$s.r.id]
            $aviso = if ($e -and $e.sessoes -gt 0) { "`r`n`r`nAtenção: ele tem $($e.sessoes) sessão(ões) abertas, que vão cair." } else { '' }
            $q = [Windows.Forms.MessageBox]::Show($form, "Remover '$($s.r.nome)'?`r`n`r`nEle para de rodar e a tarefa do Windows é apagada. O login da conta fica guardado.$aviso", 'Remover', 'YesNo', 'Warning')
            if ($q -eq 'Yes') { Invoke-Acao { Remove-Remote $s.r } }
        }
        'solta' {
            $nome = if ($s.s.nome) { $s.s.nome } else { $s.s.tarefa }
            $q = [Windows.Forms.MessageBox]::Show($form, "Remover '$nome'?`r`n`r`nEle para de rodar (as sessões abertas caem) e a tarefa do Windows '$($s.s.tarefa)' é apagada. O login da conta fica guardado.", 'Remover', 'YesNo', 'Warning')
            if ($q -eq 'Yes') { Invoke-Acao { Remove-TarefaSolta $s.s } }
        }
        'modelo' {
            $q = [Windows.Forms.MessageBox]::Show($form, "Não criar '$($s.m.nome)' neste PC?`r`n`r`nEle some da lista deste PC. Nada é apagado.", 'Remover', 'YesNo', 'Question')
            if ($q -eq 'Yes') { Invoke-Acao { Hide-Modelo $s.m } }
        }
    }
})
$bLogs.Add_Click({
    $s = Get-Selecionado
    $d = Get-RcDir $s.r
    New-Item -ItemType Directory -Force $d | Out-Null
    Start-Process explorer.exe $d
})

# ---------------------------------------------------------------- atualização do programa

$script:Atualizacao = $null

function Test-Atualizacao([switch]$PodePedirLogin) {
    try { $info = Get-AtualizacaoDisponivel -PodePedirLogin:$PodePedirLogin } catch { $info = $null }
    $script:Atualizacao = $info
    if ($info) {
        $faixaTexto.Text = "Nova versão $($info.versao) disponível (você está na $(Get-VersaoLocal)). $($info.notas)"
        $faixa.Visible = $true
    } else { $faixa.Visible = $false }
}

$bAtualizarApp.Add_Click({
    if (-not $script:Atualizacao) { return }
    $bAtualizarApp.Enabled = $false; $bAtualizarApp.Text = 'Atualizando...'
    $form.UseWaitCursor = $true
    [Windows.Forms.Application]::DoEvents()
    if (Install-Atualizacao $script:Atualizacao) {
        Start-ProgramaDeNovo
        $form.Close()
        return
    }
    $form.UseWaitCursor = $false
    $bAtualizarApp.Enabled = $true; $bAtualizarApp.Text = 'Atualizar agora'
    [void][Windows.Forms.MessageBox]::Show($form, 'Não consegui baixar a atualização agora. Tente de novo em alguns minutos.', 'Atualização', 'OK', 'Warning')
})

$bVerificar.Add_Click({
    $form.UseWaitCursor = $true; [Windows.Forms.Application]::DoEvents()
    Test-Atualizacao -PodePedirLogin
    $form.UseWaitCursor = $false
    if ($script:Atualizacao) { Say "Nova versão $($script:Atualizacao.versao) disponível: clique em Atualizar agora, na faixa amarela." }
    elseif (Get-SiteUrl) {
        if (Get-VersaoSite) { Say "Você já está na versão mais nova ($(Get-VersaoLocal))." }
        else { Say 'Não consegui consultar o site agora (sem internet ou sem login do site).' }
    }
})

$relogio = New-Object Windows.Forms.Timer
$relogio.Interval = 10 * 60 * 1000
$relogio.Add_Tick({ if (-not $form.UseWaitCursor) { Test-Atualizacao } })

function Start-Janela {
    Invoke-Acao { }
    if ($script:ExeErro) { Say "Não consegui gerar o Claude Remote Manager.exe (o programa segue pelo PowerShell): $($script:ExeErro)" }
    if (-not $Captura) { Test-Atualizacao -PodePedirLogin; $relogio.Start() }
    if (Get-ModelosPendentes) { Say 'Há remotes "Não criado" (azul): selecione e clique Criar, ou Remover se não quiser neste PC.' }
}

if ($Captura) {
    # Sem mostrar a janela: monta, lê o estado e salva a imagem.
    [void]$form.Handle
    $form.PerformLayout()
    Start-Janela
    $bmp = New-Object Drawing.Bitmap($form.Width, $form.Height)
    $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
    $bmp.Save($Captura)
    $topo.Text
    foreach ($it in $lista.Items) { ($it.SubItems | ForEach-Object { $_.Text }) -join ' | ' }
    foreach ($k in $botoes.Keys) { "botão $($botoes[$k].Text): $(if ($botoes[$k].Enabled) {'ativo'} else {'inativo'})" }
    $detalhe.Text
    return
}

$form.Add_Shown({ Start-Janela })
[void]$form.ShowDialog()
