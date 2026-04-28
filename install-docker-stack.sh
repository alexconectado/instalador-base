#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[ERRO] Falha na linha $LINENO. Comando: $BASH_COMMAND"' ERR

TRAEFIK_VERSION="v3.6.14"
PORTAINER_VERSION="2.21.0"

NETWORK_NAME="network_public"
TRAEFIK_STACK="traefik"
PORTAINER_STACK="portainer"

CERT_VOLUME="volume_swarm_certificates"
PORTAINER_VOLUME="portainer_data"

INSTALL_DIR="/opt/stacks"
LOGFILE="/var/log/vps-bootstrap.log"

log() { echo -e "\n[INFO] $*"; }
warn() { echo -e "\n[AVISO] $*"; }
fail() { echo -e "\n[ERRO] $*" >&2; exit 1; }

check_root() {
  [ "$(id -u)" -eq 0 ] || fail "Execute como root."
}

check_ubuntu() {
  grep -qi "ubuntu" /etc/os-release || fail "Script pensado para Ubuntu 22.04/24.04."
}

ask_required() {
  local var_name="$1"
  local label="$2"
  local value=""

  read -rp "$label: " value
  [ -n "$value" ] || fail "$label não pode ficar vazio."

  printf -v "$var_name" "%s" "$value"
}

validate_email() {
  local email="$1"

  [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] \
    || fail "E-mail inválido: $email"
}

install_base_packages() {
  log "Atualizando sistema e instalando pacotes base..."

  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

  apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    ufw \
    dnsutils \
    jq \
    htop \
    nano \
    vim \
    unzip \
    fail2ban
}

remove_old_docker_packages() {
  log "Removendo possíveis pacotes Docker antigos/conflitantes..."

  apt-get remove -y \
    docker \
    docker-engine \
    docker.io \
    docker-doc \
    docker-compose \
    docker-compose-v2 \
    podman-docker \
    containerd \
    runc 2>/dev/null || true
}

install_docker_official_repo() {
  log "Instalando Docker pelo repositório oficial..."

  install -m 0755 -d /etc/apt/keyrings

  rm -f /etc/apt/keyrings/docker.gpg
  rm -f /etc/apt/sources.list.d/docker.list

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y

  apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  systemctl enable docker
  systemctl restart docker
}

validate_docker_api() {
  log "Validando Docker e versão da API..."

  docker --version
  docker compose version || true

  local api_version
  api_version="$(docker version --format '{{.Server.APIVersion}}' 2>/dev/null || true)"

  [ -n "$api_version" ] || fail "Não foi possível obter a API version do Docker."

  echo "Docker Server API version: $api_version"

  local major minor
  major="$(echo "$api_version" | cut -d. -f1)"
  minor="$(echo "$api_version" | cut -d. -f2)"

  if [ "$major" -lt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -lt 40 ]; }; then
    fail "Docker API muito antiga: $api_version. Mínimo necessário: 1.40."
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker já instalado. Validando..."
    validate_docker_api
    return
  fi

  remove_old_docker_packages
  install_docker_official_repo
  validate_docker_api
}

reset_docker_if_requested() {
  echo ""
  read -rp "Deseja resetar completamente o Docker antes de instalar? Isso apaga containers, imagens, volumes e Swarm. (s/n): " RESET_DOCKER
  RESET_DOCKER="${RESET_DOCKER:-n}"

  if [ "$RESET_DOCKER" != "s" ]; then
    return
  fi

  warn "Reset completo do Docker solicitado."
  warn "Todos os containers, imagens, volumes, redes e Swarm serão removidos."

  read -rp "Digite RESET para confirmar: " CONFIRM_RESET
  [ "$CONFIRM_RESET" = "RESET" ] || fail "Reset cancelado."

  docker stack rm "$PORTAINER_STACK" 2>/dev/null || true
  docker stack rm "$TRAEFIK_STACK" 2>/dev/null || true
  sleep 15

  if docker info 2>/dev/null | grep -q "Swarm: active"; then
    docker swarm leave --force || true
  fi

  systemctl stop docker 2>/dev/null || true
  systemctl stop containerd 2>/dev/null || true

  remove_old_docker_packages

  rm -rf /var/lib/docker
  rm -rf /var/lib/containerd
  rm -rf /etc/docker

  install_docker_official_repo
  validate_docker_api
}

