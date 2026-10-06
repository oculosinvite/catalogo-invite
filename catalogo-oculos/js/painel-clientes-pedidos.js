// =====================================================================
//  PAINEL — ficha do cliente, cadastro manual e pedidos criados pela loja
// =====================================================================

const CAMPOS_CLIENTE = ['nome', 'email', 'telefone', 'cpf', 'data_nascimento', 'cep', 'endereco', 'numero',
                        'complemento', 'bairro', 'cidade', 'uf', 'observacoes'];
let fichaId = null;          // cliente aberto na ficha (null = novo)
let aoSalvarCliente = null;  // callback quando a ficha é usada a partir do "novo pedido"

async function garantirClientes() {
  if (!clientes.length) {
    const { data, error } = await sb.rpc('admin_listar_clientes');
    if (error) { toast(erro(error), 'erro'); return; }
    clientes = data;
  }
}

// ------------------------- ficha do cliente -------------------------
async function abrirFicha(id, aba = 'dados') {
  await garantirClientes();
  const c = id ? clientes.find(x => x.id === id) : null;
  if (id && !c) { await carregarClientes(); return abrirFicha(id, aba); }
  fichaId = id || null;
  const f = $('#formCliente');
  f.reset();
  CAMPOS_CLIENTE.forEach(k => f.elements[k].value = c?.[k] ?? '');
  f.ativo.checked = c ? !c.bloqueado : true;
  f.email.readOnly = !!c?.possui_login;
  f.email.title = c?.possui_login ? 'Cliente com login na loja: o e-mail é o login e não pode ser alterado aqui.' : '';
  $('#cliTitulo').textContent = c ? c.nome : 'Novo cliente';

  if (c) {
    const end = U.enderecoTexto(c), zap = U.linkZap(c.telefone);
    $('#cliResumo').innerHTML = `
      <div class="msg" style="margin-bottom:14px;display:grid;gap:4px;font-size:14px">
        <div><b>Endereço:</b> ${end ? esc(end) : '<span class="muted">não informado</span>'}</div>
        <div class="row-actions">
          ${end ? `<a class="btn btn-ghost btn-sm" href="${U.linkMapa(c)}" target="_blank" rel="noopener">Abrir no mapa</a>
                   <button type="button" class="btn btn-ghost btn-sm" data-copiar="${esc(end)}">Copiar endereço</button>` : ''}
          ${zap ? `<a class="btn btn-ghost btn-sm" href="${zap}" target="_blank" rel="noopener">WhatsApp</a>` : ''}
          ${c.email ? `<a class="btn btn-ghost btn-sm" href="mailto:${esc(c.email)}">E-mail</a>` : ''}
          <span class="muted" style="align-self:center">${c.possui_login ? 'Tem login na loja' : 'Sem login na loja'} · cliente desde ${new Date(c.criado_em).toLocaleDateString('pt-BR')} · ${c.pedidos_qtd || 0} pedido(s)</span>
        </div>
      </div>`;
  } else $('#cliResumo').innerHTML = '';

  $('#cliTabs').classList.toggle('hidden', !c);
  abaFicha(c ? aba : 'dados');
  if (!$('#dlgCliente').open) $('#dlgCliente').showModal();
  if (!c) f.nome.focus();
}

function abaFicha(aba) {
  $$('#cliTabs button').forEach(b => b.classList.toggle('on', b.dataset.tab === aba));
  $('#formCliente').classList.toggle('hidden', aba !== 'dados');
  $('#cliPedidos').classList.toggle('hidden', aba !== 'pedidos');
  if (aba === 'pedidos') carregarPedidosCliente();
}
$$('#cliTabs button').forEach(b => b.onclick = () => abaFicha(b.dataset.tab));
U.bindCep($('#formCliente'));

