# Jarbas: plano de arquitetura

Site pessoal do Lucas para conversar com um "agente" que distribui pedidos entre as contas do Claude Code e os PCs, mostra quem está fazendo o quê e oferece o download do Claude Remote Manager.

Status: **arquivado em 27/11/2026**. O Lucas desistiu do site; o foco é o app local. Fica aqui só como referência.

## O que dá e o que não dá hoje (verificado no Claude Code 2.1.x)

- **Não há API pública para o site mandar mensagem a uma sessão de Remote Control.** O Remote Control liga o PC ao claude.ai/app pela conta logada; quem fala com ele é o claude.ai, não um site nosso. Então o site **não** conversa direto com o Remote Control.
- **O que dá:** um programa no PC (o "agente Jarbas", parte deste app) roda o próprio `claude` em modo sem janela, com a pasta da conta:
  `CLAUDE_CONFIG_DIR=<pasta da conta> claude -p "<pedido>" --output-format stream-json --resume <sessão do projeto> --permission-mode <modo>`
  - `-p` funciona com o login da assinatura (o mesmo que o Remote Control usa), sem chave de API e sem custo extra além da assinatura.
  - `--resume <id>` continua a conversa do projeto, então cada projeto tem memória entre pedidos.
  - `stream-json` dá o andamento em tempo real, que o agente reenvia ao site.
- **O Remote Control continua útil** do jeito que está: para abrir a sessão no app do celular/claude.ai e mexer na mão. O Jarbas é um caminho a mais, não substitui.
- **Os limites de uso são por conta** (cada assinatura tem os seus). O Jarbas só escolhe para qual conta vai cada pedido; não soma nem burla limites.
- Uso pessoal, só o Lucas acessando. Não abrir o site para outras pessoas usarem as contas dele.

## Desenho

```
 Navegador (Lucas)                     Site Jarbas (grátis)                    PC (Windows)
 ┌──────────────┐   HTTPS    ┌───────────────────────────────┐   HTTPS   ┌──────────────────────────┐
 │ projetos     │ ─────────▶ │ páginas + API                 │ ◀──────── │ agente Jarbas (PowerShell)│
 │ chat         │ ◀───────── │ banco: projetos, pedidos,     │  o PC     │  - avisa "estou vivo"     │
 │ quem faz o quê│           │        PCs, contas, mensagens │  chama o  │  - pega pedidos dele      │
 │ download     │            │ download do app               │  site     │  - roda claude -p na conta│
 └──────────────┘            └───────────────────────────────┘ (sai, não │  - manda a resposta       │
                                                                 entra)  │ Remote Control (como hoje)│
                                                                         └──────────────────────────┘
```

- **O PC sempre chama o site** (sai para a internet). Não precisa abrir porta no roteador nem IP fixo.
- O agente roda como os remotes de hoje: tarefa agendada S4U, sobe com o Windows, sem janela, reinicia se cair.
- Cada PC tem um **token** próprio (gerado no site, colado no app). O site só aceita o PC com token válido.

### Site

- **Projetos**: nome, pasta no PC, conta padrão, PC padrão, id da sessão do Claude.
- **Chat do projeto**: o Lucas escreve, o site cria um pedido na fila com (projeto, conta, PC). A resposta chega em partes e aparece no chat.
- **Painel "quem faz o quê"**: cada PC (online/offline, última vez visto), cada conta (logada? ocupada? em qual projeto?), pedidos em andamento e últimos concluídos.
- **Download**: botão que baixa o zip do Claude Remote Manager (da última versão).

### Roteamento ("para qual conta vai")

- Fase 1: regra fixa. Cada projeto tem conta e PC padrão; no chat dá para trocar antes de mandar. Se a conta está ocupada, o pedido espera na fila.
- Fase 2 (opcional): "Jarbas decide", escolhendo a conta logada e livre, ou mandando a pergunta "para quem vai?" a um `claude -p` barato em uma das contas.

### Agente no PC

- Lê `remotes.json` e as contas já conhecidas pelo app (mesmo núcleo, `Nucleo.ps1`).
- A cada ~10 s: envia status (contas logadas, remotes rodando) e pergunta "tem pedido para mim?".
- Pedido recebido: roda `claude -p` na pasta do projeto com `CLAUDE_CONFIG_DIR` da conta, lê o `stream-json` e manda os pedaços para o site. No fim manda o resultado e o id da sessão.
- Um pedido por conta de cada vez (evita duas conversas na mesma conta brigando).
- Pedido cancelado no site: o agente encerra o processo.

## Hospedagem grátis (sem nada pago)

| Opção | O que usa | Grátis até | Observação |
|---|---|---|---|
| **Cloudflare (recomendado)** | Workers (site + API), D1 (banco), R2 ou GitHub para o download, Access para login | 100 mil requisições/dia, 5 GB de banco | Não dorme, não pede cartão para o plano grátis. Com 2 PCs chamando a cada 10 s são ~17 mil requisições/dia. |
| Vercel + Supabase | Vercel Hobby (site), Supabase Free (banco + login) | uso pessoal | O projeto grátis do Supabase **pausa depois de 1 semana sem uso**. |
| GitHub Pages | só páginas | ilimitado para estático | Serve para a página de download, não para o chat (sem servidor). |

**Railway: não usar.** Só tem um período de teste; depois disso é pago.

**Login no site:** Cloudflare Access (grátis até 50 pessoas) com o e-mail do Lucas, código chega no e-mail. Não precisa escrever tela de senha.

## Fases

1. Site com projetos, chat e fila; agente que pega o pedido e roda `claude -p`; resposta no chat (sem tempo real, só no fim).
2. Resposta em tempo real, painel "quem faz o quê", cancelar pedido.
3. Download do app pelo site e configuração do token pelo app (botão "Ligar ao Jarbas").
4. Roteamento automático (opcional).

## Decisões abertas (só o Lucas decide)

1. **Hospedagem**: Cloudflare (recomendado) ou Vercel + Supabase.
2. **Permissões quando o Jarbas roda um pedido sozinho no PC**: `acceptEdits` (edita arquivos, mas comandos fora da lista são recusados), `auto` (o Claude decide o que é seguro) ou liberar tudo (`bypassPermissions`, mais arriscado). Perguntar no site a cada permissão é possível, mas é bem mais trabalho; fica para depois.
3. **Roteamento**: começar com conta/PC fixo por projeto (recomendado) ou já querer "Jarbas decide".

## Já decidido

- Repositório privado: o zip do app fica no próprio site (R2 grátis ou servido pelo Worker), não em GitHub Releases públicas.
- Código do site na pasta `site/` deste repositório, no master (mesmas regras: fetch + merge, push sem force, sem LFS).
