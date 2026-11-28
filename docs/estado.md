# Estado

Memória compartilhada entre as contas do Claude que trabalham neste repositório. Antes de começar: `git fetch`, ler este arquivo, marcar a tarefa como "em andamento" com conta e máquina, e fazer push.

## Em andamento

(nada)

## Feito

- 27/11/2026, conta Claude Gufe, PC Letícia (DESKTOP-53QAL6R): primeira versão. Janela (WinForms) + núcleo em PowerShell + `.bat` com elevação. Testado neste PC com remotes de teste: criar do zero (tarefa S4U, subiu e registrou no claude.ai), conferir de novo sem derrubar, conta sem login (grava FALHA-LOGIN e não sobe), adotar tarefa antiga sem matar o processo, reiniciar com nome novo, remover. A janela foi verificada só por dump de estado (a sessão de teste roda na sessão 0, sem área de trabalho).

- 27/11/2026, sessão na nuvem: plano do site Jarbas em `docs/jarbas.md`. Arquivado, o Lucas preferiu focar no app local.

- 27/11/2026, sessão na nuvem (thread do site CruzVerbenaGroup): site https://site-production-9ae5c440.up.railway.app (repo `CruzVerbenaGroup`, login nas variáveis do Railway) com o download do app e `/api/versao/claude-remote-manager`. Versão 1.0.0: atualização automática ao abrir a janela (`app/Atualizacao.ps1`). Versão 1.1.0/1.1.1: aviso de versão nova numa faixa amarela no topo com botão **Atualizar agora** (checa ao abrir e a cada 10 min, reabre sozinho); **Remover...** com confirmação também para tarefas feitas fora do programa (ex.: MedievalOnline) e para sugestões; estados simples (Ativo, Parado, Sem login, Erro, Não criado) e coluna "O que fazer"; lista não cobre mais o painel de botões. Não testado no Windows (o container não tem PowerShell): conferir a janela, o Remover numa tarefa solta e a faixa de atualização.

- 27/11/2026, sessão na nuvem: 1.1.2 corrige "Entrar na conta" (no PC Lucas a janela piscava e fechava). O login agora abre um `.cmd` visível (`rc\<id>\login.cmd`) que mostra o erro e espera uma tecla se falhar; o programa espera pelo arquivo de fim ou pela conta logada, sem depender do processo da janela. `app/login.ps1` saiu. 1.1.3: botão **Verificar atualização** (seção Geral). Não testado no Windows.

- 27/11/2026, sessão na nuvem: 1.2.0, login pelo próprio programa (sem terminal). O `claude auth login` roda escondido com a entrada redirecionada (testado no Linux: com stdin em pipe ele imprime o link e lê o código de uma linha). A janela do programa abre o link numa janela anônima (Edge InPrivate ou Chrome, como usuário comum via `runas /trustlevel`), tem caixa para colar o código (enviado sem espaços) e mostra o erro em português. No PC Lucas o código colado no terminal dava "invalid code". Não testado no Windows.

- 28/11/2026, sessão na nuvem: 1.2.1, resumo geral no topo e no log ("Tudo certo" só quando todos estão ativos; senão lista quem precisa de atenção) e detalhes rotulados com o nome do remote. No PC Lucas o log mostrava "Tudo certo" da Gufe com a Cruz Verbena sem login. Não testado no Windows.

- 28/11/2026, sessão na nuvem: 1.2.2, "Abrir em janela anônima" travava a janelinha de login (o `runas /trustlevel` com `-Wait` ficava esperando o navegador). Agora abre o Edge/Chrome direto, sem esperar. Não testado no Windows.

- 28/11/2026, sessão na nuvem: 1.3.0, o programa vira `Claude Remote Manager.exe` (ícone próprio, pede administrador pelo manifesto). O .exe é um lançador em C# (`app/Lancador.cs`) que roda `app/Janela.ps1` dentro do próprio processo (runspace STA, console escondido para os comandos filhos). É compilado no PC por `app/Executavel.ps1` com o csc.exe do .NET Framework e refeito quando o código dele muda; fica fora do git. Quem abre pelo PowerShell (o .bat ou uma atualização) passa sozinho para o .exe. O login do site agora é uma janelinha própria (sem Get-Credential). Não testado no Windows.

