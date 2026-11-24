#!/bin/sh

torpress_validate_secret() {
    name=$1
    path="/run/secrets/$name"
    if [ ! -r "$path" ] || ! LC_ALL=C awk '
        NR != 1 || length($0) != 64 || $0 !~ /^[[:xdigit:]]+$/ { exit 1 }
        {
            value = tolower($0)
            for (i = 1; i <= 64; i++) {
                character = substr(value, i, 1)
                count[character]++
                if (count[character] == 1) distinct++
                if (count[character] > 12) exit 1
            }
            if (distinct < 8) exit 1
            for (period = 1; period <= 32; period++) {
                for (i = period + 1; i <= 64; i++) {
                    if (substr(value, i, 1) != substr(value, i - period, 1)) break
                }
                if (i == 65) exit 1
            }
        }
        END { if (NR != 1) exit 1 }
    ' "$path"; then
        printf 'Missing or weak secret: %s. Generate it with openssl rand -hex 32.\n' "$name" >&2
        return 1
    fi
}

torpress_require_distinct() {
    if [ "$(tr 'A-F' 'a-f' < "/run/secrets/$1")" = "$(tr 'A-F' 'a-f' < "/run/secrets/$2")" ]; then
        printf 'Secrets %s and %s must be different.\n' "$1" "$2" >&2
        return 1
    fi
}
