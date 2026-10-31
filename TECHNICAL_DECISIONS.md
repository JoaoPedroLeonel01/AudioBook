# Decisões técnicas

## D1 — Parser EPUB próprio, sem dependências
Avaliados: EPUBKit (MIT; depende de ZIPFoundation e AEXML) e Readium Swift Toolkit (BSD-3; completo, mas grande
e voltado a renderização/navegação). Necessitamos apenas de metadados, spine, sumário, capa e texto limpo.
Escolhido: ZIP mínimo (`Compression`, deflate cru) + `XMLParser` + tokenizador HTML tolerante (~600 linhas).
Motivos: zero dependências (requisito de "ausência de dependências desnecessárias"), controle total da
normalização de texto para fala, execução rápida (≈0,05–0,1 s por livro real) e sem custo de rede/SPM.
Contrapartida: não suporta ZIP64 nem entradas ZIP criptografadas (reportado como EPUB corrompido).

## D2 — Posição = offset UTF-16 no texto normalizado do capítulo
`AVSpeechSynthesizer` reporta `NSRange` em UTF-16; usar a mesma unidade evita conversões. O texto é re-extraído do
EPUB sob demanda (nada de livros inteiros em memória; só o capítulo atual e vizinhos ficam em cache).
O comprimento de cada capítulo é gravado no import (`ChapterInfo.length`) para calcular o progresso global.

## D3 — Motor com fila curta (lookahead = 2) e tokens de geração
Um trecho (~500 caracteres, quebrado em parágrafo > sentença > cláusula > palavra) por `AVSpeechUtterance`.
Manter 2 utterances na fila do sintetizador evita lacunas e ajuda a manter o áudio vivo em segundo plano.
Todo comando que reposiciona a fala incrementa `generation`; carregamentos assíncronos antigos e eventos de
utterances que não estão em `inFlight` são ignorados, impedindo repetições/omissões em comandos concorrentes.
Mudar velocidade/voz reinicia a partir da palavra atual (`willSpeakRange`), pois `AVSpeechUtterance.rate` é fixo por utterance.
O sintetizador é abstraído (`SpeechSynthesizing`) para testar o motor deterministicamente com um mock.

## D4 — Mapeamento de velocidade
Multiplicador 0,5×–2,0× → `rate` 0,30–0,70 (1× = 0,50, padrão do sistema). Acima de 0,70 a fala degrada.

## D5 — Interrupções de áudio (iOS 27)
`AVAudioSessionInterruptionNotification` está obsoleta no iOS 27. Usamos `didBecomeInactiveNotification`
(apenas `source == .system`) e `resumptionRecommendationNotification`. Mudança de rota
`oldDeviceUnavailable` (fones desconectados) pausa. Categoria `.playback`, modo `.spokenAudio`.

## D6 — Background mode via `Config/Info.plist`
`INFOPLIST_KEY_UIBackgroundModes` não é emitido pelo Xcode; um plist parcial (`INFOPLIST_FILE`) é mesclado ao gerado.

## D7 — Persistência
SwiftData: `Book` (metadados + `[ChapterInfo]` codificado), `ReadingProgress` (cascade), `UserPreferences` (linha única).
Arquivos em `Application Support/AudioBook/Books/<uuid>/` (`book.epub`, `cover.jpg`); o caminho nunca é gravado (o container muda).
Progresso é salvo ao pausar, mudar de capítulo, finalizar, ir para segundo plano e a cada 5 s tocando.
Se o banco não abrir, o app cai para armazenamento em memória e avisa o usuário (não corrompe o original).
Sobras de importações interrompidas (pastas sem registro) são removidas na inicialização.

## D8 — Texto narrável
Ignora `head/script/style/nav/svg/math`, `hidden`, `aria-hidden`, `epub:type` = pagebreak/noteref/toc; cabeçalhos
ganham ponto final se faltar pontuação; parágrafos só com símbolos ("* * *") e URLs são descartados; remove hífen suave
e caracteres de largura zero; expande ligaduras; normaliza espaços e Unicode (NFC).

## D9 — DRM
Falha com mensagem clara se `META-INF/encryption.xml` cifra documentos da spine com algoritmo diferente de
ofuscação de fontes (IDPF/Adobe). Nenhuma tentativa de contornar DRM.

## D10 — Idioma padrão pt-BR
Alguns EPUBs declaram idioma errado (ex.: livro em português com `en`), então o padrão é pt-BR;
"Automático (idioma do livro)" é opcional em Ajustes.

## D11 — Deploy target
Mantido iOS 27.0 (config original do projeto). Baixar para iOS 18 exigiria ramificar o tratamento de interrupções (D5).

## D12 — Vozes da Siri não estão disponíveis
`AVSpeechSynthesizer` só expõe vozes de síntese do sistema (padrão/Aprimorada/Premium); as vozes da Siri não são acessíveis a apps de terceiros.
Alternativa: baixar vozes Aprimoradas/Premium (Ajustes › Acessibilidade › Conteúdo Falado › Vozes); o app escolhe a de melhor qualidade automaticamente.

## D13 — Leitura acompanhada
Offsets UTF-16 do `willSpeakRange` viram `SpokenHighlight` (trecho + palavra) no motor; a view divide o capítulo em parágrafos
(`ReadParagraph`), destaca por interseção de intervalos e rola até o parágrafo atual (desligado enquanto o usuário rola à mão).

## D14 — Vozes neurais Piper (sherpa-onnx)
As vozes do sistema em pt-BR soam robóticas. Avaliados: APIs na nuvem (Azure, Polly, ElevenLabs; custo por caractere e envio
do texto para fora), Kokoro v1.0 via speech-swift e Piper via sherpa-onnx (ambos offline).
O Kokoro foi testado e descartado: o phonemizer de português do speech-swift é baseado em regras sem traços do pt-BR
(sem "tchi/dji", "e"/"o" finais reduzidos, "l" final → "u"), e as vozes soavam como português de Portugal.
Escolhido: Piper via `k2-fsa/sherpa-onnx`, versão exata 1.13.8. A 2.0 removeu o espeak-ng, que o Piper usa para gerar os
fonemas `pt-br`. É a única dependência (exceção consciente ao D1): xcframework pré-compilado + onnxruntime.
Vozes empacotadas em `PiperVoices/` (referência de pasta, copiada com a árvore intacta), modelos int8 de 18 MB cada:
`cadu-medium` (CC0, pode ir para o Git e para a loja) e `miro-high` (CC BY-NC-SA 4.0, só uso pessoal; fora do Git via
`.gitignore`, e deve ser removida antes de publicar). `espeak-ng-data` reduzido de 18 MB para 1,6 MB mantendo só `pt_dict` e
os dados de fonemas; a saída é idêntica à do pacote completo. Licença: o espeak-ng é GPLv3, então publicar na App Store
exige revisão. `RoutedSpeechService` escolhe o sintetizador pela voz (`piper:<pasta>` → `PiperSpeechService`; demais →
`SpeechService`). Se o Piper falhar, o que já foi sintetizado termina e o restante vai, em ordem, para a voz do sistema.
O Piper não informa tempo por palavra: `willSpeak` é estimado proporcionalmente ao tamanho das palavras (`WordTiming`).
