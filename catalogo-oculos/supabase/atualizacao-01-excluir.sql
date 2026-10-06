-- =====================================================================
--  ATUALIZAÇÃO 01 — permite excluir clientes pelo painel
--  Rode UMA vez: Supabase > SQL Editor > New query > cole > Run
--  (não apaga nenhum dado)
-- =====================================================================

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