$('#formCliente').onsubmit = async e => {
  e.preventDefault();
  const f = e.target, dados = {};
  CAMPOS_CLIENTE.forEach(k => dados[k] = f.elements[k].value.trim());
  if (f.email.readOnly) delete dados.email;
  dados.ativo = f.ativo.checked ? 'Sim' : 'Não';
  const btn = $('#btnSalvarCli'); btn.disabled = true;
  const { data: id, error } = await sb.rpc('admin_salvar_cliente', { p_id: fichaId, p_dados: dados });
  btn.disabled = false;
  if (error) return toast(erro(error), 'erro');
  toast(fichaId ? 'Cliente atualizado' : 'Cliente cadastrado', 'ok');
  await carregarClientes();
  if (aoSalvarCliente) { const cb = aoSalvarCliente; aoSalvarCliente = null; $('#dlgCliente').close(); return cb(id); }
  abrirFicha(id);
};
$('#dlgCliente').addEventListener('close', () => { aoSalvarCliente = null; });

async function carregarPedidosCliente() {
  const box = $('#cliPedidos');
  box.innerHTML = '<p class="muted">Carregando…</p>';
  const { data: lista, error } = await sb.from('pedidos').select('*, itens_pedido(*)')
    .eq('cliente_id', fichaId).order('criado_em', { ascending: false });
  if (error) { box.innerHTML = `<p class="msg erro">${esc(erro(error))}</p>`; return; }
  const total = lista.filter(p => ['aprovado', 'enviado', 'entregue'].includes(p.status)).reduce((s, p) => s + Number(p.valor_total), 0);
  box.innerHTML = `
    <div class="main-head" style="margin-bottom:10px">
      <span class="muted">${lista.length} pedido(s) · comprado (aprovados): <b>${fmt(total)}</b></span>
      <button type="button" class="btn btn-accent btn-sm" data-novo-pedido-cli="${fichaId}">+ Novo pedido para este cliente</button>
    </div>
    ${lista.length ? lista.map(p => `
      <div class="pedido">
        <div class="pedido-top">
          <b>Pedido #${p.id}</b><span class="muted">${data(p.criado_em)}${p.origem === 'painel' ? ' · painel' : ' · loja'}</span>
          <span class="st st-${p.status}">${statusLabel(p.status)}</span><b>${fmt(p.valor_total)}</b>
        </div>
        <ul>${p.itens_pedido.map(i => `<li>${i.quantidade}x ${esc(i.descricao)} — ${fmt(i.preco_unitario)}</li>`).join('')}</ul>
        <div class="muted" style="font-size:13px">${esc(p.forma_pagamento || '')}${p.parcelas > 1 ? ` · ${p.parcelas}x de ${fmt(p.valor_parcela)}` : ''}${p.observacao ? ` · ${esc(p.observacao)}` : ''}</div>
      </div>`).join('') : '<p class="vazio">Nenhum pedido ainda.</p>'}`;
}

$('#btnNovoCliente').onclick = () => abrirFicha(null);

// ------------------------- escolher cliente -------------------------
let escolhaResolver = null;
function escolherCliente() {
  return new Promise(async res => {
    escolhaResolver = res;
    await garantirClientes();
    $('#escBusca').value = '';
    renderEscolha();
    $('#dlgEscolherCli').showModal();
    $('#escBusca').focus();
  });
}
function renderEscolha() {
  const b = norm($('#escBusca').value);
  const lista = clientes.filter(c => !b || norm([c.nome, c.email, c.telefone, c.cpf, c.cidade].join(' ')).includes(b)).slice(0, 60);
  $('#escLista').innerHTML = lista.length ? lista.map(c => `
    <button type="button" class="esc-item" data-escolher="${c.id}">
      <b>${esc(c.nome)}</b>${c.bloqueado ? ' <span class="st st-cancelado">inativo</span>' : ''}
      <small class="muted">${esc([c.telefone, c.email].filter(Boolean).join(' · ') || 'sem contato')}</small>
      <small class="muted">${esc(U.enderecoTexto(c) || 'sem endereço')}</small>
    </button>`).join('') : '<p class="muted">Nenhum cliente encontrado. Use “+ Novo”.</p>';
}
$('#escBusca').oninput = renderEscolha;
$('#escLista').onclick = e => {
  const b = e.target.closest('[data-escolher]'); if (!b) return;
  const r = escolhaResolver; escolhaResolver = null;
  $('#dlgEscolherCli').close();
  r?.(b.dataset.escolher);
};
$('#escNovo').onclick = () => {
  const r = escolhaResolver; escolhaResolver = null;
  $('#dlgEscolherCli').close();
  aoSalvarCliente = id => r?.(id);
  abrirFicha(null);
};
$('#dlgEscolherCli').addEventListener('close', () => { const r = escolhaResolver; escolhaResolver = null; r?.(null); });

