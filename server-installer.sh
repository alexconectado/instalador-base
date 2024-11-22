#!/bin/bash

# Função para verificar se o usuário é root
function check_root {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Este script precisa ser executado como root ou com sudo."
        exit 1
    fi
}

# Verificar se é root
check_root

# Atualização inicial do sistema
echo "Atualizando pacotes do sistema..."
apt update && apt upgrade -y

# Instalar Docker e Docker Compose
echo "Instalando Docker e Docker Compose..."
apt install -y docker.io docker-compose

# Solicitar informações do usuário
echo "Configuração inicial para o servidor Docker:"
read -p "Digite o nome do servidor (exemplo: meu-servidor): " SERVER_NAME
read -p "Digite o domínio para o Portainer (exemplo: painel.seusite.com): " PORTAINER_DOMAIN
read -p "Digite o e-mail para o Let's Encrypt: " LETS_ENCRYPT_EMAIL

# Criar rede Docker compartilhada
echo "Criando rede Docker compartilhada..."
docker network create --driver=overlay --attachable network_public

# Criar volumes Docker compartilhados
echo "Criando volumes Docker compartilhados..."
docker volume create volume_swarm_certificates
docker volume create portainer_data

# Gerar arquivo docker-compose para Traefik
echo "Gerando arquivo docker-compose para o Traefik..."
cat <<EOF > traefik-stack.yml
version: "3.7"

services:
  traefik:
    image: traefik:2.11.2
    command:
      - "--api.dashboard=true"
      - "--providers.docker.swarmMode=true"
      - "--providers.docker.endpoint=unix:///var/run/docker.sock"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.docker.network=network_public"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencryptresolver.acme.email=$LETS_ENCRYPT_EMAIL"
      - "--certificatesresolvers.letsencryptresolver.acme.storage=/etc/traefik/letsencrypt/acme.json"
      - "--log.level=DEBUG"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "volume_swarm_certificates:/etc/traefik/letsencrypt"
    networks:
      - network_public

networks:
  network_public:
    external: true
volumes:
  volume_swarm_certificates:
    external: true
EOF

# Gerar arquivo docker-compose para o Portainer
echo "Gerando arquivo docker-compose para o Portainer..."
cat <<EOF > portainer-stack.yml
version: "3.7"

services:
  agent:
    image: portainer/agent:2.20.1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - network_public
    deploy:
      mode: global

  portainer:
    image: portainer/portainer-ce:2.20.1
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - portainer_data:/data
    networks:
      - network_public
    deploy:
      mode: replicated
      replicas: 1
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.portainer.rule=Host(\`$PORTAINER_DOMAIN\`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.tls.certresolver=letsencryptresolver"

networks:
  network_public:
    external: true
volumes:
  portainer_data:
    external: true
EOF

# Inicializar Docker Swarm (caso não esteja inicializado)
if ! docker info | grep -q "Swarm: active"; then
    echo "Inicializando Docker Swarm..."
    docker swarm init
fi

# Fazer deploy das stacks
echo "Fazendo deploy das stacks..."
docker stack deploy -c traefik-stack.yml traefik
docker stack deploy -c portainer-stack.yml portainer

echo "Instalação concluída!"
echo "Acesse o Portainer em https://$PORTAINER_DOMAIN"
