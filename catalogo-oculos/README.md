# Catálogo de Óculos — Supabase + GitHub + Vercel

Loja virtual em formato de catálogo: o cliente escolhe modelo e cor, coloca no carrinho e envia o pedido. A loja aprova ou recusa no painel e, ao aprovar, o estoque é baixado automaticamente.

## O que tem

**Loja (`index.html`)**
- Catálogo com foto, descrição, preço (com promoção e parcelamento) e bolinhas de cor
- Filtro por categoria, gênero, formato, polarizado, busca e ordenação
- Página do produto: troca a foto ao escolher a cor, mostra estoque da cor, medidas (lente□ponte haste), materiais etc.
- Carrinho (fica salvo no navegador), forma de pagamento e observação
- Cadastro do cliente com preenchimento automático pelo CEP
- "Minha conta": acompanhar pedidos, cancelar pedido pendente, editar dados, recuperar senha
- Botão para avisar a loja pelo WhatsApp após o pedido

**Painel (`admin.html`)**
- Resumo: pedidos aguardando, faturamento, lucro e margem do mês, valor do estoque, estoque baixo, mais vendidos
- Pedidos: aprovar (baixa o estoque), recusar com motivo, marcar enviado (com rastreio) / entregue, cancelar (devolve o estoque). Mostra custo, venda e margem de cada item
- Produtos: cadastro completo com preço de custo, venda, promocional, margem calculada na hora, fotos e cores (cada cor com SKU, foto e estoque próprios)
- Estoque: entradas e saídas manuais com histórico de todas as movimentações
- Categorias, marcas e clientes (com bloqueio)

**Segurança**
- O cliente nunca enxerga o preço de custo (a loja lê de uma "view" sem esse campo)
- O preço do pedido é recalculado no servidor — ninguém altera preço pelo navegador
- Só administradores aprovam pedidos, mexem em produtos e estoque (regras RLS no banco)

---

## Passo a passo

### 1. Banco de dados (Supabase)
1. Abra seu projeto no [supabase.com](https://supabase.com) → menu **SQL Editor** → **New query**.
2. Abra o arquivo `supabase/schema.sql`, copie **tudo**, cole e clique em **Run**.
   - ⚠️ Ele apaga as tabelas que você criou antes e recria tudo melhorado. Já vem com 5 categorias e 3 óculos de exemplo.
3. Vá em **Project Settings → API Keys** (ou **Data API**) e copie:
   - **Project URL** (ex.: `https://abcd1234.supabase.co`)
   - A chave **publishable** (`sb_publishable_...`) ou a **anon public** (legacy). **Nunca** use a `service_role`/`secret`.

### 2. Configurar o site
1. Abra `js/config.js` num editor de texto (Bloco de Notas serve).
2. Cole a URL e a chave nos campos `SUPABASE_URL` e `SUPABASE_KEY`.
3. Troque `nomeLoja`, `whatsapp` (só números com 55 + DDD), parcelas e formas de pagamento.

### 3. Subir para o GitHub
1. No GitHub, clique em **New repository** → nome `catalogo-oculos` → **Create repository**.
2. Na página do repositório, clique em **uploading an existing file**.
3. Arraste **o conteúdo** da pasta `catalogo-oculos` (os arquivos `index.html`, `admin.html` e as pastas `css`, `js`, `supabase`) → **Commit changes**.

### 4. Publicar na Vercel
1. Na Vercel: **Add New… → Project** → importe o repositório `catalogo-oculos`.
2. Em **Framework Preset**, escolha **Other**. Não precisa mudar mais nada → **Deploy**.
3. Em ~1 minuto você recebe o endereço, ex.: `https://catalogo-oculos.vercel.app`.
   - Toda vez que você alterar um arquivo no GitHub, a Vercel publica sozinha.

### 5. Ligar o login ao seu site (Supabase)
1. **Authentication → URL Configuration**:
   - **Site URL**: o endereço da Vercel
   - **Redirect URLs**: adicione `https://SEU-SITE.vercel.app/**`
2. **Authentication → Sign In / Providers → Email**: deixe **Confirm email** ligado (mais seguro) ou desligue para o cliente entrar na hora.
   - O e-mail grátis do Supabase envia poucas mensagens por hora. Para produção, configure um SMTP próprio em **Authentication → Emails → SMTP Settings**.

### 6. Criar o seu acesso de administrador
1. Abra o seu site e clique em **Entrar → Criar conta** (cadastre-se como se fosse cliente).
2. No Supabase, **SQL Editor**, rode trocando o e-mail:
   ```sql
   insert into admins (user_id)
   select id from auth.users where email = 'SEU-EMAIL@exemplo.com';
   ```
3. Acesse `https://SEU-SITE.vercel.app/admin.html` e entre com essa conta.

### 7. Começar a usar
1. **Categorias e marcas**: ajuste as categorias e cadastre suas marcas.
2. **Produtos**: apague/desative os exemplos e cadastre os seus (fotos em JPG/PNG/WebP, de preferência na proporção 4:3, até ~500 KB).
3. Faça um pedido de teste na loja com outra conta → aprove no painel → veja o estoque baixar na aba **Estoque**.

---

## Como funciona o fluxo do pedido

```
Cliente envia  →  PENDENTE ──aprovar──→ APROVADO ──→ ENVIADO ──→ ENTREGUE
                     │        (baixa estoque)  │           │
                     └─recusar→ RECUSADO        └──cancelar─┴→ CANCELADO (devolve estoque)
```

- Ao enviar, o sistema confere se há estoque, mas **só reserva/baixa na aprovação**.
- Se dois pedidos disputarem a última peça, o segundo não consegue ser aprovado (aparece a mensagem de estoque insuficiente).

## Estrutura dos arquivos

```
index.html          loja
admin.html          painel administrativo
css/style.css       visual (cores no topo do arquivo, em :root)
js/config.js        ⚙️ suas chaves e dados da loja
js/loja.js          lógica da loja
js/admin.js         lógica do painel
supabase/schema.sql banco de dados completo
```

## Dúvidas comuns

- **"Não foi possível carregar o catálogo"** → confira a URL e a chave em `js/config.js`.
- **"Esta conta não tem acesso ao painel"** → faltou o passo 6.2 (ou o e-mail está diferente).
- **Cliente não recebe o e-mail de confirmação** → limite do e-mail grátis do Supabase; configure SMTP ou desligue "Confirm email".
- **Mudar cores do site** → edite as variáveis no começo de `css/style.css` (`--accent` é a cor principal).
- **O Supabase avisa "Security Definer View" em `vw_catalogo`** → é proposital: é o que permite mostrar o catálogo sem expor o preço de custo.

## Próximos passos sugeridos
- Pagamento online (Mercado Pago / Pix automático) e cálculo de frete (Melhor Envio)
- E-mail ou WhatsApp automático quando o pedido for aprovado
- Domínio próprio (Vercel → Settings → Domains)
