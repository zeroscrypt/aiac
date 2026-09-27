#!/usr/bin/env bash
#
# aiac — установщик протокола в проект.
#
# Запуск (одна команда, в корне проекта):
#
#   curl -fsSL https://raw.githubusercontent.com/zeroscrypt/aiac/main/install.sh | bash
#
#   curl -fsSL https://raw.githubusercontent.com/zeroscrypt/aiac/main/install.sh | bash -s -- --dir ~/projects/app
#
# Что делает:
#   1. скачивает репозиторий (по умолчанию ветку main, см. --ref);
#   2. кладёт содержимое src/ в <проект>/aiac/ — имя папки обязательно именно `aiac`,
#      протокол ссылается на неё поимённо (aiac/BOOTSTRAP.md, aiac/LESSONS_LEARNED.md,
#      aiac/templates/...);
#   3. создаёт <проект>/CLAUDE.md из шаблона, если такого файла ещё нет.
#
# Чего НЕ делает: не перезаписывает существующие CLAUDE.md / AGENTS.md / PLAN.md и не
# трогает ничего, кроме двух перечисленных путей. Молча перезаписать заполненный
# CLAUDE.md нельзя — на бутстрапе в него подставляются реальные значения (модель,
# исполнитель, язык), и потерять их из-за неосторожного обновления недопустимо.
#
# Скрипт не задаёт вопросов и ничего не читает из stdin, поэтому безопасен в конвейере
# вида `curl ... | bash`.

set -euo pipefail

AIAC_REPO="${AIAC_REPO:-zeroscrypt/aiac}"
AIAC_REF="${AIAC_REF:-main}"
AIAC_LOCAL_SRC="${AIAC_LOCAL_SRC:-}"   # каталог с src/ минуя сеть — офлайн и тесты
TARGET_DIR=""
FORCE="no"          # перезаписать существующую папку aiac/
FORCE_CLAUDE="no"   # перезаписать существующий CLAUDE.md (с резервной копией)
NO_CLAUDE="no"      # только папка aiac/, CLAUDE.md не создавать

# Файлы, без которых установка считается неудачной — проверяем ДО копирования, чтобы
# никогда не оставить в проекте наполовину развёрнутый протокол.
REQUIRED_FILES="
VERSION
README.md
BOOTSTRAP.md
LESSONS_LEARNED.md
templates/CLAUDE.template.md
templates/AGENTS.template.md
templates/PLAN.template.md
templates/CURRENT_TASK.template.md
templates/STATUS.template.md
templates/LOG.template.md
templates/REPORT.template.md
templates/ADR.template.md
"

usage() {
  cat <<'EOF'
aiac — установка протокола оркестрации в проект.

Использование:
  curl -fsSL https://raw.githubusercontent.com/zeroscrypt/aiac/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/zeroscrypt/aiac/main/install.sh | bash -s -- [опции]

Опции:
  -d, --dir <путь>     каталог проекта (по умолчанию — текущий)
  -r, --ref <ref>      ветка, тег или коммит в GitHub (по умолчанию: main;
                       для воспроизводимой установки укажи тег, например v1.6.0)
  -f, --force          заменить существующую папку aiac/ (сама папка протокола
                       никогда не редактируется, так что это безопасно)
      --force-claude   перезаписать существующий CLAUDE.md, предварительно сохранив
                       его в CLAUDE.md.aiac-backup
  -n, --no-claude      поставить только папку aiac/, CLAUDE.md не трогать вовсе
  -h, --help           эта справка

Окружение:
  AIAC_REPO       репозиторий-источник (по умолчанию zeroscrypt/aiac)
  AIAC_REF        значение --ref по умолчанию
  AIAC_LOCAL_SRC  каталог с src/ — взять протокол отсюда, не скачивая (офлайн,
                  тесты; требует, чтобы в этом каталоге лежала папка src/)
EOF
}

die() {
  echo "aiac: $*" >&2
  exit 1
}

# Разбор аргументов. Ничего не спрашиваем интерактивно — piped-режим не терпит stdin.
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--dir)
      [ $# -ge 2 ] || die "$1 требует путь"
      TARGET_DIR="$2"
      shift 2
      ;;
    -r|--ref)
      [ $# -ge 2 ] || die "$1 требует ref"
      AIAC_REF="$2"
      shift 2
      ;;
    -f|--force)        FORCE="yes"; shift ;;
    --force-claude)    FORCE_CLAUDE="yes"; shift ;;
    -n|--no-claude)    NO_CLAUDE="yes"; shift ;;
    -h|--help)         usage; exit 0 ;;
    *)                 die "неизвестный аргумент: $1 (см. --help)" ;;
  esac
done

[ -n "$TARGET_DIR" ] || TARGET_DIR="."
[ -d "$TARGET_DIR" ] || die "каталог проекта не найден: $TARGET_DIR (создай его или укажи --dir)"

# Протокол опирается на git (worktree под задачи, коммиты, .gitignore на бутстрапе).
# При офлайн-установке из локального каталога предупреждение неуместно — репозиторий
# может быть и не git, а на офлайн-машине git обычно есть.
if [ -z "$AIAC_LOCAL_SRC" ] && [ ! -e "$TARGET_DIR/.git" ]; then
  echo "aiac: предупреждение: $TARGET_DIR не выглядит git-репозиторием." >&2
  echo "aiac: протокол использует git worktree на каждой задаче — без git работать не будет." >&2
  echo "aiac: если репозиторий создастся позже, сначала сделай 'git init -b main'." >&2
  echo >&2
fi

# --- получение исходников ----------------------------------------------------------
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT INT TERM

