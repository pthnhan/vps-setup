#!/usr/bin/env bash
set -Eeuo pipefail

# Edit these values before running the script.
ADMIN_USER="deploy"
SSH_PORT="2222"
SSH_PUBLIC_KEY="PASTE_YOUR_PUBLIC_KEY_HERE"
TIMEZONE="UTC"
SWAP_SIZE_GB="2"

SCRIPT_PATH="$(readlink -f "$0")"
SSH_CONFIG="/etc/ssh/sshd_config.d/00-vps-setup.conf"
FAIL2BAN_CONFIG="/etc/fail2ban/jail.d/sshd.local"

log() {
  printf '\n==> %s\n' "$1"
}

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

validate() {
  [[ $EUID -eq 0 ]] || die "Run this script as root or with sudo."
  [[ -r /etc/os-release ]] || die "Cannot detect the operating system."

  # shellcheck disable=SC1091
  . /etc/os-release
  [[ ${ID:-} == "ubuntu" ]] || die "This script supports Ubuntu only."
  [[ $ADMIN_USER =~ ^[a-z_][a-z0-9_-]*$ ]] || die "ADMIN_USER is invalid."
  [[ $ADMIN_USER != root && $(id -u "$ADMIN_USER" 2>/dev/null || true) != 0 ]] || die "ADMIN_USER must not be root (UID 0)."
  [[ $SSH_PORT =~ ^[0-9]{1,5}$ ]] || die "SSH_PORT must contain 1 to 5 digits."
  (( 10#$SSH_PORT >= 1024 && 10#$SSH_PORT <= 65535 )) || die "SSH_PORT must be between 1024 and 65535."
  SSH_PORT=$((10#$SSH_PORT))
  [[ $SSH_PUBLIC_KEY != "PASTE_YOUR_PUBLIC_KEY_HERE" ]] || die "Set SSH_PUBLIC_KEY before running."
  [[ $SSH_PUBLIC_KEY != *$'\n'* ]] || die "SSH_PUBLIC_KEY must contain exactly one line."
  [[ $SWAP_SIZE_GB =~ ^[0-9]+$ ]] || die "SWAP_SIZE_GB must be a non-negative integer."
  timedatectl list-timezones | grep -Fx "$TIMEZONE" >/dev/null || die "TIMEZONE is invalid."

  local key_file
  key_file="$(mktemp)"
  printf '%s\n' "$SSH_PUBLIC_KEY" > "$key_file"
  ssh-keygen -l -f "$key_file" >/dev/null 2>&1 || {
    rm -f "$key_file"
    die "SSH_PUBLIC_KEY is not a valid public key."
  }
  rm -f "$key_file"
}

install_packages() {
  log "Updating Ubuntu and installing base packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get upgrade -y
  apt-get install -y \
    build-essential ca-certificates curl fail2ban git gnupg htop \
    nano sudo unattended-upgrades ufw unzip zsh
}

create_admin_user() {
  log "Creating administrative user: $ADMIN_USER"
  if ! id "$ADMIN_USER" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "$ADMIN_USER"
  fi

  usermod -aG sudo "$ADMIN_USER"

  if [[ $(passwd -S "$ADMIN_USER" | awk '{print $2}') != "P" ]]; then
    printf 'Set a password for %s. It will be used for sudo, not SSH.\n' "$ADMIN_USER"
    passwd "$ADMIN_USER"
  fi

  local ssh_dir authorized_keys admin_group
  ssh_dir="$(getent passwd "$ADMIN_USER" | cut -d: -f6)/.ssh"
  admin_group="$(id -gn "$ADMIN_USER")"
  authorized_keys="$ssh_dir/authorized_keys"
  install -d -m 700 -o "$ADMIN_USER" -g "$admin_group" "$ssh_dir"
  touch "$authorized_keys"
  grep -qxF "$SSH_PUBLIC_KEY" "$authorized_keys" || printf '\n%s\n' "$SSH_PUBLIC_KEY" >> "$authorized_keys"
  chown "$ADMIN_USER:$admin_group" "$authorized_keys"
  chmod 600 "$authorized_keys"
}

write_ssh_config() {
  local phase="$1" config_file backup_file had_config=false
  config_file="$(mktemp)"

  if [[ $phase == "setup" ]]; then
    cat > "$config_file" <<EOF
Port 22
Port $SSH_PORT
PubkeyAuthentication yes
EOF
  else
    cat > "$config_file" <<EOF
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowUsers $ADMIN_USER
EOF
  fi

  install -d -m 755 /etc/ssh/sshd_config.d
  backup_file="$(mktemp)"
  if [[ -f $SSH_CONFIG ]]; then
    cp -a "$SSH_CONFIG" "$backup_file"
    had_config=true
  fi
  install -m 600 -o root -g root "$config_file" "$SSH_CONFIG"
  rm -f "$config_file"

  if sshd -t && check_ssh_config "$phase" && restart_ssh &&
      port_is_listening "$SSH_PORT" &&
      { if [[ $phase == setup ]]; then port_is_listening 22;
        else ! port_is_listening 22; fi; }; then
    rm -f "$backup_file"
    return
  fi

  if [[ $had_config == true ]]; then
    cp -a "$backup_file" "$SSH_CONFIG"
  else
    rm -f "$SSH_CONFIG"
  fi
  rm -f "$backup_file"
  restart_ssh || die "SSH recovery failed. Keep this session open and use the provider console; inspect journalctl -u ssh.service -u ssh.socket."
  die "SSH change failed; previous configuration restored. Check sshd -T and other files in /etc/ssh before retrying."
}

check_ssh_config() {
  local phase="$1" effective expected context_user client_ip client_port server_ip connected_port
  effective="$(sshd -T)" || return 1
  grep -qxF "port $SSH_PORT" <<< "$effective" || return 1
  grep -qxF 'pubkeyauthentication yes' <<< "$effective" || return 1
  if [[ $phase == setup ]]; then
    grep -qxF 'port 22' <<< "$effective"
    return
  fi

  # Ports and AllowUsers are additive; Match blocks can override authentication.
  [[ $(awk '$1 == "port" {print $2}' <<< "$effective" | sort -u) == "$SSH_PORT" ]] || return 1
  read -r client_ip client_port server_ip connected_port <<< "$SSH_CONNECTION"
  for context_user in "$ADMIN_USER" root; do
    effective="$(sshd -T -C "user=$context_user,host=$client_ip,addr=$client_ip,laddr=$server_ip,lport=$SSH_PORT")" || return 1
    [[ $(awk '$1 == "allowusers" {for (i=2; i<=NF; i++) print $i}' <<< "$effective" | sort -u) == "$ADMIN_USER" ]] || return 1
    for expected in 'permitrootlogin no' 'passwordauthentication no' \
        'kbdinteractiveauthentication no' 'pubkeyauthentication yes'; do
      grep -qxF "$expected" <<< "$effective" || return 1
    done
    if [[ $context_user == "$ADMIN_USER" ]]; then
      grep -qxE 'authenticationmethods (any|publickey)' <<< "$effective" || return 1
    fi
  done
}

restart_ssh() {
  systemctl daemon-reload || return 1
  if systemctl is-active --quiet ssh.socket; then
    systemctl restart ssh.socket || return 1
  fi
  systemctl restart ssh.service
}

port_is_listening() {
  ss -H -ltn | awk -v port=":$1" '$4 ~ port "$" { found = 1 } END { exit !found }'
}

configure_firewall() {
  log "Allowing the old and new SSH ports in UFW"
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp comment 'temporary SSH fallback'
  ufw limit "$SSH_PORT/tcp" comment 'SSH'
  ufw --force enable
}

configure_fail2ban() {
  local ports="$1"
  cat > "$FAIL2BAN_CONFIG" <<EOF
[sshd]
enabled = true
port = $ports
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF
  chmod 644 "$FAIL2BAN_CONFIG"
  fail2ban-client -t
  systemctl enable fail2ban
  systemctl restart fail2ban
}

configure_system() {
  log "Configuring automatic security updates and timezone"
  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
  systemctl enable --now unattended-upgrades
  timedatectl set-timezone "$TIMEZONE"

  if (( 10#$SWAP_SIZE_GB > 0 )) && ! swapon --show --noheadings | grep . >/dev/null; then
    log "Creating ${SWAP_SIZE_GB} GiB swap file"
    if [[ ! -e /swapfile ]]; then
      fallocate -l "${SWAP_SIZE_GB}G" /swapfile
      chmod 600 /swapfile
      mkswap /swapfile
    fi
    swapon /swapfile
    grep -qF '/swapfile none swap sw 0 0' /etc/fstab || printf '%s\n' '/swapfile none swap sw 0 0' >> /etc/fstab
  fi
}

install_docker() {
  log "Installing Docker Engine and Compose"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  # shellcheck disable=SC1091
  . /etc/os-release
  cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable
EOF

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  usermod -aG docker "$ADMIN_USER"
}

setup() {
  validate
  if [[ -f $SSH_CONFIG ]] && grep -qiE '^[[:space:]]*PermitRootLogin[[:space:]]+no([[:space:]]|$)' "$SSH_CONFIG"; then
    die "SSH is already hardened. Do not rerun setup; use --finalize to retry final checks."
  fi
  install_packages
  create_admin_user
  configure_firewall

  log "Configuring SSH on ports 22 and $SSH_PORT"
  write_ssh_config setup
  configure_fail2ban "22,$SSH_PORT"
  configure_system
  install_docker

  log "Initial setup finished"
  printf '%s\n' \
    "1. Ensure TCP $SSH_PORT is open in the VPS provider firewall." \
    "2. Keep this session open." \
    "3. From a new terminal, log in as $ADMIN_USER on port $SSH_PORT with the private key matching SSH_PUBLIC_KEY." \
    "4. Verify sudo and Docker, then run: sudo env SSH_CONNECTION=\"\$SSH_CONNECTION\" bash \"$SCRIPT_PATH\" --finalize" \
    "Port 22 remains open until finalize succeeds."

  if [[ -f /var/run/reboot-required ]]; then
    printf 'Ubuntu reports that a reboot is required. Finalize SSH first, then reboot.\n'
  fi
}

finalize() {
  validate
  id "$ADMIN_USER" >/dev/null 2>&1 || die "ADMIN_USER does not exist; run setup first."
  local authorized_keys client_ip client_port server_ip connected_port extra
  authorized_keys="$(getent passwd "$ADMIN_USER" | cut -d: -f6)/.ssh/authorized_keys"
  grep -qxF "$SSH_PUBLIC_KEY" "$authorized_keys" || die "The configured public key is not installed for ADMIN_USER."
  [[ -n ${SSH_CONNECTION:-} ]] || die 'SSH_CONNECTION is missing (sudo usually removes it). From the new SSH session run: sudo env SSH_CONNECTION="$SSH_CONNECTION" bash /root/setup.sh --finalize (adjust the script path if needed).'
  read -r client_ip client_port server_ip connected_port extra <<< "$SSH_CONNECTION"
  [[ -n $client_ip && -n $server_ip && $client_port =~ ^[0-9]+$ && $connected_port =~ ^[0-9]+$ && -z $extra && $SSH_CONNECTION != *$'\n'* ]] || die "SSH_CONNECTION is malformed; reconnect directly by SSH."
  [[ $connected_port == "$SSH_PORT" ]] || die "Reconnect on port $SSH_PORT before finalizing (current port: $connected_port)."
  [[ ${SUDO_USER:-} == "$ADMIN_USER" ]] || die "Log in directly as $ADMIN_USER and run finalize with sudo."

  log "Disabling root/password SSH login and removing port 22"
  write_ssh_config finalize
  ufw --force delete allow 22/tcp
  configure_fail2ban "$SSH_PORT"

  log "First setup complete"
  sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|allowusers) '
  ufw status
  fail2ban-client status sshd
  printf 'Remove port 22 from the VPS provider firewall.\n'
}

case "${1:-}" in
  ""|--setup)
    setup
    ;;
  --finalize)
    finalize
    ;;
  -h|--help)
    printf 'Usage: sudo bash %s [--setup|--finalize]\n' "$0"
    ;;
  *)
    die "Unknown option: $1"
    ;;
esac
