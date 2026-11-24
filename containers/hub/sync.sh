#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
namespace=${DOCKERHUB_USERNAME:-vaiprog}
if [[ ! $namespace =~ ^[a-z0-9]+([_-][a-z0-9]+)*$ ]]; then
    printf '%s\n' 'DOCKERHUB_USERNAME is not a valid Docker Hub namespace.' >&2
    exit 1
fi

repositories=(
    'torpress-wordpress:Hardened WordPress and Apache for a Torpress onion site'
    'torpress-db:MariaDB with validated secrets for Torpress'
    'torpress-tor:Tor v3 onion service for a Torpress WordPress site'
)

docker_hub_url=https://hub.docker.com/v2
if [[ $# == 0 ]]; then
    : "${DOCKERHUB_USERNAME:?Set DOCKERHUB_USERNAME}"
    : "${DOCKERHUB_TOKEN:?Set DOCKERHUB_TOKEN}"
    bearer=$(jq -nc '{identifier:env.DOCKERHUB_USERNAME,secret:env.DOCKERHUB_TOKEN}' |
        curl --fail --silent --show-error --max-time 30 --proto '=https' \
            --header 'Content-Type: application/json' --data-binary @- "$docker_hub_url/auth/token" |
        jq -er '.access_token | strings | select(test("^[A-Za-z0-9._~-]+$"))')
    unset DOCKERHUB_TOKEN
elif [[ $# != 1 || $1 != --dry-run ]]; then
    printf 'Usage: %s [--dry-run]\n' "${0##*/}" >&2
    exit 2
fi

for entry in "${repositories[@]}"; do
    repository=${entry%%:*}
    summary=${entry#*:}
    overview="$repository.md"
    bytes=$(wc -c < "$overview")
    if (( ${#summary} > 100 || bytes == 0 || bytes > 25000 )); then
        printf 'Invalid Docker Hub description length for %s.\n' "$repository" >&2
        exit 1
    fi
    if [[ $# == 1 ]]; then
        printf '%s/%s (%s bytes) %s\n' "$namespace" "$repository" "$bytes" "$summary"
        continue
    fi
    status=$(jq -nc --arg summary "$summary" --rawfile overview "$overview" \
        '{description:$summary,full_description:$overview}' |
        curl --silent --show-error --max-time 30 --proto '=https' \
            --output /dev/null --write-out '%{http_code}' --request PATCH \
            --header 'Content-Type: application/json' \
            --config <(printf 'header = "Authorization: Bearer %s"\n' "$bearer") \
            --data-binary @- "$docker_hub_url/repositories/$namespace/$repository/")
    case $status in
        200) printf 'Updated %s/%s\n' "$namespace" "$repository" ;;
        403)
            printf 'Docker Hub refused to edit %s/%s. Check repository access and use a Read, Write & Delete token.\n' \
                "$namespace" "$repository" >&2
            exit 1
            ;;
        404)
            printf 'Create the Docker Hub repository %s/%s or publish its first image, then retry.\n' \
                "$namespace" "$repository" >&2
            exit 1
            ;;
        *)
            printf 'Docker Hub returned HTTP %s for %s/%s.\n' "$status" "$namespace" "$repository" >&2
            exit 1
            ;;
    esac
done
