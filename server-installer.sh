#!/bin/bash

# Função para verificar se o usuário é root
function check_root {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Este script precisa ser executado como root ou com sudo."
        exit 1
    fi
}

# Função para desinstalar os serviços
function uninstall {
    echo "Removendo stacks do Docker..."
    docker stack rm traefik
    docker stack rm portainer
    echo "Aguardando remoção das stacks..."
    sleep 10

    echo "Removendo redes do Docker..."
    docker network rm network_public || echo "Rede network_public já foi removida."

    echo "Removendo volumes do Docker..."
    docker volume rm volume_swarm_certificates portainer_data || echo "Volumes já foram removidos."

    echo "Removendo logs do instalador..."
    rm -f /var/log/websolucoesmkt-installer.log || echo "Log já foi removido."

    echo "Desinstalação concluída."
    exit 0
}

# Verificar se é root
check_root

# Menu de opções
echo "***************************************"
echo "* Instalador websolucoesmkt!          *"
echo "***************************************"
echo ""
echo "Escolha uma opção:"
echo "1. Instalar serviços"
echo "2. Desinstalar serviços"
read -p "Digite sua escolha (1 ou 2): " CHOICE

if [ "$CHOICE" == "2" ]; then
    uninstall
fi

# Fluxo de instalação (mesmo conteúdo ajustado para permissões, etc.)
LOGFILE="/var/log/websolucoesmkt-installer.log"
exec > >(tee -i $LOGFILE) 2>&1

echo "Atualizando pacotes do sistema..."
apt update -yq && apt upgrade -yq

echo "Verificando dependências..."
if ! command -v docker &> /dev/null; then
    echo "Docker não está instalado. Instalando agora..."
    apt install -y docker.io
fi

if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose não está instalado. Instalando agora..."
    apt install -y docker-compose
fi

# Solicitar informações do usuário com validação
echo "Configuração inicial para o servidor Docker:"
read -p "Digite o nome do servidor (exemplo: meu-servidor): " SERVER_NAME
if [[ -z "$SERVER_NAME" ]]; then
    echo "Erro: O nome do servidor não pode estar vazio."
    exit 1
fi

read -p "Digite o domínio para o Portainer (exemplo: painel.seusite.com): " PORTAINER_DOMAIN
if [[ -z "$PORTAINER_DOMAIN" ]]; then
    echo "Erro: O domínio não pode estar vazio."
    exit 1
fi

read -p "Digite o e-mail para o Let's Encrypt: " LETS_ENCRYPT_EMAIL
if ! [[ "$LETS_ENCRYPT_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    echo "Erro: Endereço de e-mail inválido."
    exit 1
fi

echo "Alterando o hostname da máquina para $SERVER_NAME..."
hostnamectl set-hostname "$SERVER_NAME"
echo "127.0.0.1 $SERVER_NAME" >> /etc/hosts

if ! docker info | grep -q "Swarm: active"; then
    echo "Inicializando Docker Swarm..."
    ADVERTISE_ADDR=$(hostname -I | awk '{print $1}')
    docker swarm init --advertise-addr "$ADVERTISE_ADDR"
    if [ $? -ne 0 ]; then
        echo "Erro ao inicializar o Docker Swarm. Verifique os logs para mais informações."
        exit 1
    fi
fi

echo "Criando rede Docker compartilhada..."
docker network create --driver=overlay --attachable --scope swarm network_public

echo "Criando volumes Docker compartilhados..."
docker volume create volume_swarm_certificates
docker volume create portainer_data

echo "Ajustando permissões no volume de certificados..."
docker run --rm -v volume_swarm_certificates:/data alpine sh -c "touch /data/acme.json && chmod 600 /data/acme.json"

echo "Gerando arquivo docker-compose para o Traefik..."
cat <<EOF > traefik-stack.yml
version: "3.7"
services:
  traefik:
    image: traefik:2.11.2
    user: "0:0"
    command:
      - "--api.dashboard=true"
      - "--entrypoints.dashboard.address=127.0.0.1:8080"
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
      - "volume_swarm_certificates:/etc/traefik/letsencrypt:ro"
    networks:
      - network_public
networks:
  network_public:
    external: true
volumes:
  volume_swarm_certificates:
    external: true
EOF

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
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"
networks:
  network_public:
    external: true
volumes:
  portainer_data:
    external: true
EOF

echo "Fazendo deploy das stacks..."
docker stack deploy -c traefik-stack.yml traefik
docker stack deploy -c portainer-stack.yml portainer

echo "Verificando serviços em execução..."
for i in {1..30}; do
    if docker service ls | grep -q "traefik" && docker service ls | grep -q "portainer"; then
        echo "Todos os serviços estão em execução!"
        break
    fi
    echo "Aguardando os serviços subirem... Tentativa $i/30"
    sleep 5
done

echo ""
echo "************************************************"
echo "Instalação concluída pelo instalador websolucoesmkt!"
echo "Acesse o Portainer em https://$PORTAINER_DOMAIN"
echo "************************************************"
