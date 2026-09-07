#!/usr/bin/env bash
# Runs on a workstation; all privileged/system operations are replaced below.
set -euo pipefail
script="$(cd "$(dirname "$0")" && pwd)/setup.sh"
bash -n "$script"
source "$script" --help >/dev/null
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
run() { ( "$@" ) || fail "$*"; printf 'PASS: %s\n' "$*"; }

# Exercise the command printed for users across sudo's environment reset.
printed_finalize_command() {
  validate() { :; }; install_packages() { :; }; create_admin_user() { :; }
  configure_firewall() { :; }; write_ssh_config() { :; }; restart_ssh() { :; }
  port_is_listening() { return 0; }; configure_fail2ban() { :; }
  configure_system() { :; }; install_docker() { :; }
  SSH_CONFIG="$work/absent.conf"
  SCRIPT_PATH="$work/finalize.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'test "${SSH_CONNECTION:-}" = "192.0.2.1 54321 192.0.2.2 2222"' > "$SCRIPT_PATH"
  SSH_CONNECTION='192.0.2.1 54321 192.0.2.2 2222'
  local command
  command="$(setup | sed -n 's/.*then run: //p')"
  [[ -n $command ]] || fail 'setup did not print a finalize command'
  sudo() { env -i PATH="$PATH" "$@"; }
  eval "$command" || fail 'printed finalize command loses SSH_CONNECTION across sudo'
}

# These are the external side effects of finalize, not its decision logic.
mock_finalize_system() {
  validate() { :; }; id() { printf '1000\n'; }
  getent() { printf 'deploy:x:1000:1000::/home/deploy:/bin/bash\n'; }
  grep() {
    if [[ ${*: -1} == /home/*/.ssh/authorized_keys ]]; then return 0; fi
    command grep "$@"
  }
  write_ssh_config() { printf 'write\n' >> "$work/events"; }
  restart_ssh() { :; }
  port_is_listening() { [[ $1 == "$SSH_PORT" ]]; }
  ufw() { printf 'ufw\n' >> "$work/events"; }
  configure_fail2ban() { :; }; fail2ban-client() { :; }
  sshd() { printf 'port %s\n' "$SSH_PORT"; }
  SUDO_USER="$ADMIN_USER"
  SSH_CONNECTION='192.0.2.1 54321 192.0.2.2 2222'
  : > "$work/events"
}

reject_session() {
  mock_finalize_system
  case "$1" in
    missing) unset SSH_CONNECTION ;;
    wrong-port) SSH_CONNECTION='192.0.2.1 54321 192.0.2.2 22' ;;
    malformed) SSH_CONNECTION='2222' ;;
    wrong-user) SUDO_USER=root ;;
  esac
  if ( finalize ) > "$work/error" 2>&1; then fail "accepted $1 session"; fi
  [[ ! -s $work/events ]] || fail 'changed SSH/firewall before validating session'
  if [[ $1 == missing ]]; then
    command grep -q 'sudo env SSH_CONNECTION=' "$work/error" || fail 'missing recovery command'
  fi
}
accept_session() {
  mock_finalize_system
  finalize >/dev/null
  [[ $(head -n 1 "$work/events") == write ]] || fail 'did not configure SSH'
  command grep -q '^ufw$' "$work/events" || fail 'did not update firewall'
}

reject_setup_rerun() {
  validate() { :; }
  install_packages() { printf 'changed\n' > "$work/events"; exit 0; }
  SSH_CONFIG="$work/hardened.conf"
  printf 'PermitRootLogin no\n' > "$SSH_CONFIG"
  : > "$work/events"
  if ( setup ) >/dev/null 2>&1; then fail 'setup reopened hardened server'; fi
  [[ ! -s $work/events ]] || fail 'setup changed finalized server'
}

# Real temporary configuration files; fake service manager and sshd only.
config_rollback() {
  local reason="$1"
  SSH_CONNECTION='192.0.2.1 54321 192.0.2.2 2222'
  SSH_CONFIG="$work/sshd.conf"
  SSH_CONFIG_BACKUP="$work/sshd.conf.before-vps-setup"
  printf 'Port 22\nPort 2222\n# current working configuration\n' > "$SSH_CONFIG"
  cp "$SSH_CONFIG" "$work/expected.conf"
  printf 'stale backup\n' > "$SSH_CONFIG_BACKUP"
  install() {
    if [[ $1 == -d ]]; then return 0; fi
    cp "${@: -2:1}" "${@: -1}"
  }
  sshd() {
    if [[ $1 == -t ]]; then [[ $reason != syntax ]]; return; fi
    tr '[:upper:]' '[:lower:]' < "$SSH_CONFIG"
    printf 'authenticationmethods any\n'
    if [[ $reason == conflict ]]; then printf 'port 22\n'; fi
  }
  restart_ssh() {
    printf 'restart\n' >> "$work/restarts"
    [[ $reason != restart || $(wc -l < "$work/restarts") -gt 1 ]]
  }
  port_is_listening() {
    [[ $reason != listener && $1 == "$SSH_PORT" ]]
  }
  : > "$work/restarts"
  if ( write_ssh_config finalize ) > "$work/error" 2>&1; then fail "accepted $reason failure"; fi
  cmp -s "$SSH_CONFIG" "$work/expected.conf" || fail 'did not restore immediately previous config'
}

config_success() {
  local native="${2:-false}"
  SSH_CONNECTION='192.0.2.1 54321 192.0.2.2 2222'
  SSH_CONFIG="$work/success.conf"
  install() {
    if [[ $1 == -d ]]; then return 0; fi
    cp "${@: -2:1}" "${@: -1}"
  }
  sshd() {
    if [[ ${native:-false} == true ]]; then
      command sshd "$@" -f "$SSH_CONFIG" -h "$work/host-key"
    elif [[ $1 != -t ]]; then
      tr '[:upper:]' '[:lower:]' < "$SSH_CONFIG"
      printf 'authenticationmethods any\n'
    fi
  }
  restart_ssh() { :; }
  port_is_listening() { command grep -qxF "Port $1" "$SSH_CONFIG"; }
  write_ssh_config "$1"
  command grep -qxF 'Port 2222' "$SSH_CONFIG" || fail 'new port missing'
}

native_conflict() {
  SSH_CONFIG="$work/native-conflict.conf"
  SSH_CONNECTION='192.0.2.1 54321 192.0.2.2 2222'
  cat > "$SSH_CONFIG" <<'CONFIG'
Port 2222
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AllowUsers deploy
CONFIG
  case "$1" in
    extra-user) printf 'AllowUsers anotheruser\n' >> "$SSH_CONFIG" ;;
    match-password) printf 'Match User deploy\n  PasswordAuthentication yes\n' >> "$SSH_CONFIG" ;;
    match-root) printf 'Match User root\n  PermitRootLogin yes\n' >> "$SSH_CONFIG" ;;
  esac
  sshd() { command sshd "$@" -f "$SSH_CONFIG" -h "$work/host-key"; }
  if check_ssh_config finalize; then fail "accepted $1 conflict"; fi
}

run printed_finalize_command
for kind in missing wrong-port malformed wrong-user; do run reject_session "$kind"; done
run accept_session
run config_success setup
run config_success finalize
run reject_setup_rerun
for kind in syntax conflict restart listener; do run config_rollback "$kind"; done
if command -v sshd >/dev/null && command -v ssh-keygen >/dev/null; then
  ssh-keygen -q -t ed25519 -N '' -f "$work/host-key"
  run config_success setup true
  run config_success finalize true
  for kind in extra-user match-password match-root; do run native_conflict "$kind"; done
fi
printf 'All setup checks passed\n'
