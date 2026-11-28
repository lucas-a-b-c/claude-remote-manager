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

$fonte = New-Object Drawing.Font('Segoe UI', 10)
$fonteNegrito = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
$form = New-Object Windows.Forms.Form
$form.Text = "Claude Remote Manager v$(Get-VersaoLocal) - $env:COMPUTERNAME"
$form.Size = New-Object Drawing.Size(1200, 700)
$form.MinimumSize = New-Object Drawing.Size(900, 520)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [Drawing.Color]::White
if ($env:CRM_EXE) { try { $form.Icon = [Drawing.Icon]::ExtractAssociatedIcon($env:CRM_EXE) } catch { } }
$form.Font = $fonte

# ---------------------------------------------------------------- menu superior (ações gerais e configurações)
$menu = New-Object Windows.Forms.MenuStrip
$menu.Font = $fonte; $menu.BackColor = [Drawing.Color]::White; $menu.Padding = New-Object Windows.Forms.Padding(6, 3, 0, 3)
function Add-Menu($pai, $texto, $atalho) {
    $i = New-Object Windows.Forms.ToolStripMenuItem($texto)
    if ($atalho) { $i.ShortcutKeys = $atalho }
    if ($pai -is [Windows.Forms.MenuStrip]) { [void]$pai.Items.Add($i) } else { [void]$pai.DropDownItems.Add($i) }
    return $i
}
$mArquivo   = Add-Menu $menu 'Arquivo'
$bAtualizar = Add-Menu $mArquivo 'Recarregar lista' ([Windows.Forms.Keys]::F5)
[void]$mArquivo.DropDownItems.Add((New-Object Windows.Forms.ToolStripSeparator))
$mSair      = Add-Menu $mArquivo 'Sair'
$mRemotes   = Add-Menu $menu 'Remotes'
$bNovo      = Add-Menu $mRemotes 'Novo remote...' ([Windows.Forms.Keys]::Control -bor [Windows.Forms.Keys]::N)
$bTudo      = Add-Menu $mRemotes 'Criar e conferir todos'
$mConfig    = Add-Menu $menu 'Configurações'
$mPastaApp  = Add-Menu $mConfig 'Abrir pasta do programa'
$mPastaDados = Add-Menu $mConfig 'Abrir pasta de dados (remotes e logs)'
[void]$mConfig.DropDownItems.Add((New-Object Windows.Forms.ToolStripSeparator))
$mLoginSite = Add-Menu $mConfig 'Trocar login do site...'
$mAjuda     = Add-Menu $menu 'Ajuda'
$bVerificar = Add-Menu $mAjuda 'Verificar atualização'
$mSite      = Add-Menu $mAjuda 'Abrir site CruzVerbenaGroup'
[void]$mAjuda.DropDownItems.Add((New-Object Windows.Forms.ToolStripSeparator))
$mSobre     = Add-Menu $mAjuda 'Sobre'
$form.MainMenuStrip = $menu

# ---------------------------------------------------------------- faixa de atualização
$faixa = New-Object Windows.Forms.Panel
$faixa.Dock = 'Top'; $faixa.Height = 42; $faixa.BackColor = [Drawing.Color]::FromArgb(255, 236, 160); $faixa.Visible = $false
$faixaTexto = New-Object Windows.Forms.Label
$faixaTexto.AutoSize = $false; $faixaTexto.Dock = 'Fill'; $faixaTexto.TextAlign = 'MiddleLeft'; $faixaTexto.Padding = New-Object Windows.Forms.Padding(12, 0, 0, 0)
$faixaTexto.Font = $fonteNegrito
$bAtualizarApp = New-Object Windows.Forms.Button
$bAtualizarApp.Text = 'Atualizar agora'; $bAtualizarApp.Dock = 'Right'; $bAtualizarApp.Width = 160
$bAtualizarApp.Font = $fonteNegrito; $bAtualizarApp.FlatStyle = 'Flat'; $bAtualizarApp.BackColor = [Drawing.Color]::White
$faixa.Controls.Add($faixaTexto); $faixa.Controls.Add($bAtualizarApp)
$faixaTexto.BringToFront()

