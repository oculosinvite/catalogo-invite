-- =====================================================================
--  ATUALIZAÇÃO 05 — situações de pedido configuráveis + aviso por e-mail
--  Rode UMA vez: Supabase > SQL Editor > New query > cole TUDO > Run
--  (precisa das atualizações 02, 03 e 04; não apaga nenhum dado)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. SITUAÇÕES DO PEDIDO (você cadastra os nomes; cada uma pode
--    disparar uma ação do sistema que mexe no estoque com segurança)
-- ---------------------------------------------------------------------
create table if not exists situacoes_pedido (
  id              bigint generated always as identity primary key,
  nome            text not null unique,
  cor             text not null default '#1f5168',
  acao            text not null default 'nenhuma'
                  check (acao in ('nenhuma','aprovar','recusar','enviar','entregar','cancelar')),
  visivel_cliente boolean not null default true,
  inicial         boolean not null default false,
  ordem           int not null default 0,
  ativo           boolean not null default true,
  criado_em       timestamptz not null default now()
);
create unique index if not exists situacoes_uma_inicial on situacoes_pedido ((true)) where inicial;
alter table situacoes_pedido enable row level security;
drop policy if exists "situacoes_leitura" on situacoes_pedido;
drop policy if exists "situacoes_admin"   on situacoes_pedido;
create policy "situacoes_leitura" on situacoes_pedido for select using (true);
create policy "situacoes_admin"   on situacoes_pedido for all using (is_admin()) with check (is_admin());
grant select on situacoes_pedido to anon, authenticated;
grant insert, update, delete on situacoes_pedido to authenticated;

insert into situacoes_pedido (nome, cor, acao, visivel_cliente, inicial, ordem)
select v.* from (values
  ('Novo pedido',          '#b7791f', 'nenhuma',  true,  true,  1),
  ('Aguardando pagamento', '#b7791f', 'nenhuma',  true,  false, 2),
  ('Aprovado',             '#1f5168', 'aprovar',  true,  false, 3),
  ('Recebido a enviar',    '#1f5168', 'aprovar',  true,  false, 4),
  ('Em separação',         '#1f5168', 'aprovar',  true,  false, 5),
  ('Recebido enviado',     '#22578f', 'enviar',   true,  false, 6),
  ('Entregue',             '#2f7d4f', 'entregar', true,  false, 7),
  ('Recusado',             '#b83a3a', 'recusar',  true,  false, 8),
  ('Cancelado',            '#b83a3a', 'cancelar', true,  false, 9)
) as v(nome, cor, acao, visivel_cliente, inicial, ordem)
where not exists (select 1 from situacoes_pedido);   -- só na primeira vez

alter table pedidos add column if not exists situacao_id bigint references situacoes_pedido(id) on delete set null;

-- pedidos antigos recebem a situação equivalente
update pedidos p set situacao_id = s.id
  from situacoes_pedido s
 where p.situacao_id is null
   and s.nome = case p.status when 'pendente' then 'Novo pedido' when 'aprovado' then 'Aprovado'
                              when 'enviado' then 'Recebido enviado' when 'entregue' then 'Entregue'
                              when 'recusado' then 'Recusado' when 'cancelado' then 'Cancelado' end;

-- Histórico de cada pedido
create table if not exists pedidos_historico (
  id         bigint generated always as identity primary key,
  pedido_id  bigint not null references pedidos(id) on delete cascade,
  situacao   text,
  status     text,
  observacao text,
  criado_por uuid default auth.uid(),
  criado_em  timestamptz not null default now()
);
create index if not exists pedidos_historico_pedido on pedidos_historico (pedido_id, criado_em);
alter table pedidos_historico enable row level security;
drop policy if exists "historico_admin" on pedidos_historico;
create policy "historico_admin" on pedidos_historico for select using (is_admin());

-- Situação automática: pedido novo recebe a "inicial"; quando o status do
-- sistema muda (ex.: botão Aprovar), recebe a 1ª situação com a ação correspondente
create or replace function pedidos_situacao_auto() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_desejada bigint := nullif(current_setting('app.situacao_desejada', true), '')::bigint;
  v_acao text;
begin
  if tg_op = 'INSERT' then
    if new.situacao_id is null then
      select id into new.situacao_id from situacoes_pedido where inicial and ativo limit 1;
    end if;
    return new;
  end if;
  if new.status is distinct from old.status then
    if v_desejada is not null then
      new.situacao_id := v_desejada;
    else
      v_acao := case new.status when 'aprovado' then 'aprovar' when 'enviado' then 'enviar' when 'entregue' then 'entregar'
                                when 'recusado' then 'recusar' when 'cancelado' then 'cancelar' end;
      if v_acao is not null and not exists (select 1 from situacoes_pedido where id = new.situacao_id and acao = v_acao) then
        select id into new.situacao_id from situacoes_pedido where acao = v_acao and ativo order by ordem, id limit 1;
      end if;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_pedidos_situacao on pedidos;
