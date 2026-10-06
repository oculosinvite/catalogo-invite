-- =====================================================================
--  ATUALIZAÇÃO 02 — importar/exportar planilhas
--  Rode UMA vez: Supabase > SQL Editor > New query > cole TUDO > Run
--  (não apaga nenhum dado)
--
--  - Permite cadastrar clientes pela planilha (sem login ainda).
--    Quando a pessoa criar a conta na loja com o mesmo e-mail,
--    o cadastro importado é ligado automaticamente ao login.
--  - Funções de importação de produtos/cores, estoque, clientes,
--    categorias e marcas. Se uma linha tiver erro, NADA é gravado
--    e a mensagem diz qual linha corrigir.
--  - Célula vazia na planilha = mantém o valor atual.
-- =====================================================================

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
