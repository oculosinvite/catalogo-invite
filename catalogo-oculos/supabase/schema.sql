-- =====================================================================
--  CATÁLOGO DE ÓCULOS — Banco de dados (Supabase / PostgreSQL)
--
--  Como usar: Supabase > SQL Editor > New query > cole TUDO > Run
--
--  ATENÇÃO: este script APAGA as tabelas criadas anteriormente
--  (categorias, produtos, clientes, pedidos, itens_pedido) e recria
--  tudo melhorado. Rode antes de cadastrar dados reais.
-- =====================================================================

drop view  if exists vw_catalogo;
drop table if exists pedidos_historico, movimentacoes_estoque, itens_pedido, pedidos, situacoes_pedido,
                     clientes_notas, admins, clientes, produto_cores, produtos, marcas, categorias,
                     opcoes, formas_pagamento, configuracoes, config_privada cascade;
drop trigger if exists on_auth_user_deleted on auth.users;
drop trigger if exists on_auth_user_created on auth.users;

-- ---------------------------------------------------------------------
-- 1. TABELAS
-- ---------------------------------------------------------------------

create table categorias (
  id         bigint generated always as identity primary key,
  nome       text not null unique,
  descricao  text,
  ordem      int  not null default 0,
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);

create table marcas (
  id         bigint generated always as identity primary key,
  nome       text not null unique,
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);

-- Produto = o modelo (ex.: "Aviador Clássico"). As cores ficam em produto_cores.
create table produtos (
  id                bigint generated always as identity primary key,
  sku               text not null unique,              -- referência do modelo
  nome              text not null,
  descricao         text,
  categoria_id      bigint references categorias(id) on delete set null,
  marca_id          bigint references marcas(id)     on delete set null,
  genero            text not null default 'Unissex'
                    check (genero in ('Masculino','Feminino','Unissex','Infantil')),
  formato           text,          -- Aviador, Redondo, Quadrado, Gatinho, Retangular...
  material_armacao  text,          -- Acetato, Metal, TR90, Titânio...
  material_lente    text,          -- Policarbonato, Nylon, Cristal, CR-39...
  tipo_lente        text,          -- Solar, Receituário (grau), Luz azul...
  polarizado        boolean not null default false,
  protecao_uv       text default 'UV400',
  largura_lente_mm  int,           -- medidas gravadas na haste: 52□18 140
  ponte_mm          int,
  haste_mm          int,
  altura_lente_mm   int,
  peso_g            numeric(6,1),
  garantia_meses    int default 3,
  ncm               text,          -- p/ nota fiscal (sol: 9004.10.00 / armação: 9003.11.00)
  preco_custo       numeric(10,2) not null default 0 check (preco_custo >= 0),
  preco_venda       numeric(10,2) not null check (preco_venda > 0),
  preco_promocional numeric(10,2) check (preco_promocional is null
                                         or (preco_promocional > 0 and preco_promocional < preco_venda)),
  imagem_url        text,          -- foto principal
  destaque          boolean not null default false,
  ativo             boolean not null default true,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now()
);

-- Cada cor é uma variação com SKU, foto e ESTOQUE próprios
create table produto_cores (
  id             bigint generated always as identity primary key,
  produto_id     bigint not null references produtos(id) on delete cascade,
  cor            text not null,                 -- "Preto fosco"
  cor_hex        text not null default '#222222',
  cor_lente      text,                          -- "Verde G15", "Fumê degradê"
  sku            text not null unique,
  estoque        int  not null default 0 check (estoque >= 0),
  estoque_minimo int  not null default 2,
  imagem_url     text,
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  unique (produto_id, cor)
);

-- Cliente: ligado ao login do Supabase (auth.users)
create table clientes (
  id              uuid primary key references auth.users(id) on delete cascade,
  nome            text not null,
  email           text not null,
  telefone        text,
  cpf             text,
  data_nascimento date,
  cep             text,
  endereco        text,
  numero          text,
  complemento     text,
  bairro          text,
  cidade          text,
  uf              text,
  bloqueado       boolean not null default false,
  criado_em       timestamptz not null default now()
);

-- Quem pode acessar o painel administrativo
create table admins (
  user_id   uuid primary key references auth.users(id) on delete cascade,
  criado_em timestamptz not null default now()
);

create table pedidos (
  id               bigint generated always as identity primary key,
  cliente_id       uuid not null references clientes(id) on delete restrict,
  status           text not null default 'pendente'
                   check (status in ('pendente','aprovado','recusado','enviado','entregue','cancelado')),
  subtotal         numeric(10,2) not null default 0,
  desconto         numeric(10,2) not null default 0,
  frete            numeric(10,2) not null default 0,
  valor_total      numeric(10,2) not null default 0,
  forma_pagamento  text,
  observacao       text,
  motivo_recusa    text,
  codigo_rastreio  text,
  endereco_entrega jsonb,             -- cópia do endereço no momento do pedido
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  aprovado_em      timestamptz,
  aprovado_por     uuid references auth.users(id)
);

create table itens_pedido (
  id             bigint generated always as identity primary key,
  pedido_id      bigint not null references pedidos(id) on delete cascade,
  produto_id     bigint not null references produtos(id),
  cor_id         bigint not null references produto_cores(id),
  descricao      text not null,              -- "Aviador Clássico - Dourado" (cópia)
  quantidade     int  not null check (quantidade > 0),
  preco_unitario numeric(10,2) not null,     -- preço de venda no momento
  preco_custo    numeric(10,2) not null default 0  -- custo no momento (p/ margem)
);

-- Histórico de tudo que entra e sai do estoque
create table movimentacoes_estoque (
  id         bigint generated always as identity primary key,
  cor_id     bigint not null references produto_cores(id) on delete cascade,
  tipo       text not null check (tipo in ('entrada','saida','ajuste','estorno')),
  quantidade int  not null,                  -- positivo entra, negativo sai
  pedido_id  bigint references pedidos(id) on delete set null,
  observacao text,
  criado_por uuid default auth.uid(),
  criado_em  timestamptz not null default now()
);

create index on produtos (categoria_id);
create index on produto_cores (produto_id);
create index on pedidos (cliente_id);
create index on pedidos (status, criado_em desc);
create index on itens_pedido (pedido_id);
create index on movimentacoes_estoque (cor_id, criado_em desc);

-- ---------------------------------------------------------------------
-- 2. FUNÇÕES AUXILIARES E GATILHOS
-- ---------------------------------------------------------------------

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins where user_id = auth.uid());
$$;

create or replace function set_atualizado_em() returns trigger
language plpgsql as $$
begin
  new.atualizado_em := now();
  return new;
end $$;

create trigger trg_produtos_atualizado before update on produtos
  for each row execute function set_atualizado_em();
create trigger trg_pedidos_atualizado before update on pedidos
  for each row execute function set_atualizado_em();

-- Ao criar login, cria automaticamente o cadastro do cliente
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  insert into public.clientes (id, nome, email, telefone, cpf, cep, endereco, numero,
                               complemento, bairro, cidade, uf)
  values (new.id,
          coalesce(nullif(m->>'nome',''), split_part(new.email,'@',1)),
          new.email,
          m->>'telefone', m->>'cpf', m->>'cep', m->>'endereco', m->>'numero',
          m->>'complemento', m->>'bairro', m->>'cidade', m->>'uf')
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- Cria cadastro para logins que já existiam antes deste script
insert into clientes (id, nome, email)
select id, split_part(email,'@',1), email from auth.users
on conflict (id) do nothing;

-- Cliente não pode se desbloquear nem trocar o e-mail pelo cadastro
create or replace function proteger_cliente() returns trigger
language plpgsql as $$
begin
  if not is_admin() then
    new.id        := old.id;
    new.email     := old.email;
    new.bloqueado := old.bloqueado;
  end if;
  return new;
end $$;

create trigger trg_proteger_cliente before update on clientes
  for each row execute function proteger_cliente();

-- Registra o estoque inicial quando uma cor é cadastrada
create or replace function log_estoque_inicial() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.estoque > 0 then
    insert into movimentacoes_estoque (cor_id, tipo, quantidade, observacao)
    values (new.id, 'entrada', new.estoque, 'Estoque inicial');
  end if;
  return new;
end $$;

create trigger trg_estoque_inicial after insert on produto_cores
  for each row execute function log_estoque_inicial();

-- ---------------------------------------------------------------------
-- 3. REGRAS DE NEGÓCIO (pedido, aprovação, estoque)
-- ---------------------------------------------------------------------

-- Cliente finaliza o carrinho. Preços são recalculados AQUI (no servidor),
-- então ninguém consegue alterar o preço pelo navegador.
-- p_itens = [{"cor_id": 1, "quantidade": 2}, ...]
create or replace function criar_pedido(p_itens jsonb,
                                        p_observacao text default null,
                                        p_forma_pagamento text default null)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_cli      clientes%rowtype;
  v_pedido   bigint;
  v_item     jsonb;
  v_qtd      int;
  v_r        record;
  v_subtotal numeric(10,2) := 0;
