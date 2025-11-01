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

    echo "Removendo arquivos de configuração..."
    rm -f traefik-stack.yml portainer-stack.yml || echo "Arquivos de stack já foram removidos."

    echo "Desinstalação concluída."
    exit 0
}

# Verificar se é root
check_root

# Menu de opções
echo "***************************************"
echo "* Instalador websolucoesmkt!          *"
echo "* Versão 2.0 - Ubuntu 22.04/24.04     *"
echo "***************************************"
echo ""
echo "Escolha uma opção:"
echo "1. Instalar serviços"
echo "2. Desinstalar serviços"
read -p "Digite sua escolha (1 ou 2): " CHOICE

if [ "$CHOICE" == "2" ]; then
    uninstall
fi

# Fluxo de instalação
LOGFILE="/var/log/websolucoesmkt-installer.log"
exec > >(tee -i $LOGFILE) 2>&1

echo "==================================="
echo "Iniciando instalação do ambiente Docker"
echo "==================================="

echo "Atualizando pacotes do sistema..."
apt update -yq && apt upgrade -yq

echo "Instalando dependências básicas..."
apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common

# Instalar Docker via repositório oficial (mais atualizado)
if ! command -v docker &> /dev/null; then
    echo "Docker não está instalado. Instalando versão oficial..."
    
    # Remover versões antigas se existirem
    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Adicionar repositório oficial do Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt update -yq
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Habilitar Docker para iniciar no boot
    systemctl enable docker
    systemctl start docker
    
    echo "Docker instalado com sucesso!"
else
    echo "Docker já está instalado."
    docker --version
fi

# Docker Compose v2 (plugin) já vem com Docker CE
if ! docker compose version &> /dev/null; then
    echo "Docker Compose não está instalado. Instalando..."
    apt install -y docker-compose-plugin
fi

echo "Docker Compose instalado:"
docker compose version

# Solicitar informações do usuário com validação
echo ""
echo "==================================="
echo "Configuração inicial do servidor"
echo "==================================="

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

echo ""
echo "Configurando hostname do servidor..."
hostnamectl set-hostname "$SERVER_NAME"
echo "127.0.0.1 $SERVER_NAME" >> /etc/hosts

# Configurar firewall básico (UFW)
echo "Configurando firewall..."
apt install -y ufw
ufw --force enable
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw allow 2377/tcp  # Docker Swarm
ufw allow 7946/tcp  # Docker Swarm
ufw allow 7946/udp  # Docker Swarm
ufw allow 4789/udp  # Docker Swarm overlay
echo "Firewall configurado!"

# Inicializar Docker Swarm
if ! docker info | grep -q "Swarm: active"; then
    echo ""
    echo "Inicializando Docker Swarm..."
    ADVERTISE_ADDR=$(hostname -I | awk '{print $1}')
    docker swarm init --advertise-addr "$ADVERTISE_ADDR"
    if [ $? -ne 0 ]; then
        echo "Erro ao inicializar o Docker Swarm. Verifique os logs."
        exit 1
    fi
    echo "Docker Swarm inicializado com sucesso!"
else
    echo "Docker Swarm já está ativo."
fi

echo ""
echo "Criando rede Docker compartilhada..."
docker network create --driver=overlay --attachable --scope swarm network_public 2>/dev/null || echo "Rede já existe."

echo "Criando volumes Docker compartilhados..."
docker volume create volume_swarm_certificates 2>/dev/null || echo "Volume de certificados já existe."
docker volume create portainer_data 2>/dev/null || echo "Volume do Portainer já existe."

echo "Ajustando permissões no volume de certificados..."
docker run --rm -v volume_swarm_certificates:/data alpine sh -c "touch /data/acme.json && chmod 600 /data/acme.json"

echo ""
echo "==================================="
echo "Gerando configurações das stacks"
echo "==================================="

# Stack do Traefik (atualizado para v3.0)
cat <<EOF > traefik-stack.yml
version: "3.8"
services:
  traefik:
    image: traefik:v3.0
    command:
      - "--api.dashboard=false"
      - "--api.insecure=false"
      - "--providers.swarm=true"
      - "--providers.swarm.endpoint=unix:///var/run/docker.sock"
      - "--providers.swarm.exposedbydefault=false"
      - "--providers.swarm.network=network_public"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencryptresolver.acme.email=$LETS_ENCRYPT_EMAIL"
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
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "volume_swarm_certificates:/etc/traefik/letsencrypt"
    networks:
      - network_public
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
networks:
  network_public:
    external: true
volumes:
  volume_swarm_certificates:
    external: true
EOF

# Stack do Portainer (atualizado para 2.21)
cat <<EOF > portainer-stack.yml
version: "3.8"
services:
  agent:
    image: portainer/agent:2.21.0
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - network_public
    deploy:
      mode: global
      placement:
        constraints:
          - node.platform.os == linux
  
  portainer:
    image: portainer/portainer-ce:2.21.0
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - portainer_data:/data
    networks:
      - network_public
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.portainer.rule=Host(\`$PORTAINER_DOMAIN\`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.portainer.service=portainer"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"
        - "traefik.docker.network=network_public"
networks:
  network_public:
    external: true
volumes:
  portainer_data:
    external: true
EOF

echo ""
echo "==================================="
echo "Fazendo deploy das stacks"
echo "==================================="

echo "Deploying Traefik..."
docker stack deploy -c traefik-stack.yml traefik

echo "Aguardando Traefik inicializar..."
sleep 10

echo "Deploying Portainer..."
docker stack deploy -c portainer-stack.yml portainer

echo ""
echo "Verificando serviços em execução..."
for i in {1..30}; do
    if docker service ls | grep -q "traefik" && docker service ls | grep -q "portainer"; then
        TRAEFIK_STATUS=$(docker service ls | grep traefik | awk '{print $4}')
        PORTAINER_STATUS=$(docker service ls | grep portainer | awk '{print $4}')
        
        if [[ "$TRAEFIK_STATUS" == *"1/1"* ]] && [[ "$PORTAINER_STATUS" == *"1/1"* ]]; then
            echo ""
            echo "✅ Todos os serviços estão em execução!"
            break
        fi
    fi
    echo "Aguardando os serviços subirem... Tentativa $i/30"
    sleep 5
done

echo ""
echo "==================================="
echo "Status dos serviços:"
echo "==================================="
docker service ls

echo ""
echo "************************************************"
echo "✅ Instalação concluída com sucesso!"
echo "************************************************"
echo ""
echo "📋 Informações importantes:"
echo "   • Portainer: https://$PORTAINER_DOMAIN"
echo "   • Traefik Dashboard: desativado por padr�o"
echo "   • Logs: $LOGFILE"
echo ""
echo "📌 Próximos passos:"
echo "   1. Acesse o Portainer e crie sua conta admin"
echo "   2. Configure seus containers/stacks"
echo "   3. Certifique-se que o domínio $PORTAINER_DOMAIN"
echo "      está apontando para o IP: $(hostname -I | awk '{print $1}')"
echo ""
echo "💡 Dicas:"
echo "   • Ver logs: docker service logs -f <service_name>"
echo "   • Listar serviços: docker service ls"
echo "   • Remover stack: docker stack rm <stack_name>"
echo ""
echo "************************************************"