configure_hostname() {
  log "Configurando hostname..."

  hostnamectl set-hostname "$SERVER_NAME"

  if ! grep -q "$SERVER_NAME" /etc/hosts; then
    echo "127.0.0.1 $SERVER_NAME" >> /etc/hosts
  fi
}

configure_firewall() {
  log "Configurando firewall..."

  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing

  ufw allow 22/tcp comment "SSH"
  ufw allow 80/tcp comment "HTTP"
  ufw allow 443/tcp comment "HTTPS"

  if [ "$CLUSTER_MODE" = "s" ]; then
    warn "Modo cluster ativado."

    if [ -n "${CLUSTER_ALLOWED_IP:-}" ]; then
      ufw allow from "$CLUSTER_ALLOWED_IP" to any port 2377 proto tcp comment "Docker Swarm Manager"
      ufw allow from "$CLUSTER_ALLOWED_IP" to any port 7946 proto tcp comment "Docker Swarm Gossip TCP"
      ufw allow from "$CLUSTER_ALLOWED_IP" to any port 7946 proto udp comment "Docker Swarm Gossip UDP"
      ufw allow from "$CLUSTER_ALLOWED_IP" to any port 4789 proto udp comment "Docker Swarm Overlay"
    else
      warn "Nenhum IP informado. Por segurança, portas Swarm NÃO serão abertas."
    fi
  fi

  ufw --force enable
  ufw status verbose
}

configure_fail2ban() {
  log "Configurando Fail2Ban..."

  cat > /etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = %(sshd_log)s
maxretry = 5
bantime = 1h
findtime = 10m
EOF

  systemctl enable fail2ban
  systemctl restart fail2ban
}

validate_dns() {
  log "Validando DNS..."

  local server_ip
  local domain_ip

  server_ip="$(curl -4 -s ifconfig.me || true)"
  domain_ip="$(dig +short "$PORTAINER_DOMAIN" A | tail -n1 || true)"

  echo "IP da VPS: $server_ip"
  echo "IP do domínio: $domain_ip"

  if [ -z "$domain_ip" ]; then
    warn "Domínio ainda não resolveu DNS. O SSL pode falhar."
    return
  fi

  if [ "$server_ip" != "$domain_ip" ]; then
    warn "Domínio não aponta diretamente para o IP da VPS."
    warn "Se estiver usando Cloudflare proxy ativo, isso pode ser normal."
  fi
}

init_swarm() {
  if docker info | grep -q "Swarm: active"; then
    log "Docker Swarm já ativo."
    return
  fi

  log "Inicializando Docker Swarm..."

  local advertise_addr
  advertise_addr="$(hostname -I | awk '{print $1}')"

  docker swarm init --advertise-addr "$advertise_addr"
}

create_networks_and_volumes() {
  log "Criando rede e volumes..."

  if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "Rede $NETWORK_NAME já existe."
  else
    docker network create \
      --driver=overlay \
      --attachable \
      --scope swarm \
      "$NETWORK_NAME"
  fi

  if docker volume inspect "$CERT_VOLUME" >/dev/null 2>&1; then
    echo "Volume $CERT_VOLUME já existe."
  else
    docker volume create "$CERT_VOLUME" >/dev/null
  fi

  if docker volume inspect "$PORTAINER_VOLUME" >/dev/null 2>&1; then
    echo "Volume $PORTAINER_VOLUME já existe."
  else
    docker volume create "$PORTAINER_VOLUME" >/dev/null
  fi

  log "Ajustando permissões do acme.json..."

  docker pull alpine:3.20

  docker run --rm \
    -v "$CERT_VOLUME":/data \
    alpine:3.20 \
    sh -c "touch /data/acme.json && chmod 600 /data/acme.json"

  log "Rede e volumes prontos."
}