begin
  if auth.uid() is null then
    raise exception 'Faça login para finalizar o pedido';
  end if;

  select * into v_cli from clientes where id = auth.uid();
  if not found then raise exception 'Cadastro de cliente não encontrado'; end if;
  if v_cli.bloqueado then raise exception 'Cadastro bloqueado. Entre em contato com a loja.'; end if;

  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Carrinho vazio';
  end if;

  insert into pedidos (cliente_id, observacao, forma_pagamento, endereco_entrega)
  values (v_cli.id, nullif(trim(p_observacao),''), p_forma_pagamento,
          jsonb_build_object('nome', v_cli.nome, 'telefone', v_cli.telefone,
                             'cep', v_cli.cep, 'endereco', v_cli.endereco,
                             'numero', v_cli.numero, 'complemento', v_cli.complemento,
                             'bairro', v_cli.bairro, 'cidade', v_cli.cidade, 'uf', v_cli.uf))
  returning id into v_pedido;

  for v_item in select * from jsonb_array_elements(p_itens) loop
    v_qtd := (v_item->>'quantidade')::int;
    if v_qtd is null or v_qtd <= 0 or v_qtd > 100 then
      raise exception 'Quantidade inválida';
    end if;

    select c.id as cor_id, c.cor, c.estoque, c.ativo as cor_ativa,
           p.id as produto_id, p.nome, p.ativo, p.preco_custo,
           coalesce(p.preco_promocional, p.preco_venda) as preco
      into v_r
      from produto_cores c join produtos p on p.id = c.produto_id
     where c.id = (v_item->>'cor_id')::bigint;

    if not found or not v_r.ativo or not v_r.cor_ativa then
      raise exception 'Um dos produtos do carrinho não está mais disponível';
    end if;
    if v_r.estoque < v_qtd then
      raise exception 'Estoque insuficiente para % - % (disponível: %)', v_r.nome, v_r.cor, v_r.estoque;
    end if;

    insert into itens_pedido (pedido_id, produto_id, cor_id, descricao, quantidade, preco_unitario, preco_custo)
    values (v_pedido, v_r.produto_id, v_r.cor_id, v_r.nome || ' - ' || v_r.cor, v_qtd, v_r.preco, v_r.preco_custo);

    v_subtotal := v_subtotal + v_r.preco * v_qtd;
  end loop;

  update pedidos set subtotal = v_subtotal, valor_total = v_subtotal where id = v_pedido;
  return v_pedido;
end $$;

