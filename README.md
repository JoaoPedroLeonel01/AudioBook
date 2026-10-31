# AudioBook

Leitor de EPUB para iOS que narra os livros com a voz nativa do iPhone (`AVSpeechSynthesizer`).
Uso pessoal, 100% local: sem backend, login, assinatura ou API paga. Os livros nunca saem do aparelho.

## Requisitos
- Xcode 27 (Swift 6.4 em modo de linguagem 5), alvo **iOS 27.0** (configuração original do projeto).
- Nenhuma dependência externa (sem SPM/CocoaPods). EPUB é lido por parser próprio (ver `TECHNICAL_DECISIONS.md`).

## Como abrir e executar
1. Abra `AudioBook.xcodeproj` no Xcode.
2. Escolha o esquema **AudioBook** e um simulador iOS 27 (ou seu iPhone; ajuste o *Team* em Signing se necessário).
3. `⌘R`. Toque em **+** para importar um `.epub` do app Arquivos e em ▶︎ para ouvir.

Linha de comando:
```bash
xcodebuild build -project AudioBook.xcodeproj -scheme AudioBook \
  -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test  -project AudioBook.xcodeproj -scheme AudioBook \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```
Teste opcional com EPUBs reais (não incluídos no repositório):
`TEST_RUNNER_AUDIOBOOK_SAMPLE_EPUBS=/pasta/com/epubs xcodebuild test ...`

Ganchos de depuração (apenas build Debug): argumentos de lançamento `-ImportEPUBPath <arquivo>`,
`-AutoPlayFirstBook YES` e `-AutoPlayChapter <n>` importam/tocam um livro sem usar o seletor de arquivos.

## Uso
- **Biblioteca**: lista com capa, autor e progresso; ▶︎ continua de onde parou; deslize ou segure para excluir.
- **Detalhes**: capítulos na ordem de leitura; toque em um capítulo para ouvir a partir dele.
- **Player**: botão de texto na barra alterna capa ↔ **leitura acompanhada** (trecho e palavra falados em destaque, rolagem automática, toque em um parágrafo para ir até ele; mostra página aproximada). play/pause, capítulo anterior/próximo, ±trecho, barra de posição no capítulo, velocidade 0,5×–2×, timer de repouso (minutos ou fim do capítulo).
- **Ajustes**: idioma, voz (padrão/aprimorada/premium), velocidade e "Teste de voz". Para vozes melhores instale-as em Ajustes › Acessibilidade › Conteúdo Falado › Vozes.
- Reprodução continua com a tela bloqueada/em segundo plano e responde aos controles de mídia do sistema.

## Estrutura
```
AudioBook/App         composição (AppEnvironment) e ponto de entrada
AudioBook/Models      Book, ReadingProgress, UserPreferences (SwiftData), ReadingMath
AudioBook/Epub        ZipArchive, EPUBPackage, HTMLScanner/HTMLTextExtractor, EPUBReaderService
AudioBook/Speech      NarrationEngine, SpeechService, TextChunker, AudioSessionManager, NowPlayingManager
AudioBook/Services    EPUBFileStorage, BookRepository
AudioBook/ViewModels  LibraryViewModel, PlayerViewModel, SettingsViewModel
AudioBook/Views       SwiftUI (Biblioteca, Detalhes, Player, Mini-player, Ajustes)
AudioBookTests        testes (Swift Testing) + fixtures geradas por Scripts/make_fixtures.py
Config/Info.plist     UIBackgroundModes = audio (mesclado ao Info.plist gerado)
```

## Limitações conhecidas
Veja `TASKS.md` (seção "Não validado") e `TECHNICAL_DECISIONS.md`. Resumo: EPUBs com DRM são recusados;
ZIP64 não é suportado; o capítulo é cada documento da *spine* (âncoras internas do sumário não dividem o capítulo).
