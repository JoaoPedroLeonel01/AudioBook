# TASKS

Estado em 2026-10-21. Status: ✅ concluída · ⚠️ concluída com validação parcial · ⛔ bloqueada.

| ID | Objetivo | Status | Arquivos principais | Validação realizada |
|----|----------|--------|---------------------|---------------------|
| A | PoC de áudio (voz pt-BR, iniciar/pausar/retomar/parar, velocidade) | ✅ | `Speech/SpeechService.swift`, `Views/SettingsView.swift` (Teste de voz) | Build; fala real no simulador com eventos `didStart/willSpeak/didFinish` avançando o progresso. **Não** foi possível ouvir o áudio (sem humano); validado por eventos. |
| B | Importação/processamento de EPUB | ✅ | `Epub/*` | 60 testes; 4 EPUBs reais (pt/en, EPUB2 NCX e EPUB3) importados em 0,05–0,1 s com título, autor, idioma, capa e capítulos. |
| C | Biblioteca SwiftUI | ✅ | `Views/LibraryView.swift`, `BookDetailsView.swift`, `ViewModels/LibraryViewModel.swift` | Screenshots no simulador (lista, detalhes, vazio via testes de lógica); exclusão testada (arquivos + registros). **Seleção via `fileImporter` não foi exercitada com toque** (usado gancho de depuração equivalente). |
| D | Motor de narração | ✅ | `Speech/NarrationEngine.swift`, `TextChunker.swift` | 13 testes com sintetizador falso (ordem, sem repetição/omissão, pausa/retomada, troca de velocidade, seek, comandos concorrentes, capítulo indisponível). No simulador: virada automática de capítulo 1→4 com fala real. |
| E | Persistência | ✅ | `Models/*`, `Services/BookRepository.swift` | Testes (progresso, reabertura com SQLite em disco, limites). No simulador: reabrir o app mostra "capítulo 4 de 26". |
| F | Segundo plano / controles do sistema | ⚠️ | `Speech/AudioSessionManager.swift`, `NowPlayingManager.swift`, `Config/Info.plist` | `UIBackgroundModes=audio` confirmado no Info.plist do build; categoria `.playback/.spokenAudio`; comandos remotos e Now Playing implementados. **Não validado**: tela bloqueada, outro app, controles da Central de Controle, interrupção por chamada, fones (exige aparelho físico). |
| G | Configurações | ✅ | `ViewModels/SettingsViewModel.swift`, `Views/SettingsView.swift` | Teste de persistência; screenshot. Timer de repouso (minutos / fim do capítulo) implementado no player, **sem teste automatizado**. |
| H | Refinamento | ⚠️ | — | Acessibilidade básica (rótulos/valores), estados vazio/carregando/erro, exclusão segura (nunca sai da raiz), limpeza de órfãos, tratamento de arquivo ausente. Sem teste de desempenho com livros muito grandes (maior testado: 10 MB, 570 mil caracteres). |

| I | Leitura acompanhada + página aproximada | ✅ | `Views/ReadAlongView.swift`, `Models/ReadParagraph.swift` | 3 testes novos (63 no total) e screenshot no simulador com destaque de trecho/palavra. Página é estimativa (~1800 caracteres), pois EPUB não tem páginas fixas. |

## Não validado (exige dispositivo/humano)
- Áudio com tela bloqueada e em segundo plano; Central de Controle/tela de bloqueio; interrupções (chamada, Siri); fones conectados/desconectados.
- Qualidade audível da voz/velocidade; VoiceOver real; Dynamic Type extremo.
- Importação pelo seletor de arquivos tocando na UI; arquivos em iCloud não baixados.
- Timer de repouso e `PlayerViewModel` (lógica de interrupção) sem testes automatizados.

## Problemas encontrados e resolvidos
- Chave `INFOPLIST_KEY_UIBackgroundModes` não é emitida pelo Xcode → plist parcial (D6).
- `AVAudioSessionInterruptionNotification` obsoleta no iOS 27 → nova API (D5).
- Livros com notas de rodapé de URL: URLs agora não são narradas.
- Sumário com rótulo numérico ("1") + título → combinados ("1. Introdução…").
- Livro pt-BR com `dc:language=en` → padrão de idioma pt-BR (D10).

## Limitações conhecidas
- Capítulo = documento da spine; sumários com âncoras internas (ex.: 284 entradas em 27 arquivos) mostram só o primeiro título (combinado) por arquivo.
- Front matter sem título recebe "Seção N". ZIP64/ZIP criptografado não suportados. DRM recusado (por desenho).
- Deploy target iOS 27.0 (herdado do projeto).

## Próximo passo sugerido
Instalar em iPhone físico e executar a checklist da seção "Não validado", incluindo a voz neural Piper (Cadu) com tela bloqueada. Repositório: https://github.com/JoaoPedroLeonel01/AudioBook
