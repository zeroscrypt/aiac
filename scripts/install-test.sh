#!/bin/sh
#
# Сквозной тест install.sh: раскладывает протокол в свежие проекты и проверяет, что
# установка не разрушает то, что уже есть. Именно эти свойства важнее «файлы скопировались»:
# молча перезаписанный заполненный CLAUDE.md или папка aiac/ — это потеря работы человека
# (см. те же правила про не-molчание в aiac/BOOTSTRAP.md и aiac/LESSONS_LEARNED.md).
#
# Сеть не используется: источник берётся из текущего рабочего дерева (AIAC_LOCAL_SRC),
# поэтому тест проверяет именно те файлы, что лежат в репозитории, а не ветку main на GitHub.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

FAILED=0

ok()   { echo "  ok   — $*"; }
fail() { echo "  FAIL — $*"; FAILED=$((FAILED + 1)); }

exists() {
  if [ -f "$1" ]; then ok "$2 существует"; else fail "$2 отсутствует: $1"; fi
}
absent() {
  if [ ! -e "$1" ]; then ok "$2 не создан"; else fail "$2 не должен был появиться: $1"; fi
}

new_project() {
  p="$WORK/$1"
  mkdir -p "$p"
  git -C "$p" init -q -b main 2>/dev/null || git -C "$p" init -q
  echo "$p"
}

run_install() {
  AIAC_LOCAL_SRC="$ROOT" "$ROOT/install.sh" "$@" >"$WORK/out.log" 2>&1 && return 0 || return $?
}

echo "1. Чистая установка в новый проект"
P1="$(new_project p1)"
if run_install --dir "$P1"; then
  exists "$P1/aiac/VERSION" "aiac/VERSION"
  exists "$P1/aiac/BOOTSTRAP.md" "aiac/BOOTSTRAP.md"
  exists "$P1/aiac/LESSONS_LEARNED.md" "aiac/LESSONS_LEARNED.md"
  exists "$P1/aiac/templates/CLAUDE.template.md" "aiac/templates/CLAUDE.template.md"
  exists "$P1/aiac/templates/AGENTS.template.md" "aiac/templates/AGENTS.template.md"
  exists "$P1/CLAUDE.md" "CLAUDE.md"
  # CLAUDE.md обязан остаться ШАБЛОНОМ с плейсхолдерами — иначе бутстрап не сможет
  # подставить модель/исполнителя/язык и не поймёт, что протокол ещё не настроен.
  if grep -q '{{AIAC_VERSION}}' "$P1/CLAUDE.md"; then
    ok "CLAUDE.md — необработанный шаблон (плейсхолдеры на месте)"
  else
    fail "CLAUDE.md не похож на шаблон — плейсхолдеры потеряны"
  fi
  # Папка aiac/ — справочник, а не git-репозиторий: вложенный .git сломал бы историю проекта.
  absent "$P1/aiac/.git" "вложенный .git внутри aiac/"
  # Имя папки критично: протокол ссылается на aiac/BOOTSTRAP.md поимённо (50 ссылок).
  absent "$P1/src" "каталог src/ не должен попасть в проект как есть"
else
  fail "чистая установка упала: $(cat "$WORK/out.log")"
fi

echo "2. Повторная установка без --force обязана отказаться, а не перезаписать"
printf 'мои правки\n' > "$P1/aiac/VERSION"
if run_install --dir "$P1"; then
  fail "установка поверх существующей aiac/ прошла вместо отказа"
else
  ok "отказ, ненулевой код выхода"
  if [ "$(cat "$P1/aiac/VERSION")" = "мои правки" ]; then
    ok "файлы не тронуты"
  else
    fail "файл внутри aiac/ изменён при отказе — установщик не должен ничего трогать"
  fi
fi