// ------------------------- novo pedido pelo painel -------------------------
let np = { cliente: null, itens: [], cores: [] };

async function abrirNovoPedido(clienteId = null) {
  await Promise.all([garantirClientes(), carregarBase()]);
  const { data: prods, error } = await sb.from('produtos').select('id, nome, sku, ativo, preco_venda, preco_promocional, produto_cores(*)').order('nome');
  if (error) return toast(erro(error), 'erro');
  np = { cliente: clienteId, itens: [], cores: [] };
  prods.forEach(p => p.produto_cores.sort((a, b) => a.id - b.id).forEach(c => np.cores.push({
    id: c.id, produto: p.nome, cor: c.cor, sku: c.sku, estoque: c.estoque,
    ativo: p.ativo && c.ativo, preco: Number(p.preco_promocional ?? p.preco_venda) })));

  $('#npBusca').value = ''; $('#npQtd').value = 1; $('#npObs').value = ''; $('#npAprovar').checked = true;
  $('#npForma').innerHTML = '<option value="">A combinar (sem forma definida)</option>' +
    formas.filter(f => f.ativo).map(f => `<option value="${f.id}">${esc(f.nome)}</option>`).join('');
  $('#npParcelas').innerHTML = '';
  renderOpcoesCor(); renderNpCliente(); renderNpItens();
  if (!$('#dlgNovoPedido').open) $('#dlgNovoPedido').showModal();
}

function renderOpcoesCor() {
  const b = norm($('#npBusca').value);
  const lista = np.cores.filter(c => !b || norm([c.produto, c.cor, c.sku].join(' ')).includes(b));
  $('#npCor').innerHTML = lista.length ? lista.map(c => `<option value="${c.id}" ${c.estoque <= 0 ? 'disabled' : ''}>
      ${esc(c.produto)} — ${esc(c.cor)} · estoque ${c.estoque}${c.ativo ? '' : ' · inativo'} · ${fmt(c.preco)}</option>`).join('')
    : '<option value="">Nenhum produto encontrado</option>';
  const primeiro = lista.find(c => c.estoque > 0);
  if (primeiro) $('#npCor').value = primeiro.id;
  atualizarPrecoSugerido();
}
function atualizarPrecoSugerido() {
  const c = np.cores.find(x => x.id === Number($('#npCor').value));
  $('#npPreco').value = c ? c.preco.toFixed(2) : '';
}
$('#npBusca').oninput = renderOpcoesCor;
$('#npCor').onchange = atualizarPrecoSugerido;

$('#npAdd').onclick = () => {
  const c = np.cores.find(x => x.id === Number($('#npCor').value));
  if (!c) return toast('Escolha um produto', 'erro');
  const qtd = Math.max(1, parseInt($('#npQtd').value, 10) || 1);
  const preco = $('#npPreco').value === '' ? c.preco : Number($('#npPreco').value);
  const ja = np.itens.find(i => i.cor_id === c.id && i.preco === preco);
  const totalQtd = np.itens.filter(i => i.cor_id === c.id).reduce((s, i) => s + i.quantidade, 0) + qtd;
  if (totalQtd > c.estoque) return toast(`Estoque de ${c.produto} — ${c.cor}: ${c.estoque} unidade(s)`, 'erro');
  if (ja) ja.quantidade += qtd;
  else np.itens.push({ cor_id: c.id, nome: `${c.produto} — ${c.cor}`, sku: c.sku, quantidade: qtd, preco, tabela: c.preco });
  $('#npQtd').value = 1;
  renderNpItens();
};