# ---------------------------------------------------------------- cabeçalho (título, PC e resumo geral)
function New-Cor([string]$hex) { return [Drawing.ColorTranslator]::FromHtml($hex) }
$cabecalho = New-Object Windows.Forms.Panel
$cabecalho.Dock = 'Top'; $cabecalho.Height = 76; $cabecalho.BackColor = New-Cor '#111827'
$titulo = New-Object Windows.Forms.Label
$titulo.Text = 'Claude Remote Manager'; $titulo.AutoSize = $true; $titulo.ForeColor = [Drawing.Color]::White
$titulo.Font = New-Object Drawing.Font('Segoe UI Semibold', 17); $titulo.Location = New-Object Drawing.Point(18, 9)
$subtitulo = New-Object Windows.Forms.Label
$subtitulo.AutoSize = $true; $subtitulo.ForeColor = New-Cor '#9CA3AF'; $subtitulo.Font = New-Object Drawing.Font('Segoe UI', 9.5)
$subtitulo.Location = New-Object Drawing.Point(21, 47); $subtitulo.Text = "PC $env:COMPUTERNAME"
$topo = New-Object Windows.Forms.Label
$topo.AutoSize = $true; $topo.Font = New-Object Drawing.Font('Segoe UI Semibold', 10.5); $topo.ForeColor = [Drawing.Color]::White
$topo.Padding = New-Object Windows.Forms.Padding(14, 7, 14, 7); $topo.BackColor = New-Cor '#374151'; $topo.Text = 'Lendo o estado...'
$cabecalho.Controls.AddRange(@($titulo, $subtitulo, $topo))
$posicionarResumo = {
    $topo.MaximumSize = New-Object Drawing.Size([Math]::Max(200, $cabecalho.Width - 400), 0)
    $topo.Left = $cabecalho.Width - $topo.Width - 20
    $topo.Top = [int](($cabecalho.Height - $topo.Height) / 2)
}
$cabecalho.Add_Resize($posicionarResumo)
$topo.Add_TextChanged($posicionarResumo)
$topo.Add_SizeChanged($posicionarResumo)

# ---------------------------------------------------------------- barra de ações do remote selecionado
$barra = New-Object Windows.Forms.ToolStrip
$barra.GripStyle = 'Hidden'; $barra.Font = $fonte; $barra.Padding = New-Object Windows.Forms.Padding(8, 4, 8, 4)
$barra.BackColor = New-Cor '#F9FAFB'; $barra.RenderMode = 'System'; $barra.AutoSize = $false; $barra.Height = 42
$rotuloBarra = New-Object Windows.Forms.ToolStripLabel('Remote selecionado:')
$rotuloBarra.ForeColor = New-Cor '#6B7280'
[void]$barra.Items.Add($rotuloBarra)

$botoes = @{}
function Add-Botao($chave, $texto, $dica) {
    $b = New-Object Windows.Forms.ToolStripButton($texto)
    $b.DisplayStyle = 'Text'; $b.ToolTipText = $dica
    $b.Padding = New-Object Windows.Forms.Padding(6, 2, 6, 2)
    [void]$barra.Items.Add($b)
    $botoes[$chave] = $b
    return $b
}
$bCriar     = Add-Botao 'criar'     'Criar' 'Cria o remote que ainda não existe, ou passa a gerenciar uma tarefa feita fora do programa (sem derrubar).'
$bCriar.Font = $fonteNegrito
$bLogin     = Add-Botao 'login'     'Entrar na conta' 'Abre o login da conta do remote selecionado.'
$bConsertar = Add-Botao 'consertar' 'Conferir e consertar' 'Confere o remote selecionado e conserta o que estiver errado. Não derruba o que está rodando.'
$bTestar    = Add-Botao 'testar'    'Testar conexão' 'Se está rodando, confere a conexão; se não, sobe e espera conectar.'
$bReiniciar = Add-Botao 'reiniciar' 'Reiniciar' 'Derruba e sobe de novo (as sessões desse remote caem).'
$bEditar    = Add-Botao 'editar'    'Editar...' 'Muda nome, conta, pasta ou modo.'
$bLogs      = Add-Botao 'logs'      'Logs' 'Abre a pasta com os logs do remote selecionado.'
$bRemover   = Add-Botao 'remover'   'Remover...' 'Para o Remote Control e apaga a tarefa do Windows (pede confirmação; o login da conta fica guardado).'
$bRemover.ForeColor = New-Cor '#B91C1C'; $bRemover.Alignment = 'Right'

# ---------------------------------------------------------------- lista
$lista = New-Object Windows.Forms.ListView
$lista.View = 'Details'; $lista.FullRowSelect = $true; $lista.MultiSelect = $false; $lista.HideSelection = $false
$lista.Dock = 'Fill'; $lista.BorderStyle = 'None'; $lista.GridLines = $false; $lista.Font = $fonte
$altura = New-Object Windows.Forms.ImageList; $altura.ImageSize = New-Object Drawing.Size(1, 36); $lista.SmallImageList = $altura
foreach ($c in @(@('Remote', 210), @('Estado', 100), @('Conta', 300), @('Sessões', 75), @('Pasta', 150), @('O que fazer', 300))) {
    [void]$lista.Columns.Add($c[0], $c[1])
}
$ajustarColunas = {
    $soma = 0
    for ($i = 0; $i -lt $lista.Columns.Count - 1; $i++) { $soma += $lista.Columns[$i].Width }
    $resto = $lista.ClientSize.Width - $soma - 4
    if ($resto -gt 150) { $lista.Columns[$lista.Columns.Count - 1].Width = $resto }
}
$lista.Add_Resize($ajustarColunas)

