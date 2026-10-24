<div align="center">

<img src="Docs/images/icon.png" width="112" alt="Ícone do Aura Notch">

# Aura Notch

**Transforme o notch do MacBook em um painel útil e discreto.**
Controles do que está tocando, uma prateleira temporária de arquivos, seus próximos eventos, um temporizador, volume, bateria e histórico da Área de Transferência, a um passar de mouse de distância.

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [简体中文](README.zh-CN.md)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)
![License MIT](https://img.shields.io/badge/license-MIT-blue)
![Status beta](https://img.shields.io/badge/status-beta-yellow)

<img src="Docs/images/closed.png" width="420" alt="Notch fechado enquanto toca música">

</div>

O Aura Notch é um app nativo para macOS escrito em Swift (SwiftUI + AppKit), sem dependências de terceiros. Ele fica no notch, não atrapalha e se abre em um painel quando você aponta para ele. Tudo roda localmente: sem conta, sem análise de dados, sem telemetria.

<div align="center">
<img src="Docs/images/home.png" width="720" alt="Painel Início com o que está tocando, hoje, Área de Transferência e prateleira">
</div>

## Recursos

- **Notch fechado com atividade ao vivo.** Um equalizador animado e o título da faixa aparecem ao lado do notch enquanto algo toca, um temporizador mostra a contagem regressiva e avisos curtos (reunião próxima, carregador conectado, temporizador concluído) deslizam para dentro. A forma fechada tem largura fixa e simétrica, então nunca cresce com o título da música e cobre o mínimo possível da sua barra de menus.
- **Início.** Data e bateria de hoje, o que está tocando com capa e controles de reprodução, eventos de hoje, itens recentes da Área de Transferência e sua prateleira, tudo de relance.
- **Mídia.** Música e Spotify: título, artista, progresso e busca, reproduzir/pausar/próxima/anterior no estilo macOS. Deslize dois dedos sobre o notch fechado para pular faixas. A capa do Spotify é opcional e é a única coisa que o app baixa.
- **Prateleira.** Arraste arquivos ou links em direção ao notch e ele se abre para recebê-los. A prateleira guarda referências, nunca move nem apaga seus originais. Abra, mostre no Finder, copie o caminho, compartilhe ou envie por AirDrop e arraste os itens de volta para fora. Manter os itens entre sessões é opcional.
- **Calendário.** Seus próximos eventos, somente leitura, usando EventKit com permissão explícita.
- **Widgets.** Temporizador, volume, bateria, data e ações rápidas, organizados em uma grade organizada de duas colunas.
- **Histórico da Área de Transferência (opcional).** Texto, links e imagens, guardados apenas na memória. Ignora itens marcados como ocultos ou transitórios (como os de gerenciadores de senhas) e fica desligado até você ativá-lo.
- **Temas e idiomas.** Escolha uma cor de destaque e o tamanho do notch fechado. A interface está disponível em inglês, espanhol, francês, alemão, português do Brasil e chinês simplificado.
- **Bom cidadão.** Painel que não ativa a janela e nunca rouba o foco, atalho global (`⌃⌥N`), ícone na barra de menus, abrir ao fazer login, respeita *Reduzir Movimento*, some sobre apps em tela inteira (configurável) e fica em cerca de 0% de CPU quando ocioso.
- **Funciona sem notch.** Em Macs e telas sem notch, ele vira uma pequena pílula flutuante no centro do topo da tela.

<div align="center">
<img src="Docs/images/media.png" width="360" alt="Painel Mídia"> <img src="Docs/images/clipboard.png" width="360" alt="Painel Área de Transferência">
</div>

## Instalação

1. Baixe o `AuraNotch.zip` da [versão mais recente](https://github.com/PabloJuGo/AuraNotch/releases/latest) e descompacte.
2. Arraste o **AuraNotch.app** para a pasta Aplicativos.
3. Na primeira vez, **clique com o botão direito > Abrir** no app e confirme. O app tem assinatura ad-hoc, mas não é notarizado (a notarização exige uma conta paga de desenvolvedor Apple), então o macOS pede que você o aprove uma vez. Se o macOS ainda recusar, execute:
   ```sh
   xattr -dr com.apple.quarantine /Applications/AuraNotch.app
   ```
4. Procure a faixa do notch no topo da tela (e o ícone na barra de menus). Passe o ponteiro ou clique nela, ou pressione `⌃⌥N`.

**Requisitos:** macOS 14 ou posterior. Foi desenvolvido e testado em um MacBook com notch rodando macOS 27; outras configurações devem funcionar, mas foram menos testadas.

## Ajustes

Abra os **Ajustes** pela engrenagem no cabeçalho do painel ou pelo ícone na barra de menus.

| Seção | O que você pode mudar |
|---|---|
| Geral | Abrir ao fazer login, modo de tela, **idioma da interface**, cor de destaque, tamanho do notch fechado |
| Interação | Abrir ao passar o ponteiro, ao clicar ou com o atalho global; atraso ao passar o ponteiro; comportamento em tela inteira; título no notch fechado; deslizar para pular; avisos |
| Animações | Movimento (seguir o sistema, reduzido ou nenhum) |
| Módulos | Ativar, desativar e reordenar Início, Mídia, Prateleira, Calendário, Widgets e Área de Transferência |
| Privacidade | Manter a prateleira entre sessões, limite do histórico, capa do Spotify, apagar todos os dados |

A mudança de idioma só tem efeito após reiniciar; o app oferece um botão **Reiniciar agora**.

## Privacidade e permissões

- Sem conta, sem análise de dados, sem telemetria, sem verificação de atualizações.
- **Rede:** a única requisição é a imagem da capa do Spotify, a partir do endereço que o próprio Spotify fornece. Você pode desativá-la em Ajustes → Privacidade.
- **As permissões são solicitadas apenas quando você usa o recurso que precisa delas:** *Automação* para controlar a Música e o Spotify (ver o que está tocando não exige permissão) e *Calendários* para listar seus eventos (somente leitura).
- A prateleira guarda referências aos seus arquivos, o histórico da Área de Transferência fica apenas na memória, e **Ajustes → Privacidade → Apagar todos os dados** limpa tudo.

Mais detalhes em [PRIVACY.md](PRIVACY.md) e [SECURITY.md](SECURITY.md) (ambos em espanhol por enquanto).

## Compilar a partir do código-fonte

Você só precisa do toolchain do Swift 6 (as Xcode Command Line Tools bastam).

```sh
git clone https://github.com/PabloJuGo/AuraNotch.git
cd AuraNotch
swift build
swift run AuraSelfTests            # test suite with detailed failures
swift run AuraNotch                # run without packaging (no Calendar/Automation prompts)
Scripts/package-app.sh             # builds dist/AuraNotch.app (release, ad-hoc signed)
```

Flags úteis: `--skip-onboarding`, `--start-module=<home|media|shelf|calendar|widgets|clipboard>`.

As notas de arquitetura estão em [ARCHITECTURE.md](ARCHITECTURE.md) e as decisões de design em [Docs/decisions](Docs/decisions) (em espanhol).

## Status e limitações conhecidas

O Aura Notch está em **beta**. O que vale saber:

- Não é notarizado (veja Instalação). Não há atualização automática.
- Os fluxos de Calendário e AirDrop dependem de permissões e diálogos do sistema e foram pouco testados em hardware real.
- Telas externas, várias telas e VoiceOver foram pouco testados na prática.
- O pedido de permissão de Automação do Spotify pode demorar a aparecer em versões recentes do macOS; nesse caso, o macOS pergunta na primeira vez que você usar um controle.
- As traduções além do inglês e do espanhol foram feitas com auxílio de máquina e não foram revisadas por falantes nativos. Correções são muito bem-vindas.
- Alguns documentos do projeto (notas de arquitetura, decisões, privacidade) ainda estão em espanhol.

## Contribuindo

Issues e pull requests são bem-vindos; veja [CONTRIBUTING.md](CONTRIBUTING.md). Para corrigir ou adicionar uma tradução, edite `Resources/<language>.lproj/Localizable.strings` e execute `Scripts/check-localizations.py`.

## Licença

[MIT](LICENSE). O Aura Notch é um projeto independente e não é afiliado à Apple, ao Spotify nem a qualquer outro app mencionado aqui.
