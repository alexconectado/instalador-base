🚀 Instalador Base — Docker + Traefik + Portainer

Script automatizado para instalação e configuração de ambiente Docker com Traefik (proxy reverso) e Portainer (gerenciamento) em Ubuntu 22.04/24.04.

⚡ Instalação Rápida
bash <(curl -sSL https://raw.githubusercontent.com/alexconectado/instalador-base/main/install-docker-stack.sh)

Ou manual:

wget https://raw.githubusercontent.com/alexconectado/instalador-base/main/install-docker-stack.sh
chmod +x install-docker-stack.sh
sudo ./install-docker-stack.sh
✨ Funcionalidades
✅ Instalação completa do Docker CE (repositório oficial)
✅ Docker Swarm configurado automaticamente
✅ Traefik v3 com SSL automático (Let's Encrypt)
✅ Portainer 2.21 para gerenciamento visual
✅ Firewall UFW configurado automaticamente
✅ Redirecionamento HTTP → HTTPS
✅ Fail2Ban para proteção básica SSH
✅ Health checks e restart policies
✅ Opção de desinstalação completa
📋 Pré-requisitos
Ubuntu 22.04 ou 24.04 LTS
Acesso root ou sudo
Domínio apontando para o IP da VPS
Portas abertas: 22, 80, 443
🛠️ O que será instalado
Serviço	Versão	Função
Docker CE	Latest	Container runtime
Traefik	v3	Proxy reverso + SSL
Portainer	2.21	Gerenciamento web
UFW	Latest	Firewall
Fail2Ban	Latest	Proteção contra brute
📖 Como usar
1. Instalação
sudo ./install-docker-stack.sh

O script irá solicitar:

Nome do servidor
Domínio do Portainer (ex: panel.seusite.com)
E-mail para Let's Encrypt
Configuração de cluster (opcional)
2. Desinstalação
sudo ./install-docker-stack.sh

Escolha a opção 2 no menu.

🌐 Acesso após instalação
Portainer:
👉 https://seu-dominio.com
Traefik Dashboard:
❌ Desativado por padrão (segurança)
📊 Comandos úteis
# Listar serviços
docker service ls

# Ver logs
docker service logs -f portainer_portainer

# Listar stacks
docker stack ls

# Remover stack
docker stack rm portainer

# Status do Swarm
docker node ls
🔒 Segurança
Firewall UFW ativo
SSL automático com Let's Encrypt
Docker socket restrito
Fail2Ban ativo
Traefik Dashboard desabilitado por padrão
🧰 Troubleshooting
❌ Serviços não sobem
docker service logs traefik_traefik
docker service logs portainer_portainer
docker service ps traefik_traefik --no-trunc
❌ SSL não funciona
Verifique o DNS do domínio
Aguarde propagação
Ver logs:
docker service logs traefik_traefik
❌ Portainer não acessível
docker service ps portainer_portainer
docker service update --force portainer_portainer
📁 Arquivos gerados
/var/log/vps-bootstrap.log
/opt/stacks/traefik-stack.yml
/opt/stacks/portainer-stack.yml
🔄 Atualização

Para atualizar versões:

nano /opt/stacks/traefik-stack.yml
docker stack deploy -c /opt/stacks/traefik-stack.yml traefik
💡 Próximos passos
Criar conta no Portainer
Subir suas stacks
Configurar aplicações
📞 Suporte

Logs:

docker service logs <service>
Issues no GitHub
📄 Licença

MIT License — livre para uso pessoal e comercial

👨‍💻 Autor

Alex Conectado
https://github.com/alexconectado/instalador-base
