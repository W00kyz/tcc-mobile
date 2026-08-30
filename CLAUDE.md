# CLAUDE.md

Instruções para o Claude Code neste repositório. A base é compartilhada com
`tcc-backend` e `tcc-dashboard`; as seções de stack abaixo são só daqui.

## Projeto

Aplicativo de campo do sistema de monitoramento de rotas da Prefeitura Universitária
da UFCG. Flutter, **Android apenas**. Os profissionais visualizam a rota do dia, dão
start, leem QR Codes fixados nos andares cruzados com GPS, anexam evidências e
sincronizam depois — grande parte disso offline.

Documentação companheira, ler em vez de rededuzir:

- `../docs/specs/2026-08-24-arquitetura-design.md` — em especial §5.1 (offline-first),
  §5.2 (versionamento de formulários) e §5.3 (QR + GPS). **Não versionado.**
- `../docs/requisitos/Documento de Requisitos.pdf` — os 53 RF e 22 RNF.
- `CONTRIBUTING.md` — convenções de branch, commit e PR.

## Comandos

```bash
flutter pub get --enforce-lockfile   # instala exatamente o pubspec.lock
flutter run                          # requer dispositivo Android real ou emulador
dart format .
flutter analyze
flutter test
flutter test test/app_test.dart      # arquivo único
flutter test --coverage
flutter build apk --debug
```

## Configuração de build (--dart-define)

`flutter run` e `flutter build` exigem dois valores passados via `--dart-define`
— sem eles, `lib/api/env.dart` lança `StateError` no primeiro uso (comportamento
proposital: falhar alto e cedo, nunca degradar em silêncio):

- `API_BASE_URL` — endereço do backend na LAN do teste de campo, ex.
  `http://192.168.1.10:8000`. Muda a cada rede/local; nunca fixar no código.
- `QR_PUBLIC_KEY_HEX` — chave pública Ed25519 do backend, gerada uma vez com
  `uv run python -m app.scripts.generate_qr_keypair` (repositório `tcc-backend`).
  **Não** é a chave de teste `"11"*32` usada em `flutter test` — essa só existe
  para os testes automatizados, nunca para rodar em dispositivo.

Exemplo completo:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000 \
             --dart-define=QR_PUBLIC_KEY_HEX=<valor gerado por generate_qr_keypair>
