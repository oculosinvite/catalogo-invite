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
drop table if exists movimentacoes_estoque, itens_pedido, pedidos, admins, clientes,
                     produto_cores, produtos, marcas, categorias cascade;
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

-- =====================================================================
-- PRONTO! Agora crie sua conta na loja e depois rode (trocando o e-mail):
--
--   insert into admins (user_id)
--   select id from auth.users where email = 'SEU-EMAIL@exemplo.com';
-- =====================================================================
