-- =====================================================================
--  ATUALIZAÇÃO 04 — cadastro manual de clientes e pedidos pelo painel
--  Rode UMA vez: Supabase > SQL Editor > New query > cole TUDO > Run
--  (precisa das atualizações 02 e 03; não apaga nenhum dado)
-- =====================================================================

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