-- Admin aprova: dá baixa no estoque (tudo ou nada)
create or replace function aprovar_pedido(p_pedido_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_status text;
  v_item   record;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;

  select status into v_status from pedidos where id = p_pedido_id for update;
  if not found then raise exception 'Pedido não encontrado'; end if;
  if v_status <> 'pendente' then raise exception 'Este pedido já está "%"', v_status; end if;

  for v_item in select * from itens_pedido where pedido_id = p_pedido_id order by cor_id loop
    update produto_cores set estoque = estoque - v_item.quantidade
     where id = v_item.cor_id and estoque >= v_item.quantidade;
    if not found then
      raise exception 'Estoque insuficiente para "%". Ajuste o estoque ou recuse o pedido.', v_item.descricao;
    end if;
    insert into movimentacoes_estoque (cor_id, tipo, quantidade, pedido_id, observacao)
    values (v_item.cor_id, 'saida', -v_item.quantidade, p_pedido_id, 'Pedido #' || p_pedido_id || ' aprovado');
  end loop;

  update pedidos set status = 'aprovado', aprovado_em = now(), aprovado_por = auth.uid()
   where id = p_pedido_id;
end $$;

-- Admin recusa (não mexe no estoque)
create or replace function recusar_pedido(p_pedido_id bigint, p_motivo text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_status text;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;
  select status into v_status from pedidos where id = p_pedido_id for update;
  if not found then raise exception 'Pedido não encontrado'; end if;
  if v_status <> 'pendente' then raise exception 'Só pedidos pendentes podem ser recusados'; end if;
  update pedidos set status = 'recusado', motivo_recusa = nullif(trim(p_motivo),'') where id = p_pedido_id;
end $$;

-- Cancelar: cliente cancela o próprio pedido pendente; admin cancela qualquer
-- pedido não finalizado. Se já tinha baixado estoque, devolve (estorno).
create or replace function cancelar_pedido(p_pedido_id bigint, p_motivo text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_ped  pedidos%rowtype;
  v_item record;
begin
  select * into v_ped from pedidos where id = p_pedido_id for update;
  if not found then raise exception 'Pedido não encontrado'; end if;

  if not is_admin() then
    if auth.uid() is null or v_ped.cliente_id <> auth.uid() then raise exception 'Acesso negado'; end if;
    if v_ped.status <> 'pendente' then
      raise exception 'Só é possível cancelar pedidos pendentes. Fale com a loja.';
    end if;
  end if;

  if v_ped.status in ('cancelado','recusado','entregue') then
    raise exception 'Pedido não pode ser cancelado (status: %)', v_ped.status;
  end if;

  if v_ped.status in ('aprovado','enviado') then
    for v_item in select * from itens_pedido where pedido_id = p_pedido_id loop
      update produto_cores set estoque = estoque + v_item.quantidade where id = v_item.cor_id;
      insert into movimentacoes_estoque (cor_id, tipo, quantidade, pedido_id, observacao)
      values (v_item.cor_id, 'estorno', v_item.quantidade, p_pedido_id, 'Cancelamento do pedido #' || p_pedido_id);
    end loop;
  end if;

  update pedidos set status = 'cancelado',
                     motivo_recusa = coalesce(nullif(trim(p_motivo),''), motivo_recusa)
   where id = p_pedido_id;
end $$;

-- Admin marca como enviado / entregue
create or replace function atualizar_status_pedido(p_pedido_id bigint, p_status text,
                                                   p_rastreio text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_status text;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;
  select status into v_status from pedidos where id = p_pedido_id for update;
  if not found then raise exception 'Pedido não encontrado'; end if;

  if p_status = 'enviado' and v_status <> 'aprovado' then
    raise exception 'Só pedidos aprovados podem ser enviados';
  elsif p_status = 'entregue' and v_status not in ('aprovado','enviado') then
    raise exception 'Só pedidos aprovados/enviados podem ser entregues';
  elsif p_status not in ('enviado','entregue') then
    raise exception 'Status inválido';
  end if;

  update pedidos set status = p_status,
                     codigo_rastreio = coalesce(nullif(trim(p_rastreio),''), codigo_rastreio)
   where id = p_pedido_id;
end $$;

-- Admin dá entrada / saída manual no estoque (ex.: chegou mercadoria, avaria)
create or replace function ajustar_estoque(p_cor_id bigint, p_delta int, p_obs text default null)
returns int
language plpgsql security definer set search_path = public as $$
declare v_novo int;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;
  if p_delta is null or p_delta = 0 then raise exception 'Informe uma quantidade diferente de zero'; end if;

  update produto_cores set estoque = estoque + p_delta
   where id = p_cor_id and estoque + p_delta >= 0
  returning estoque into v_novo;
  if not found then raise exception 'Cor não encontrada ou o estoque ficaria negativo'; end if;

  insert into movimentacoes_estoque (cor_id, tipo, quantidade, observacao)
  values (p_cor_id, case when p_delta > 0 then 'entrada' else 'ajuste' end, p_delta, nullif(trim(p_obs),''));
  return v_novo;
end $$;

-- Admin exclui cliente (só se não tiver pedidos; apaga também o login)
create or replace function admin_excluir_cliente(p_id uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;
  if p_id = auth.uid() then
    raise exception 'Você não pode excluir a sua própria conta.';
  end if;
  if exists (select 1 from admins where user_id = p_id) then
    raise exception 'Este cliente é administrador. Remova-o dos administradores antes de excluir.';
  end if;
  if exists (select 1 from pedidos where cliente_id = p_id) then
    raise exception 'Este cliente tem pedidos e não pode ser excluído (o histórico de vendas seria perdido). Use "Inativar".';
  end if;
  delete from auth.users where id = p_id;          -- apaga o login (e o cadastro junto)
  if not found then delete from clientes where id = p_id; end if;
end $$;

-- Números do painel (faturamento, custo, lucro, estoque...)
create or replace function admin_resumo() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_ini timestamptz := date_trunc('month', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo';
  r jsonb;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;

  select jsonb_build_object(
    'pendentes',        (select count(*) from pedidos where status = 'pendente'),
    'pedidos_mes',      (select count(*) from pedidos
                          where status in ('aprovado','enviado','entregue') and aprovado_em >= v_ini),
    'faturamento_mes',  (select coalesce(sum(i.preco_unitario * i.quantidade), 0)
                           from itens_pedido i join pedidos p on p.id = i.pedido_id
                          where p.status in ('aprovado','enviado','entregue') and p.aprovado_em >= v_ini),
    'custo_mes',        (select coalesce(sum(i.preco_custo * i.quantidade), 0)
                           from itens_pedido i join pedidos p on p.id = i.pedido_id
                          where p.status in ('aprovado','enviado','entregue') and p.aprovado_em >= v_ini),
    'estoque_baixo',    (select count(*) from produto_cores c join produtos p on p.id = c.produto_id
                          where c.ativo and p.ativo and c.estoque <= c.estoque_minimo),
    'pecas_estoque',    (select coalesce(sum(estoque), 0) from produto_cores),
    'valor_estoque_custo', (select coalesce(sum(c.estoque * p.preco_custo), 0)
                              from produto_cores c join produtos p on p.id = c.produto_id),
    'valor_estoque_venda', (select coalesce(sum(c.estoque * coalesce(p.preco_promocional, p.preco_venda)), 0)
                              from produto_cores c join produtos p on p.id = c.produto_id),
    'clientes',         (select count(*) from clientes),
    'mais_vendidos',    (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
                           select i.descricao, sum(i.quantidade) as qtd
                             from itens_pedido i join pedidos p on p.id = i.pedido_id
                            where p.status in ('aprovado','enviado','entregue')
                            group by i.descricao order by qtd desc limit 5) x)
  ) into r;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- 4. CATÁLOGO PÚBLICO (sem preço de custo!)
--    A loja lê desta "view". As tabelas de produtos ficam só para o admin,
--    assim o cliente nunca enxerga o seu custo.
-- ---------------------------------------------------------------------

create view vw_catalogo as
select p.id, p.sku, p.nome, p.descricao,
       p.categoria_id, c.nome as categoria,
       p.marca_id, m.nome as marca,
       p.genero, p.formato, p.material_armacao, p.material_lente, p.tipo_lente,
       p.polarizado, p.protecao_uv, p.largura_lente_mm, p.ponte_mm, p.haste_mm,
       p.altura_lente_mm, p.peso_g, p.garantia_meses,
       p.preco_venda, p.preco_promocional,
       coalesce(p.preco_promocional, p.preco_venda) as preco_final,
       p.imagem_url, p.destaque, p.criado_em,
       coalesce((select jsonb_agg(jsonb_build_object(
                   'id', pc.id, 'cor', pc.cor, 'cor_hex', pc.cor_hex, 'cor_lente', pc.cor_lente,
                   'sku', pc.sku, 'estoque', pc.estoque, 'imagem_url', pc.imagem_url) order by pc.id)
                   from produto_cores pc where pc.produto_id = p.id and pc.ativo), '[]'::jsonb) as cores
  from produtos p
  left join categorias c on c.id = p.categoria_id
  left join marcas m on m.id = p.marca_id
 where p.ativo and (c.id is null or c.ativo);

grant select on vw_catalogo to anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. SEGURANÇA (Row Level Security)
-- ---------------------------------------------------------------------

alter table categorias            enable row level security;
alter table marcas                enable row level security;
alter table produtos              enable row level security;
alter table produto_cores         enable row level security;
alter table clientes              enable row level security;
alter table admins                enable row level security;
alter table pedidos               enable row level security;
alter table itens_pedido          enable row level security;
alter table movimentacoes_estoque enable row level security;

-- Categorias e marcas: todos leem; só admin altera
create policy "categorias_leitura" on categorias for select using (ativo or is_admin());
create policy "categorias_admin"   on categorias for all using (is_admin()) with check (is_admin());
create policy "marcas_leitura"     on marcas     for select using (ativo or is_admin());
create policy "marcas_admin"       on marcas     for all using (is_admin()) with check (is_admin());

-- Produtos e cores: SÓ admin (a loja usa vw_catalogo)
create policy "produtos_admin" on produtos      for all using (is_admin()) with check (is_admin());
create policy "cores_admin"    on produto_cores for all using (is_admin()) with check (is_admin());

-- Clientes: cada um vê/edita o próprio cadastro; admin vê todos
create policy "clientes_proprio_ler"   on clientes for select using (id = auth.uid() or is_admin());
create policy "clientes_proprio_editar" on clientes for update
  using (id = auth.uid() or is_admin()) with check (id = auth.uid() or is_admin());

-- Admins: cada um só enxerga a si mesmo
create policy "admins_ler" on admins for select using (user_id = auth.uid());

-- Pedidos: cliente vê os seus; criação/alteração só pelas funções acima
create policy "pedidos_ler" on pedidos for select using (cliente_id = auth.uid() or is_admin());
create policy "pedidos_admin_editar" on pedidos for update using (is_admin()) with check (is_admin());

create policy "itens_ler" on itens_pedido for select using (
  is_admin() or exists (select 1 from pedidos p where p.id = pedido_id and p.cliente_id = auth.uid()));

create policy "mov_admin" on movimentacoes_estoque for select using (is_admin());

-- ---------------------------------------------------------------------
-- 6. FOTOS DOS PRODUTOS (Supabase Storage)
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('produtos', 'produtos', true)
on conflict (id) do update set public = true;

drop policy if exists "fotos_admin_ler"     on storage.objects;
drop policy if exists "fotos_admin_enviar"  on storage.objects;
drop policy if exists "fotos_admin_alterar" on storage.objects;
drop policy if exists "fotos_admin_apagar"  on storage.objects;

create policy "fotos_admin_ler" on storage.objects for select to authenticated
  using (bucket_id = 'produtos' and public.is_admin());
create policy "fotos_admin_enviar" on storage.objects for insert to authenticated
  with check (bucket_id = 'produtos' and public.is_admin());
create policy "fotos_admin_alterar" on storage.objects for update to authenticated
  using (bucket_id = 'produtos' and public.is_admin())
  with check (bucket_id = 'produtos' and public.is_admin());
create policy "fotos_admin_apagar" on storage.objects for delete to authenticated
  using (bucket_id = 'produtos' and public.is_admin());

-- ---------------------------------------------------------------------
-- 7. DADOS DE EXEMPLO (pode apagar depois pelo painel)
-- ---------------------------------------------------------------------

insert into categorias (nome, ordem) values
  ('Óculos de Sol', 1), ('Armações de Grau', 2), ('Esportivos', 3),
  ('Infantis', 4), ('Acessórios', 5);

insert into marcas (nome) values ('Marca Própria');

with p as (
  insert into produtos (sku, nome, descricao, categoria_id, marca_id, genero, formato,
                        material_armacao, material_lente, tipo_lente, polarizado,
                        largura_lente_mm, ponte_mm, haste_mm, preco_custo, preco_venda, destaque, ncm)
  values ('SOL-AV-001', 'Aviador Clássico',
          'O clássico que nunca sai de moda. Armação leve em metal e lentes polarizadas que reduzem reflexos.',
          (select id from categorias where nome = 'Óculos de Sol'),
          (select id from marcas where nome = 'Marca Própria'),
          'Unissex', 'Aviador', 'Metal', 'Policarbonato', 'Solar', true, 58, 14, 140, 45, 189.90, true, '9004.10.00')
  returning id)
insert into produto_cores (produto_id, cor, cor_hex, cor_lente, sku, estoque)
select p.id, x.cor, x.hex, x.lente, x.sku, x.qtd from p,
  (values ('Dourado', '#C9A227', 'Verde G15', 'SOL-AV-001-DO', 10),
          ('Prata',   '#B8B8B8', 'Cinza',     'SOL-AV-001-PR', 8)) as x(cor, hex, lente, sku, qtd);

with p as (
  insert into produtos (sku, nome, descricao, categoria_id, marca_id, genero, formato,
                        material_armacao, material_lente, tipo_lente,
                        largura_lente_mm, ponte_mm, haste_mm, preco_custo, preco_venda, preco_promocional, ncm)
  values ('SOL-RD-002', 'Redondo Retrô',
          'Estilo vintage em acetato encorpado, confortável para o dia todo.',
          (select id from categorias where nome = 'Óculos de Sol'),
          (select id from marcas where nome = 'Marca Própria'),
          'Unissex', 'Redondo', 'Acetato', 'Nylon', 'Solar', 49, 21, 145, 38, 159.90, 139.90, '9004.10.00')
  returning id)
insert into produto_cores (produto_id, cor, cor_hex, cor_lente, sku, estoque)
select p.id, x.cor, x.hex, x.lente, x.sku, x.qtd from p,
  (values ('Tartaruga', '#6B3E26', 'Marrom degradê', 'SOL-RD-002-TA', 5),
          ('Preto',     '#151515', 'Fumê',           'SOL-RD-002-PT', 12)) as x(cor, hex, lente, sku, qtd);

with p as (
  insert into produtos (sku, nome, descricao, categoria_id, marca_id, genero, formato,
                        material_armacao, tipo_lente,
                        largura_lente_mm, ponte_mm, haste_mm, preco_custo, preco_venda, ncm)
  values ('GRA-QD-003', 'Armação Quadrada Slim',
          'Armação de grau leve e flexível em TR90. Aceita lentes de receituário.',
          (select id from categorias where nome = 'Armações de Grau'),
          (select id from marcas where nome = 'Marca Própria'),
          'Masculino', 'Quadrado', 'TR90', 'Receituário (grau)', 54, 18, 145, 30, 129.90, '9003.11.00')
  returning id)
insert into produto_cores (produto_id, cor, cor_hex, sku, estoque)
select p.id, x.cor, x.hex, x.sku, x.qtd from p,
  (values ('Preto fosco',  '#2A2A2A', 'GRA-QD-003-PF', 7),
          ('Azul marinho', '#1F2F55', 'GRA-QD-003-AZ', 1)) as x(cor, hex, sku, qtd);

-- ---------------------------------------------------------------------
-- 8. PLANILHAS (importar/exportar) — mesmo conteúdo da atualizacao-02
-- ---------------------------------------------------------------------
-- ---------- 1. Clientes podem existir antes do login ----------
alter table clientes drop constraint if exists clientes_id_fkey;
alter table clientes alter column id set default gen_random_uuid();
alter table clientes add column if not exists possui_login boolean not null default false;
update clientes c set possui_login = exists (select 1 from auth.users u where u.id = c.id);
create unique index if not exists clientes_email_unico on clientes (lower(email));

-- se o id do cliente mudar (ao ligar com o login), os pedidos acompanham
alter table pedidos drop constraint if exists pedidos_cliente_id_fkey;
alter table pedidos add constraint pedidos_cliente_id_fkey
  foreign key (cliente_id) references clientes(id) on update cascade on delete restrict;

-- Ao criar login: liga ao cadastro importado (mesmo e-mail) ou cria um novo
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  m    jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_id uuid;
begin
  select id into v_id from public.clientes
   where lower(email) = lower(new.email) and not possui_login limit 1;

  if v_id is not null then
    update public.clientes set
      id = new.id, email = new.email, possui_login = true,
      nome        = coalesce(nullif(m->>'nome',''), nome),
      telefone    = coalesce(nullif(m->>'telefone',''), telefone),
      cpf         = coalesce(nullif(m->>'cpf',''), cpf),
      cep         = coalesce(nullif(m->>'cep',''), cep),
      endereco    = coalesce(nullif(m->>'endereco',''), endereco),
      numero      = coalesce(nullif(m->>'numero',''), numero),
      complemento = coalesce(nullif(m->>'complemento',''), complemento),
      bairro      = coalesce(nullif(m->>'bairro',''), bairro),
      cidade      = coalesce(nullif(m->>'cidade',''), cidade),
      uf          = coalesce(nullif(m->>'uf',''), uf)
    where id = v_id;
  else
    insert into public.clientes (id, nome, email, telefone, cpf, cep, endereco, numero,
                                 complemento, bairro, cidade, uf, possui_login)
    values (new.id,
            coalesce(nullif(m->>'nome',''), split_part(new.email,'@',1)),
            new.email, m->>'telefone', m->>'cpf', m->>'cep', m->>'endereco', m->>'numero',
            m->>'complemento', m->>'bairro', m->>'cidade', m->>'uf', true)
    on conflict (id) do nothing;
  end if;
  return new;
end $$;

-- Se um login for apagado pelo Supabase, o cadastro fica "sem login"
create or replace function handle_deleted_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.clientes set possui_login = false where id = old.id;
  return old;
end $$;
drop trigger if exists on_auth_user_deleted on auth.users;
create trigger on_auth_user_deleted after delete on auth.users
  for each row execute function handle_deleted_user();

-- Cliente logado não pode alterar campos de controle (admin e sistema podem)
create or replace function proteger_cliente() returns trigger
language plpgsql as $$
begin
  if auth.uid() is not null and not is_admin() then
    new.id           := old.id;
    new.email        := old.email;
    new.bloqueado    := old.bloqueado;
    new.possui_login := old.possui_login;
  end if;
  return new;
end $$;

-- Excluir cliente: apaga login (se tiver) e cadastro
create or replace function admin_excluir_cliente(p_id uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;
  if p_id = auth.uid() then raise exception 'Você não pode excluir a sua própria conta.'; end if;
  if exists (select 1 from admins where user_id = p_id) then
    raise exception 'Este cliente é administrador. Remova-o dos administradores antes de excluir.';
  end if;
  if exists (select 1 from pedidos where cliente_id = p_id) then
    raise exception 'Este cliente tem pedidos e não pode ser excluído (o histórico de vendas seria perdido). Use "Inativar".';
  end if;
  delete from auth.users where id = p_id;
  delete from clientes where id = p_id;
end $$;

-- ---------- 2. Conversores de célula (aceitam o jeito brasileiro) ----------
create or replace function imp_txt(r jsonb, k text) returns text
language sql immutable as $$ select nullif(trim(r->>k), '') $$;

-- "1.234,56", "189,90", "R$ 189,90", "189.9" -> número
create or replace function imp_num(t text) returns numeric
language plpgsql immutable as $$
declare s text := replace(replace(replace(trim(coalesce(t,'')), 'R$', ''), ' ', ''), '%', '');
begin
  if s = '' then return null; end if;
  if position(',' in s) > 0 and position('.' in s) > 0 then
    if strpos(reverse(s), ',') < strpos(reverse(s), '.') then s := replace(replace(s, '.', ''), ',', '.');
    else s := replace(s, ',', ''); end if;
  elsif position(',' in s) > 0 then
    s := replace(s, ',', '.');
  end if;
  return s::numeric;
exception when others then
  raise exception 'número inválido: "%"', t;
end $$;

create or replace function imp_int(t text) returns int
language sql immutable as $$ select round(imp_num(t))::int $$;

create or replace function imp_bool(t text) returns boolean
language plpgsql immutable as $$
declare s text := lower(trim(coalesce(t,'')));
begin
  if s = '' then return null; end if;
  if s in ('sim','s','true','verdadeiro','1','x','yes','y','ativo','ativa') then return true; end if;
  if s in ('não','nao','n','false','falso','0','no','inativo','inativa') then return false; end if;
  raise exception 'use Sim ou Não (recebido: "%")', t;
end $$;

create or replace function imp_date(t text) returns date
language plpgsql immutable as $$
declare s text := trim(coalesce(t,''));
begin
  if s = '' then return null; end if;
  if s ~ '^\d{4}-\d{2}-\d{2}' then return left(s,10)::date; end if;
  if s ~ '^\d{1,2}/\d{1,2}/\d{4}$' then return to_date(s, 'DD/MM/YYYY'); end if;
  raise exception 'data inválida: "%" (use DD/MM/AAAA)', t;
end $$;

-- Ajusta o estoque de uma cor para uma quantidade exata (registra no histórico)
create or replace function imp_definir_estoque(p_cor bigint, p_qtd int, p_obs text) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_atual int;
begin
  if p_qtd is null then return false; end if;
  if p_qtd < 0 then raise exception 'estoque não pode ser negativo'; end if;
  select estoque into v_atual from produto_cores where id = p_cor for update;
  if v_atual = p_qtd then return false; end if;
  update produto_cores set estoque = p_qtd where id = p_cor;
  insert into movimentacoes_estoque (cor_id, tipo, quantidade, observacao)
  values (p_cor, case when p_qtd > v_atual then 'entrada' else 'ajuste' end, p_qtd - v_atual,
          coalesce(nullif(trim(p_obs),''), 'Importação de planilha'));
  return true;
end $$;
revoke execute on function imp_definir_estoque(bigint, int, text) from public, anon, authenticated;

-- ---------- 3. Importar PRODUTOS (uma linha por cor) ----------
create or replace function admin_importar_produtos(p_linhas jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r jsonb; n int := 1;
  v_sku text; v_prod bigint; v_cat bigint; v_marca bigint; v_gen text;
  v_cor bigint; v_nomecor text; v_skucor text; v_hex text;
  novos_p bigint[] := '{}'; atu_p bigint[] := '{}';
  novas_c int := 0; atu_c int := 0; ajustes int := 0;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;

  for r in select * from jsonb_array_elements(p_linhas) loop
    n := n + 1;
    continue when r = '{}'::jsonb;   -- linha em branco
    begin
      v_sku := imp_txt(r, 'sku');
      if v_sku is null then raise exception 'a coluna "SKU produto" é obrigatória'; end if;

      v_cat := null; v_marca := null;
      if imp_txt(r, 'categoria') is not null then
        select id into v_cat from categorias where lower(nome) = lower(imp_txt(r, 'categoria'));
        if v_cat is null then
          insert into categorias (nome, ordem)
          values (imp_txt(r, 'categoria'), (select coalesce(max(ordem), 0) + 1 from categorias))
          returning id into v_cat;
        end if;
      end if;
      if imp_txt(r, 'marca') is not null then
        select id into v_marca from marcas where lower(nome) = lower(imp_txt(r, 'marca'));
        if v_marca is null then
          insert into marcas (nome) values (imp_txt(r, 'marca')) returning id into v_marca;
        end if;
      end if;

      v_gen := case lower(left(coalesce(imp_txt(r, 'genero'), ''), 1))
                 when '' then null when 'm' then 'Masculino' when 'f' then 'Feminino'
                 when 'u' then 'Unissex' when 'i' then 'Infantil' else '?' end;
      if v_gen = '?' then
        raise exception 'gênero "%" inválido (use Masculino, Feminino, Unissex ou Infantil)', imp_txt(r, 'genero');
      end if;

      select id into v_prod from produtos where sku = v_sku;
      if v_prod is null then
        if imp_txt(r, 'nome') is null or imp_num(imp_txt(r, 'preco_venda')) is null then
          raise exception 'produto novo "%" precisa de Nome e Preço venda', v_sku;
        end if;
        insert into produtos (sku, nome, preco_venda)
        values (v_sku, imp_txt(r, 'nome'), imp_num(imp_txt(r, 'preco_venda')))
        returning id into v_prod;
        novos_p := novos_p || v_prod;
      elsif not (v_prod = any(novos_p) or v_prod = any(atu_p)) then
        atu_p := atu_p || v_prod;
      end if;

      update produtos p set
        nome              = coalesce(imp_txt(r, 'nome'), p.nome),
        descricao         = coalesce(imp_txt(r, 'descricao'), p.descricao),
        categoria_id      = coalesce(v_cat, p.categoria_id),
        marca_id          = coalesce(v_marca, p.marca_id),
        genero            = coalesce(v_gen, p.genero),
        formato           = coalesce(imp_txt(r, 'formato'), p.formato),
        material_armacao  = coalesce(imp_txt(r, 'material_armacao'), p.material_armacao),
        material_lente    = coalesce(imp_txt(r, 'material_lente'), p.material_lente),
        tipo_lente        = coalesce(imp_txt(r, 'tipo_lente'), p.tipo_lente),
        polarizado        = coalesce(imp_bool(imp_txt(r, 'polarizado')), p.polarizado),
        protecao_uv       = coalesce(imp_txt(r, 'protecao_uv'), p.protecao_uv),
        largura_lente_mm  = coalesce(imp_int(imp_txt(r, 'largura_lente_mm')), p.largura_lente_mm),
        ponte_mm          = coalesce(imp_int(imp_txt(r, 'ponte_mm')), p.ponte_mm),
        haste_mm          = coalesce(imp_int(imp_txt(r, 'haste_mm')), p.haste_mm),
        altura_lente_mm   = coalesce(imp_int(imp_txt(r, 'altura_lente_mm')), p.altura_lente_mm),
        peso_g            = coalesce(imp_num(imp_txt(r, 'peso_g')), p.peso_g),
        garantia_meses    = coalesce(imp_int(imp_txt(r, 'garantia_meses')), p.garantia_meses),
        ncm               = coalesce(imp_txt(r, 'ncm'), p.ncm),
        preco_custo       = coalesce(imp_num(imp_txt(r, 'preco_custo')), p.preco_custo),
        preco_venda       = coalesce(imp_num(imp_txt(r, 'preco_venda')), p.preco_venda),
        preco_promocional = case when imp_txt(r, 'preco_promocional') is null then p.preco_promocional
                                 else nullif(imp_num(imp_txt(r, 'preco_promocional')), 0) end,
        destaque          = coalesce(imp_bool(imp_txt(r, 'destaque')), p.destaque),
        ativo             = coalesce(imp_bool(imp_txt(r, 'ativo')), p.ativo),
        imagem_url        = coalesce(imp_txt(r, 'imagem_url'), p.imagem_url)
      where p.id = v_prod;

      -- cor / variação
      v_nomecor := imp_txt(r, 'cor');
      v_skucor  := imp_txt(r, 'sku_cor');
      if v_nomecor is not null or v_skucor is not null then
        v_cor := null;
        if v_skucor is not null then
          select id into v_cor from produto_cores where sku = v_skucor;
        end if;
        if v_cor is null and v_nomecor is not null then
          select id into v_cor from produto_cores where produto_id = v_prod and lower(cor) = lower(v_nomecor);
        end if;

        if v_cor is null then
          if v_nomecor is null then
            raise exception 'SKU cor "%" não existe; preencha também a coluna Cor para criá-la', v_skucor;
          end if;
          insert into produto_cores (produto_id, cor, sku, estoque)
          values (v_prod, v_nomecor,
                  coalesce(v_skucor, v_sku || '-' || ((select count(*) from produto_cores where produto_id = v_prod) + 1)),
                  greatest(coalesce(imp_int(imp_txt(r, 'estoque')), 0), 0))
          returning id into v_cor;
          novas_c := novas_c + 1;
        else
          atu_c := atu_c + 1;
          if imp_definir_estoque(v_cor, imp_int(imp_txt(r, 'estoque')), 'Importação de planilha (produtos)') then
            ajustes := ajustes + 1;
          end if;
        end if;

        v_hex := imp_txt(r, 'cor_hex');
        if v_hex is not null then
          v_hex := '#' || ltrim(v_hex, '#');
          if v_hex !~* '^#[0-9a-f]{6}$' then raise exception 'Cor hex "%" inválida (ex.: #1F5168)', imp_txt(r, 'cor_hex'); end if;
        end if;

        update produto_cores c set
          cor            = coalesce(v_nomecor, c.cor),
          cor_hex        = coalesce(v_hex, c.cor_hex),
          cor_lente      = coalesce(imp_txt(r, 'cor_lente'), c.cor_lente),
          estoque_minimo = coalesce(imp_int(imp_txt(r, 'estoque_minimo')), c.estoque_minimo),
          ativo          = coalesce(imp_bool(imp_txt(r, 'cor_ativa')), c.ativo),
          imagem_url     = coalesce(imp_txt(r, 'imagem_cor_url'), c.imagem_url)
        where c.id = v_cor;
      end if;
    exception when others then
      raise exception 'Linha %: %', n, sqlerrm;
    end;
  end loop;

  return jsonb_build_object('produtos_novos', cardinality(novos_p), 'produtos_atualizados', cardinality(atu_p),
                            'cores_novas', novas_c, 'cores_atualizadas', atu_c, 'ajustes_estoque', ajustes);
end $$;

-- ---------- 4. Importar ESTOQUE (contagem/inventário) ----------
create or replace function admin_importar_estoque(p_linhas jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r jsonb; n int := 1; v_cor bigint; v_qtd int;
  alterados int := 0; iguais int := 0;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;
  for r in select * from jsonb_array_elements(p_linhas) loop
    n := n + 1;
    continue when r = '{}'::jsonb;   -- linha em branco
    begin
      if imp_txt(r, 'sku_cor') is null then raise exception 'a coluna "SKU cor" é obrigatória'; end if;
      select id into v_cor from produto_cores where sku = imp_txt(r, 'sku_cor');
      if v_cor is null then raise exception 'SKU cor "%" não encontrado', imp_txt(r, 'sku_cor'); end if;

      v_qtd := imp_int(imp_txt(r, 'estoque'));
      if imp_definir_estoque(v_cor, v_qtd, imp_txt(r, 'observacao')) then alterados := alterados + 1;
      else iguais := iguais + 1; end if;

      update produto_cores set estoque_minimo = coalesce(imp_int(imp_txt(r, 'estoque_minimo')), estoque_minimo)
       where id = v_cor;
    exception when others then
      raise exception 'Linha %: %', n, sqlerrm;
    end;
  end loop;
  return jsonb_build_object('estoque_alterado', alterados, 'sem_alteracao', iguais);
end $$;

-- ---------- 5. Importar CLIENTES ----------
create or replace function admin_importar_clientes(p_linhas jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r jsonb; n int := 1; v_email text; v_id uuid; novos int := 0; atualizados int := 0;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;
  for r in select * from jsonb_array_elements(p_linhas) loop
    n := n + 1;
    continue when r = '{}'::jsonb;   -- linha em branco
    begin
      v_email := lower(imp_txt(r, 'email'));
      if v_email is null then raise exception 'a coluna "E-mail" é obrigatória'; end if;
      if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'e-mail inválido: "%"', v_email; end if;

      select id into v_id from clientes where lower(email) = v_email;
      if v_id is null then
        if imp_txt(r, 'nome') is null then raise exception 'cliente novo "%" precisa de Nome', v_email; end if;
        insert into clientes (nome, email) values (imp_txt(r, 'nome'), v_email) returning id into v_id;
        novos := novos + 1;
      else
        atualizados := atualizados + 1;
      end if;

      update clientes c set
        nome            = coalesce(imp_txt(r, 'nome'), c.nome),
        telefone        = coalesce(imp_txt(r, 'telefone'), c.telefone),
        cpf             = coalesce(imp_txt(r, 'cpf'), c.cpf),
        data_nascimento = coalesce(imp_date(imp_txt(r, 'data_nascimento')), c.data_nascimento),
        cep             = coalesce(imp_txt(r, 'cep'), c.cep),
        endereco        = coalesce(imp_txt(r, 'endereco'), c.endereco),
        numero          = coalesce(imp_txt(r, 'numero'), c.numero),
        complemento     = coalesce(imp_txt(r, 'complemento'), c.complemento),
        bairro          = coalesce(imp_txt(r, 'bairro'), c.bairro),
        cidade          = coalesce(imp_txt(r, 'cidade'), c.cidade),
        uf              = coalesce(upper(imp_txt(r, 'uf')), c.uf),
        bloqueado       = coalesce(not imp_bool(imp_txt(r, 'ativo')), c.bloqueado)
      where c.id = v_id;
    exception when others then
      raise exception 'Linha %: %', n, sqlerrm;
    end;
  end loop;
  return jsonb_build_object('clientes_novos', novos, 'clientes_atualizados', atualizados);
end $$;

-- ---------- 6. Importar CATEGORIAS ou MARCAS ----------
create or replace function admin_importar_cadastro(p_tabela text, p_linhas jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r jsonb; n int := 1; v_id bigint; v_nome text; novos int := 0; atualizados int := 0;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;
  if p_tabela not in ('categorias', 'marcas') then raise exception 'Tabela inválida'; end if;

  for r in select * from jsonb_array_elements(p_linhas) loop
    n := n + 1;
    continue when r = '{}'::jsonb;   -- linha em branco
    begin
      v_nome := imp_txt(r, 'nome');
      v_id := null;
      if imp_txt(r, 'id') is not null then
        v_id := imp_int(imp_txt(r, 'id'));
        if p_tabela = 'categorias' then perform 1 from categorias where id = v_id;
        else perform 1 from marcas where id = v_id; end if;
        if not found then raise exception 'ID % não encontrado (deixe o ID vazio para cadastrar novo)', v_id; end if;
      elsif v_nome is not null then
        if p_tabela = 'categorias' then select id into v_id from categorias where lower(nome) = lower(v_nome);
        else select id into v_id from marcas where lower(nome) = lower(v_nome); end if;
      else
        raise exception 'a coluna "Nome" é obrigatória';
      end if;

      if v_id is null then
        if p_tabela = 'categorias' then
          insert into categorias (nome, ordem, descricao, ativo)
          values (v_nome, coalesce(imp_int(imp_txt(r, 'ordem')), (select coalesce(max(ordem), 0) + 1 from categorias)),
                  imp_txt(r, 'descricao'), coalesce(imp_bool(imp_txt(r, 'ativo')), true));
        else
          insert into marcas (nome, ativo) values (v_nome, coalesce(imp_bool(imp_txt(r, 'ativo')), true));
        end if;
        novos := novos + 1;
      else
        if p_tabela = 'categorias' then
          update categorias set nome = case when imp_txt(r, 'id') is not null then coalesce(v_nome, nome) else nome end,
                                ordem = coalesce(imp_int(imp_txt(r, 'ordem')), ordem),
                                descricao = coalesce(imp_txt(r, 'descricao'), descricao),
                                ativo = coalesce(imp_bool(imp_txt(r, 'ativo')), ativo)
           where id = v_id;
        else
          update marcas set nome = case when imp_txt(r, 'id') is not null then coalesce(v_nome, nome) else nome end, ativo = coalesce(imp_bool(imp_txt(r, 'ativo')), ativo)
           where id = v_id;
        end if;
        atualizados := atualizados + 1;
      end if;
    exception when others then
      raise exception 'Linha %: %', n, sqlerrm;
    end;
  end loop;
  return jsonb_build_object('novos', novos, 'atualizados', atualizados);
end $$;

-- ---------------------------------------------------------------------
-- 9. ATRIBUTOS, PREÇO E PAGAMENTO — mesmo conteúdo da atualizacao-03
-- ---------------------------------------------------------------------
-- ---------------------------------------------------------------------
-- 1. ATRIBUTOS: listas de Formato, Material da armação, Material da
--    lente e Tipo de lente (usadas no cadastro do produto)
-- ---------------------------------------------------------------------
create table if not exists opcoes (
  id        bigint generated always as identity primary key,
  tipo      text not null check (tipo in ('formato','material_armacao','material_lente','tipo_lente')),
  nome      text not null,
  ordem     int  not null default 0,
  ativo     boolean not null default true,
  criado_em timestamptz not null default now(),
  unique (tipo, nome)
);
alter table opcoes enable row level security;
drop policy if exists "opcoes_leitura" on opcoes;
drop policy if exists "opcoes_admin"   on opcoes;
create policy "opcoes_leitura" on opcoes for select using (ativo or is_admin());
create policy "opcoes_admin"   on opcoes for all using (is_admin()) with check (is_admin());
grant select on opcoes to anon, authenticated;
grant insert, update, delete on opcoes to authenticated;

insert into opcoes (tipo, nome, ordem) values
  ('formato','Aviador',1), ('formato','Redondo',2), ('formato','Quadrado',3), ('formato','Retangular',4),
  ('formato','Gatinho',5), ('formato','Oversized',6), ('formato','Hexagonal',7), ('formato','Clubmaster',8),
  ('formato','Esportivo',9), ('formato','Máscara',10),
  ('material_armacao','Acetato',1), ('material_armacao','Metal',2), ('material_armacao','TR90',3),
  ('material_armacao','Titânio',4), ('material_armacao','Aço inox',5), ('material_armacao','Policarbonato',6),
  ('material_armacao','Madeira',7),
  ('material_lente','Policarbonato',1), ('material_lente','Nylon',2), ('material_lente','Cristal',3),
  ('material_lente','CR-39',4), ('material_lente','Acrílico',5),
  ('tipo_lente','Solar',1), ('tipo_lente','Receituário (grau)',2), ('tipo_lente','Proteção luz azul',3),
  ('tipo_lente','Fotossensível',4), ('tipo_lente','Espelhada',5)
on conflict (tipo, nome) do nothing;

-- Valores já usados nos produtos entram na lista
insert into opcoes (tipo, nome, ordem)
select distinct t.tipo, t.nome, 50 from produtos p,
  lateral (values ('formato', p.formato), ('material_armacao', p.material_armacao),
                  ('material_lente', p.material_lente), ('tipo_lente', p.tipo_lente)) as t(tipo, nome)
where t.nome is not null and trim(t.nome) <> ''
on conflict (tipo, nome) do nothing;

-- Produto salvo (tela ou planilha) com valor novo -> entra na lista automaticamente
create or replace function produtos_registrar_opcoes() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into opcoes (tipo, nome, ordem)
  select t.tipo, trim(t.nome), (select coalesce(max(o.ordem), 0) + 1 from opcoes o where o.tipo = t.tipo)
    from (values ('formato', new.formato), ('material_armacao', new.material_armacao),
                 ('material_lente', new.material_lente), ('tipo_lente', new.tipo_lente)) as t(tipo, nome)
   where t.nome is not null and trim(t.nome) <> ''
  on conflict (tipo, nome) do nothing;
  return new;
end $$;
drop trigger if exists trg_produtos_opcoes on produtos;
create trigger trg_produtos_opcoes after insert or update of formato, material_armacao, material_lente, tipo_lente
  on produtos for each row execute function produtos_registrar_opcoes();

-- Renomear uma opção atualiza os produtos que a usam
create or replace function opcoes_renomear() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.nome is distinct from old.nome then
    case old.tipo
      when 'formato'          then update produtos set formato          = new.nome where formato          = old.nome;
      when 'material_armacao' then update produtos set material_armacao = new.nome where material_armacao = old.nome;
      when 'material_lente'   then update produtos set material_lente   = new.nome where material_lente   = old.nome;
      when 'tipo_lente'       then update produtos set tipo_lente       = new.nome where tipo_lente       = old.nome;
    end case;
  end if;
  return new;
end $$;
drop trigger if exists trg_opcoes_renomear on opcoes;
create trigger trg_opcoes_renomear after update of nome on opcoes
  for each row execute function opcoes_renomear();

-- Importar atributos por planilha (colunas: Tipo, ID, Nome, Ordem, Ativo)
create or replace function admin_importar_opcoes(p_linhas jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r jsonb; n int := 1; v_tipo text; v_t text; v_id bigint; v_nome text; novos int := 0; atualizados int := 0;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;
  for r in select * from jsonb_array_elements(p_linhas) loop
    n := n + 1;
    continue when r = '{}'::jsonb;
    begin
      v_t := translate(lower(coalesce(imp_txt(r, 'tipo'), '')), 'áàâãéêíóôõúç', 'aaaaeeiooouc');
      v_tipo := case when v_t like '%formato%' then 'formato'
                     when v_t like '%armac%'   then 'material_armacao'
                     when v_t like '%material%' and v_t like '%lente%' then 'material_lente'
                     when v_t like '%tipo%'    then 'tipo_lente' end;
      v_nome := imp_txt(r, 'nome');
      v_id := null;
      if imp_txt(r, 'id') is not null then
        v_id := imp_int(imp_txt(r, 'id'));
        select tipo into v_tipo from opcoes where id = v_id;
        if not found then raise exception 'ID % não encontrado (deixe o ID vazio para cadastrar novo)', v_id; end if;
      else
        if v_tipo is null then
          raise exception 'Tipo "%" inválido (use Formato, Material da armação, Material da lente ou Tipo de lente)', imp_txt(r, 'tipo');
        end if;
        if v_nome is null then raise exception 'a coluna "Nome" é obrigatória'; end if;
        select id into v_id from opcoes where tipo = v_tipo and lower(nome) = lower(v_nome);
      end if;

      if v_id is null then
        insert into opcoes (tipo, nome, ordem, ativo)
        values (v_tipo, v_nome, coalesce(imp_int(imp_txt(r, 'ordem')), (select coalesce(max(ordem), 0) + 1 from opcoes where tipo = v_tipo)),
                coalesce(imp_bool(imp_txt(r, 'ativo')), true));
        novos := novos + 1;
      else
        update opcoes set nome  = case when imp_txt(r, 'id') is not null then coalesce(v_nome, nome) else nome end,
                          ordem = coalesce(imp_int(imp_txt(r, 'ordem')), ordem),
                          ativo = coalesce(imp_bool(imp_txt(r, 'ativo')), ativo)
         where id = v_id;
        atualizados := atualizados + 1;
      end if;
    exception when others then
      raise exception 'Linha %: %', n, sqlerrm;
    end;
  end loop;
  return jsonb_build_object('novos', novos, 'atualizados', atualizados);
end $$;

-- ---------------------------------------------------------------------
-- 2. CONFIGURAÇÕES DA LOJA (exibição de preço)
-- ---------------------------------------------------------------------
create table if not exists configuracoes (
  id              int primary key default 1 check (id = 1),
  mostrar_precos  text not null default 'sempre' check (mostrar_precos in ('sempre','logados','nunca')),
  texto_sem_preco text not null default 'Consulte o preço',
  atualizado_em   timestamptz not null default now()
);
insert into configuracoes (id) values (1) on conflict (id) do nothing;
alter table configuracoes enable row level security;
drop policy if exists "config_leitura" on configuracoes;
drop policy if exists "config_admin"   on configuracoes;
create policy "config_leitura" on configuracoes for select using (true);
create policy "config_admin"   on configuracoes for update using (is_admin()) with check (is_admin());
grant select on configuracoes to anon, authenticated;
grant update on configuracoes to authenticated;

-- O visitante pode ver preço agora?
create or replace function pode_ver_preco() returns boolean
language sql stable security definer set search_path = public as $$
  select case coalesce((select mostrar_precos from configuracoes where id = 1), 'sempre')
           when 'sempre'  then true
           when 'logados' then auth.uid() is not null
           else false end
         or is_admin();
$$;

-- ---------------------------------------------------------------------
-- 3. FORMAS DE PAGAMENTO E PARCELAMENTO
-- ---------------------------------------------------------------------
create table if not exists formas_pagamento (
  id                  bigint generated always as identity primary key,
  nome                text not null unique,
  descricao           text,
  desconto_percentual numeric(5,2) not null default 0 check (desconto_percentual between 0 and 100),
  max_parcelas        int not null default 1 check (max_parcelas between 1 and 24),
  parcelas_sem_juros  int not null default 1 check (parcelas_sem_juros >= 1),
  juros_mes           numeric(5,2) not null default 0 check (juros_mes >= 0),
  parcela_minima      numeric(10,2) not null default 0 check (parcela_minima >= 0),
  ordem               int not null default 0,
  ativo               boolean not null default true,
  criado_em           timestamptz not null default now()
);
alter table formas_pagamento enable row level security;
drop policy if exists "formas_leitura" on formas_pagamento;
drop policy if exists "formas_admin"   on formas_pagamento;
create policy "formas_leitura" on formas_pagamento for select using (ativo or is_admin());
create policy "formas_admin"   on formas_pagamento for all using (is_admin()) with check (is_admin());
grant select on formas_pagamento to anon, authenticated;
grant insert, update, delete on formas_pagamento to authenticated;

insert into formas_pagamento (nome, descricao, desconto_percentual, max_parcelas, parcelas_sem_juros, juros_mes, parcela_minima, ordem) values
  ('Pix',               'Pagamento à vista com desconto', 5, 1, 1, 0, 0, 1),
  ('Cartão de crédito', 'Parcelado no cartão',            0, 10, 3, 1.99, 30, 2),
  ('Cartão de débito',  null,                             0, 1, 1, 0, 0, 3),
  ('Boleto',            'À vista',                        0, 1, 1, 0, 0, 4),
  ('A combinar',        'Combinar com a loja',            0, 1, 1, 0, 0, 5)
on conflict (nome) do nothing;

alter table pedidos add column if not exists forma_pagamento_id bigint references formas_pagamento(id) on delete set null;
alter table pedidos add column if not exists parcelas      int not null default 1;
alter table pedidos add column if not exists juros         numeric(10,2) not null default 0;
alter table pedidos add column if not exists valor_parcela numeric(10,2);

-- Cálculo oficial (o site mostra o mesmo cálculo, mas o que vale é este)
-- Juros compostos (tabela Price) a partir da 1ª parcela com juros.
create or replace function calcular_pagamento(p_subtotal numeric, p_forma_id bigint, p_parcelas int default 1)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  f formas_pagamento%rowtype;
  n int := coalesce(p_parcelas, 1);
  v_desc numeric; v_base numeric; v_parc numeric; v_total numeric; i numeric;
begin
  select * into f from formas_pagamento where id = p_forma_id and ativo;
  if not found then raise exception 'Forma de pagamento inválida'; end if;
  if n < 1 or n > f.max_parcelas then
    raise exception '% permite no máximo %x', f.nome, f.max_parcelas;
  end if;

  v_desc := round(p_subtotal * f.desconto_percentual / 100, 2);
  v_base := p_subtotal - v_desc;
  if n <= f.parcelas_sem_juros or f.juros_mes = 0 then
    v_parc  := round(v_base / n, 2);
    v_total := v_base;
  else
    i := f.juros_mes / 100;
    v_parc  := round(v_base * i / (1 - power(1 + i, -n)), 2);
    v_total := v_parc * n;
  end if;
  if n > 1 and v_parc < f.parcela_minima then
    raise exception 'A parcela mínima é de R$ % — escolha menos parcelas', replace(to_char(f.parcela_minima, 'FM999990.00'), '.', ',');
  end if;

  return jsonb_build_object('forma', f.nome, 'parcelas', n, 'desconto', v_desc,
                            'juros', v_total - v_base, 'total', v_total, 'valor_parcela', v_parc);
end $$;

-- Pedido agora recebe forma de pagamento + parcelas e calcula tudo no servidor
drop function if exists criar_pedido(jsonb, text, text);
create or replace function criar_pedido(p_itens jsonb,
                                        p_observacao text default null,
                                        p_forma_id bigint default null,
                                        p_parcelas int default 1)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_cli      clientes%rowtype;
  v_pedido   bigint;
  v_item     jsonb;
  v_qtd      int;
  v_r        record;
  v_subtotal numeric(10,2) := 0;
  v_pag      jsonb;
begin
  if auth.uid() is null then raise exception 'Faça login para finalizar o pedido'; end if;

  select * into v_cli from clientes where id = auth.uid();
  if not found then raise exception 'Cadastro de cliente não encontrado'; end if;
  if v_cli.bloqueado then raise exception 'Cadastro bloqueado. Entre em contato com a loja.'; end if;

  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Carrinho vazio';
  end if;
  if p_forma_id is null and exists (select 1 from formas_pagamento where ativo) then
    raise exception 'Escolha a forma de pagamento';
  end if;

  insert into pedidos (cliente_id, observacao, endereco_entrega)
  values (v_cli.id, nullif(trim(p_observacao),''),
          jsonb_build_object('nome', v_cli.nome, 'telefone', v_cli.telefone,
                             'cep', v_cli.cep, 'endereco', v_cli.endereco,
                             'numero', v_cli.numero, 'complemento', v_cli.complemento,
                             'bairro', v_cli.bairro, 'cidade', v_cli.cidade, 'uf', v_cli.uf))
  returning id into v_pedido;

  for v_item in select * from jsonb_array_elements(p_itens) loop
    v_qtd := (v_item->>'quantidade')::int;
    if v_qtd is null or v_qtd <= 0 or v_qtd > 100 then raise exception 'Quantidade inválida'; end if;

    select c.id as cor_id, c.cor, c.estoque, c.ativo as cor_ativa,
           p.id as produto_id, p.nome, p.ativo, p.preco_custo,
           coalesce(p.preco_promocional, p.preco_venda) as preco
      into v_r
      from produto_cores c join produtos p on p.id = c.produto_id
     where c.id = (v_item->>'cor_id')::bigint;

    if not found or not v_r.ativo or not v_r.cor_ativa then
      raise exception 'Um dos produtos do carrinho não está mais disponível';
    end if;
    if v_r.estoque < v_qtd then
      raise exception 'Estoque insuficiente para % - % (disponível: %)', v_r.nome, v_r.cor, v_r.estoque;
    end if;

    insert into itens_pedido (pedido_id, produto_id, cor_id, descricao, quantidade, preco_unitario, preco_custo)
    values (v_pedido, v_r.produto_id, v_r.cor_id, v_r.nome || ' - ' || v_r.cor, v_qtd, v_r.preco, v_r.preco_custo);
    v_subtotal := v_subtotal + v_r.preco * v_qtd;
  end loop;

  if p_forma_id is not null then
    v_pag := calcular_pagamento(v_subtotal, p_forma_id, p_parcelas);
    update pedidos set subtotal = v_subtotal,
                       desconto = (v_pag->>'desconto')::numeric,
                       juros = (v_pag->>'juros')::numeric,
                       valor_total = (v_pag->>'total')::numeric,
                       parcelas = (v_pag->>'parcelas')::int,
                       valor_parcela = (v_pag->>'valor_parcela')::numeric,
                       forma_pagamento = v_pag->>'forma',
                       forma_pagamento_id = p_forma_id
     where id = v_pedido;
  else
    update pedidos set subtotal = v_subtotal, valor_total = v_subtotal, valor_parcela = v_subtotal
     where id = v_pedido;
  end if;
  return v_pedido;
end $$;

-- ---------------------------------------------------------------------
-- 4. CATÁLOGO PÚBLICO respeitando a exibição de preço
--    (o preço nem sai do servidor quando estiver oculto)
-- ---------------------------------------------------------------------
drop view if exists vw_catalogo;
create view vw_catalogo as
select p.id, p.sku, p.nome, p.descricao,
       p.categoria_id, c.nome as categoria,
       p.marca_id, m.nome as marca,
       p.genero, p.formato, p.material_armacao, p.material_lente, p.tipo_lente,
       p.polarizado, p.protecao_uv, p.largura_lente_mm, p.ponte_mm, p.haste_mm,
       p.altura_lente_mm, p.peso_g, p.garantia_meses,
       case when v.ver then p.preco_venda end as preco_venda,
       case when v.ver then p.preco_promocional end as preco_promocional,
       case when v.ver then coalesce(p.preco_promocional, p.preco_venda) end as preco_final,
       v.ver as preco_visivel,
       p.imagem_url, p.destaque, p.criado_em,
       coalesce((select jsonb_agg(jsonb_build_object(
                   'id', pc.id, 'cor', pc.cor, 'cor_hex', pc.cor_hex, 'cor_lente', pc.cor_lente,
                   'sku', pc.sku, 'estoque', pc.estoque, 'imagem_url', pc.imagem_url) order by pc.id)
                   from produto_cores pc where pc.produto_id = p.id and pc.ativo), '[]'::jsonb) as cores
  from produtos p
  cross join (select pode_ver_preco() as ver) v
  left join categorias c on c.id = p.categoria_id
  left join marcas m on m.id = p.marca_id
 where p.ativo and (c.id is null or c.ativo);

grant select on vw_catalogo to anon, authenticated;

-- ---------------------------------------------------------------------
-- 10. CLIENTES MANUAIS E PEDIDOS PELO PAINEL — mesmo conteúdo da atualizacao-04
-- ---------------------------------------------------------------------
-- ---------- 1. Ajustes nas tabelas ----------
alter table clientes alter column email drop not null;          -- cliente de balcão pode não ter e-mail

alter table pedidos add column if not exists origem text not null default 'loja';
alter table pedidos drop constraint if exists pedidos_origem_check;
alter table pedidos add constraint pedidos_origem_check check (origem in ('loja', 'painel'));
alter table pedidos add column if not exists criado_por uuid;

-- Observações internas do cliente (só o painel vê)
create table if not exists clientes_notas (
  cliente_id    uuid primary key references clientes(id) on delete cascade on update cascade,
  observacoes   text,
  atualizado_em timestamptz not null default now()
);
alter table clientes_notas enable row level security;
drop policy if exists "notas_admin" on clientes_notas;
create policy "notas_admin" on clientes_notas for all using (is_admin()) with check (is_admin());

-- Lista completa para o painel (com observações e quantidade de pedidos)
create or replace function admin_listar_clientes() returns setof jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(c) || jsonb_build_object(
           'pedidos_qtd', (select count(*) from pedidos p where p.cliente_id = c.id),
           'observacoes', (select n.observacoes from clientes_notas n where n.cliente_id = c.id))
    from clientes c
   where is_admin()
   order by c.criado_em desc;
$$;

-- ---------- 2. Salvar cliente pelo painel (novo ou edição) ----------
create or replace function admin_salvar_cliente(p_id uuid, p_dados jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id    uuid := p_id;
  v_email text := lower(imp_txt(p_dados, 'email'));
  v_atual clientes%rowtype;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;
  if imp_txt(p_dados, 'nome') is null then raise exception 'Informe o nome do cliente'; end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'E-mail inválido: %', v_email;
  end if;
  if v_email is not null and exists (select 1 from clientes where lower(email) = v_email and id is distinct from p_id) then
    raise exception 'Já existe um cliente com o e-mail %', v_email;
  end if;

  if v_id is null then
    insert into clientes (nome, email) values (imp_txt(p_dados, 'nome'), v_email) returning id into v_id;
  else
    select * into v_atual from clientes where id = v_id;
    if not found then raise exception 'Cliente não encontrado'; end if;
    if p_dados ? 'email' and v_atual.possui_login and v_email is distinct from lower(v_atual.email) then
      raise exception 'Este cliente já tem login na loja; o e-mail não pode ser alterado pelo painel';
    end if;
  end if;

  -- só altera os campos enviados (o formulário do painel envia todos; vazio = apaga)
  update clientes set
    nome            = imp_txt(p_dados, 'nome'),
    email           = case when p_dados ? 'email' then v_email else email end,
    telefone        = case when p_dados ? 'telefone' then imp_txt(p_dados, 'telefone') else telefone end,
    cpf             = case when p_dados ? 'cpf' then imp_txt(p_dados, 'cpf') else cpf end,
    cep             = case when p_dados ? 'cep' then imp_txt(p_dados, 'cep') else cep end,
    endereco        = case when p_dados ? 'endereco' then imp_txt(p_dados, 'endereco') else endereco end,
    numero          = case when p_dados ? 'numero' then imp_txt(p_dados, 'numero') else numero end,
    complemento     = case when p_dados ? 'complemento' then imp_txt(p_dados, 'complemento') else complemento end,
    bairro          = case when p_dados ? 'bairro' then imp_txt(p_dados, 'bairro') else bairro end,
    cidade          = case when p_dados ? 'cidade' then imp_txt(p_dados, 'cidade') else cidade end,
    uf              = case when p_dados ? 'uf' then upper(imp_txt(p_dados, 'uf')) else uf end,
    data_nascimento = case when p_dados ? 'data_nascimento' then imp_date(imp_txt(p_dados, 'data_nascimento')) else data_nascimento end,
    bloqueado       = coalesce(not imp_bool(imp_txt(p_dados, 'ativo')), bloqueado)
  where id = v_id;

  if p_dados ? 'observacoes' then
    insert into clientes_notas (cliente_id, observacoes) values (v_id, imp_txt(p_dados, 'observacoes'))
    on conflict (cliente_id) do update set observacoes = excluded.observacoes, atualizado_em = now();
  end if;
  return v_id;
end $$;

-- ---------- 3. Montagem do pedido (usada pela loja e pelo painel) ----------
create or replace function pedido_montar(p_cliente uuid, p_itens jsonb, p_observacao text,
                                         p_forma_id bigint, p_parcelas int,
                                         p_origem text, p_preco_livre boolean)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_cli      clientes%rowtype;
  v_pedido   bigint;
  v_item     jsonb;
  v_qtd      int;
  v_r        record;
  v_preco    numeric(10,2);
  v_subtotal numeric(10,2) := 0;
  v_pag      jsonb;
begin
  select * into v_cli from clientes where id = p_cliente;
  if not found then raise exception 'Cliente não encontrado'; end if;
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Inclua pelo menos um produto';
  end if;

  insert into pedidos (cliente_id, observacao, origem, criado_por, endereco_entrega)
  values (v_cli.id, nullif(trim(p_observacao), ''), p_origem, auth.uid(),
          jsonb_build_object('nome', v_cli.nome, 'telefone', v_cli.telefone,
                             'cep', v_cli.cep, 'endereco', v_cli.endereco,
                             'numero', v_cli.numero, 'complemento', v_cli.complemento,
                             'bairro', v_cli.bairro, 'cidade', v_cli.cidade, 'uf', v_cli.uf))
  returning id into v_pedido;

  for v_item in select * from jsonb_array_elements(p_itens) loop
    v_qtd := (v_item->>'quantidade')::int;
    if v_qtd is null or v_qtd <= 0 or v_qtd > 1000 then raise exception 'Quantidade inválida'; end if;

    select c.id as cor_id, c.cor, c.estoque, c.ativo as cor_ativa,
           p.id as produto_id, p.nome, p.ativo, p.preco_custo,
           coalesce(p.preco_promocional, p.preco_venda) as preco
      into v_r
      from produto_cores c join produtos p on p.id = c.produto_id
     where c.id = (v_item->>'cor_id')::bigint;

    if not found then raise exception 'Produto não encontrado'; end if;
    if p_origem = 'loja' and (not v_r.ativo or not v_r.cor_ativa) then
      raise exception 'Um dos produtos do carrinho não está mais disponível';
    end if;
    if v_r.estoque < v_qtd then
      raise exception 'Estoque insuficiente para % - % (disponível: %)', v_r.nome, v_r.cor, v_r.estoque;
    end if;

    v_preco := v_r.preco;
    if p_preco_livre and nullif(trim(v_item->>'preco'), '') is not null then
      v_preco := imp_num(v_item->>'preco');
      if v_preco < 0 then raise exception 'Preço inválido para %', v_r.nome; end if;
    end if;

    insert into itens_pedido (pedido_id, produto_id, cor_id, descricao, quantidade, preco_unitario, preco_custo)
    values (v_pedido, v_r.produto_id, v_r.cor_id, v_r.nome || ' - ' || v_r.cor, v_qtd, v_preco, v_r.preco_custo);
    v_subtotal := v_subtotal + v_preco * v_qtd;
  end loop;

  if p_forma_id is not null then
    v_pag := calcular_pagamento(v_subtotal, p_forma_id, p_parcelas);
    update pedidos set subtotal = v_subtotal,
                       desconto = (v_pag->>'desconto')::numeric,
                       juros = (v_pag->>'juros')::numeric,
                       valor_total = (v_pag->>'total')::numeric,
                       parcelas = (v_pag->>'parcelas')::int,
                       valor_parcela = (v_pag->>'valor_parcela')::numeric,
                       forma_pagamento = v_pag->>'forma',
                       forma_pagamento_id = p_forma_id
     where id = v_pedido;
  else
    update pedidos set subtotal = v_subtotal, valor_total = v_subtotal, valor_parcela = v_subtotal,
                       forma_pagamento = case when p_origem = 'painel' then 'A combinar' end
     where id = v_pedido;
  end if;
  return v_pedido;
end $$;
revoke execute on function pedido_montar(uuid, jsonb, text, bigint, int, text, boolean) from public, anon, authenticated;

-- Loja (cliente logado): mesmas regras de antes
create or replace function criar_pedido(p_itens jsonb,
                                        p_observacao text default null,
                                        p_forma_id bigint default null,
                                        p_parcelas int default 1)
returns bigint
language plpgsql security definer set search_path = public as $$
declare v_cli clientes%rowtype;
begin
  if auth.uid() is null then raise exception 'Faça login para finalizar o pedido'; end if;
  select * into v_cli from clientes where id = auth.uid();
  if not found then raise exception 'Cadastro de cliente não encontrado'; end if;
  if v_cli.bloqueado then raise exception 'Cadastro bloqueado. Entre em contato com a loja.'; end if;
  if p_forma_id is null and exists (select 1 from formas_pagamento where ativo) then
    raise exception 'Escolha a forma de pagamento';
  end if;
  return pedido_montar(v_cli.id, p_itens, p_observacao, p_forma_id, p_parcelas, 'loja', false);
end $$;

-- Painel: pedido para qualquer cliente, preço ajustável, aprovação opcional
create or replace function admin_criar_pedido(p_cliente uuid, p_itens jsonb,
                                              p_observacao text default null,
                                              p_forma_id bigint default null,
                                              p_parcelas int default 1,
                                              p_aprovar boolean default false)
returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;
  v_id := pedido_montar(p_cliente, p_itens, p_observacao, p_forma_id, p_parcelas, 'painel', true);
  if p_aprovar then perform aprovar_pedido(v_id); end if;
  return v_id;
end $$;

-- Painel: trocar o cliente de um pedido (antes de enviar)
create or replace function admin_trocar_cliente_pedido(p_pedido_id bigint, p_cliente uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_status text; v_cli clientes%rowtype;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;
  select status into v_status from pedidos where id = p_pedido_id for update;
  if not found then raise exception 'Pedido não encontrado'; end if;
  if v_status not in ('pendente', 'aprovado') then
    raise exception 'Só é possível trocar o cliente de pedidos pendentes ou aprovados';
  end if;
  select * into v_cli from clientes where id = p_cliente;
  if not found then raise exception 'Cliente não encontrado'; end if;
  update pedidos set cliente_id = v_cli.id,
         endereco_entrega = jsonb_build_object('nome', v_cli.nome, 'telefone', v_cli.telefone,
                             'cep', v_cli.cep, 'endereco', v_cli.endereco,
                             'numero', v_cli.numero, 'complemento', v_cli.complemento,
                             'bairro', v_cli.bairro, 'cidade', v_cli.cidade, 'uf', v_cli.uf)
   where id = p_pedido_id;
end $$;

-- ---------- 4. Importação de clientes também aceita "Observações" ----------
create or replace function admin_importar_clientes(p_linhas jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r jsonb; n int := 1; v_email text; v_id uuid; novos int := 0; atualizados int := 0;
begin
  if not is_admin() then raise exception 'Acesso negado'; end if;
  for r in select * from jsonb_array_elements(p_linhas) loop
    n := n + 1;
    continue when r = '{}'::jsonb;
    begin
      v_email := lower(imp_txt(r, 'email'));
      if v_email is null then raise exception 'a coluna "E-mail" é obrigatória'; end if;
      if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'e-mail inválido: "%"', v_email; end if;

      select id into v_id from clientes where lower(email) = v_email;
      if v_id is null then
        if imp_txt(r, 'nome') is null then raise exception 'cliente novo "%" precisa de Nome', v_email; end if;
        insert into clientes (nome, email) values (imp_txt(r, 'nome'), v_email) returning id into v_id;
        novos := novos + 1;
      else
        atualizados := atualizados + 1;
      end if;

      update clientes c set
        nome            = coalesce(imp_txt(r, 'nome'), c.nome),
        telefone        = coalesce(imp_txt(r, 'telefone'), c.telefone),
        cpf             = coalesce(imp_txt(r, 'cpf'), c.cpf),
        data_nascimento = coalesce(imp_date(imp_txt(r, 'data_nascimento')), c.data_nascimento),
        cep             = coalesce(imp_txt(r, 'cep'), c.cep),
        endereco        = coalesce(imp_txt(r, 'endereco'), c.endereco),
        numero          = coalesce(imp_txt(r, 'numero'), c.numero),
        complemento     = coalesce(imp_txt(r, 'complemento'), c.complemento),
        bairro          = coalesce(imp_txt(r, 'bairro'), c.bairro),
        cidade          = coalesce(imp_txt(r, 'cidade'), c.cidade),
        uf              = coalesce(upper(imp_txt(r, 'uf')), c.uf),
        bloqueado       = coalesce(not imp_bool(imp_txt(r, 'ativo')), c.bloqueado)
      where c.id = v_id;
      if imp_txt(r, 'observacoes') is not null then
        insert into clientes_notas (cliente_id, observacoes) values (v_id, imp_txt(r, 'observacoes'))
        on conflict (cliente_id) do update set observacoes = excluded.observacoes, atualizado_em = now();
      end if;
    exception when others then
      raise exception 'Linha %: %', n, sqlerrm;
    end;
  end loop;
  return jsonb_build_object('clientes_novos', novos, 'clientes_atualizados', atualizados);
end $$;

-- ---------------------------------------------------------------------
-- 11. SITUAÇÕES DE PEDIDO E AVISO POR E-MAIL — mesmo conteúdo da atualizacao-05
-- ---------------------------------------------------------------------
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

-- =====================================================================
-- PRONTO! Agora crie sua conta na loja e depois rode (trocando o e-mail):
--
--   insert into admins (user_id)
--   select id from auth.users where email = 'SEU-EMAIL@exemplo.com';
-- =====================================================================
