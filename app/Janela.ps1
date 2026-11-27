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

$fonte = New-Object Drawing.Font('Segoe UI', 9.5)
$form = New-Object Windows.Forms.Form
$form.Text = "Claude Remote Manager - $env:COMPUTERNAME"
$form.Size = New-Object Drawing.Size(1180, 680)
$form.MinimumSize = New-Object Drawing.Size(900, 500)
$form.StartPosition = 'CenterScreen'
$form.Font = $fonte

$topo = New-Object Windows.Forms.Label
$topo.Dock = 'Top'; $topo.Height = 28; $topo.Padding = New-Object Windows.Forms.Padding(8, 6, 0, 0)

$lista = New-Object Windows.Forms.ListView
$lista.View = 'Details'; $lista.FullRowSelect = $true; $lista.MultiSelect = $false; $lista.HideSelection = $false
$lista.Dock = 'Fill'
foreach ($c in @(@('Remote', 190), @('Conta (login)', 260), @('Situação', 140), @('Rodando', 120), @('Conexão', 100), @('Pasta', 140), @('Tarefa do Windows', 250))) {
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

$bAtualizar = Add-Botao 'atualizar' 'Atualizar' 'Lê de novo o estado de tudo.'
$bCriar     = Add-Botao 'criar'     'Criar este remote' 'Cria o remote sugerido ou adota a tarefa antiga selecionada.'
$bNovo      = Add-Botao 'novo'      'Novo remote...' 'Cria um Remote Control novo (nome, conta e pasta).'
$bConsertar = Add-Botao 'consertar' 'Conferir e consertar' 'Confere o remote selecionado e conserta o que estiver errado. Não derruba o que está rodando.'
$bTudo      = Add-Botao 'tudo'      'Consertar todos' 'Cria os sugeridos que faltam e confere/conserta todos.'
$bLogin     = Add-Botao 'login'     'Entrar na conta' 'Abre o login da conta do remote selecionado.'
$bTestar    = Add-Botao 'testar'    'Testar' 'Se está rodando, confere a conexão; se não, sobe e espera conectar.'
$bReiniciar = Add-Botao 'reiniciar' 'Reiniciar' 'Derruba e sobe de novo (as sessões desse remote caem).'
$bEditar    = Add-Botao 'editar'    'Editar...' 'Muda nome, conta, pasta ou modo.'
$bRemover   = Add-Botao 'remover'   'Remover' 'Para o remote e apaga a tarefa (mantém o login da conta).'
$bLogs      = Add-Botao 'logs'      'Abrir pasta de logs' 'Abre a pasta com os logs do remote selecionado.'

$form.Controls.Add($lista)
$form.Controls.Add($painel)
$form.Controls.Add($detalhe)
$form.Controls.Add($topo)

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
    $bCriar.Text = if ($s -and $s.tipo -eq 'solta') { 'Adotar esta tarefa' } else { 'Criar este remote' }
    foreach ($k in 'consertar', 'login', 'testar', 'reiniciar', 'editar', 'remover', 'logs') { $botoes[$k].Enabled = $gerenciado }
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
    $l = @("== $($s.r.nome)   conta: $(Get-ContaDir $s.r.conta)")
    if ($e.problemas.Count) { $l += @($e.problemas | ForEach-Object { "  - $_" }) } else { $l += '  Tudo certo.' }
    $detalhe.AppendText(($l -join "`r`n") + "`r`n")
}

function Update-Lista {
    $sel = Get-Selecionado
    $selId = if ($sel) { $sel.chave } else { '' }
    $topo.Text = 'Lendo o estado...'
    [Windows.Forms.Application]::DoEvents()
    $lista.BeginUpdate()
    $lista.Items.Clear()
    $procs = Get-ProcessosRC
    foreach ($r in Read-Remotes) {
        $e = Get-Estado $r $procs
        $script:Estados[$r.id] = $e
        $conta = Get-ContaRotulo $r.conta
        $login = if ($e.login.logado) { $e.login.email } else { 'NÃO LOGADA' }
        $situacao = if ($e.problemas.Count -eq 0) { 'OK' } else { "$($e.problemas.Count) problema(s)" }
        $rodando = if ($e.processo) { "sim, $($e.sessoes) sessão(ões)" } else { 'não' }
        $nome = if ($e.nomeAntigo) { "$($r.nome) (reiniciar p/ renomear)" } else { $r.nome }
        $cor = if ($e.problemas.Count -eq 0) { [Drawing.Color]::DarkGreen } elseif ($e.processo -and $e.login.logado) { [Drawing.Color]::DarkOrange } else { [Drawing.Color]::Firebrick }
        Add-Linha ([pscustomobject]@{ tipo = 'remote'; chave = "r:$($r.id)"; r = $r }) @($nome, "$login  [$conta]", $situacao, $rodando, $e.conexao, $r.pasta, $r.tarefa) $cor
    }
    foreach ($m in Get-ModelosPendentes) {
        $pasta = if ($m.pasta) { $m.pasta } else { Get-PastaPadrao }
        Add-Linha ([pscustomobject]@{ tipo = 'modelo'; chave = "m:$($m.nome)"; m = $m }) @($m.nome, "(conta: $($m.conta))", 'sugerido: Criar', '-', '-', $pasta, '-') ([Drawing.Color]::SteelBlue)
    }
    foreach ($s in Find-TarefasSoltas) {
        $p = $procs | Where-Object { $s.nome -and (Test-TemTexto $_.CommandLine "--name `"$($s.nome)`"") } | Select-Object -First 1
        $rod = if ($p) { "sim, $(Get-Sessoes $p) sessão(ões)" } else { 'não' }
        Add-Linha ([pscustomobject]@{ tipo = 'solta'; chave = "s:$($s.tarefa)"; s = $s }) @($s.nome, "[$(Get-ContaRotulo $s.conta)]", 'antiga: Adotar', $rod, '-', $s.pasta, $s.tarefa) ([Drawing.Color]::DimGray)
    }
    $lista.EndUpdate()
    foreach ($it in $lista.Items) { if ($it.Tag.chave -eq $selId) { $it.Selected = $true } }
    if ($lista.SelectedItems.Count -eq 0 -and $lista.Items.Count) { $lista.Items[0].Selected = $true }
    $adm = if (Test-Admin) { '' } else { '   ATENÇÃO: aberto sem administrador, consertar vai falhar.' }
    $topo.Text = "PC $env:COMPUTERNAME   |   $(Get-ClaudeVersao)   |   atualizado às $(Get-Date -Format HH:mm:ss)$adm"
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

$lista.Add_SelectedIndexChanged({ Update-Botoes })
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
    $q = [Windows.Forms.MessageBox]::Show($form, "Remover '$($s.r.nome)'? Ele para de rodar e a tarefa do Windows é apagada. O login da conta fica guardado.", 'Remover', 'YesNo', 'Warning')
    if ($q -eq 'Yes') { Invoke-Acao { Remove-Remote $s.r } }
})
$bLogs.Add_Click({
    $s = Get-Selecionado
    $d = Get-RcDir $s.r
    New-Item -ItemType Directory -Force $d | Out-Null
    Start-Process explorer.exe $d
})

function Start-Janela {
    Invoke-Acao { }
    if (Get-ModelosPendentes) { Say 'Há remotes sugeridos (azul) que ainda não existem neste PC: selecione e clique Criar, ou use Consertar todos.' }
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