# Desenho próprio da lista: cabeçalho discreto, linha selecionada azul-clara e o estado como etiqueta colorida.
$lista.OwnerDraw = $true
$script:CoresEstado = @{
    'Ativo'      = @((New-Cor '#DCFCE7'), (New-Cor '#166534'), (New-Cor '#22C55E'))
    'Parado'     = @((New-Cor '#FEF3C7'), (New-Cor '#92400E'), (New-Cor '#F59E0B'))
    'Sem login'  = @((New-Cor '#FEE2E2'), (New-Cor '#991B1B'), (New-Cor '#EF4444'))
    'Erro'       = @((New-Cor '#FEE2E2'), (New-Cor '#991B1B'), (New-Cor '#EF4444'))
    'Iniciando'  = @((New-Cor '#E0F2FE'), (New-Cor '#075985'), (New-Cor '#0EA5E9'))
    'Não criado' = @((New-Cor '#DBEAFE'), (New-Cor '#1E40AF'), (New-Cor '#3B82F6'))
}
$script:CorTexto = New-Cor '#111827'; $script:CorFraca = New-Cor '#6B7280'; $script:CorSel = New-Cor '#E0ECFF'; $script:CorLinha = New-Cor '#F1F5F9'
$script:FonteCab = New-Object Drawing.Font('Segoe UI Semibold', 9)
$script:FontePill = New-Object Drawing.Font('Segoe UI Semibold', 9)
function New-Arredondado([Drawing.Rectangle]$r, [int]$raio) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $d = $raio * 2
    $p.AddArc($r.X, $r.Y, $d, $d, 180, 90); $p.AddArc($r.Right - $d, $r.Y, $d, $d, 270, 90)
    $p.AddArc($r.Right - $d, $r.Bottom - $d, $d, $d, 0, 90); $p.AddArc($r.X, $r.Bottom - $d, $d, $d, 90, 90)
    $p.CloseFigure(); return $p
}
$lista.Add_DrawColumnHeader({
    param($s, $e)
    $e.Graphics.FillRectangle((New-Object Drawing.SolidBrush((New-Cor '#F9FAFB'))), $e.Bounds)
    $e.Graphics.DrawLine((New-Object Drawing.Pen((New-Cor '#E5E7EB'))), $e.Bounds.Left, $e.Bounds.Bottom - 1, $e.Bounds.Right, $e.Bounds.Bottom - 1)
    $r = New-Object Drawing.Rectangle(($e.Bounds.X + 10), $e.Bounds.Y, ($e.Bounds.Width - 12), $e.Bounds.Height)
    [Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Header.Text.ToUpper(), $script:FonteCab, $r, $script:CorFraca, ([Windows.Forms.TextFormatFlags]'VerticalCenter, Left, EndEllipsis'))
})
$lista.Add_DrawItem({ param($s, $e) })
$lista.Add_DrawSubItem({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = 'AntiAlias'
    $fundo = if ($e.Item.Selected) { $script:CorSel } else { [Drawing.Color]::White }
    $g.FillRectangle((New-Object Drawing.SolidBrush($fundo)), $e.Bounds)
    $g.DrawLine((New-Object Drawing.Pen($script:CorLinha)), $e.Bounds.Left, $e.Bounds.Bottom - 1, $e.Bounds.Right, $e.Bounds.Bottom - 1)
    $txt = $e.SubItem.Text
    if ($e.ColumnIndex -eq 1 -and $script:CoresEstado.ContainsKey($txt)) {
        $c = $script:CoresEstado[$txt]
        $tam = [Windows.Forms.TextRenderer]::MeasureText($txt, $script:FontePill)
        $w = $tam.Width + 22; $h = 22
        $r = New-Object Drawing.Rectangle(($e.Bounds.X + 8), ($e.Bounds.Y + [int](($e.Bounds.Height - $h) / 2)), $w, $h)
        $g.FillPath((New-Object Drawing.SolidBrush($c[0])), (New-Arredondado $r 10))
        $g.FillEllipse((New-Object Drawing.SolidBrush($c[2])), ($r.X + 8), ($r.Y + 8), 6, 6)
        $rt = New-Object Drawing.Rectangle(($r.X + 16), $r.Y, ($w - 16), $h)
        [Windows.Forms.TextRenderer]::DrawText($g, $txt, $script:FontePill, $rt, $c[1], ([Windows.Forms.TextFormatFlags]'VerticalCenter, Left'))
        return
    }
    $cor = if ($e.ColumnIndex -eq 0) { $script:CorTexto } elseif ($e.ColumnIndex -eq 5) { $script:CorFraca } else { New-Cor '#374151' }
    $fonteC = if ($e.ColumnIndex -eq 0) { $script:FontePill } else { $lista.Font }
    $r = New-Object Drawing.Rectangle(($e.Bounds.X + 10), $e.Bounds.Y, ($e.Bounds.Width - 14), $e.Bounds.Height)
    [Windows.Forms.TextRenderer]::DrawText($g, $txt, $fonteC, $r, $cor, ([Windows.Forms.TextFormatFlags]'VerticalCenter, Left, EndEllipsis, NoPrefix'))
})
$lista.Add_SelectedIndexChanged({ $lista.Invalidate() })

