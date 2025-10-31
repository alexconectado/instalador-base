# 🐳 Instalador Base - Docker + Traefik + Portainer

Script automatizado para instalação e configuração de ambiente Docker com Traefik (proxy reverso) e Portainer (gerenciamento) em Ubuntu 22.04/24.04.

## 🚀 Instalação Rápida

```bash
# Baixar o script
wget https://raw.githubusercontent.com/alexconectado/instalador-base/main/install-docker-stack.sh

# Dar permissão de execução
chmod +x install-docker-stack.sh

# Executar como root
sudo ./install-docker-stack.sh
```

## ✨ Funcionalidades

- ✅ Instalação completa do Docker CE (versão oficial)
- ✅ Docker Swarm configurado automaticamente
- ✅ Traefik v3.0 com SSL automático (Let's Encrypt)
- ✅ Portainer 2.21.0 para gerenciamento visual
- ✅ Firewall UFW configurado
- ✅ Redirecionamento HTTP → HTTPS automático
- ✅ Health checks e restart policies
- ✅ Opção de desinstalação completa

## 📋 Pré-requisitos

- Ubuntu 22.04 ou 24.04 LTS
- Acesso root ou sudo
- Domínio apontando para o IP do servidor
- Portas 80, 443, 22 abertas

## 🛠️ O que será instalado

| Serviço | Versão | Função |
|---------|--------|--------|
| Docker CE | Latest | Container runtime |
| Traefik | v3.0 | Proxy reverso + SSL |
| Portainer | 2.21.0 | Gerenciamento web |
| UFW | Latest | Firewall |

## 📖 Como usar

### 1. Instalação

```bash
sudo ./install-docker-stack.sh
```

O script irá solicitar:
- Nome do servidor
- Domínio para o Portainer (ex: `painel.seusite.com`)
- E-mail para Let's Encrypt

### 2. Desinstalação

```bash
sudo ./install-docker-stack.sh
# Escolha opção 2
```

## 🌐 Acesso após instalação

- **Portainer**: `https://seu-dominio.com`
- **Traefik Dashboard**: `http://localhost:8080` (apenas local)

## 📊 Comandos Úteis

```bash
# Listar serviços
docker service ls

# Ver logs de um serviço
docker service logs -f portainer_portainer

# Listar stacks
docker stack ls

# Remover uma stack
docker stack rm portainer

# Status do Swarm
docker node ls
```

## 🔒 Segurança

- Firewall UFW configurado automaticamente
- SSL/TLS via Let's Encrypt
- Docker socket protegido
- Traefik dashboard apenas local

## 🐛 Troubleshooting

### Serviços não sobem

```bash
# Verificar logs
docker service logs traefik_traefik
docker service logs portainer_portainer

# Verificar status
docker service ps traefik_traefik --no-trunc
```

### SSL não funciona

- Verifique se o domínio aponta para o IP correto
- Aguarde alguns minutos para propagação DNS
- Veja logs do Traefik: `docker service logs traefik_traefik`

### Portainer não acessível

```bash
# Verificar se está rodando
docker service ps portainer_portainer

# Recriar serviço
docker service update --force portainer_portainer
```

## 📁 Arquivos gerados

- `/var/log/websolucoesmkt-installer.log` - Log de instalação
- `traefik-stack.yml` - Configuração do Traefik
- `portainer-stack.yml` - Configuração do Portainer

## 🔄 Atualização

Para atualizar versões:

```bash
# Editar os arquivos *-stack.yml
nano traefik-stack.yml

# Redeployar
docker stack deploy -c traefik-stack.yml traefik
```

## 💡 Próximos passos

Após instalação bem-sucedida:

1. Acesse o Portainer e crie sua conta admin
2. Configure seus containers/stacks
3. Adicione suas aplicações

## 📞 Suporte

Em caso de problemas:
- Verifique os logs: `docker service logs <service_name>`
- Consulte a documentação oficial do Docker
- Issues no GitHub

## 📄 Licença

MIT License - Livre para uso comercial e pessoal

---

**Desenvolvido por**: Alex Conectado  
**Repositório**: github.com/alexconectado/instalador-base
