#!/bin/sh

# Проверяем, передан ли аргумент
if [ -z "$1" ]; then
    echo "Использование: $0 <исходный_файл>" >&2
    exit 1
fi

SRC_FILE="$1"

# Убеждаемся, что файл существует
if [ ! -f "$SRC_FILE" ]; then
    echo "Ошибка: файл '$SRC_FILE' не найден." >&2
    exit 1
fi

# 1. Ищем имя конечного файла строго по стандарту POSIX (без grep -m 1 и \t)
OUT_NAME=$(sed -n '/Output:/ { s/.*Output:[[:space:]]*//p; q; }' "$SRC_FILE" | tr -d '\r')

if [ -z "$OUT_NAME" ]; then
    echo "Ошибка: не найден комментарий 'Output: <имя_файла>'." >&2
    exit 2
fi

# 2. Идеальная ловушка: ставим trap ДО создания папки
TMP_DIR=""
cleanup_handler() {
    rc=$?
    trap - EXIT
    # Удаляем, только если папка успела создаться
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
    exit $rc
}
trap cleanup_handler EXIT HUP INT QUIT PIPE TERM

# Теперь безопасно создаем временный каталог
TMP_DIR=$(mktemp -d)
if [ -z "$TMP_DIR" ]; then
    echo "Ошибка: не удалось создать временный каталог." >&2
    exit 3
fi

# 3. Подготовка к сборке
SRC_BASE="${SRC_FILE##*/}" 
SRC_DIR=$(cd "$(dirname "$SRC_FILE")" && pwd)

cp "$SRC_FILE" "$TMP_DIR/"
cd "$TMP_DIR" || exit 4

EXT="${SRC_BASE##*.}"

echo "Сборка $SRC_BASE..."

# 4. Компиляция
case "$EXT" in
    c)
        gcc -Wall -O2 "$SRC_BASE" -o "$OUT_NAME"
        BUILD_RC=$?
        ;;
    cpp)
        g++ -Wall -O2 "$SRC_BASE" -o "$OUT_NAME"
        BUILD_RC=$?
        ;;
    tex)
        pdflatex -interaction=nonstopmode -jobname="${OUT_NAME%.*}" "$SRC_BASE"
        BUILD_RC=$?
        ;;
    *)
        echo "Ошибка: неподдерживаемое расширение .$EXT (ожидаются .c, .cpp, .tex)." >&2
        exit 5
        ;;
esac

# 5. Проверка результата
if [ "$BUILD_RC" -ne 0 ]; then
    echo "Ошибка компиляции (код $BUILD_RC)." >&2
    exit "$BUILD_RC"
fi

if [ -f "$OUT_NAME" ]; then
    cp "$OUT_NAME" "$SRC_DIR/"
    echo "Готово. Файл сохранен: $SRC_DIR/$OUT_NAME"
else
    echo "Ошибка: компиляция прошла, но целевой файл $OUT_NAME не был создан." >&2
    exit 6
fi

exit 0

