#!/usr/bin/env bash

_stackname() {
    if [ -z ${1##*.yml} ]; then
        echo -n "$(basename $1 .yml)"
        return
    fi

    echo -n "$1"
}

_filename() {
    if [ -z ${1##*.yml} ]; then
        echo -n "$1"
        return
    fi

    echo -n "$1.yml"
}

up() {
    local params=("$@")

    if [[ -z "${params}" ]]; then
        params=(*.yml)
    fi

    for k in "${params[@]}"; do
        local stack=$(_stackname "${k}")
        local file=$(_filename "${k}")
        echo "Up'ing stack \`${stack}\` (from \`${file}\`)..."
        docker compose --file "${file}" --project-name "${stack}" up --detach
    done
}

down() {
    local params=("$@")

    if [[ -z "${params}" ]]; then
        params=(*.yml)
    fi

    for k in "${params[@]}"; do
        local stack=$(_stackname "${k}")
        local file=$(_filename "${k}")
        echo "Down'ing stack \`${stack}\` (from \`${file}\`)..."
        docker compose --file "${file}" --project-name "${stack}" down
    done
}

pull() {
    local params=("$@")

    if [[ -z "${params}" ]]; then
        params=(*.yml)
    fi

    for k in "${params[@]}"; do
        local stack=$(_stackname "${k}")
        local file=$(_filename "${k}")
        echo "Pulling images for stack \`${stack}\` (from \`${file}\`)..."
        docker compose --file "${file}" pull
    done
}

update() {
    local params=("$@")

    if [[ -z "${params}" ]]; then
        params=(*.yml)
    fi

    for k in "${params[@]}"; do
        echo "Updating stack \`${stack}\` (from \`${file}\`)..."
        down "${k}"
        pull "${k}"
        up "${k}"
    done
}

ls() {
    docker compose ls
}

log() {
    local stack=_stackname "${1}"
    docker compose --project-name "${stack}" logs "$@"
}

tail() {
    log $1 $2 --follow
}

ps() {
    local params=("$@")

    if [[ -z "${params}" ]]; then
        params=(*.yml)
    fi

    local green='\033[0;32m'
    local nc='\033[0m'

    for k in "${params[@]}"; do
        local stack=$(_stackname "${k}")
        local file=$(_filename "${k}")
        echo -e "\n${green}Process status stack \`${stack}\` (from \`${file}\`)${nc}"
        docker compose --file "${file}" --project-name "${stack}" ps --format "table {{.Service}}\t{{.Image}}\t{{.Status}}\t{{.State}}"
    done
}

help() {
    echo "Usage: $(basename $0) <cmd> [<args>]"
    echo ""
    echo "Commands:"
    echo "  help                                - prints this help"
    echo "  ls                                  - list running stacks"
    echo "  up [<(yml|stack)>+]                 - starts all stacks or those listed"
    echo "  down [<(yml|stack)>+]               - stops all stacks or those listed"
    echo "  pull [<(yml|stack)>+]               - updates latest images for stacks"
    echo "  update [<(yml|stack)>+]             - pulls and re-launch stacks"
    echo "  log <(yml|stack)> <image> [(opts)]  - shows log for a particular image"
    echo "  tail <(yml|stack)> <image> [(opts)] - tails log for a particular image"
}

if [[ $# -eq 0 ]]; then
    help
    exit 1
fi

# Runs function with provided arguments
if declare -f "${1}" >/dev/null; then
    func="${1}"
    shift        # pop $1 off the argument list
    "$func" "$@" # invoke our named function w/ all remaining arguments
else
    echo "Function \`$1\` not recognized" >&2
    help
    exit 1
fi
