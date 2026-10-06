-- =====================================================================
--  ATUALIZAÇÃO 06 — aparência da loja editável pelo painel
--  (logo, nome, textos do topo e do rodapé, WhatsApp e cores)
--  Rode UMA vez: Supabase > SQL Editor > New query > cole TUDO > Run
--  (precisa da atualização 03; não apaga nenhum dado)
-- =====================================================================

alter table configuracoes add column if not exists nome_loja        text;
alter table configuracoes add column if not exists logo_url         text;
alter table configuracoes add column if not exists titulo_inicio    text;
alter table configuracoes add column if not exists subtitulo_inicio text;
alter table configuracoes add column if not exists texto_rodape     text;
alter table configuracoes add column if not exists whatsapp         text;
alter table configuracoes add column if not exists cor_principal    text;
alter table configuracoes add column if not exists cor_destaque     text;

-- Valida os campos (evita cor ou WhatsApp em formato errado)
alter table configuracoes drop constraint if exists configuracoes_cores_check;
alter table configuracoes add constraint configuracoes_cores_check check (
  (cor_principal is null or cor_principal ~* '^#[0-9a-f]{6}$') and
  (cor_destaque  is null or cor_destaque  ~* '^#[0-9a-f]{6}$') and
  (whatsapp      is null or whatsapp ~ '^[0-9]{10,15}$'));

-- O admin já pode alterar a tabela configuracoes (política "config_admin")
-- e enviar imagens para o armazenamento "produtos" (o logo fica em produtos/loja/).
