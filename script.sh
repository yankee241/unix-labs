#!/bin/sh

DIR="${DATA_DIR:-/data}"
LOCK="$DIR/.lock"

# проверка окружения
if ! command -v flock >/dev/null 2>&1; then
    echo "flock is not installed" >&2
    exit 1
fi

if [ ! -d "$DIR" ] || [ ! -w "$DIR" ]; then
    echo "shared directory $DIR is not available" >&2
    exit 1
fi

# случайный идентификатор контейнера (один на весь запуск)
ID=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')
COUNT=0

while true; do
    COUNT=$((COUNT + 1))

    # атомарная операция: поиск свободного имени + создание файла
    NAME=$(
        flock 9 || exit 1
        i=1
        while [ -e "$DIR/$(printf '%03d' "$i")" ]; do
            i=$((i + 1))
        done
        NAME=$(printf '%03d' "$i")
        echo "$ID $COUNT" > "$DIR/$NAME"
        echo "$NAME"
    ) 9>"$LOCK"

    if [ -z "$NAME" ]; then
        echo "failed to create file in $DIR" >&2
        exit 1
    fi

    sleep 1
    rm -f "$DIR/$NAME"
    sleep 1
done
