# aiac — AI Agents Core

[![npm](https://img.shields.io/npm/v/aiac.svg)](https://www.npmjs.com/package/aiac)
[![license](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](./LICENSE)
[![ci](https://github.com/zeroscrypt/aiac/actions/workflows/ci.yml/badge.svg)](https://github.com/zeroscrypt/aiac/actions/workflows/ci.yml)

Переносимый протокол разработки через связку **умный оркестратор (Claude Code) + дешёвый объёмный
исполнитель (по умолчанию opencode)**. Это не библиотека и не генератор кода: это набор протокольных
файлов и правил, которые разворачиваются в корень вашего проекта одной командой.

Вытащен из реального проекта (macOS-приложение для локальной транскрибации звонков) после того, как
этот процесс сложился на практике, включая все найденные на нём болевые точки. Не абстрактная теория
«как должно быть», а методология, проверенная на десятке раундов реальной работы, с
[уроками из живых багов](src/LESSONS_LEARNED.md) — поэтому в каждом нетривиальном правиле можно
прочитать, какой именно баг его вынудил.

## Какую боль решает

Один агент держит в голове архитектурную картину: зачем проект, что уже сделано, какие решения
приняты и почему, какие риски. Он не пишет код объёмными раундами сам — формулирует **ровно одну
задачу за раз** с явными критериями готовности, запускает исполнителя, **не верит его самоотчёту**,
независимо пересобирает и проверяет руками, и только потом идёт дальше.

Второй агент (большое контекстное окно, дешёвая модель) архитектурной картины не держит: получает
предельно конкретную задачу, реализует её, отчитывается через три файла, коммитит. Архитектурных
решений не принимает — все развилки решает оркестратор, явно, а не оставляет на волю исполнителя.

Что из этого уже реализовано в файлах протокола:

- **Разделение ролей и явные границы**: оркестратор не пишет объёмный код, исполнитель не
  проектирует.
- **`git worktree` на каждую задачу** вместо общей рабочей папки — структурная изоляция, а не
  дисциплинарная, отсюда же возможность нескольких исполнителей параллельно.
- **Definition of Ready / Definition of Done**: задача проверяется на готовность до запуска,
  результат — после, независимо от того, что написал исполнитель.
- **Обязательный тест на новую функциональность.** «Код выглядит правильным» не считается проверкой.
- **Защита от секретов** на трёх уровнях: аудит истории при подключении к существующему проекту,
  `.gitignore` с первого коммита, проверка собственного diff перед каждым коммитом.
- **Отчётность, переживающая обрыв**: `STATUS.md` (снимок), `LOG.md` (путь до точки), `REPORT.md`
  (по задаче) — чтобы после сбоя или перезагрузки машины было видно, где именно остановились.
- **Никогда не изобретать API по памяти**: сверяться с реальным источником или фиксировать
  `blocked`, а не угадывать.

## Установка

Одна команда в корне проекта:

```bash
curl -fsSL https://raw.githubusercontent.com/zeroscrypt/aiac/main/install.sh | bash
```

Установщик:

1. скачивает репозиторий;
2. кладёт содержимое `src/` в `<проект>/aiac/` — имя папки именно `aiac`, протокол ссылается на
   неё поимённо (`aiac/BOOTSTRAP.md`, `aiac/LESSONS_LEARNED.md`, `aiac/templates/…`);
3. создаёт `<проект>/CLAUDE.md` из шаблона, **если такого файла ещё нет**.

Чего он **не** делает: не перезаписывает существующие `CLAUDE.md` / `AGENTS.md` / `PLAN.md` и не трогает
ничего, кроме этих двух путей. Молча перезаписать `CLAUDE.md` нельзя — на бутстрапе в него
подставляются реальные значения (модель, исполнитель, язык), и потерять их из-за неосторожного
обновления недопустимо. Если `CLAUDE.md` уже есть, установщик скажет об этом и оставит файл в
покое; что делать дальше (переименовать в `CLAUDE.orig.md` и сказать Claude самому либо оставить
как есть) решаете вы.

### Другие способы

```bash
# в конкретный каталог
curl -fsSL https://raw.githubusercontent.com/zeroscrypt/aiac/main/install.sh | bash -s -- --dir ~/projects/app

# зафиксировать версию (воспроизводимо, а не «что там сегодня в main»)
curl -fsSL https://raw.githubusercontent.com/zeroscrypt/aiac/main/install.sh | bash -s -- --ref v1.6.0
```

`curl … | bash -s -- <флаги>` — флаги идут после `--`, иначе `bash` не пробросит их скрипту.
Полный список: `bash install.sh --help` (`--force`, `--force-claude`, `--no-claude`, `--dir`, `--ref`).

Установка вручную, если по каким-то причинам не хочется выполнять код из сети:

```bash
git clone https://github.com/zeroscrypt/aiac.git /tmp/aiac
cp -R /tmp/aiac/src ./aiac
cp aiac/templates/CLAUDE.template.md ./CLAUDE.md
```

Пакет есть и на npm ([`aiac`](https://www.npmjs.com/package/aiac)) — он содержит ровно те же
файлы, что и репозиторий. Бинарника у него нет и не предполагается: `npm i aiac` положит их в
`node_modules/aiac/src`, откуда их копируют в проект вручную. Ставит именно `install.sh`.

## Быстрый старт

```bash
cd ~/projects/app
curl -fsSL https://raw.githubusercontent.com/zeroscrypt/aiac/main/install.sh | bash
claude
```

Дальше всё делает сам Claude, вам остаётся отвечать на вопросы:

- `CLAUDE.md` в корне — единственный файл, который читается всегда. Он увидит, что `PLAN.md` ещё
  нет, и сам перейдёт к `aiac/BOOTSTRAP.md` (отсутствие `PLAN.md` означает «процесс здесь ещё не
  заводили», а вовсе не «проект пустой»).
- Бутстрап сам определит, подключается протокол к проекту с нуля или к уже существующему, и
  разойдётся по шагам. Для существующего проекта он сначала изучит код и покажет вам черновик
  своего понимания архитектуры, прежде чем задавать следующие вопросы.
- Дальше — обычная работа: задачи в `tasks/`, отчётность, ревью, мерж.

## Что появляется в проекте

```
<проект>/
├── aiac/                     ← протокол, остаётся в проекте как справочник
│   ├── VERSION               ← версия протокола; её же бутстрап штампует в CLAUDE.md
│   ├── BOOTSTRAP.md          ← протокол первого запуска в новом или существующем проекте
│   ├── LESSONS_LEARNED.md    ← 15 конкретных багов процесса и принципов, которые из них выросли
│   ├── README.md             ← устройство протокола подробно
│   └── templates/            ← шаблоны CLAUDE/AGENTS/PLAN/задачи/STATUS/LOG/REPORT/ADR
└── CLAUDE.md                 ← создан из шаблона, плейсхолдеры заполнит бутстрап
```

А дальше Claude допишет сам: `PLAN.md` (архитектура, roadmap, статус), `AGENTS.md` (протокол для
исполнителя), `tasks/{pending,in_progress,done}/`, `STATUS.md`, `LOG.md`, `REPORT.md`, `.gitignore`
под стек проекта. Ничего дописывать руками не нужно.

## Требования

- **`git`** — обязателен: протокол создаёт `git worktree` под каждую задачу. Без git работать не
  будет, установщик об этом предупредит.
- **Claude Code** — роль оркестратора (это тот агент, который запускает исполнителя).
- **opencode** — исполнитель по умолчанию. Другой агент тоже можно: на бутстрапе задаётся имя,
  команда запуска и модель, а протокол отчётности подстраивается под его реальные возможности.
- **macOS / Linux / WSL** — установка через `curl | bash`. На чистом Windows без WSL используйте
  ручную копию.

## Обновление протокола в уже подключённом проекте

```bash
curl -fsSL https://raw.githubusercontent.com/zeroscrypt/aiac/main/install.sh | bash -s -- --force
```

`--force` заменяет только папку `aiac/` (она никогда не редактируется — это справочник, так что
замена безопасна) и **не трогает** `CLAUDE.md`: в нём остаётся версия, на которой шёл бутстрап.
Дальше срабатывает механизм, уже встроенный в протокол: при следующем запуске Claude увидит, что
`aiac/VERSION` новее, и спросит, переносить ли изменения в проект. Переносить молча он не будет —
новые правила протокола меняют поведение вашего агента, и это стоит решить осознанно.

Перед `--force` имеет смысл убедиться, что в `aiac/` нет ваших правок: `git status --short`.

## Состав репозитория

| Путь | Что это |
| --- | --- |
| [`src/`](src/) | сам протокол: то, что ставится в проект |
| [`src/README.md`](src/README.md) | подробное устройство протокола и оба сценария подключения |
| [`src/BOOTSTRAP.md`](src/BOOTSTRAP.md) | протокол первого запуска: интервью, генерация файлов, первый коммит |
| [`src/LESSONS_LEARNED.md`](src/LESSONS_LEARNED.md) | 15 уроков с реального проекта — почему протокол устроен именно так |
| [`src/templates/`](src/templates/) | шаблоны файлов-протокола с плейсхолдерами `{{…}}` |
| [`install.sh`](install.sh) | установщик (одна команда, описан выше) |
| [`CHANGELOG.md`](CHANGELOG.md) | история версий протокола |

## English

**aiac (AI Agents Core)** is a portable development protocol that pairs a smart orchestrator
(Claude Code) with a cheap high-volume executor (opencode by default). It is not a library and
generates no code: it is a set of protocol files and rules you drop into the root of your project
with a single command.

```bash
curl -fsSL https://raw.githubusercontent.com/zeroscrypt/aiac/main/install.sh | bash
cd your-project && claude
```

The installer copies the protocol into `aiac/` and creates `CLAUDE.md` from a template. It never
overwrites an existing `CLAUDE.md`/`AGENTS.md`/`PLAN.md` — losing a project's bootstrap
configuration silently is not an acceptable failure mode. After that Claude runs the bootstrap
itself: it figures out whether the project is new or existing, interviews you, writes `PLAN.md`,
`AGENTS.md` and the first task, and then works by the protocol — one task at a time, each in its own
`git worktree`, independently verified rather than trusted.

Requires `git` and Claude Code. Extracted from a real project, together with the bugs the process
itself accumulated — see [`src/LESSONS_LEARNED.md`](src/LESSONS_LEARNED.md).

## Лицензия и участие

[Apache-2.0](LICENSE) — свободная лицензия с патентной оговоркой.

Правки приветствуются: [CONTRIBUTING.md](CONTRIBUTING.md) описывает, что нужно обновить вместе с
изменением протокола (в первую очередь — версию и changelog).

Название рабочее. Если захотите другое (`crew-kit`, `agent-forge`, `architect-executor`,
`pair-protocol`) — переименовать папку и поправить ссылки на неё в `CLAUDE.md`, больше ничто на
конкретное имя не завязано.