function renderNpCliente() {
  const c = clientes.find(x => x.id === np.cliente);
  $('#npCliente').innerHTML = c ? `
    <div style="color:var(--ink);display:grid;gap:2px">
      <b>${esc(c.nome)}</b>${c.bloqueado ? ' <span class="st st-cancelado">inativo</span>' : ''}
      <span style="font-size:14px">${esc([c.telefone, c.email].filter(Boolean).join(' · ') || 'sem contato')}</span>
      <span class="muted" style="font-size:13px">${esc(U.enderecoTexto(c) || 'Sem endereço cadastrado')}</span>
    </div>` : 'Nenhum cliente escolhido.';
}

function renderNpItens() {
  $('#npItens').innerHTML = np.itens.length ? `
    <thead><tr><th>Produto</th><th class="num">Qtd</th><th class="num">Preço unit.</th><th class="num">Total</th><th></th></tr></thead>
    <tbody>${np.itens.map((i, n) => `<tr>
      <td>${esc(i.nome)}<br><small class="muted">${esc(i.sku)}${i.preco !== i.tabela ? ` · tabela ${fmt(i.tabela)}` : ''}</small></td>
      <td class="num"><input type="number" min="1" value="${i.quantidade}" data-np-qtd="${n}" style="width:70px"></td>
      <td class="num"><input type="number" min="0" step="0.01" value="${i.preco.toFixed(2)}" data-np-preco="${n}" style="width:100px"></td>
      <td class="num">${fmt(i.preco * i.quantidade)}</td>
      <td><button type="button" class="x" data-np-rm="${n}" title="Remover">&times;</button></td>
    </tr>`).join('')}</tbody>` : '<tr><td class="muted">Nenhum produto adicionado.</td></tr>';
  renderNpPagamento();
}
$('#npItens').addEventListener('change', e => {
  const q = e.target.closest('[data-np-qtd]'), p = e.target.closest('[data-np-preco]');
  if (q) np.itens[q.dataset.npQtd].quantidade = Math.max(1, parseInt(q.value, 10) || 1);
  if (p) np.itens[p.dataset.npPreco].preco = Math.max(0, Number(p.value) || 0);
  renderNpItens();
});
$('#npItens').addEventListener('click', e => {
  const r = e.target.closest('[data-np-rm]'); if (!r) return;
  np.itens.splice(Number(r.dataset.npRm), 1); renderNpItens();
});

function renderNpPagamento() {
  const subtotal = np.itens.reduce((s, i) => s + i.preco * i.quantidade, 0);
  const f = formas.find(x => x.id === Number($('#npForma').value));
  const sel = $('#npParcelas');
  if (!f) {
    $('#npLblParc').classList.add('hidden');
    $('#npResumo').innerHTML = `<div class="total-row"><span>Total</span><span>${fmt(subtotal)}</span></div>`;
    return;
  }
  const max = U.maxParcelas(subtotal || 1, f), atual = Math.min(Number(sel.value) || 1, max);
  sel.innerHTML = Array.from({ length: max }, (_, k) => {
    const c = U.calcPagamento(subtotal, f, k + 1);
    return `<option value="${k + 1}">${k ? `${k + 1}x` : 'À vista'} de ${fmt(c.parcela)}${c.semJuros ? (k ? ' sem juros' : '') : ` (total ${fmt(c.total)})`}</option>`;
  }).join('');
  sel.value = atual;
  $('#npLblParc').classList.toggle('hidden', max <= 1);
  const c = U.calcPagamento(subtotal, f, atual);
  $('#npResumo').innerHTML = `
    <div class="resumo-linha"><span>Subtotal</span><span>${fmt(subtotal)}</span></div>
    ${c.desconto ? `<div class="resumo-linha ok"><span>Desconto ${esc(f.nome)}</span><span>− ${fmt(c.desconto)}</span></div>` : ''}
    ${c.juros ? `<div class="resumo-linha"><span>Juros do parcelamento</span><span>+ ${fmt(c.juros)}</span></div>` : ''}
    <div class="total-row"><span>Total</span><span>${fmt(c.total)}${atual > 1 ? ` <small class="muted" style="font-size:13px">(${atual}x de ${fmt(c.parcela)})</small>` : ''}</span></div>`;
}
$('#npForma').onchange = () => { $('#npParcelas').value = 1; renderNpPagamento(); };
$('#npParcelas').onchange = renderNpPagamento;