- 28/11/2026, sessão na nuvem: 1.3.1, a janela de login dava "Não deu certo. Paste code here if prompted >" assim que abria: o processo que abrimos terminava logo, provavelmente porque o claude.exe passa o trabalho para outro processo. Agora a falha só conta com "Couldn't log in" na saída ou quando nenhum `claude.exe auth login` está vivo; a saída fica em `rc\<id>\login-saida.txt`. Não testado no Windows.

- 28/11/2026, sessão na nuvem: 1.3.2, a atualização só troca a pasta `app` e atualiza o `.bat`/README só se ainda existem. O zip do site passa a ter só `app/` (`git archive HEAD app`), com `app/Abrir.bat` para instalação nova. Não testado no Windows.

- 28/11/2026, sessão na nuvem: 1.3.3, o `claude auth login` abria sozinho o navegador normal. Agora roda com `BROWSER=%WINDIR%\System32\where.exe` (no código do CLI para Linux a variável BROWSER substitui o abridor; no Windows não confirmado). Não testado no Windows.

- 28/11/2026, sessão na nuvem: 1.4.0, visual novo. Menu superior (Arquivo, Remotes, Configurações, Ajuda) com as ações gerais e configurações (recarregar F5, novo remote Ctrl+N, criar e conferir todos, pastas, trocar login do site, verificar atualização, sobre). Ações do remote selecionado numa barra acima da lista e no botão direito; sem painel lateral com rolagem. Linhas mais altas, última coluna ocupa o espaço, registro embaixo com título. Não testado no Windows.

- 28/11/2026, sessão na nuvem: 1.5.0, visual caprichado: cabeçalho escuro com título, PC/versões e o resumo geral numa etiqueta verde/vermelha; lista desenhada pelo programa (OwnerDraw) com cabeçalho discreto, linhas altas, seleção azul-clara e o Estado como etiqueta colorida com bolinha; barra de ações e registro em cinza-claro. Não testado no Windows.

- 28/11/2026, sessão na nuvem: 1.5.1, a janela parecia travada enquanto esperava o Remote Control registrar (Wait-Um dormia 1 s por vez); agora dorme em pedaços de 40 ms. Depois de um login bem-sucedido, apaga FALHA-LOGIN.txt (antes pedia login de novo). Se não registrar, mostra as últimas linhas do remote-control.log no registro. No PC Lucas a Cruz Verbena logou (cruzverbenagroup@gmail.com) mas não vimos ainda se registrou.

- 28/11/2026, sessão na nuvem: 1.5.2, o detalhe dizia "está funcionando" com o estado Erro; agora, se o processo roda mas não conectou, o detalhe diz isso. O lançador grava a saída do `claude remote-control` em `rc\<id>\saida.log` (antes ia para nul) e a janela mostra o fim de saida.log, remote-control.log e debug.log quando o remote não está Ativo. Objetivo: ver por que a Cruz Verbena roda e não registra (suspeita: pergunta de primeira execução na conta nova). Não testado no Windows.

- 28/11/2026, sessão na nuvem: 1.5.3, a janela travava enquanto lia o estado ou esperava o Remote Control (tudo rodava na thread da janela; cada leitura chama `claude auth status` por conta, CIM e tarefas agendadas). Agora ler o estado, as ações (conferir, testar, reiniciar, login, remover), a consulta ao site e a atualização rodam em outra thread (runspace STA), e o registro chega por uma fila. Botões Copiar registro e Limpar. A espera do registro não usa mais a data do debug.log (o Windows não atualiza a data de arquivo aberto) e lê o arquivo mesmo aberto pelo claude; nos primeiros 3 minutos o estado é Iniciando, não Erro; depois de 90 s sem confirmar, diz que continua conferindo. A lista se confere sozinha a cada minuto quando algo precisa de atenção (senão a cada 5). No PC Lucas os dois remotes (Gufe e Cruz Verbena) ficaram Ativos em 1.5.2. Não testado no Windows.