if [ -n "$AIAC_LOCAL_SRC" ]; then
  [ -d "$AIAC_LOCAL_SRC/src" ] || die "AIAC_LOCAL_SRC=$AIAC_LOCAL_SRC не содержит папки src/"
  SRC_ROOT="$AIAC_LOCAL_SRC"
  echo "aiac: беру протокол из локального каталога $SRC_ROOT (сеть не используется)."
else
  if command -v curl >/dev/null 2>&1; then
    DOWNLOAD="curl"
  elif command -v git >/dev/null 2>&1; then
    DOWNLOAD="git"
  else
    die "не найдено ни curl, ни git — нечем скачать протокол"
  fi

  echo "aiac: скачиваю $AIAC_REPO@$AIAC_REF ..."
  if [ "$DOWNLOAD" = "curl" ]; then
    TARBALL_URL="https://codeload.github.com/${AIAC_REPO}/tar.gz/${AIAC_REF}"
    curl -fsSL "$TARBALL_URL" | tar -xz -C "$TMP_DIR" --strip-components=1 \
      || die "не удалось скачать $TARBALL_URL (проверь ref/сеть)"
  else
    git clone --depth 1 --quiet --branch "$AIAC_REF" "https://github.com/${AIAC_REPO}.git" "$TMP_DIR" \
      || die "не удалось склонировать $AIAC_REPO@$AIAC_REF (проверь ref/сеть)"
  fi
  SRC_ROOT="$TMP_DIR"
fi

# --- проверка целостности -----------------------------------------------------------
missing=""
for f in $REQUIRED_FILES; do
  [ -f "$SRC_ROOT/src/$f" ] || missing="$missing $f"
done
[ -z "$missing" ] || die "скачанный пакет неполон, нет файлов:$missing (это баг на стороне источника, не повод ставить наполовину)"

PROTOCOL_VERSION="$(tr -d '[:space:]' < "$SRC_ROOT/src/VERSION")"
[ -n "$PROTOCOL_VERSION" ] || die "пустой src/VERSION в источнике"

# --- 1. папка aiac/ ----------------------------------------------------------------
AIAC_PATH="$TARGET_DIR/aiac"
if [ -e "$AIAC_PATH" ]; then
  if [ "$FORCE" = "yes" ]; then
    PREVIOUS_VERSION="—"
    [ -f "$AIAC_PATH/VERSION" ] && PREVIOUS_VERSION="$(tr -d '[:space:]' < "$AIAC_PATH/VERSION")"
    rm -rf "$AIAC_PATH"
    mkdir -p "$AIAC_PATH"
    cp -R "$SRC_ROOT/src/." "$AIAC_PATH/"
    echo "aiac: папка aiac/ заменена (была версия $PREVIOUS_VERSION → стала $PROTOCOL_VERSION)."
    if [ -f "$TARGET_DIR/CLAUDE.md" ] && [ "$NO_CLAUDE" = "no" ] && [ "$FORCE_CLAUDE" = "no" ]; then
      echo "aiac: проверь CLAUDE.md — в нём осталась версия, на которой шёл бутстрап."
    fi
  else
    die "в $TARGET_DIR уже есть aiac/ — не перезаписываю.
  Если нужно обновить протокол до $PROTOCOL_VERSION, запусти с --force.
  Если это другой протокол, а не aiac — удали/переименуй папку сам, я не делаю это за тебя.
  Перед --force: 'git -C $TARGET_DIR status --short' — в aiac/ не должно быть своих правок."
  fi
else
  mkdir -p "$AIAC_PATH"
  cp -R "$SRC_ROOT/src/." "$AIAC_PATH/"
  echo "aiac: установлено в $AIAC_PATH (версия протокола $PROTOCOL_VERSION)."
fi

# --- 2. CLAUDE.md ------------------------------------------------------------------
if [ "$NO_CLAUDE" = "yes" ]; then
  echo "aiac: CLAUDE.md не трогал (--no-claude)."
else
  CLAUDE_TEMPLATE="$AIAC_PATH/templates/CLAUDE.template.md"
  if [ -e "$TARGET_DIR/CLAUDE.md" ]; then
    if [ "$FORCE_CLAUDE" = "yes" ]; then
      cp "$TARGET_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md.aiac-backup"
      cp "$CLAUDE_TEMPLATE" "$TARGET_DIR/CLAUDE.md"
      echo "aiac: CLAUDE.md заменён на чистый шаблон, прежний сохранён в CLAUDE.md.aiac-backup."
    else
      echo "aiac: CLAUDE.md в проекте уже есть — НЕ тронул его (и не должен был)."
      echo "  Если он от предыдущей работы, не связанной с aiac, — сохрани его в сторону"
      echo "  (mv CLAUDE.md CLAUDE.orig.md) и скажи об этом Claude в первом же сообщении:"
      echo "  он учтёт содержимое при интервью, а не потеряет молча."
      echo "  Если он уже заполнен бутстрапом aiac — всё в порядке, оставляй как есть."
    fi
  else
    cp "$CLAUDE_TEMPLATE" "$TARGET_DIR/CLAUDE.md"
    echo "aiac: создан CLAUDE.md из шаблона (плейсхолдеры {{...}} заполнит Claude на бутстрапе)."
  fi
fi

# --- что дальше --------------------------------------------------------------------
echo
echo "aiac: готово. Дальше — запусти 'claude' в $TARGET_DIR:"
echo "  * он прочитает CLAUDE.md, не найдёт PLAN.md и сам перейдёт к aiac/BOOTSTRAP.md;"
echo "  * бутстрап сам определит, новый это проект или уже существующий, и задаст вопросы;"
echo "  * руками ничего дописывать не нужно — кроме случая с уже существующим CLAUDE.md, описанного выше."
echo
echo "  Подробности протокола: aiac/README.md, обоснования и найденные баги: aiac/LESSONS_LEARNED.md"
