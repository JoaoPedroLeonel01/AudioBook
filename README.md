<p align="center">
  <img src="docs/icon.png" width="128" alt="Ícone do AudioBook">
</p>

<h1 align="center">AudioBook</h1>

<p align="center">
  Leitor de EPUB para iOS que transforma qualquer livro em audiolivro, com voz neural em português do Brasil gerada no próprio iPhone.
</p>

<p align="center">
  <img alt="iOS 27" src="https://img.shields.io/badge/iOS-27-blue">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6.4-orange">
  <img alt="SwiftUI" src="https://img.shields.io/badge/UI-SwiftUI-purple">
  <img alt="Licença MIT" src="https://img.shields.io/badge/licença-MIT-green">
</p>

## Sobre

O AudioBook importa um `.epub`, extrai o texto dos capítulos e narra o livro em voz alta, com o texto acompanhando a fala.
Tudo acontece no aparelho: sem backend, login, assinatura ou API paga, e os livros nunca saem do iPhone.

A narração usa vozes neurais do [Piper](https://github.com/rhasspy/piper) rodando localmente via
[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx), com pronúncia brasileira de verdade
("tarde" soa como "tardji", "cidade" como "cidadji"). As vozes nativas do iOS continuam disponíveis como alternativa.

## Funcionalidades

- **Biblioteca**: capa, autor e progresso de cada livro; ▶︎ continua de onde parou.
- **Leitura acompanhada**: o trecho e a palavra falados ficam em destaque, com rolagem automática; toque num parágrafo para ir até ele.
- **Player completo**: capítulo anterior/próximo, avançar/voltar trecho, velocidade de 0,5× a 2×, timer de repouso (minutos ou fim do capítulo) e página aproximada.
- **Segundo plano**: continua tocando com a tela bloqueada e responde aos controles de mídia do sistema.
- **Vozes neurais offline**: síntese no aparelho, sem internet, com troca automática para a voz do sistema se algo falhar.
- **Parser de EPUB próprio**: EPUB 2 e 3, sumário NCX e de navegação, capas, sem dependências; EPUBs com DRM são recusados com mensagem clara.

## Vozes

| Voz | Origem | Licença | No repositório |
|---|---|---|---|
| **Cadu** | Piper `pt_BR-cadu-medium` (int8, 18 MB) | CC0 | ✅ |
| Miro | Piper `pt_BR-miro-high` | CC BY-NC-SA 4.0 (não comercial) | ❌ opcional, uso pessoal |
| Vozes do sistema | `AVSpeechSynthesizer` (padrão, Aprimorada, Premium) | — | nativo do iOS |

O app mostra só as vozes cuja pasta existe em `PiperVoices/`. Para usar o Miro localmente, baixe
[`vits-piper-pt_BR-miro-high-int8.tar.bz2`](https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models)
e copie `pt_BR-miro-high.onnx` e `tokens.txt` para `PiperVoices/miro-high/` (a pasta é ignorada pelo Git).

## Tecnologias

- **SwiftUI** + **Observation** na interface, com view models `@MainActor`.
- **SwiftData** para livros, progresso de leitura e preferências.
- **AVFoundation**: `AVSpeechSynthesizer`, `AVAudioPlayer`, sessão de áudio e Now Playing.
- **sherpa-onnx 1.13.8** + **ONNX Runtime** para as vozes Piper; **espeak-ng** converte o texto em fonemas pt-BR.
- **Swift Testing**: 72 testes, incluindo síntese real com o Piper no simulador.

As escolhas estão explicadas em [`TECHNICAL_DECISIONS.md`](TECHNICAL_DECISIONS.md), como o parser de EPUB sem dependências,
a fila de narração com tokens de geração e por que o Kokoro foi testado e trocado pelo Piper.

## Como executar

Requisitos: Xcode 27 e iOS 27.0.

1. Abra `AudioBook.xcodeproj`. Na primeira vez o Xcode baixa o pacote do sherpa-onnx.
2. Escolha o esquema **AudioBook** e um simulador iOS 27 ou seu iPhone (ajuste o *Team* em Signing).
3. `⌘R`. Toque em **+** para importar um `.epub` do app Arquivos e em ▶︎ para ouvir.
4. Em **Ajustes › Voz**, escolha **Cadu** para a voz neural.

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
`-AutoPlayFirstBook YES` e `-AutoPlayChapter <n>` importam e tocam um livro sem usar o seletor de arquivos.

## Estrutura

```
AudioBook/App         composição (AppEnvironment) e ponto de entrada
AudioBook/Models      Book, ReadingProgress, UserPreferences (SwiftData), ReadingMath
AudioBook/Epub        ZipArchive, EPUBPackage, HTMLScanner/HTMLTextExtractor, EPUBReaderService
AudioBook/Speech      NarrationEngine, TextChunker, VoiceCatalog, sessão de áudio e Now Playing
                      RoutedSpeechService → SpeechService (sistema) | PiperSpeechService + PiperEngine (neural)
AudioBook/Services    EPUBFileStorage, BookRepository
AudioBook/ViewModels  LibraryViewModel, PlayerViewModel, SettingsViewModel
AudioBook/Views       SwiftUI (Biblioteca, Detalhes, Player, Mini-player, Ajustes)
AudioBookTests        testes (Swift Testing) + fixtures geradas por Scripts/make_fixtures.py
PiperVoices           modelos das vozes neurais + espeak-ng-data (só português)
Scripts               gerador de fixtures e do ícone (make_icon.swift)
Config/Info.plist     UIBackgroundModes = audio (mesclado ao Info.plist gerado)
```

## Limitações conhecidas

- EPUBs com DRM são recusados; ZIP64 não é suportado.
- O capítulo é cada documento da *spine* (âncoras internas do sumário não dividem o capítulo).
- Com as vozes Piper, o destaque da palavra falada é estimado pelo tamanho das palavras, pois o modelo não informa o tempo de cada uma.

Mais detalhes em [`TASKS.md`](TASKS.md) e [`TECHNICAL_DECISIONS.md`](TECHNICAL_DECISIONS.md).

## Licença

Código sob a [licença MIT](LICENSE). Componentes de terceiros (sherpa-onnx, ONNX Runtime, dados do espeak-ng e a voz Cadu)
mantêm as próprias licenças; veja [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
