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
SSH_CONFIG_BACKUP="${SSH_CONFIG}.before-vps-setup"
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
  [[ $SSH_PORT =~ ^[0-9]+$ ]] || die "SSH_PORT must be a number."
  (( 10#$SSH_PORT >= 1024 && 10#$SSH_PORT <= 65535 )) || die "SSH_PORT must be between 1024 and 65535."
  [[ $SSH_PORT != "22" ]] || die "SSH_PORT must differ from port 22."
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

  local ssh_dir authorized_keys
  ssh_dir="/home/$ADMIN_USER/.ssh"
  authorized_keys="$ssh_dir/authorized_keys"
  install -d -m 700 -o "$ADMIN_USER" -g "$ADMIN_USER" "$ssh_dir"
  touch "$authorized_keys"
  grep -qxF "$SSH_PUBLIC_KEY" "$authorized_keys" || printf '%s\n' "$SSH_PUBLIC_KEY" >> "$authorized_keys"
  chown "$ADMIN_USER:$ADMIN_USER" "$authorized_keys"
  chmod 600 "$authorized_keys"
}

write_ssh_config() {
  local phase="$1" config_file
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
  if [[ -f $SSH_CONFIG && ! -f $SSH_CONFIG_BACKUP ]]; then
    cp -a "$SSH_CONFIG" "$SSH_CONFIG_BACKUP"
  fi
  install -m 600 -o root -g root "$config_file" "$SSH_CONFIG"
  rm -f "$config_file"

  if ! sshd -t; then
    if [[ -f $SSH_CONFIG_BACKUP ]]; then
      cp -a "$SSH_CONFIG_BACKUP" "$SSH_CONFIG"
    else
      rm -f "$SSH_CONFIG"
    fi
    die "SSH configuration is invalid; the previous file was restored."
  fi
}

restart_ssh() {
  systemctl daemon-reload
  if systemctl is-active --quiet ssh.socket; then
    systemctl restart ssh.socket
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
  install_packages
  create_admin_user
  configure_firewall

  log "Configuring SSH on ports 22 and $SSH_PORT"
  write_ssh_config setup
  restart_ssh
  port_is_listening 22 || die "Port 22 is not listening; use the provider console to recover."
  port_is_listening "$SSH_PORT" || die "Port $SSH_PORT is not listening; port 22 remains available."
  configure_fail2ban "22,$SSH_PORT"
  configure_system
  install_docker

  log "Initial setup finished"
  printf '%s\n' \
    "1. Ensure TCP $SSH_PORT is open in the VPS provider firewall." \
    "2. Keep this session open." \
    "3. From a new terminal, log in as $ADMIN_USER on port $SSH_PORT with the private key matching SSH_PUBLIC_KEY." \
    "4. Verify sudo and Docker, then run: sudo bash $SCRIPT_PATH --finalize" \
    "Port 22 remains open until finalize succeeds."

  if [[ -f /var/run/reboot-required ]]; then
    printf 'Ubuntu reports that a reboot is required. Finalize SSH first, then reboot.\n'
  fi
}

finalize() {
  validate
  id "$ADMIN_USER" >/dev/null 2>&1 || die "ADMIN_USER does not exist; run setup first."
  grep -qxF "$SSH_PUBLIC_KEY" "/home/$ADMIN_USER/.ssh/authorized_keys" || die "The configured public key is not installed for ADMIN_USER."
  [[ -n ${SSH_CONNECTION:-} ]] || die "Run finalize from an SSH session connected to the new port."

  local connected_port
  connected_port="${SSH_CONNECTION##* }"
  [[ $connected_port == "$SSH_PORT" ]] || die "Reconnect on port $SSH_PORT before finalizing."

  log "Disabling root/password SSH login and removing port 22"
  write_ssh_config finalize
  restart_ssh
  port_is_listening "$SSH_PORT" || die "Port $SSH_PORT stopped listening; use the current session or provider console to recover."
  if port_is_listening 22; then
    die "Port 22 is still listening; check other SSH configuration files before closing it."
  fi
  ufw --force delete allow 22/tcp || true
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