create trigger trg_pedidos_situacao before insert or update on pedidos
  for each row execute function pedidos_situacao_auto();

create or replace function pedidos_registrar_historico() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_sit text := (select nome from situacoes_pedido where id = new.situacao_id);
begin
  if tg_op = 'INSERT' or new.situacao_id is distinct from old.situacao_id or new.status is distinct from old.status then
    -- vários passos na mesma ação (ex.: aprovar + enviar) viram uma linha só
    if tg_op = 'UPDATE' then
      update pedidos_historico set status = new.status
       where pedido_id = new.id and criado_em = now() and situacao is not distinct from v_sit;
      if found then return null; end if;
    end if;
    insert into pedidos_historico (pedido_id, situacao, status, observacao)
    values (new.id, v_sit, new.status,
            case when tg_op = 'INSERT' then case new.origem when 'painel' then 'Criado no painel' else 'Recebido pela loja' end
                 else nullif(current_setting('app.obs_situacao', true), '') end);
  end if;
  return null;
end $$;
drop trigger if exists trg_pedidos_historico on pedidos;
create trigger trg_pedidos_historico after insert or update on pedidos
  for each row execute function pedidos_registrar_historico();

-- Mudar a situação de um pedido (executa a ação do sistema quando houver)
create or replace function admin_definir_situacao(p_pedido_id bigint, p_situacao_id bigint,
                                                  p_observacao text default null, p_rastreio text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  s situacoes_pedido%rowtype;
  v_status text;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;
  select * into s from situacoes_pedido where id = p_situacao_id;
  if not found then raise exception 'Situação não encontrada'; end if;
  select status into v_status from pedidos where id = p_pedido_id for update;
  if not found then raise exception 'Pedido não encontrado'; end if;

  perform set_config('app.situacao_desejada', s.id::text, true);
  perform set_config('app.obs_situacao', coalesce(p_observacao, ''), true);

  if s.acao in ('aprovar','enviar','entregar') and v_status in ('recusado','cancelado') then
    raise exception 'O pedido está %; não pode ir para "%"', v_status, s.nome;
  end if;

  case s.acao
    when 'aprovar' then
      if v_status = 'pendente' then perform aprovar_pedido(p_pedido_id); end if;
    when 'enviar' then
      if v_status = 'pendente' then perform aprovar_pedido(p_pedido_id); v_status := 'aprovado'; end if;
      if v_status = 'aprovado' then perform atualizar_status_pedido(p_pedido_id, 'enviado', p_rastreio);
      elsif nullif(trim(p_rastreio), '') is not null then
        update pedidos set codigo_rastreio = trim(p_rastreio) where id = p_pedido_id;
      end if;
    when 'entregar' then
      if v_status = 'pendente' then perform aprovar_pedido(p_pedido_id); v_status := 'aprovado'; end if;
      if v_status in ('aprovado','enviado') then perform atualizar_status_pedido(p_pedido_id, 'entregue', p_rastreio); end if;
    when 'recusar' then
      if v_status = 'pendente' then perform recusar_pedido(p_pedido_id, p_observacao);
      elsif v_status <> 'recusado' then
        raise exception 'Só pedidos novos podem ser recusados. Para este pedido use uma situação de cancelamento.';
      end if;
    when 'cancelar' then
      if v_status not in ('cancelado','recusado') then perform cancelar_pedido(p_pedido_id, p_observacao); end if;
    else null;
  end case;

  update pedidos set situacao_id = s.id where id = p_pedido_id;
  perform set_config('app.situacao_desejada', '', true);
end $$;

-- ---------------------------------------------------------------------
-- 2. AVISO POR E-MAIL A CADA NOVO PEDIDO
--    Envio pelo próprio Supabase (extensão pg_net) via Brevo ou Resend.
--    A chave da API fica numa tabela que ninguém lê pela internet.
-- ---------------------------------------------------------------------
create extension if not exists pg_net with schema extensions;

create table if not exists config_privada (
  id                   int primary key default 1 check (id = 1),
  emails_pedidos       text[] not null default '{}',
  notificar_painel     boolean not null default false,
  email_provedor       text not null default 'brevo' check (email_provedor in ('brevo','resend')),
  email_remetente      text,
  email_remetente_nome text,
  email_api_key        text,
  url_site             text,
  atualizado_em        timestamptz not null default now()
);
insert into config_privada (id) values (1) on conflict (id) do nothing;
alter table config_privada enable row level security;   -- sem políticas: só funções internas acessam
revoke all on config_privada from anon, authenticated;

create or replace function admin_obter_notificacoes() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c config_privada%rowtype;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;
  select * into c from config_privada where id = 1;
  return jsonb_build_object('emails_pedidos', c.emails_pedidos, 'notificar_painel', c.notificar_painel,
    'email_provedor', c.email_provedor, 'email_remetente', c.email_remetente,
    'email_remetente_nome', c.email_remetente_nome, 'url_site', c.url_site,
    'tem_chave', c.email_api_key is not null and c.email_api_key <> '',
    'final_chave', right(c.email_api_key, 4));
end $$;

create or replace function admin_salvar_notificacoes(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_emails text[]; v_e text;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;
  select coalesce(array_agg(distinct lower(trim(e))) filter (where trim(e) <> ''), '{}')
    into v_emails
    from jsonb_array_elements_text(coalesce(p->'emails_pedidos', '[]'::jsonb)) e;
  foreach v_e in array v_emails loop
    if v_e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'E-mail inválido: %', v_e; end if;
  end loop;
  if nullif(trim(p->>'email_remetente'), '') is not null and trim(p->>'email_remetente') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'E-mail do remetente inválido';
  end if;
  update config_privada set
    emails_pedidos       = v_emails,
    notificar_painel     = coalesce((p->>'notificar_painel')::boolean, notificar_painel),
    email_provedor       = coalesce(nullif(p->>'email_provedor', ''), email_provedor),
    email_remetente      = nullif(trim(p->>'email_remetente'), ''),
    email_remetente_nome = nullif(trim(p->>'email_remetente_nome'), ''),
    url_site             = coalesce(nullif(trim(p->>'url_site'), ''), url_site),
    email_api_key        = case when nullif(trim(p->>'email_api_key'), '') is not null then trim(p->>'email_api_key')
                                when (p->>'apagar_chave')::boolean then null else email_api_key end,
    atualizado_em        = now()
  where id = 1;
end $$;

create or replace function html_esc(t text) returns text
language sql immutable as $$
  select replace(replace(replace(replace(coalesce(t, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;')
$$;
create or replace function brl(v numeric) returns text
language sql immutable as $$
  select 'R$ ' || translate(to_char(coalesce(v, 0), 'FM999,999,990.00'), ',.', '.,')
$$;

-- Envia um e-mail (fica na fila e sai quando a transação termina)
create or replace function enviar_email(p_para text[], p_assunto text, p_html text) returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare c config_privada%rowtype; v_id bigint;
begin
  select * into c from config_privada where id = 1;
  if c.email_api_key is null or c.email_api_key = '' then raise exception 'Informe a chave da API de e-mail'; end if;
  if c.email_remetente is null then raise exception 'Informe o e-mail do remetente'; end if;
  if p_para is null or cardinality(p_para) = 0 then raise exception 'Nenhum e-mail de destino cadastrado'; end if;

  if c.email_provedor = 'resend' then
    select net.http_post(
      url := 'https://api.resend.com/emails',
      headers := jsonb_build_object('Authorization', 'Bearer ' || c.email_api_key, 'Content-Type', 'application/json'),
      body := jsonb_build_object('from', coalesce(c.email_remetente_nome, 'Loja') || ' <' || c.email_remetente || '>',
                                 'to', to_jsonb(p_para), 'subject', p_assunto, 'html', p_html),
      timeout_milliseconds := 10000) into v_id;
  else
    select net.http_post(
      url := 'https://api.brevo.com/v3/smtp/email',
      headers := jsonb_build_object('api-key', c.email_api_key, 'Content-Type', 'application/json', 'accept', 'application/json'),
      body := jsonb_build_object('sender', jsonb_build_object('email', c.email_remetente, 'name', coalesce(c.email_remetente_nome, 'Loja')),
                                 'to', (select jsonb_agg(jsonb_build_object('email', e)) from unnest(p_para) e),
                                 'subject', p_assunto, 'htmlContent', p_html),
      timeout_milliseconds := 10000) into v_id;
  end if;
  return v_id;
end $$;
revoke execute on function enviar_email(text[], text, text) from public, anon, authenticated;

-- Monta e envia o aviso de um pedido
create or replace function notificar_novo_pedido(p_pedido_id bigint) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  c config_privada%rowtype; p pedidos%rowtype; cli clientes%rowtype; v_itens text; v_html text; v_end jsonb;
begin
  select * into c from config_privada where id = 1;
  if c.email_api_key is null or c.email_remetente is null or cardinality(c.emails_pedidos) = 0 then return null; end if;
  select * into p from pedidos where id = p_pedido_id;
  if not found or (p.origem = 'painel' and not c.notificar_painel) then return null; end if;
  select * into cli from clientes where id = p.cliente_id;
  v_end := coalesce(p.endereco_entrega, '{}'::jsonb);

  select string_agg(format('<tr><td style="padding:6px 8px;border-bottom:1px solid #eee">%s</td><td style="padding:6px 8px;border-bottom:1px solid #eee;text-align:center">%s</td><td style="padding:6px 8px;border-bottom:1px solid #eee;text-align:right">%s</td></tr>',
                           html_esc(descricao), quantidade, brl(preco_unitario * quantidade)), '' order by id)
    into v_itens from itens_pedido where pedido_id = p_pedido_id;

  v_html := format($h$
<div style="font-family:Arial,sans-serif;max-width:620px;color:#14303d">
  <h2 style="margin:0 0 4px">Novo pedido #%s</h2>
  <p style="margin:0 0 16px;color:#77716a">%s · %s</p>
  <h3 style="margin:16px 0 6px">Cliente</h3>
  <p style="margin:0">%s<br>%s%s</p>
  <p style="margin:6px 0 0;color:#555">%s</p>
  <h3 style="margin:16px 0 6px">Itens</h3>
  <table style="border-collapse:collapse;width:100%%;font-size:14px">%s</table>
  <p style="font-size:16px;margin:12px 0 4px"><b>Total: %s</b></p>
  <p style="margin:0;color:#555">Pagamento: %s%s</p>
  %s
  %s
</div>$h$,
    p.id, to_char(p.criado_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
    case p.origem when 'painel' then 'criado no painel' else 'recebido pela loja' end,
    html_esc(cli.nome), html_esc(coalesce(cli.telefone, '')),
    case when cli.email is not null then ' · ' || html_esc(cli.email) else '' end,
    html_esc(concat_ws(' - ', nullif(concat_ws(', ', v_end->>'endereco', v_end->>'numero'), ''), v_end->>'complemento',
             nullif(concat_ws(', ', v_end->>'bairro', nullif(concat_ws('/', v_end->>'cidade', v_end->>'uf'), '')), ''),
             case when v_end->>'cep' is not null then 'CEP ' || (v_end->>'cep') end)),
    coalesce(v_itens, ''), brl(p.valor_total),
    html_esc(coalesce(p.forma_pagamento, 'não informado')),
    case when p.parcelas > 1 then format(' em %sx de %s', p.parcelas, brl(p.valor_parcela)) else '' end,
    case when p.observacao is not null then '<p style="margin:8px 0 0"><b>Observação:</b> ' || html_esc(p.observacao) || '</p>' else '' end,
    case when c.url_site is not null then format('<p style="margin:20px 0 0"><a href="%s/admin.html" style="background:#1f5168;color:#fff;padding:10px 18px;border-radius:20px;text-decoration:none">Abrir o painel</a></p>', html_esc(c.url_site)) else '' end);

  return enviar_email(c.emails_pedidos, format('Novo pedido #%s — %s — %s', p.id, cli.nome, brl(p.valor_total)), v_html);
exception when others then
  raise warning 'Aviso de pedido % não enviado: %', p_pedido_id, sqlerrm;   -- nunca impede o pedido
  return null;
end $$;
revoke execute on function notificar_novo_pedido(bigint) from public, anon, authenticated;

-- Dispara no FIM da transação (quando os itens e o total já estão gravados)
create or replace function trg_notificar_pedido() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform notificar_novo_pedido(new.id);
  return null;
end $$;
drop trigger if exists trg_pedido_email on pedidos;
create constraint trigger trg_pedido_email after insert on pedidos
  deferrable initially deferred for each row execute function trg_notificar_pedido();

-- Teste pelo painel
create or replace function admin_testar_email() returns bigint
language plpgsql security definer set search_path = public as $$
declare c config_privada%rowtype;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;
  select * into c from config_privada where id = 1;
  return enviar_email(c.emails_pedidos, 'Teste de aviso de pedidos',
    '<div style="font-family:Arial,sans-serif"><h2>Tudo certo!</h2><p>Este é um e-mail de teste do painel da loja. '
    || 'Os avisos de novos pedidos chegarão neste endereço.</p></div>');
end $$;

create or replace function admin_status_email(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare r record;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;
  select status_code, content, error_msg, timed_out into r from net._http_response where id = p_id;
  if not found then return jsonb_build_object('pendente', true); end if;
  return jsonb_build_object('pendente', false, 'status', r.status_code, 'ok', r.status_code between 200 and 299,
                            'erro', coalesce(r.error_msg, case when r.timed_out then 'tempo esgotado' end, left(r.content, 400)));
end $$;
