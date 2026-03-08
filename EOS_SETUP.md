# Epic Online Services (EOS) Setup Guide

Este guia explica como configurar o EOS para multiplayer online no Easter Egg Horror.

## Passo 1: Criar Conta no Epic Developer Portal

1. Acesse: https://dev.epicgames.com/portal
2. Crie uma conta ou faça login
3. Aceite os termos de serviço

## Passo 2: Criar um Produto

1. No portal, clique em **"Create Product"**
2. Preencha o nome do jogo: `Easter Egg Horror`
3. Selecione a organização

## Passo 3: Configurar o Produto

### 3.1 Product Settings
1. Vá em **Product Settings**
2. Copie os seguintes valores:
   - **Product ID**
   - **Sandbox ID** (use o sandbox de Dev para testes)
   - **Deployment ID**

### 3.2 Criar Client
1. Vá em **Product Settings > Clients**
2. Clique em **"Add New Client"**
3. Selecione **"GameClient"** como tipo
4. Copie:
   - **Client ID**
   - **Client Secret**

### 3.3 Configurar Client Policy
1. Vá em **Product Settings > Clients > [Seu Client] > Client Policy**
2. Selecione **"Custom policy"**
3. Marque **"User is required"**
4. Habilite as features:
   - ✅ Lobbies
   - ✅ P2P
   - ✅ Presence
   - ✅ Auth (deixe Connect desmarcado)

### 3.4 Configurar Permissions
1. Vá em **Epic Account Services > Permissions**
2. Habilite:
   - ✅ Basic Profile
   - ✅ Online Presence
   - ✅ Friends

## Passo 4: Instalar o Plugin EOSG no Godot

1. No Godot, vá em **AssetLib**
2. Pesquise por **"EOSG"**
3. Instale o plugin **"Epic Online Services Godot (EOSG)"** por 3ddelano
4. Vá em **Project > Project Settings > Plugins**
5. Habilite o plugin **"Epic Online Services Godot 4.2+ (EOSG)"**
6. Reinicie o Godot

## Passo 5: Configurar Credenciais no Projeto

Edite o arquivo `scripts/eos_config.gd` e preencha suas credenciais:

```gdscript
const PRODUCT_ID := "sua_product_id_aqui"
const SANDBOX_ID := "sua_sandbox_id_aqui"
const DEPLOYMENT_ID := "sua_deployment_id_aqui"
const CLIENT_ID := "sua_client_id_aqui"
const CLIENT_SECRET := "sua_client_secret_aqui"
```

## Passo 6: Testar

1. Execute o jogo
2. O botão **"Online (Internet)"** deve estar habilitado
3. Clique em **"Host Game"** para criar uma sala
4. Um código de 6 caracteres será gerado
5. Outro jogador pode clicar em **"Online"** > digitar o código > **"Join Game"**

## Troubleshooting

### "EOS not configured"
- Verifique se preencheu todas as credenciais em `eos_config.gd`
- Verifique se o plugin EOSG está instalado e habilitado

### "Connection failed"
- Verifique sua conexão com a internet
- Verifique se as credenciais estão corretas
- Verifique se o Client Policy está configurado corretamente

### Lobby não encontrado
- O código expira se o host sair
- Verifique se digitou o código corretamente (6 caracteres)

## Links Úteis

- [Epic Developer Portal](https://dev.epicgames.com/portal)
- [EOSG Plugin GitHub](https://github.com/3ddelano/epic-online-services-godot)
- [EOSG Documentation](https://3ddelano.github.io/epic-online-services-godot/)
- [EOS Documentation](https://dev.epicgames.com/docs/epic-online-services)
