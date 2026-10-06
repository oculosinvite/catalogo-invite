-- =====================================================================
--  ATUALIZAÇÃO 03 — atributos, exibição de preço e formas de pagamento
--  Rode UMA vez: Supabase > SQL Editor > New query > cole TUDO > Run
--  (não apaga nenhum dado; pode rodar de novo sem problema)
-- =====================================================================

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