$('#npEscolher').onclick = async () => {
  const id = await escolherCliente();
  if (id) { np.cliente = id; renderNpCliente(); }
};
$('#npNovoCli').onclick = () => {
  aoSalvarCliente = id => { np.cliente = id; renderNpCliente(); };
  abrirFicha(null);
};

$('#npCriar').onclick = async () => {
  if (!np.cliente) return toast('Escolha o cliente do pedido', 'erro');
  if (!np.itens.length) return toast('Adicione pelo menos um produto', 'erro');
  const aprovar = $('#npAprovar').checked;
  const btn = $('#npCriar'); btn.disabled = true; btn.textContent = 'Criando…';
  const { data: id, error } = await sb.rpc('admin_criar_pedido', {
    p_cliente: np.cliente,
    p_itens: np.itens.map(i => ({ cor_id: i.cor_id, quantidade: i.quantidade, preco: i.preco })),
    p_observacao: $('#npObs').value,
    p_forma_id: $('#npForma').value ? Number($('#npForma').value) : null,
    p_parcelas: Number($('#npParcelas').value) || 1,
    p_aprovar: aprovar,
  });
  btn.disabled = false; btn.textContent = 'Criar pedido';
  if (error) return toast(erro(error), 'erro');
  $('#dlgNovoPedido').close();
  toast(`Pedido #${id} criado${aprovar ? ' e aprovado' : ''}`, 'ok');
  $('#fStatus').value = aprovar ? 'aprovado' : 'pendente';
  abertos.add(id);
  abrirSecao('pedidos');
  clientes = []; // força recarregar contagem de pedidos
};

$('#btnNovoPedido').onclick = () => abrirNovoPedido();

// ------------------------- botões espalhados pelo painel -------------------------
document.addEventListener('click', async e => {
  const fi = e.target.closest('[data-ficha]');
  if (fi) return abrirFicha(fi.dataset.ficha);
  const np2 = e.target.closest('[data-novo-pedido-cli]');
  if (np2) { $('#dlgCliente').close(); return abrirNovoPedido(np2.dataset.novoPedidoCli); }
  const cp = e.target.closest('[data-copiar]');
  if (cp) { try { await navigator.clipboard.writeText(cp.dataset.copiar); toast('Endereço copiado', 'ok'); } catch { prompt('Copie o endereço:', cp.dataset.copiar); } return; }
  const tr = e.target.closest('[data-trocar-cli]');
  if (tr) {
    const novo = await escolherCliente(); if (!novo) return;
    const nome = clientes.find(c => c.id === novo)?.nome;
    if (!confirm(`Trocar o cliente do pedido #${tr.dataset.trocarCli} para "${nome}"?\nO endereço de entrega também será trocado.`)) return;
    const { error } = await sb.rpc('admin_trocar_cliente_pedido', { p_pedido_id: Number(tr.dataset.trocarCli), p_cliente: novo });
    if (error) return toast(erro(error), 'erro');
    toast('Cliente do pedido atualizado', 'ok'); carregarPedidos();
  }
});