# Botão direito na lista: as mesmas ações da barra.
$menuLinha = New-Object Windows.Forms.ContextMenuStrip
$menuLinha.Font = $fonte
foreach ($k in 'criar', 'login', 'consertar', 'testar', 'reiniciar', 'editar', 'logs', 'remover') {
    $orig = $botoes[$k]
    $i = New-Object Windows.Forms.ToolStripMenuItem($orig.Text)
    $i.Tag = $k
    $i.Add_Click({ param($s) $botoes[$s.Tag].PerformClick() })
    [void]$menuLinha.Items.Add($i)
}
$menuLinha.Add_Opening({
    foreach ($i in $menuLinha.Items) { $b = $botoes[$i.Tag]; $i.Text = $b.Text; $i.Enabled = $b.Enabled; $i.ForeColor = $b.ForeColor }
})
$lista.ContextMenuStrip = $menuLinha

# ---------------------------------------------------------------- registro (log) embaixo
$painelLog = New-Object Windows.Forms.Panel
$painelLog.Dock = 'Bottom'; $painelLog.Height = 170; $painelLog.BackColor = New-Cor '#F9FAFB'; $painelLog.Padding = New-Object Windows.Forms.Padding(10, 0, 4, 6)
$cabLog = New-Object Windows.Forms.Panel
$cabLog.Dock = 'Top'; $cabLog.Height = 30
$rotuloLog = New-Object Windows.Forms.Label
$rotuloLog.Text = 'REGISTRO'; $rotuloLog.Dock = 'Fill'; $rotuloLog.ForeColor = New-Cor '#6B7280'; $rotuloLog.Font = New-Object Drawing.Font('Segoe UI Semibold', 9)
$rotuloLog.Padding = New-Object Windows.Forms.Padding(0, 8, 0, 0)
function New-BotaoLog($texto) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $texto; $b.Dock = 'Right'; $b.Width = 120; $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderColor = New-Cor '#D1D5DB'
    $b.BackColor = [Drawing.Color]::White; $b.ForeColor = New-Cor '#374151'; $b.Font = New-Object Drawing.Font('Segoe UI', 9); $b.Cursor = [Windows.Forms.Cursors]::Hand
    return $b
}
$bCopiarLog = New-BotaoLog 'Copiar registro'
$bLimparLog = New-BotaoLog 'Limpar'; $bLimparLog.Width = 80
$espacoLog = New-Object Windows.Forms.Panel; $espacoLog.Dock = 'Right'; $espacoLog.Width = 6
$cabLog.Controls.Add($rotuloLog); $cabLog.Controls.Add($bLimparLog); $cabLog.Controls.Add($espacoLog); $cabLog.Controls.Add($bCopiarLog)
$detalhe = New-Object Windows.Forms.TextBox
$detalhe.Multiline = $true; $detalhe.ReadOnly = $true; $detalhe.ScrollBars = 'Vertical'; $detalhe.BorderStyle = 'None'
$detalhe.Dock = 'Fill'; $detalhe.Font = New-Object Drawing.Font('Consolas', 9.5); $detalhe.BackColor = New-Cor '#F9FAFB'; $detalhe.ForeColor = New-Cor '#374151'
$painelLog.Controls.Add($detalhe); $painelLog.Controls.Add($cabLog)

# Ordem do encaixe: o último adicionado fica mais em cima; a lista ocupa o que sobra.
$form.Controls.Add($lista)
$form.Controls.Add($painelLog)
$form.Controls.Add($barra)
$form.Controls.Add($faixa)
$form.Controls.Add($cabecalho)
$form.Controls.Add($menu)

$script:OnLog = {
    param($m)
    $detalhe.AppendText("[$(Get-Date -Format HH:mm:ss)] $m`r`n")
}
$script:OnEspera = $null

$bCopiarLog.Add_Click({
    if (-not $detalhe.Text) { return }
    try { [Windows.Forms.Clipboard]::SetText($detalhe.Text); $bCopiarLog.Text = 'Copiado!' } catch { $bCopiarLog.Text = 'Não copiou' }
    $volta = New-Object Windows.Forms.Timer; $volta.Interval = 1500
    $volta.Add_Tick({ param($t) $t.Stop(); $t.Dispose(); $bCopiarLog.Text = 'Copiar registro' })
    $volta.Start()
})
$bLimparLog.Add_Click({ $detalhe.Clear() })

# ---------------------------------------------------------------- trabalho em segundo plano
# Tudo que demora (ler o estado, consertar, testar, reiniciar, consultar o site) roda em outra thread,
# para a janela nunca travar. As linhas do registro chegam por uma fila que o relógio abaixo esvazia.
$script:Fila = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
$script:Trabalhos = New-Object System.Collections.ArrayList
$script:Ocupado = $false
$script:PreparoFundo = @'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
. (Join-Path $AppPasta 'Nucleo.ps1')
. (Join-Path $AppPasta 'Atualizacao.ps1')
$script:OnLog = { param($m) $global:FilaLog.Enqueue([string]$m) }
$script:OnEspera = $null
'@