- 28/11/2026, sessão na nuvem: 1.5.4, a 1.5.3 abria com a lista vazia no PC Lucas: a thread de fundo não carregava o Nucleo.ps1 (as funções não existiam lá; causa exata não confirmada) e os erros eram ignorados. Agora o núcleo é carregado pelo texto ([scriptblock]::Create, sem política de execução nem $PSScriptRoot), os erros da thread de fundo aparecem no registro, e se mesmo assim não carregar o programa volta a rodar tudo na thread da janela (como na 1.5.2). A 1.5.3 não consegue se atualizar sozinha (a consulta ao site também rodava na thread quebrada): instalar a 1.5.4 à mão. Não testado no Windows.

- 28/11/2026, sessão na nuvem: 1.5.5, instalação em PC novo: o zip do site tem `Instalar.bat` na raiz (pede administrador e chama `app\Instalar.ps1`), que copia a pasta app para `%LOCALAPPDATA%\Programs\Claude Remote Manager`, gera o .exe, cria atalhos na área de trabalho e no menu Iniciar e abre o programa. A atualização continua trocando só a pasta app (o Instalar.bat não vai para a pasta instalada). A página do site mostra os 3 passos. Não testado no Windows.

- 28/11/2026, sessão na nuvem: 1.5.6, o zip do site traz o `Claude Remote Manager.exe` pronto na raiz (Lucas: "pq já não baixa com o exe?"): extrair e abrir. O .exe é compilado na publicação com o Mono (`ferramentas/Gerar-Exe.sh`); o lançador carrega o PowerShell do Windows por reflexão (não precisa dele para compilar) e, como o mcs não põe manifesto, pede administrador sozinho (reabre com runas). A atualização troca também o .exe (renomeia o aberto para .old, o novo apaga). O PC só compila o .exe se ele faltar. Tirado o Instalar.bat da 1.5.5. Não testado no Windows.

- 28/11/2026, sessão na nuvem: 1.5.7, as versões 1.5.2 a 1.5.6 estavam quebradas por um erro de sintaxe no Nucleo.ps1 (`$dir:` dentro de uma string; o PowerShell lê como unidade de disco). Agora há teste de verdade no Windows: `.github/workflows/teste-windows.yml` gera o .exe com o Mono, confere a sintaxe de todos os .ps1, instala o Claude Code e abre o .exe em modo de teste (`CRM_TESTE=<arquivo>`, `ferramentas/Teste-Windows.ps1`), exigindo lista carregada sem erro. Passou (leitura em 6 s, em segundo plano). Publicar só com esse teste verde. A janela também mostra o passo da leitura quando demora.

- 28/11/2026, sessão na nuvem: 1.5.8, a leitura reescreve sozinha o lançador de versão antiga (Gufe aparecia "o lançador precisa ser atualizado"; não derruba nada, vale no próximo início). Remote que registrou e não teve erro depois conta como conectado mesmo com o debug.log parado (Cruz Verbena aparecia Erro "sem sinal há 37 min" com 0 sessões; sem sessões o log fica quieto). Testado no Windows pelo CI.

- 28/11/2026, sessão na nuvem: 1.5.9, causa da Cruz Verbena não registrar: na primeira vez de uma conta, `claude remote-control` pergunta "Enable Remote Control? (y/n)" e fica parado (visto no saida.log do PC Lucas). A resposta fica em `remoteDialogSeen: true` no .claude.json da conta (achado no código do CLI 2.1.332). O programa grava isso antes de subir (Start-Remote) e, se o processo já está parado na pergunta, Conferir e consertar derruba e sobe de novo já respondido. Estado mostra Erro com essa explicação. Testado no CI.

## Pendente

- Publicar versão nova: `ferramentas/Publicar-Versao.ps1` (ou pedir ao Claude), commit e push no app e no site.
- PC Letícia e PC Lucas: abrir o programa, criar "Claude Gufe" (adota a tarefa antiga "Claude Remote Control - MedievalOnline") e "Claude Cruz Verbena" (pede login da outra conta).
- Conferir a janela visualmente na primeira vez que for aberta numa área de trabalho.
