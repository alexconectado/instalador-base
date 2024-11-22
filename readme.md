Server Installer Script
Descrição: Este script automatiza a configuração inicial de servidores com base no Ubuntu 22.04. Ele instala e configura o Portainer, Traefik, e solicita informações do usuário para personalização, como nome do servidor, domínio do Portainer e e-mail para o Let's Encrypt.

Recursos:

Configurações iniciais do servidor, como atualização de pacotes.
Instalação e configuração do Docker e Docker Compose.
Configuração do Traefik como proxy reverso com suporte a HTTPS via Let's Encrypt.
Configuração do Portainer para gerenciar contêineres Docker.
Suporte para entrada de dados do usuário para personalização:
Nome do servidor.
Domínio para o Portainer.
E-mail para certificados HTTPS.
Pré-requisitos:

Servidor rodando Ubuntu 22.04.
Acesso root ou usuário com permissões de sudo.
Um domínio configurado e apontando para o IP do servidor.
Instruções de Uso:

Baixe o script:
bash
Copiar código
git clone https://github.com/seu-usuario/server-installer.git
cd server-installer
Torne o script executável:
bash
Copiar código
chmod +x server-installer.sh
Execute o script:
bash
Copiar código
sudo ./server-installer.sh
Durante a execução, o script solicitará:
Nome do servidor.
Domínio do Portainer (ex.: painel.seudominio.com.br).
E-mail para certificados HTTPS.
Acessando o Portainer:

Após a instalação, acesse o Portainer no domínio configurado:
bash
Copiar código
https://seu-dominio.com
Estrutura de Stacks:

Traefik:
Configuração para gerenciar certificados SSL com Let's Encrypt.
Proxy reverso com suporte para HTTP e HTTPS.
Portainer:
Gerenciamento centralizado de contêineres Docker.
Acesso seguro com autenticação.
Notas:

Certifique-se de que o domínio fornecido esteja apontando corretamente para o servidor.
Se houver problemas com certificados SSL, verifique os logs do Traefik:
bash
Copiar código
docker logs traefik
Exemplo de Configuração:

Entrada no Script:
vbnet
Copiar código
Digite o nome do servidor: meu-servidor
Digite o domínio do Portainer: painel.meudominio.com.br
Digite um e-mail para o Let's Encrypt: admin@meudominio.com
Resultado:
O Traefik estará configurado para gerenciar o domínio painel.meudominio.com.br.
O Portainer estará acessível em:
arduino
Copiar código
https://painel.meudominio.com.br
Contribuições:

Sinta-se à vontade para abrir uma issue ou enviar um pull request se tiver ideias ou melhorias.
Licença:

Este projeto está licenciado sob a MIT License.
