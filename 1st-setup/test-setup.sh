#!/usr/bin/env bash
set -euo pipefail

script="$(dirname "$0")/setup.sh"

assert_before() {
  local content="$1" first="$2" second="$3" first_line second_line
  first_line="$(awk -v text="$first" 'index($0, text) { print NR; exit }' <<< "$content")"
  second_line="$(awk -v text="$second" 'index($0, text) { print NR; exit }' <<< "$content")"
  [[ -n $first_line && -n $second_line && $first_line -lt $second_line ]]
}

bash -n "$script"
grep -q '^ADMIN_USER="deploy"$' "$script"
grep -q '^SSH_PORT="2222"$' "$script"
grep -q '^SSH_PUBLIC_KEY="PASTE_YOUR_PUBLIC_KEY_HERE"$' "$script"
grep -q 'SSH_CONNECTION' "$script"
grep -q 'port_is_listening "$SSH_PORT"' "$script"
grep -q 'ufw --force delete allow 22/tcp' "$script"
grep -q -- '--finalize' "$script"
! grep -Eq 'athena|187\.53\.133\.35' "$script"

setup_body="$(sed -n '/^setup() {$/,/^}$/p' "$script")"
finalize_body="$(sed -n '/^finalize() {$/,/^}$/p' "$script")"
! grep -q 'delete allow 22/tcp' <<< "$setup_body"
assert_before "$finalize_body" 'connected_port == "$SSH_PORT"' 'write_ssh_config finalize'
assert_before "$finalize_body" 'port_is_listening "$SSH_PORT"' 'delete allow 22/tcp'
assert_before "$finalize_body" 'port_is_listening 22' 'delete allow 22/tcp'

echo "setup.sh checks passed"
