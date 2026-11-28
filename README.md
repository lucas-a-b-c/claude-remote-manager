# Claude Remote Manager

Programa com janela para gerenciar os **Remote Control do Claude Code** de um PC Windows, com várias contas lado a lado.

Ele mostra os remotes configurados na máquina, se cada um está rodando e conectado, qual conta está logada, e permite criar, conferir, consertar, entrar na conta, testar, reiniciar e remover. Cada remote sobe com o Windows **sem login e sem janela** (tarefa agendada S4U) e é reiniciado sozinho se cair.

## Como usar

1. Clone este repositório no PC (por exemplo em `C:\Projetos\claude-remote-manager`).
2. Dê dois cliques em **`Gerenciar Remote Control.bat`** e aceite o pedido de administrador. Na primeira vez ele gera o **`Claude Remote Manager.exe`** na mesma pasta (compilado no próprio PC com o .NET que vem no Windows) e passa a abrir por ele: daí em diante use o `.exe` (dá para fixar na barra de tarefas). No Gerenciador de Tarefas ele aparece como Claude Remote Manager.
3. Na janela:
   - A coluna **Estado** diz em uma palavra como está cada um: **Ativo**, **Parado**, **Sem login**, **Erro** ou **Não criado**. A coluna **O que fazer** diz qual botão usar.
   - **Não criado** (azul) são remotes sugeridos (de `app/modelos.json`) que ainda não existem neste PC: selecione e clique **Criar**, ou **Remover...** se não quiser neste PC.
   - Tarefas de Remote Control feitas fora do programa aparecem com "Feito fora do programa": **Gerenciar pelo programa** passa a cuidar delas sem derrubar o que está rodando, e **Remover...** para e apaga a tarefa.
   - **Remover...** sempre pede confirmação e mantém o login da conta.
   - Quando uma conta não está logada, **Entrar na conta** abre uma janelinha do próprio programa: um botão abre o login numa janela anônima do navegador e uma caixa recebe o código que o site mostra. Sem terminal.

Rodar de novo só confere e conserta: nada que está rodando é derrubado (o nome novo de um remote vale depois de **Reiniciar** ou do próximo boot).

Sem janela: `"Gerenciar Remote Control.bat" /consertar` (abre login se precisar) ou `/consertar-sem-login` (só avisa; para uma sessão remota rodar).

## Como funciona

- **Conta** = pasta de configuração do Claude Code (`CLAUDE_CONFIG_DIR`, o jeito documentado de usar várias contas: cada pasta tem seu login, settings e histórico). A conta `padrao` é a `%USERPROFILE%\.claude` normal; as outras ficam em `%USERPROFILE%\.claude-contas\<nome>`. Uma conta nova recebe uma cópia do `settings.json` da padrão.
- **Remote** = nome + conta + pasta de trabalho + modo (`same-dir`, `worktree` ou `session`). Fica salvo em `%USERPROFILE%\.claude-remote-manager\remotes.json` (por PC, fora do repositório).
- Para cada remote o programa gera `%USERPROFILE%\.claude-remote-manager\rc\<id>\iniciar.cmd` e a tarefa agendada que o chama: no boot, a cada 5 min e ao voltar da suspensão, reiniciando a cada 1 min se cair, uma cópia só. Os logs ficam na mesma pasta (`remote-control.log`, `debug.log`); transcrições com mais de 7 dias são apagadas a cada início.
- Se o login expirar, o lançador grava `FALHA-LOGIN.txt` na pasta do remote, e a janela mostra o problema e oferece **Entrar na conta**.
- A pasta de trabalho é marcada como confiável na conta (sem terminal o Remote Control recusa pasta não confiável).
- Atualizar a tarefa agendada não derruba o processo que já está rodando (testado).

## Atualização automática

Com a janela aberta, o programa pergunta ao site **CruzVerbenaGroup** (endereço em `app/site.json`) qual é a versão publicada, ao abrir, a cada 10 minutos e quando você clica em **Verificar atualização**. Se for mais nova que `app/versao.txt`, aparece uma faixa amarela no topo, "Nova versão X disponível", com o botão **Atualizar agora**: ele baixa o pacote, instala por cima da pasta e reabre a janela sozinho. Os Remote Control que estão rodando não caem. Na primeira vez ele pede o login do site e guarda criptografado para o seu usuário do Windows (`%USERPROFILE%\.claude-remote-manager\site-login.xml`). Sem internet, segue sem aviso. O modo sem janela (`/consertar`) não atualiza.

Para publicar uma versão nova: `powershell -ExecutionPolicy Bypass -File ferramentas\Publicar-Versao.ps1 -Versao 1.0.1 -Notas "O que mudou" -Site C:\Projetos\CruzVerbenaGroup`, depois commit e push nos dois repositórios (ou peça ao Claude).

## Modelos

`app/modelos.json` lista os remotes sugeridos e a pasta padrão:

```json
{
  "pastaPadrao": "C:\\Projetos",
  "remotes": [
    { "nome": "Claude Gufe", "conta": "padrao" },
    { "nome": "Claude Cruz Verbena", "conta": "cruz-verbena" }
  ]
}
```

Ao criar um sugerido, se já existe uma tarefa antiga de Remote Control da mesma conta e pasta, ela é adotada em vez de duplicada.

## Requisitos

Windows 10/11, Windows PowerShell 5.1, Claude Code instalado (`%USERPROFILE%\.local\bin\claude.exe` ou no PATH) e uma conta claude.ai com assinatura (Remote Control não funciona com chave de API nem com `CLAUDE_CODE_OAUTH_TOKEN`).
