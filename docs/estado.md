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

## Pendente

- Publicar versão nova: `ferramentas/Publicar-Versao.ps1` (ou pedir ao Claude), commit e push no app e no site.
- PC Letícia e PC Lucas: abrir o programa, criar "Claude Gufe" (adota a tarefa antiga "Claude Remote Control - MedievalOnline") e "Claude Cruz Verbena" (pede login da outra conta).
- Conferir a janela visualmente na primeira vez que for aberta numa área de trabalho.