# Roda $codigo (que usa $ArgFundo) em outra thread; quando termina, chama $aoTerminar($saida, $erro) na janela.
function Start-Fundo([scriptblock]$codigo, $arg, [scriptblock]$aoTerminar) {
    if ($Captura) {
        # Na captura (sem janela visível) roda direto.
        $ArgFundo = $arg
        $saida = $null; $erro = $null
        try { $saida = @(& $codigo) } catch { $erro = $_.Exception.Message }
        & $aoTerminar $saida $erro
        return
    }
    try {
        $iss = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        try { $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass } catch { }
        $rs = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
        $rs.ApartmentState = [Threading.ApartmentState]::STA
        $rs.ThreadOptions = [Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
        $rs.Open()
        $rs.SessionStateProxy.SetVariable('FilaLog', $script:Fila)
        $rs.SessionStateProxy.SetVariable('AppPasta', $PSScriptRoot)
        $rs.SessionStateProxy.SetVariable('ArgFundo', $arg)
        $ps = [Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript($script:PreparoFundo + "`r`n" + $codigo.ToString())
        $h = $ps.BeginInvoke()
        [void]$script:Trabalhos.Add(@{ ps = $ps; rs = $rs; h = $h; fim = $aoTerminar })
        $bomba.Start()
    } catch {
        & $aoTerminar $null "não consegui iniciar o trabalho em segundo plano: $($_.Exception.Message)"
    }
}

function Write-Fila {
    $m = $null
    while ($script:Fila.TryDequeue([ref]$m)) { & $script:OnLog $m }
}

$bomba = New-Object Windows.Forms.Timer
$bomba.Interval = 100
$bomba.Add_Tick({
    Write-Fila
    foreach ($t in @($script:Trabalhos)) {
        if (-not $t.h.IsCompleted) { continue }
        [void]$script:Trabalhos.Remove($t)
        $saida = $null; $erro = $null
        try { $saida = @($t.ps.EndInvoke($t.h)) } catch { $erro = $_.Exception.Message }
        if ($t.ps.InvocationStateInfo.State -eq 'Failed' -and $t.ps.InvocationStateInfo.Reason) { $erro = $t.ps.InvocationStateInfo.Reason.Message }
        try { $t.ps.Dispose(); $t.rs.Close(); $t.rs.Dispose() } catch { }
        Write-Fila
        try { & $t.fim $saida $erro } catch { Say "ERRO: $($_.Exception.Message)" }
    }
    if ($script:Trabalhos.Count -eq 0) { $bomba.Stop() }
})

function Get-Ultimo($saida) {
    if (-not $saida -or $saida.Count -eq 0) { return $null }
    return $saida[$saida.Count - 1]
}

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
    $script:Ocupado = $o
    foreach ($b in $botoes.Values) { $b.Enabled = -not $o }
    $mRemotes.Enabled = -not $o
    # Cursor de "trabalhando" só na lista e nas barras: o registro continua livre para selecionar e copiar.
    $c = if ($o) { [Windows.Forms.Cursors]::AppStarting } else { [Windows.Forms.Cursors]::Default }
    $lista.Cursor = $c; $barra.Cursor = $c; $cabecalho.Cursor = $c
    if (-not $o) { Update-Botoes }
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
    if ((Get-EstadoSimples $e).texto -ne 'Ativo') { Show-FimDoLog $s.r 6 }
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
    if ($e.processo -and $e.conexao -eq 'iniciando') { return @{ texto = 'Iniciando'; cor = [Drawing.Color]::SteelBlue; dica = 'Acabou de subir; esperando registrar no claude.ai. A lista confere sozinha a cada minuto.' } }
    if ($e.processo) { return @{ texto = 'Erro'; cor = [Drawing.Color]::Firebrick; dica = "Está rodando mas não conectou ($($e.conexao)). Veja o registro embaixo; tente Reiniciar." } }
    return @{ texto = 'Parado'; cor = [Drawing.Color]::DarkOrange; dica = 'Clique em Conferir e consertar para subir.' }
}

# Leitura do estado (roda em segundo plano): só dados, sem mexer na janela.
$script:CodigoLeitura = {
    $procs = Get-ProcessosRC
    $rem = @(foreach ($r in Read-Remotes) { $e = Get-Estado $r $procs; [pscustomobject]@{ r = $r; e = $e } })
    $mod = @(foreach ($m in Get-ModelosPendentes) {
        $pasta = if ($m.pasta) { $m.pasta } else { Get-PastaPadrao }
        $conta = Get-ContaDeModelo $m
        [pscustomobject]@{ m = $m; pasta = $pasta; conta = $conta }
    })
    $sol = @(foreach ($s in Find-TarefasSoltas) {
        $p = Find-ProcessoSolta $s $procs
        $n = if ($p) { Get-Sessoes $p } else { 0 }
        [pscustomobject]@{ s = $s; p = $p; sessoes = $n }
    })
    $versao = Get-ClaudeVersao
    $admin = Test-Admin
    [pscustomobject]@{ leitura = $true; remotes = $rem; modelos = $mod; soltas = $sol; versao = $versao; admin = $admin }
}

$script:UltimoResumo = ''
$script:ComDetalhe = $false
$script:ResumoPendente = $false

# Lê o estado em segundo plano e depois redesenha a lista. -Detalhe: escreve no registro o resumo e o detalhe da linha.
function Update-Lista([switch]$Detalhe) {
    if ($Detalhe) { $script:ComDetalhe = $true }
    Set-Ocupado $true
    $subtitulo.Text = "PC $env:COMPUTERNAME   ·   lendo o estado..."
    Start-Fundo $script:CodigoLeitura $null {
        param($saida, $erro)
        $l = $null
        foreach ($x in @($saida)) { if ($x -and $x.leitura) { $l = $x } }
        if ($erro -or -not $l) {
            Say "ERRO ao ler o estado: $erro"
        } else {
            try { Show-Leitura $l } catch { Say "ERRO ao mostrar a lista: $($_.Exception.Message)" }
        }
        $script:ComDetalhe = $false
        Set-Ocupado $false
    }
}

function Show-Leitura($l) {
    $sel = Get-Selecionado
    $selId = if ($sel) { $sel.chave } else { '' }
    $script:Lendo = $true
    $lista.BeginUpdate()
    $lista.Items.Clear()
    $pendentes = @()
    foreach ($x in @($l.remotes)) {
        $r = $x.r; $e = $x.e
        $script:Estados[$r.id] = $e
        $est = Get-EstadoSimples $e
        $conta = Get-ContaTexto $r.conta $e.login
        $sessoes = if ($e.processo) { [string]$e.sessoes } else { '-' }
        $nome = if ($e.nomeAntigo) { "$($r.nome) (reinicie para trocar o nome)" } else { $r.nome }
        Add-Linha ([pscustomobject]@{ tipo = 'remote'; chave = "r:$($r.id)"; r = $r }) @($nome, $est.texto, $conta, $sessoes, $r.pasta, $est.dica) $est.cor
        if ($est.texto -ne 'Ativo' -or $est.cor -ne [Drawing.Color]::DarkGreen) { $pendentes += "$($r.nome) ($($est.texto))" }
    }
    foreach ($x in @($l.modelos)) {
        Add-Linha ([pscustomobject]@{ tipo = 'modelo'; chave = "m:$($x.m.nome)"; m = $x.m }) @($x.m.nome, 'Não criado', (Get-ContaNome $x.conta), '-', $x.pasta, 'Clique em Criar (ou Remover, se não quiser neste PC).') ([Drawing.Color]::SteelBlue)
        $pendentes += "$($x.m.nome) (Não criado)"
    }
    foreach ($x in @($l.soltas)) {
        $s = $x.s; $p = $x.p
        $txt = if ($p) { 'Ativo' } else { 'Parado' }
        $cor = if ($p) { [Drawing.Color]::DarkGreen } else { [Drawing.Color]::DarkOrange }
        $sessoes = if ($p) { [string]$x.sessoes } else { '-' }
        $nome = if ($s.nome) { $s.nome } else { $s.tarefa }
        Add-Linha ([pscustomobject]@{ tipo = 'solta'; chave = "s:$($s.tarefa)"; s = $s }) @($nome, $txt, (Get-ContaNome $s.conta), $sessoes, $s.pasta, 'Feito fora do programa: Gerenciar pelo programa, ou Remover.') $cor
        if (-not $p) { $pendentes += "$nome (Parado)" }
    }
    $lista.EndUpdate()
    foreach ($it in $lista.Items) { if ($it.Tag.chave -eq $selId) { $it.Selected = $true } }
    if ($lista.SelectedItems.Count -eq 0 -and $lista.Items.Count) { $lista.Items[0].Selected = $true }
    $adm = if ($l.admin) { '' } else { '   ATENÇÃO: aberto sem administrador, consertar vai falhar.' }
    if ($pendentes.Count) {
        $resumo = if ($pendentes.Count -eq 1) { "1 precisa de atenção: $($pendentes[0])" } else { "$($pendentes.Count) precisam de atenção: $($pendentes -join ', ')" }
        $topo.BackColor = New-Cor '#B91C1C'
    } elseif ($lista.Items.Count) {
        $resumo = 'Tudo certo: todos os remotes estão ativos.'
        $topo.BackColor = New-Cor '#15803D'
    } else {
        $resumo = 'Nenhum remote neste PC. Use Remotes > Novo remote.'
        $topo.BackColor = New-Cor '#374151'
    }
    $topo.Text = $resumo
    $subtitulo.Text = "PC $env:COMPUTERNAME   ·   $($l.versao)   ·   programa v$(Get-VersaoLocal)   ·   atualizado às $(Get-Date -Format HH:mm:ss)$adm"
    $script:Lendo = $false
    $script:TemPendente = [bool]$pendentes.Count
    # Na conferência automática só escreve no registro quando o resumo muda.
    if ($script:ComDetalhe -or $resumo -ne $script:UltimoResumo) {
        Say "Resumo: $resumo"
        $script:UltimoResumo = $resumo
        Update-Botoes
        Show-Detalhe
    } else { Update-Botoes }
}

# Roda uma ação em segundo plano ($acao usa $ArgFundo) e depois relê o estado.
function Invoke-Acao([scriptblock]$acao, $arg = $null) {
    if ($script:Ocupado) { Say 'Espere terminar o que está em andamento.'; return }
    Set-Ocupado $true
    Start-Fundo $acao $arg {
        param($saida, $erro)
        if ($erro) { Say "ERRO: $erro" }
        Update-Lista -Detalhe
    }
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
$bAtualizar.Add_Click({ if (-not $script:Ocupado) { Update-Lista -Detalhe } })
$bNovo.Add_Click({
    $r = Show-DialogoRemote $null
    if ($r) { Invoke-Acao { Say "Criado '$($ArgFundo.nome)'."; [void](Repair-Remote $ArgFundo) } $r }
})
$bCriar.Add_Click({
    $s = Get-Selecionado
    if (-not $s) { return }
    Invoke-Acao {
        $s = $ArgFundo
        if ($s.tipo -eq 'modelo') { $r = New-RemoteDeModelo $s.m }
        else { $r = Convert-TarefaSolta $s.s; Say "Tarefa '$($s.s.tarefa)' adotada como '$($r.nome)'." }
        [void](Repair-Remote $r)
    } $s
})
$bConsertar.Add_Click({ $s = Get-Selecionado; Invoke-Acao { [void](Repair-Remote $ArgFundo) } $s.r })
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
        $r = $ArgFundo
        Initialize-Conta $r.conta
        if (Start-Login $r) {
            $l = Get-Login $r.conta
            $r.email = $l.email; Save-Remote $r
            if (-not (Find-Processo $r (Get-ProcessosRC))) { [void](Repair-Remote $r) }
        }
    } $s.r
})
$bTestar.Add_Click({ $s = Get-Selecionado; Invoke-Acao { [void](Test-Remote $ArgFundo) } $s.r })
$bReiniciar.Add_Click({
    $s = Get-Selecionado
    $e = $script:Estados[$s.r.id]
    if ($e -and $e.sessoes -gt 0) {
        $q = [Windows.Forms.MessageBox]::Show($form, "'$($s.r.nome)' tem $($e.sessoes) sessão(ões) abertas. Reiniciar derruba essas sessões (inclusive um Claude que esteja trabalhando nelas). Continuar?", 'Reiniciar', 'YesNo', 'Warning')
        if ($q -ne 'Yes') { return }
    }
    Invoke-Acao { [void](Restart-Remote $ArgFundo) } $s.r
})
$bEditar.Add_Click({
    $s = Get-Selecionado
    $r = Show-DialogoRemote $s.r
    if ($r) { Invoke-Acao { Say "Salvei '$($ArgFundo.nome)'."; [void](Repair-Remote $ArgFundo) } $r }
})
$bRemover.Add_Click({
    $s = Get-Selecionado
    if (-not $s) { return }
    switch ($s.tipo) {
        'remote' {
            $e = $script:Estados[$s.r.id]
            $aviso = if ($e -and $e.sessoes -gt 0) { "`r`n`r`nAtenção: ele tem $($e.sessoes) sessão(ões) abertas, que vão cair." } else { '' }
            $q = [Windows.Forms.MessageBox]::Show($form, "Remover '$($s.r.nome)'?`r`n`r`nEle para de rodar e a tarefa do Windows é apagada. O login da conta fica guardado.$aviso", 'Remover', 'YesNo', 'Warning')
            if ($q -eq 'Yes') { Invoke-Acao { Remove-Remote $ArgFundo } $s.r }
        }
        'solta' {
            $nome = if ($s.s.nome) { $s.s.nome } else { $s.s.tarefa }
            $q = [Windows.Forms.MessageBox]::Show($form, "Remover '$nome'?`r`n`r`nEle para de rodar (as sessões abertas caem) e a tarefa do Windows '$($s.s.tarefa)' é apagada. O login da conta fica guardado.", 'Remover', 'YesNo', 'Warning')
            if ($q -eq 'Yes') { Invoke-Acao { Remove-TarefaSolta $ArgFundo } $s.s }
        }
        'modelo' {
            $q = [Windows.Forms.MessageBox]::Show($form, "Não criar '$($s.m.nome)' neste PC?`r`n`r`nEle some da lista deste PC. Nada é apagado.", 'Remover', 'YesNo', 'Question')
            if ($q -eq 'Yes') { Invoke-Acao { Hide-Modelo $ArgFundo } $s.m }
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

$script:VerificandoAtu = $false

# Consulta o site em segundo plano. Modo: 'silencioso' (só mostra a faixa), 'verificar' (diz o resultado
# no registro) ou 'loginsite' (diz se o login do site foi salvo).
function Test-Atualizacao([switch]$PodePedirLogin, [string]$Modo = 'silencioso') {
    if ($script:VerificandoAtu) { if ($Modo -ne 'silencioso') { Say 'Já estou consultando o site, espere um pouco.' }; return }
    $script:VerificandoAtu = $true
    $script:ModoAtu = $Modo
    Start-Fundo {
        $v = $null
        try { $v = Get-VersaoSite -PodePedirLogin:$ArgFundo } catch { }
        $info = $null
        if ($v -and $v.versao) { try { if ([version]$v.versao -gt (Get-VersaoLocal)) { $info = $v } } catch { } }
        [pscustomobject]@{ atualizacao = $true; info = $info; consultou = [bool]($v -and $v.versao) }
    } ([bool]$PodePedirLogin) {
        param($saida, $erro)
        $script:VerificandoAtu = $false
        $res = $null
        foreach ($x in @($saida)) { if ($x -and $x.atualizacao) { $res = $x } }
        $info = if ($res) { $res.info } else { $null }
        $script:Atualizacao = $info
        if ($info) {
            $faixaTexto.Text = "Nova versão $($info.versao) disponível (você está na $(Get-VersaoLocal)). $($info.notas)"
            $faixa.Visible = $true
        } else { $faixa.Visible = $false }
        switch ($script:ModoAtu) {
            'verificar' {
                if ($info) { Say "Nova versão $($info.versao) disponível: clique em Atualizar agora, na faixa amarela." }
                elseif ($res -and $res.consultou) { Say "Você já está na versão mais nova ($(Get-VersaoLocal))." }
                elseif (Get-SiteUrl) { Say 'Não consegui consultar o site agora (sem internet ou sem login do site).' }
            }
            'loginsite' {
                if (Test-Path $script:AtuLogin) { Say 'Login do site salvo.' } else { Say 'Login do site não foi salvo (cancelado ou login/senha errados).' }
            }
        }
    }
}

$bAtualizarApp.Add_Click({
    if (-not $script:Atualizacao -or $script:Atualizando) { return }
    $script:Atualizando = $true
    $bAtualizarApp.Enabled = $false; $bAtualizarApp.Text = 'Atualizando...'
    Say "Baixando a versão $($script:Atualizacao.versao)..."
    Start-Fundo { Install-Atualizacao $ArgFundo } $script:Atualizacao {
        param($saida, $erro)
        $script:Atualizando = $false
        if ((Get-Ultimo $saida) -eq $true) {
            Start-ProgramaDeNovo
            $form.Close()
            return
        }
        $bAtualizarApp.Enabled = $true; $bAtualizarApp.Text = 'Atualizar agora'
        [void][Windows.Forms.MessageBox]::Show($form, 'Não consegui baixar a atualização agora. Tente de novo em alguns minutos.', 'Atualização', 'OK', 'Warning')
    }
})

$bVerificar.Add_Click({ Say 'Consultando o site...'; Test-Atualizacao -PodePedirLogin -Modo 'verificar' })

$relogio = New-Object Windows.Forms.Timer
$relogio.Interval = 10 * 60 * 1000
$relogio.Add_Tick({ Test-Atualizacao })

# Confere o estado sozinho: a cada minuto se algo precisa de atenção, senão a cada 5 minutos.
$script:Voltas = 0
$conferidor = New-Object Windows.Forms.Timer
$conferidor.Interval = 60 * 1000
$conferidor.Add_Tick({
    $script:Voltas++
    if ($script:Ocupado) { return }
    if ($script:TemPendente -or ($script:Voltas % 5 -eq 0)) { Update-Lista }
})

$mSair.Add_Click({ $form.Close() })
$mPastaApp.Add_Click({ Start-Process explorer.exe (Split-Path $PSScriptRoot -Parent) })
$mPastaDados.Add_Click({ New-Item -ItemType Directory -Force $script:Base | Out-Null; Start-Process explorer.exe $script:Base })
$mLoginSite.Add_Click({
    Remove-Item $script:AtuLogin -Force -ErrorAction SilentlyContinue
    Test-Atualizacao -PodePedirLogin -Modo 'loginsite'
})
$mSite.Add_Click({ $u = Get-SiteUrl; if ($u) { Start-Process $u } })
$mSobre.Add_Click({
    [void][Windows.Forms.MessageBox]::Show($form, "Claude Remote Manager $(Get-VersaoLocal)`r`n`r`nGerencia os Remote Control do Claude Code deste PC, com várias contas.`r`nAtualizações: $(Get-SiteUrl)", 'Sobre', 'OK', 'Information')
})

function Start-Janela {
    & $ajustarColunas
    Update-Lista -Detalhe
    if ($script:ExeErro) { Say "Não consegui gerar o Claude Remote Manager.exe (o programa segue pelo PowerShell): $($script:ExeErro)" }
    if (-not $Captura) { Test-Atualizacao -PodePedirLogin; $relogio.Start(); $conferidor.Start() }
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
# Algo ainda rodando em segundo plano (ex.: janela de login aberta)? Para tudo e fecha o programa de vez.
if ($script:Trabalhos.Count) {
    foreach ($t in @($script:Trabalhos)) { try { [void]$t.ps.BeginStop($null, $null) } catch { } }
    [Environment]::Exit(0)
}
