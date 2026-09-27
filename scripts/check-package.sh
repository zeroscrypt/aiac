#!/bin/sh
#
# Проверка того, что пакет готов к публикации. Запускается вручную (`npm run check`),
# в prepublishOnly и в CI — потому что опечатку в `files` в package.json иначе
# замечает только пользователь после установки.

set -eu

cd "$(dirname "$0")/.."

fail() {
  echo "check-package: ОШИБКА — $*" >&2
  exit 1
}

command -v npm >/dev/null 2>&1 || fail "не найден npm"

# 1. Версия протокола (src/VERSION) и версия пакета (package.json) обязаны совпадать:
#    первая попадает в подключённый проект как aiac/VERSION и штампуется в CLAUDE.md,
#    вторая определяет, какой тег npm раздаст по curl. Расхождение = установщик отдаст
#    один набор файлов, а npm-версия будет другой.
pkg_version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json | head -1)"
proto_version="$(tr -d '[:space:]' < src/VERSION)"
[ -n "$pkg_version" ] || fail "не удалось прочитать version из package.json"
[ "$pkg_version" = "$proto_version" ] \
  || fail "версии расходятся: package.json=$pkg_version, src/VERSION=$proto_version — должны быть одинаковыми"

# 2. Все файлы протокола обязаны попасть в tarball. Нет bin/автоматической подстановки
#    путей, поэтому если хоть один шаблон выпадет из `files`, протокол в подключённом
#    проекте развалится молча — скомпилировать это может только бутстрап, уже без него.
listing="$(npm pack --dry-run 2>&1)" || fail "npm pack --dry-run не отработал"

# Из вывода берём ТОЛЬКО строки со списком содержимого tarball (npm notice + размер + путь).
# Строки вида `npm notice filename: aiac-1.6.0.tgz` — это метаданные, а не содержимое, и
# проверять по ним наличие мусора нельзя: имя самого tarball'а с расширением .tgz иначе
# даёт ложное срабатывание. Если формат вывода изменится, список окажется пустым и
# проверка упадёт громко, а не пройдёт молча.
contents="$(printf '%s\n' "$listing" | grep -E '^npm notice +[0-9]' || true)"
[ -n "$contents" ] || fail "не удалось разобрать список файлов из вывода npm pack"

for f in \
  package.json README.md LICENSE \
  src/VERSION src/README.md src/BOOTSTRAP.md src/LESSONS_LEARNED.md \
  src/templates/CLAUDE.template.md \
  src/templates/AGENTS.template.md \
  src/templates/PLAN.template.md \
  src/templates/CURRENT_TASK.template.md \
  src/templates/STATUS.template.md \
  src/templates/LOG.template.md \
  src/templates/REPORT.template.md \
  src/templates/ADR.template.md \
  install.sh
do
  printf '%s\n' "$contents" | grep -qF -- "$f" || fail "в пакет не попал файл: $f"
done

# 3. Мусор в tarball — та же цена ошибки, что и в .gitignore проекта (aiac/LESSONS_LEARNED.md,
#    пункт 11): попав однажды в историю/реестр, он уже не уйдёт молча. Проверяем фиксированными
#    подстроками (grep -F) — регулярное выражение здесь само было бы источником ложных
#    срабатываний и молчаливых промахов. Проверено на npm 11: `.git/` и `.DS_Store` npm
#    исключает сам, а вот `.tgz` (артефакт npm pack) и `node_modules/` через `files` протаскивает —
#    ровно они и ловятся этой проверкой.
for junk in '.git/' '.DS_Store' '.tgz' 'node_modules/' 'Thumbs.db'; do
  if printf '%s\n' "$contents" | grep -qF -- "$junk"; then
    echo "check-package: в пакет попал мусор: $junk" >&2
    fail "проверь поле files в package.json"
  fi
done

# 4. install.sh обязан оставаться исполняемым — иначе `bash aiac/../install.sh` сработает,
#    а `./install.sh` нет, и это расхождение обнаружится у пользователя.
[ -x install.sh ] || fail "install.sh не исполняемый (chmod +x install.sh)"

echo "check-package: OK — версия $pkg_version, протокол $proto_version, все файлы на месте."
