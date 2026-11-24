#!/bin/sh
set -eu

hostname_file=/var/lib/tor/hidden_service/hostname
if [ ! -s "$hostname_file" ]; then
    tor -f /etc/tor/torrc --DisableNetwork 1 >&2 &
    pid=$!
    cleanup() {
        kill "$pid" 2>/dev/null || :
        wait "$pid" || :
    }
    trap cleanup EXIT
    trap 'exit 1' HUP INT TERM
    i=0
    while [ ! -s "$hostname_file" ]; do
        if [ "$i" -ge 15 ] || ! kill -0 "$pid" 2>/dev/null; then
            printf '%s\n' 'Tor could not create an onion hostname offline.' >&2
            exit 1
        fi
        i=$((i + 1))
        sleep 1
    done
fi
cat "$hostname_file"