echo "3. --force обновляет aiac/, но НЕ трогает заполненный CLAUDE.md"
printf 'заполненный бутстрапом CLAUDE.md: {{EXECUTOR_NAME}} = opencode\n' > "$P1/CLAUDE.md"
printf 'мои правки\n' > "$P1/aiac/VERSION"
if run_install --dir "$P1" --force; then
  ok "обновление прошло"
  if [ "$(tr -d '[:space:]' < "$P1/aiac/VERSION")" = "$(tr -d '[:space:]' < "$ROOT/src/VERSION")" ]; then
    ok "aiac/VERSION вернулся к версии протокола"
  else
    fail "aiac/ не обновился после --force"
  fi
  if grep -q 'opencode' "$P1/CLAUDE.md"; then
    ok "CLAUDE.md не перезаписан (главная защита от потери конфигурации проекта)"
  else
    fail "CLAUDE.md перезаписан шаблоном — проект потерял настройки бутстрапа"
  fi
else
  fail "--force не отработал: $(cat "$WORK/out.log")"
fi

echo "4. Существующий чужой CLAUDE.md остаётся нетронутым и без --force"
P2="$(new_project p2)"
printf 'мой собственный CLAUDE.md\n' > "$P2/CLAUDE.md"
if run_install --dir "$P2"; then
  if [ "$(cat "$P2/CLAUDE.md")" = "мой собственный CLAUDE.md" ]; then
    ok "чужой CLAUDE.md сохранён"
  else
    fail "чужой CLAUDE.md перезаписан"
  fi
else
  fail "установка в проект с чужим CLAUDE.md упала: $(cat "$WORK/out.log")"
fi

echo "4а. --force-claude заменяет CLAUDE.md, но только со сделанной резервной копией"
# Единственный путь в скрипте, который перезаписывает CLAUDE.md, поэтому и единственное
# место, где обязателен бэкап: потеря заполненного бутстрапом файла невосстановима.
# --force нужен потому, что в p2 папка aiac/ уже стоит из шага 4 и без него установщик
# откажется ещё на первом шаге, не дойдя до CLAUDE.md.
if run_install --dir "$P2" --force --force-claude; then
  exists "$P2/CLAUDE.md.aiac-backup" "CLAUDE.md.aiac-backup"
  if grep -q '{{AIAC_VERSION}}' "$P2/CLAUDE.md"; then
    ok "CLAUDE.md теперь чистый шаблон"
  else
    fail "CLAUDE.md не заменён на шаблон"
  fi
  if grep -q 'мой собственный CLAUDE.md' "$P2/CLAUDE.md.aiac-backup"; then
    ok "прежнее содержимое сохранено в бэкапе"
  else
    fail "бэкап не содержит прежнего CLAUDE.md"
  fi
else
  fail "--force-claude упал: $(cat "$WORK/out.log")"
fi

echo "4б. --force работает и когда в старой aiac/ нет VERSION (иначе падение на set -e)"
P2B="$(new_project p2b)"
mkdir -p "$P2B/aiac"
echo "какая-то старая папка без VERSION" > "$P2B/aiac/README.md"
if run_install --dir "$P2B" --force; then
  exists "$P2B/aiac/VERSION" "aiac/VERSION после замены"
else
  fail "--force на папке без VERSION упал: $(cat "$WORK/out.log")"
fi

echo "5. --no-claude ставит только папку протокола"
P3="$(new_project p3)"
if run_install --dir "$P3" --no-claude; then
  exists "$P3/aiac/BOOTSTRAP.md" "aiac/BOOTSTRAP.md"
  absent "$P3/CLAUDE.md" "CLAUDE.md"
else
  fail "--no-claude упал: $(cat "$WORK/out.log")"
fi

echo "6. Несуществующий каталог и неизвестный аргумент — понятная ошибка, не тихий успех"
if run_install --dir "$WORK/нет-такого"; then
  fail "установка в несуществующий каталог прошла"
else
  ok "отказ на несуществующем каталоге"
fi
if run_install --dir "$P3" --такой-флага-нет; then
  fail "неизвестный аргумент принят"
else
  ok "отказ на неизвестном аргументе"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "install-test: OK — все проверки прошли."
else
  echo "install-test: ПРОВАЛЕНО проверок: $FAILED" >&2
  exit 1
fi
