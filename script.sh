#!/bin/sh

DIR=/data
LOCK="$DIR/.lock"

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

    sleep 1
    rm -f "$DIR/$NAME"
    sleep 1
done