prepare_install_dir() {
  log "Preparando diretório $INSTALL_DIR..."

  mkdir -p "$INSTALL_DIR"

  if [ -f "$INSTALL_DIR/traefik-stack.yml" ]; then
    cp "$INSTALL_DIR/traefik-stack.yml" "$INSTALL_DIR/traefik-stack.yml.bak.$(date +%Y%m%d%H%M%S)"
  fi

  if [ -f "$INSTALL_DIR/portainer-stack.yml" ]; then
    cp "$INSTALL_DIR/portainer-stack.yml" "$INSTALL_DIR/portainer-stack.yml.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

write_traefik_stack() {
  log "Gerando stack Traefik..."

  cat > "$INSTALL_DIR/traefik-stack.yml" <<EOF
version: "3.8"

services:
  traefik:
    image: traefik:${TRAEFIK_VERSION}

    environment:
      - DOCKER_API_VERSION=1.41

    command:
      - "--api.dashboard=false"
      - "--api.insecure=false"

      - "--providers.swarm=true"
      - "--providers.swarm.endpoint=unix:///var/run/docker.sock"
      - "--providers.swarm.exposedbydefault=false"
      - "--providers.swarm.network=${NETWORK_NAME}"
      - "--providers.swarm.watch=true"
      - "--providers.swarm.refreshseconds=15"

      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"

      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"

      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencryptresolver.acme.email=${LETS_ENCRYPT_EMAIL}"
      - "--certificatesresolvers.letsencryptresolver.acme.storage=/etc/traefik/letsencrypt/acme.json"

      - "--log.level=INFO"
      - "--accesslog=true"

    ports:
      - target: 80
        published: 80
        mode: host
      - target: 443
        published: 443
        mode: host

    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ${CERT_VOLUME}:/etc/traefik/letsencrypt

    networks:
      - ${NETWORK_NAME}

    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 5

networks:
  ${NETWORK_NAME}:
    external: true

volumes:
  ${CERT_VOLUME}:
    external: true
EOF
}

write_portainer_stack() {
  log "Gerando stack Portainer..."

  cat > "$INSTALL_DIR/portainer-stack.yml" <<EOF
version: "3.8"

services:
  agent:
    image: portainer/agent:${PORTAINER_VERSION}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - ${NETWORK_NAME}
    deploy:
      mode: global
      placement:
        constraints:
          - node.platform.os == linux
      restart_policy:
        condition: on-failure

  portainer:
    image: portainer/portainer-ce:${PORTAINER_VERSION}
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - ${PORTAINER_VOLUME}:/data
    networks:
      - ${NETWORK_NAME}
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.portainer.rule=Host(\`${PORTAINER_DOMAIN}\`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.tls=true"
        - "traefik.http.routers.portainer.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.portainer.service=portainer"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"
        - "traefik.docker.network=${NETWORK_NAME}"

networks:
  ${NETWORK_NAME}:
    external: true

volumes:
  ${PORTAINER_VOLUME}:
    external: true
EOF
}

verify_stack_files() {
  log "Conferindo arquivos gerados..."

  ls -lah "$INSTALL_DIR"

  [ -s "$INSTALL_DIR/traefik-stack.yml" ] || fail "Arquivo traefik-stack.yml não foi gerado."
  [ -s "$INSTALL_DIR/portainer-stack.yml" ] || fail "Arquivo portainer-stack.yml não foi gerado."
}

deploy_stacks() {
  log "Deploy Traefik..."
  docker stack deploy -c "$INSTALL_DIR/traefik-stack.yml" "$TRAEFIK_STACK"

  sleep 10

  log "Deploy Portainer..."
  docker stack deploy -c "$INSTALL_DIR/portainer-stack.yml" "$PORTAINER_STACK"
}

wait_services() {
  log "Aguardando serviços..."

  for i in {1..40}; do
    traefik_replicas="$(docker service ls --format '{{.Name}} {{.Replicas}}' | grep "${TRAEFIK_STACK}_traefik" | awk '{print $2}' || true)"
    portainer_replicas="$(docker service ls --format '{{.Name}} {{.Replicas}}' | grep "${PORTAINER_STACK}_portainer" | awk '{print $2}' || true)"

    echo "Tentativa $i/40 | Traefik: ${traefik_replicas:-aguardando} | Portainer: ${portainer_replicas:-aguardando}"

    if [[ "$traefik_replicas" == "1/1" && "$portainer_replicas" == "1/1" ]]; then
      log "Serviços ativos."
      return
    fi

    sleep 5
  done

  warn "Verifique os serviços manualmente."
}

show_status() {
  echo ""
  echo "=================================================="
  echo "INSTALAÇÃO CONCLUÍDA"
  echo "=================================================="
  docker service ls
  echo ""
  echo "Portainer: https://${PORTAINER_DOMAIN}"
  echo "Stacks: ${INSTALL_DIR}"
  echo "Log: ${LOGFILE}"
  echo ""
  echo "Comandos úteis:"
  echo "docker service ls"
  echo "docker stack ps traefik"
  echo "docker stack ps portainer"
  echo "docker service logs -f traefik_traefik"
  echo "docker service logs -f portainer_portainer"
  echo "=================================================="
}

uninstall() {
  log "Removendo stacks..."

  docker stack rm "$PORTAINER_STACK" || true
  docker stack rm "$TRAEFIK_STACK" || true

  sleep 15

  read -rp "Remover volumes também? Isso apaga dados. Digite SIM: " CONFIRM

  if [ "$CONFIRM" = "SIM" ]; then
    docker volume rm "$CERT_VOLUME" || true
    docker volume rm "$PORTAINER_VOLUME" || true
  fi

  log "Remoção concluída."
}

install_flow() {
  ask_required SERVER_NAME "Nome do servidor"
  ask_required PORTAINER_DOMAIN "Domínio do Portainer"
  ask_required LETS_ENCRYPT_EMAIL "E-mail para Let's Encrypt"

  validate_email "$LETS_ENCRYPT_EMAIL"

  echo ""
  read -rp "Este servidor fará parte de um cluster Swarm futuramente? (s/n): " CLUSTER_MODE
  CLUSTER_MODE="${CLUSTER_MODE:-n}"

  if [ "$CLUSTER_MODE" = "s" ]; then
    echo ""
    read -rp "Informe o IP permitido para portas Swarm. Deixe vazio para não abrir: " CLUSTER_ALLOWED_IP
  fi

  reset_docker_if_requested

  exec > >(tee -i "$LOGFILE") 2>&1

  check_ubuntu
  install_base_packages
  install_docker
  configure_hostname
  configure_firewall
  configure_fail2ban
  validate_dns
  init_swarm
  create_networks_and_volumes
  prepare_install_dir
  write_traefik_stack
  write_portainer_stack
  verify_stack_files
  deploy_stacks
  wait_services
  show_status
}

main_menu() {
  echo "=================================================="
  echo "VPS Bootstrap"
  echo "Docker Swarm + Traefik + Portainer"
  echo "=================================================="
  echo "1. Instalar / atualizar infraestrutura"
  echo "2. Remover Traefik e Portainer"
  echo "=================================================="

  read -rp "Escolha uma opção: " OPTION

  case "$OPTION" in
    1) install_flow ;;
    2)
      exec > >(tee -i "$LOGFILE") 2>&1
      uninstall
      ;;
    *) fail "Opção inválida." ;;
  esac
}

check_root
main_menu