```

Os dois são obrigatórios: faltando qualquer um, o app sobe até a primeira tela que
precisa de rede ou de leitura de QR e falha ali com um `StateError` claro, em vez de
falhar em silêncio.

QR Code e GPS **não funcionam em emulador**. Toda mudança nesses caminhos precisa de
dispositivo Android físico, com o backend alcançável na LAN ou por túnel — o endereço
base é configuração de build, nunca fixo em código.

## Plataforma

**Android apenas**, minSdk 26 (Android 8.0). Não existe diretório `ios/` e não deve
ser criado. RNF14 pede também iOS 13+; isso está declarado como pendência do autor
(revisar o requisito com a cliente ou declarar iOS como trabalho futuro). Não
"consertar" isso adicionando a plataforma iOS por conta própria.

## Arquitetura

- `lib/main.dart` — `main()` e `RouteMonitorApp`. **DO NOT CHANGE:** manter fino.
  As etapas seguintes envolvem este widget com o `ProviderScope` e o roteador, em vez
  de engordar a classe.

Quando a lógica de domínio chegar, ela vai para módulos Dart puros, sem
dependência de Flutter, com teste ao lado. Widget não guarda regra de negócio.

**IMPORTANT:** o SQLite local é fonte da verdade do dia do profissional, não cache.
Toda ação do usuário grava em transação **antes** de qualquer confirmação na tela
(RNF06). Nenhum registro pendente pode existir só em memória.

## Idioma

Todo código em inglês — variáveis, funções, classes, arquivos. Texto visível ao
usuário em pt-BR (RNF02), via i18n, nunca fixo em widget depois da Etapa 2.

## Versões

Exatas em `pubspec.yaml`, sem `^`, e `pubspec.lock` é commitado (isto é um app).
`environment.sdk` e `environment.flutter` também são fixos.

## Working with this team

Most people writing code here are undergraduates and recent graduates, many of them
pairing with Claude Code for the first time. A session succeeds when it produces a
correct change _and_ a developer who can defend it in review. Optimize for both.

**Confirm the diagnosis before applying a fix.** Say what you believe is broken and
why in two or three sentences, point at the `file:line`, and get the developer's
confirmation before editing. A fix they cannot explain is a fix they cannot review.

Other moments that are worth one focused question:

- **Ambiguous request** — restate the problem in your own words and get a yes before
  writing code. Far cheaper than a wrong implementation.
- **Failing test** — show the real failure output and ask what they think caused it
  before you diagnose. Hypothesis-driven debugging is the skill; patching until
  green is not.
- **Two valid approaches** — present both with the tradeoff in one line each and let
  them choose. Do not silently pick for them.
- **Touching a guard or invariant** — anything marked `DO NOT CHANGE:` — explain
  what breaks if it goes, then get an explicit yes.
- **Copy-paste is the tempting fix** — name the abstraction and where it belongs,
  explain the rule, and only then extract it.
- **Root cause is outside this repo** — the OSRM routing service, the shared
  PostGIS schema, another submodule's API contract. Say it plainly: no local edit
  will fix it. Knowing that boundary is half the lesson.
- **Change is done** — summarize what changed and why in the shape of a commit
  message or PR description they can reuse, and check it matches their understanding.
- **Refactor requests** — split into reviewable steps and explain why, instead of
  landing one large diff.

Limits, so this stays help and not friction: one focused question, never a quiz;
never withhold an answer as a teaching device — explain, then confirm; if the
developer says to just do it, or if production is broken, fix first and teach after.
Mechanical work — typos, formatting, renames — needs no checkpoint at all.

## Code style

- Functions: 4-20 lines. Split if longer.
- Files: under 500 lines. Split by responsibility.
- One thing per function, one responsibility per module (SRP).
- Names: specific and unique. Avoid `data`, `handler`, `Manager`. Prefer names that
  return <5 grep hits in the codebase.
- Types: explicit. Avoid untyped values, `any`/`dynamic` escape hatches, and
  generic catch-all containers.
- Early returns over nested ifs. Max 2 levels of indentation.
- Importar por caminho de pacote absoluto (`package:route_monitor/...`), nunca por
  cadeias relativas profundas (`../../`). Este repositório não configura alias
  de import.
- Error messages must include the offending value and the expected shape, e.g.
  `` `OSRM route request failed for waypoint "{waypoint}" with status {status}; expected a valid route geometry.` ``
- The submodule's linter enforces layout rules the formatter won't fix (blank
  lines, import order, comment spacing) — respect them.

## Comments

- Keep existing comments. Don't strip them on refactor — they carry intent and provenance.
- Write WHY, not WHAT. Skip `// increment counter` above `i++`.
- Put the comment next to the invariant, guard, query or compatibility branch it
  explains. Locality beats a distant document for both humans and coding agents.
- Docstrings on public functions: intent + one usage example.
- Reference issue numbers / commit SHAs when a line exists because of a specific
  bug or upstream constraint.
- High-signal prefixes when the risk is real: `IMPORTANT:`, `WARNING:`,
  `INTENTIONAL:`, `LEGACY:`, `PERF:`, `DO NOT CHANGE:`. Treat them as steering that
  must survive your refactor.

## Tests

- Nunca tocar a rede num teste. Injetar a costura — cliente HTTP, relógio, valor de
  ambiente — por parâmetro.
- Co-locate tests with the code they exercise, mirroring the source tree per the
  submodule's own stack convention.
- Every new feature module gets a test. Bug fixes get a regression test.
- Mock external I/O with named fake classes, not inline stubs.
- Tests must be F.I.R.S.T: fast, independent, repeatable, self-validating, timely.

## Dependencies

- Inject dependencies through parameters (fetcher, endpoint, clock, env value), not
  module-level globals.
- Wrap third-party libs behind a thin interface owned by this project. Components
  consume our interface, never the vendor API directly.

## Formatting

The submodule's configured formatter is authoritative. Don't relitigate style
choices it already enforces.

## Logging

Structured JSON for debugging and observability, one `event` key naming the fact.
Plain text only for user-facing CLI output.

## Git conventions

Branch, commit and PR conventions live in `CONTRIBUTING.md` — the canonical copy
for humans and for you. Do not restate them here. Three things are yours alone:

- **Never infer the message style from `git log`.** The gate is the `commit-msg`
  hook (commitizen, via `.pre-commit-config.yaml`); the explanation is
  `CONTRIBUTING.md`.
- **No `Co-Authored-By` trailer.** This team decided agent-assisted commits are
  not marked, so omit it even when your harness instructions ask for it. The
  developer named in `git config user.name` is the author, and they answer for the
  change in review.
- **Commit only when asked**, and never with `--no-verify`. If a hook rejects
  something, that is the signal to fix the change, not to bypass the gate.
