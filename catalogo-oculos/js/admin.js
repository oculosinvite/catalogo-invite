// =====================================================================
//  PAINEL ADMINISTRATIVO
// =====================================================================
const { $, $$, fmt, esc, hex, norm, img, erro, toast, data, statusLabel } = U;
const CFG = window.APP_CONFIG;

let categorias = [], marcas = [], produtos = [], clientes = [], opcoes = [], formas = [];
let editId = null, coresEdit = [], fotoArquivo = null;
const abertos = new Set(); // pedidos expandidos

// ------------------------- acesso -------------------------
async function verificarAcesso() {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) return mostrarLogin();
  const { data: ok, error } = await sb.rpc('is_admin');
  if (error || !ok) {
    await sb.auth.signOut();
    return mostrarLogin('Esta conta não tem acesso ao painel. Peça para liberar como administrador.');
  }
  $('#adminEmail').textContent = session.user.email;
  $('#telaLogin').classList.add('hidden');
  $('#telaPainel').classList.remove('hidden');
  await carregarBase();
  abrirSecao('dashboard');
}

function mostrarLogin(msg) {
  $('#telaPainel').classList.add('hidden');
  $('#telaLogin').classList.remove('hidden');
  const m = $('#loginMsg'); m.textContent = msg || ''; m.classList.toggle('hidden', !msg);
}

$('#formLogin').onsubmit = async e => {
  e.preventDefault();
  const f = e.target;
  const { error } = await sb.auth.signInWithPassword({ email: f.email.value.trim(), password: f.senha.value });
  if (error) return mostrarLogin(erro(error));
  verificarAcesso();
};
$('#btnSair').onclick = async () => { await sb.auth.signOut(); mostrarLogin(); };

// ------------------------- navegação -------------------------
const carregadores = {
  dashboard: carregarDashboard, pedidos: carregarPedidos, produtos: carregarProdutos,
  estoque: carregarEstoque, categorias: renderCategorias, clientes: carregarClientes, config: carregarConfig,
};
function abrirSecao(sec) {
  $$('.side [data-sec]').forEach(b => b.classList.toggle('on', b.dataset.sec === sec));
  $$('[data-pane]').forEach(p => p.classList.toggle('hidden', p.dataset.pane !== sec));
  carregadores[sec]();
}
$$('.side [data-sec]').forEach(b => b.onclick = () => abrirSecao(b.dataset.sec));
$$('[data-reload]').forEach(b => b.onclick = () => carregadores[b.dataset.reload]());

async function carregarBase() {
  const [c, m, o, fp] = await Promise.all([
    sb.from('categorias').select('*').order('ordem').order('nome'),
    sb.from('marcas').select('*').order('nome'),
    sb.from('opcoes').select('*').order('ordem').order('nome'),
    sb.from('formas_pagamento').select('*').order('ordem').order('nome'),
  ]);
  categorias = c.data || []; marcas = m.data || []; opcoes = o.data || []; formas = fp.data || [];
  atualizarPillPendentes();
}

async function atualizarPillPendentes() {
  const { count } = await sb.from('pedidos').select('id', { count: 'exact', head: true }).eq('status', 'pendente');
  $('#pillPendentes').textContent = count || '';
}

// ------------------------- resumo -------------------------
async function carregarDashboard() {
  const { data: r, error } = await sb.rpc('admin_resumo');
  if (error) return toast(erro(error), 'erro');
  const lucro = r.faturamento_mes - r.custo_mes;
  const margem = r.faturamento_mes ? (lucro / r.faturamento_mes * 100).toFixed(1) + '%' : '—';
  const k = [
    ['Pedidos aguardando', r.pendentes], ['Vendas no mês', r.pedidos_mes],
    ['Faturamento no mês', fmt(r.faturamento_mes)], ['Lucro bruto no mês', fmt(lucro)],
    ['Margem no mês', margem], ['Peças em estoque', r.pecas_estoque],
    ['Estoque (a custo)', fmt(r.valor_estoque_custo)], ['Estoque (a preço de venda)', fmt(r.valor_estoque_venda)],
    ['Clientes cadastrados', r.clientes],
  ];
  $('#kpis').innerHTML = k.map(([t, v]) => `<div class="kpi"><small>${t}</small><b>${v}</b></div>`).join('');
  $('#dashTop').innerHTML = r.mais_vendidos.length
    ? '<table class="tbl">' + r.mais_vendidos.map(x => `<tr><td>${esc(x.descricao)}</td><td class="num">${x.qtd} un.</td></tr>`).join('') + '</table>'
    : '<p class="muted">Ainda sem vendas aprovadas.</p>';

  const { data: baixo } = await sb.from('produto_cores').select('cor, estoque, estoque_minimo, sku, produtos(nome)').eq('ativo', true).order('estoque');
  const lista = (baixo || []).filter(c => c.estoque <= c.estoque_minimo);
  $('#dashBaixo').innerHTML = lista.length
    ? '<table class="tbl">' + lista.map(c => `<tr><td>${esc(c.produtos?.nome)} — ${esc(c.cor)}<br><small class="muted">${esc(c.sku)}</small></td><td class="num baixo">${c.estoque}</td></tr>`).join('') + '</table>'
    : '<p class="muted">Tudo certo com o estoque. 👍</p>';
  atualizarPillPendentes();
}

// ------------------------- pedidos -------------------------
$('#fStatus').onchange = carregarPedidos;

async function carregarPedidos() {
  const st = $('#fStatus').value;
  let q = sb.from('pedidos').select('*, clientes(nome, email, telefone, cpf), itens_pedido(*)').order('criado_em', { ascending: false }).limit(200);
  if (st) q = q.eq('status', st);
  const { data: lista, error } = await q;
  if (error) return toast(erro(error), 'erro');
  atualizarPillPendentes();

  if (!lista.length) { $('#tblPedidos').innerHTML = '<tr><td class="vazio">Nenhum pedido aqui.</td></tr>'; return; }
  $('#tblPedidos').innerHTML = `
    <thead><tr><th>#</th><th>Data</th><th>Cliente</th><th>Itens</th><th class="num">Total</th><th class="num">Lucro</th><th>Status</th><th></th></tr></thead>
    <tbody>${lista.map(p => {
      const custo = p.itens_pedido.reduce((s, i) => s + i.preco_custo * i.quantidade, 0);
      const pecas = p.itens_pedido.reduce((s, i) => s + i.quantidade, 0);
      const end = p.endereco_entrega || {};
      const zap = (p.clientes?.telefone || '').replace(/\D/g, '');
      return `
      <tr>
        <td><b>${p.id}</b></td>
        <td>${data(p.criado_em)}</td>
        <td>${esc(p.clientes?.nome)}<br><small class="muted">${esc(p.clientes?.email)}</small></td>
        <td>${pecas} peça(s)</td>
        <td class="num"><b>${fmt(p.valor_total)}</b></td>
        <td class="num">${fmt(p.valor_total - custo)}</td>
        <td><span class="st st-${p.status}">${statusLabel(p.status)}</span></td>
        <td><button class="btn btn-ghost btn-sm" data-ver="${p.id}">${abertos.has(p.id) ? 'Fechar' : 'Detalhes'}</button></td>
      </tr>
      <tr class="det ${abertos.has(p.id) ? '' : 'hidden'}" data-det="${p.id}"><td colspan="8">
        <div class="det-grid">
          <div>
            <table class="tbl" style="background:#fff;border:1px solid var(--line);border-radius:10px">
              <tr><th>Item</th><th class="num">Qtd</th><th class="num">Custo</th><th class="num">Venda</th><th class="num">Margem</th></tr>
              ${p.itens_pedido.map(i => `<tr><td>${esc(i.descricao)}</td><td class="num">${i.quantidade}</td>
                <td class="num">${fmt(i.preco_custo)}</td><td class="num">${fmt(i.preco_unitario)}</td>
                <td class="num">${i.preco_unitario ? ((1 - i.preco_custo / i.preco_unitario) * 100).toFixed(0) + '%' : '—'}</td></tr>`).join('')}
            </table>
            ${p.observacao ? `<p class="msg" style="margin-top:10px"><b>Obs. do cliente:</b> ${esc(p.observacao)}</p>` : ''}
            ${p.motivo_recusa ? `<p class="msg erro" style="margin-top:10px"><b>Motivo:</b> ${esc(p.motivo_recusa)}</p>` : ''}
          </div>
          <div style="font-size:14px;display:grid;gap:4px">
            <b>Entrega</b>
            <span>${esc(end.endereco || '')} ${esc(end.numero || '')} ${esc(end.complemento || '')}</span>
            <span>${esc(end.bairro || '')} — ${esc(end.cidade || '')}/${esc(end.uf || '')} ${esc(end.cep || '')}</span>
            <span>Tel.: ${esc(p.clientes?.telefone || '—')} ${zap ? `· <a href="https://wa.me/55${zap.replace(/^55/, '')}" target="_blank" rel="noopener">WhatsApp</a>` : ''}</span>
            <span>CPF: ${esc(p.clientes?.cpf || '—')}</span>
            <span>Pagamento: <b>${esc(p.forma_pagamento || '—')}${p.parcelas > 1 ? ` · ${p.parcelas}x de ${fmt(p.valor_parcela)}` : ''}</b></span>
            ${Number(p.desconto) || Number(p.juros) ? `<span>Subtotal ${fmt(p.subtotal)}${Number(p.desconto) ? ` · desconto −${fmt(p.desconto)}` : ''}${Number(p.juros) ? ` · juros +${fmt(p.juros)}` : ''}</span>` : ''}
            ${p.codigo_rastreio ? `<span>Rastreio: <b>${esc(p.codigo_rastreio)}</b></span>` : ''}
            ${p.aprovado_em ? `<span class="muted">Aprovado em ${data(p.aprovado_em)}</span>` : ''}
            <div class="row-actions" style="margin-top:10px">${acoesPedido(p)}</div>
          </div>
        </div>
      </td></tr>`;
    }).join('')}</tbody>`;
}

function acoesPedido(p) {
  const b = (acao, txt, cls) => `<button class="btn btn-sm ${cls}" data-acao="${acao}" data-id="${p.id}">${txt}</button>`;
  switch (p.status) {
    case 'pendente': return b('aprovar', '✓ Aprovar e baixar estoque', 'btn-ok') + b('recusar', 'Recusar', 'btn-bad');
    case 'aprovado': return b('enviar', 'Marcar como enviado', '') + b('entregar', 'Entregue', 'btn-ghost') + b('cancelar', 'Cancelar (devolve estoque)', 'btn-bad');
    case 'enviado':  return b('entregar', 'Marcar como entregue', 'btn-ok') + b('cancelar', 'Cancelar (devolve estoque)', 'btn-bad');
    default: return '';
  }
}

$('#tblPedidos').addEventListener('click', async e => {
  const ver = e.target.closest('[data-ver]');
  if (ver) {
    const id = Number(ver.dataset.ver);
    abertos.has(id) ? abertos.delete(id) : abertos.add(id);
    $(`[data-det="${id}"]`).classList.toggle('hidden');
    ver.textContent = abertos.has(id) ? 'Fechar' : 'Detalhes';
    return;
  }
  const a = e.target.closest('[data-acao]'); if (!a) return;
  const id = Number(a.dataset.id);
  let res;
  if (a.dataset.acao === 'aprovar') {
    if (!confirm(`Aprovar o pedido #${id}? O estoque será baixado.`)) return;
    res = await sb.rpc('aprovar_pedido', { p_pedido_id: id });
  } else if (a.dataset.acao === 'recusar') {
    const motivo = prompt('Motivo da recusa (o cliente verá esta mensagem):');
    if (motivo === null) return;
    res = await sb.rpc('recusar_pedido', { p_pedido_id: id, p_motivo: motivo });
  } else if (a.dataset.acao === 'enviar') {
    const rastreio = prompt('Código de rastreio (opcional):', '');
    if (rastreio === null) return;
    res = await sb.rpc('atualizar_status_pedido', { p_pedido_id: id, p_status: 'enviado', p_rastreio: rastreio });
  } else if (a.dataset.acao === 'entregar') {
    res = await sb.rpc('atualizar_status_pedido', { p_pedido_id: id, p_status: 'entregue' });
  } else if (a.dataset.acao === 'cancelar') {
    const motivo = prompt('Motivo do cancelamento:');
    if (motivo === null) return;
    res = await sb.rpc('cancelar_pedido', { p_pedido_id: id, p_motivo: motivo });
  }
  if (res.error) return toast(erro(res.error), 'erro');
  toast(`Pedido #${id} atualizado`, 'ok');
  carregarPedidos();
});

// ------------------------- inativar / excluir (todas as telas) -------------------------
const badgeStatus = ativo => ativo ? '<span class="st st-entregue">Ativo</span>' : '<span class="st st-cancelado">Inativo</span>';
const botoesStatus = (tipo, id, ativo) => `<div class="acoes">
  <button class="btn btn-ghost btn-sm" data-toggle="${tipo}" data-id="${id}" data-v="${!ativo}">${ativo ? 'Inativar' : 'Ativar'}</button>
  <button class="btn btn-bad btn-sm" data-excluir="${tipo}" data-id="${id}">Excluir</button></div>`;

const CADASTROS = {
  produtos:   { nome: id => produtos.find(x => x.id === id)?.nome, recarregar: () => carregarProdutos(),
                aviso: 'As fotos, cores e o histórico de estoque deste produto também serão apagados.' },
  categorias: { nome: id => categorias.find(x => x.id === id)?.nome, recarregar: async () => { await carregarBase(); renderCategorias(); },
                aviso: 'Os produtos desta categoria ficarão "sem categoria".' },
  marcas:     { nome: id => marcas.find(x => x.id === id)?.nome, recarregar: async () => { await carregarBase(); renderCategorias(); },
                aviso: 'Os produtos desta marca ficarão "sem marca".' },
  opcoes:     { nome: id => opcoes.find(x => x.id === id)?.nome, recarregar: async () => { await carregarBase(); renderCategorias(); },
                aviso: 'Os produtos que usam esta opção continuam com o valor gravado.' },
  formas_pagamento: { nome: id => formas.find(x => x.id === id)?.nome, recarregar: async () => { await carregarBase(); renderFormas(); },
                aviso: 'Pedidos antigos continuam mostrando esta forma de pagamento.' },
  clientes:   { nome: id => clientes.find(x => x.id === id)?.nome, recarregar: () => carregarClientes(),
                aviso: 'O login do cliente também será apagado.' },
};

document.addEventListener('click', async e => {
  const t = e.target.closest('[data-toggle]');
  if (t) {
    const tipo = t.dataset.toggle, ativar = t.dataset.v === 'true';
    const id = tipo === 'clientes' ? t.dataset.id : Number(t.dataset.id);
    const nome = CADASTROS[tipo].nome(id);
    if (!ativar && !confirm(`Inativar "${nome}"?\n\n` + (tipo === 'clientes'
        ? 'O cliente continua cadastrado, mas não consegue fazer novos pedidos.'
        : 'Ele deixa de aparecer na loja, mas continua salvo e pode ser reativado.'))) return;
    const dados = tipo === 'clientes' ? { bloqueado: !ativar } : { ativo: ativar };
    const { error } = await sb.from(tipo).update(dados).eq('id', id);
    if (error) return toast(erro(error), 'erro');
    toast(`"${nome}" ${ativar ? 'ativado' : 'inativado'}`, 'ok');
    return CADASTROS[tipo].recarregar();
  }
  const x = e.target.closest('[data-excluir]');
  if (x) {
    const tipo = x.dataset.excluir;
    const id = tipo === 'clientes' ? x.dataset.id : Number(x.dataset.id);
    const nome = CADASTROS[tipo].nome(id);
    if (!confirm(`EXCLUIR definitivamente "${nome}"?\n\n${CADASTROS[tipo].aviso}\nEsta ação não pode ser desfeita.`)) return;
    const { error } = tipo === 'clientes'
      ? await sb.rpc('admin_excluir_cliente', { p_id: id })
      : await sb.from(tipo).delete().eq('id', id);
    if (error) return toast(erro(error), 'erro');
    toast(`"${nome}" excluído`, 'ok');
    return CADASTROS[tipo].recarregar();
  }
});

// ------------------------- produtos -------------------------
$('#fStatusProd').onchange = renderProdutos;
$('#buscaProd').oninput = renderProdutos;
$('#btnNovoProd').onclick = () => abrirProduto(null);

async function carregarProdutos() {
  const { data: lista, error } = await sb.from('produtos')
    .select('*, produto_cores(*), categorias(nome), marcas(nome)').order('nome');
  if (error) return toast(erro(error), 'erro');
  produtos = lista;
  renderProdutos();
}

function renderProdutos() {
  const b = norm($('#buscaProd').value);
  const st = $('#fStatusProd').value;
  const lista = produtos.filter(p => (!st || String(p.ativo) === st) && (!b || norm([p.nome, p.sku, p.categorias?.nome, p.marcas?.nome].join(' ')).includes(b)));
  if (!lista.length) { $('#tblProdutos').innerHTML = '<tr><td class="vazio">Nenhum produto encontrado.</td></tr>'; return; }
  $('#tblProdutos').innerHTML = `
    <thead><tr><th></th><th>Produto</th><th>Categoria</th><th>Cores</th><th class="num">Custo</th><th class="num">Venda</th><th class="num">Margem</th><th class="num">Estoque</th><th>Status</th><th></th></tr></thead>
    <tbody>${lista.map(p => {
      const venda = p.preco_promocional ?? p.preco_venda;
      const estoque = p.produto_cores.reduce((s, c) => s + c.estoque, 0);
      const margem = venda ? ((venda - p.preco_custo) / venda * 100).toFixed(0) + '%' : '—';
      const foto = p.imagem_url || p.produto_cores.find(c => c.imagem_url)?.imagem_url;
      return `<tr>
        <td><img class="thumb" src="${esc(img(foto))}" alt=""></td>
        <td><b>${esc(p.nome)}</b><br><small class="muted">${esc(p.sku)}${p.marcas ? ' · ' + esc(p.marcas.nome) : ''}</small></td>
        <td>${esc(p.categorias?.nome || '—')}</td>
        <td><div class="dots">${p.produto_cores.map(c => `<span class="dot" style="background:${hex(c.cor_hex)};${c.ativo ? '' : 'opacity:.3'}" title="${esc(c.cor)}: ${c.estoque}"></span>`).join('')}</div></td>
        <td class="num">${fmt(p.preco_custo)}</td>
        <td class="num">${p.preco_promocional != null ? `<s class="muted">${fmt(p.preco_venda)}</s><br>` : ''}${fmt(venda)}</td>
        <td class="num">${margem}</td>
        <td class="num ${estoque === 0 ? 'baixo' : ''}">${estoque}</td>
        <td>${badgeStatus(p.ativo)}${p.destaque ? ' ⭐' : ''}</td>
        <td><div class="acoes"><button class="btn btn-sm" data-edit="${p.id}">Editar</button>${botoesStatus('produtos', p.id, p.ativo)}</div></td>
      </tr>`;
    }).join('')}</tbody>`;
}
$('#tblProdutos').addEventListener('click', e => {
  const b = e.target.closest('[data-edit]'); if (b) abrirProduto(Number(b.dataset.edit));
});

// Lista de opções (Formato, Materiais, Tipo de lente) + "Cadastrar nova..."
function preencherOpcoes(sel, atual) {
  const lista = opcoes.filter(o => o.tipo === sel.dataset.opcao && (o.ativo || o.nome === atual));
  const extra = atual && !lista.some(o => o.nome === atual) ? [{ nome: atual }] : [];
  sel.innerHTML = '<option value="">— selecione —</option>' +
    [...lista, ...extra].map(o => `<option>${esc(o.nome)}</option>`).join('') +
    '<option value="__novo">+ Cadastrar nova opção…</option>';
  sel.value = atual || '';
  sel.dataset.anterior = sel.value;
}
$('#formProduto').addEventListener('change', async e => {
  const sel = e.target.closest('[data-opcao]'); if (!sel) return;
  if (sel.value !== '__novo') { sel.dataset.anterior = sel.value; return; }
  const titulo = sel.closest('label').firstChild.textContent.trim();
  const nome = (prompt(`Nova opção para "${titulo}":`) || '').trim();
  if (!nome) { sel.value = sel.dataset.anterior || ''; return; }
  const existe = opcoes.find(o => o.tipo === sel.dataset.opcao && norm(o.nome) === norm(nome));
  if (!existe) {
    const ordem = Math.max(0, ...opcoes.filter(o => o.tipo === sel.dataset.opcao).map(o => o.ordem)) + 1;
    const { error } = await sb.from('opcoes').insert({ tipo: sel.dataset.opcao, nome, ordem });
    if (error) { sel.value = sel.dataset.anterior || ''; return toast(erro(error), 'erro'); }
    await carregarBase();
    toast(`"${nome}" cadastrado em ${titulo}`, 'ok');
  }
  preencherOpcoes(sel, existe ? existe.nome : nome);
});

function abrirProduto(id) {
  const f = $('#formProduto');
  f.reset();
  editId = id; fotoArquivo = null;
  const p = id ? produtos.find(x => x.id === id) : null;

  f.categoria_id.innerHTML = '<option value="">— sem categoria —</option>' + categorias.map(c => `<option value="${c.id}">${esc(c.nome)}${c.ativo ? '' : ' (inativa)'}</option>`).join('');
  f.marca_id.innerHTML = '<option value="">— sem marca —</option>' + marcas.map(m => `<option value="${m.id}">${esc(m.nome)}${m.ativo ? '' : ' (inativa)'}</option>`).join('');
  $$('[data-opcao]', f).forEach(sel => preencherOpcoes(sel, p?.[sel.name]));

  $('#tituloProduto').textContent = p ? `Editar: ${p.nome}` : 'Novo produto';
  const campos = ['nome', 'sku', 'categoria_id', 'marca_id', 'genero', 'descricao', 'formato', 'material_armacao', 'material_lente',
    'tipo_lente', 'protecao_uv', 'largura_lente_mm', 'ponte_mm', 'haste_mm', 'altura_lente_mm', 'peso_g', 'garantia_meses',
    'ncm', 'preco_custo', 'preco_venda', 'preco_promocional'];
  if (p) {
    campos.forEach(k => f[k].value = p[k] ?? '');
    f.polarizado.checked = p.polarizado; f.destaque.checked = p.destaque; f.ativo.checked = p.ativo;
    coresEdit = p.produto_cores.sort((a, b) => a.id - b.id).map(c => ({ ...c }));
  } else {
    f.protecao_uv.value = 'UV400'; f.garantia_meses.value = 3; f.ativo.checked = true; f.preco_custo.value = 0;
    coresEdit = [{ cor: '', cor_hex: '#222222', cor_lente: '', sku: '', estoque: 0, estoque_minimo: 2, ativo: true }];
  }
  $('#fotoPrev').src = img(p?.imagem_url);
  renderCores(); calcMargem();
  $('#dlgProduto').showModal();
}

function renderCores() {
  $('#coresBody').innerHTML = coresEdit.map((c, i) => `
    <tr data-i="${i}">
      <td><input type="color" data-k="cor_hex" value="${hex(c.cor_hex)}"></td>
      <td><input data-k="cor" value="${esc(c.cor)}" placeholder="Ex.: Preto fosco" style="min-width:120px"></td>
      <td><input data-k="cor_lente" value="${esc(c.cor_lente || '')}" placeholder="Ex.: G15" style="min-width:100px"></td>
      <td><input data-k="sku" value="${esc(c.sku)}" placeholder="${esc(($('#formProduto').sku.value || 'SKU') + '-' + (i + 1))}" style="min-width:120px"></td>
      <td><input data-k="estoque" type="number" min="0" value="${c.estoque}" style="width:80px" ${c.id ? 'disabled title="Ajuste pela aba Estoque"' : ''}></td>
      <td><input data-k="estoque_minimo" type="number" min="0" value="${c.estoque_minimo}" style="width:64px"></td>
      <td><div style="display:flex;gap:6px;align-items:center">
        <img class="mini-img" src="${esc(c._preview || img(c.imagem_url))}" alt="">
        <input type="file" data-foto accept="image/*" style="width:190px;padding:4px">
      </div></td>
      <td><input type="checkbox" data-k="ativo" ${c.ativo ? 'checked' : ''}></td>
      <td><button type="button" class="x" data-rmcor title="Excluir esta cor" style="color:var(--bad)">&times;</button></td>
    </tr>`).join('');
}

$('#coresBody').addEventListener('input', e => {
  const tr = e.target.closest('[data-i]'); if (!tr) return;
  const c = coresEdit[Number(tr.dataset.i)], k = e.target.dataset.k;
  if (k) c[k] = e.target.type === 'checkbox' ? e.target.checked : e.target.type === 'number' ? Number(e.target.value) : e.target.value;
});
$('#coresBody').addEventListener('change', e => {
  if (!e.target.matches('[data-foto]')) return;
  const c = coresEdit[Number(e.target.closest('[data-i]').dataset.i)];
  c._file = e.target.files[0];
  if (c._file) { c._preview = URL.createObjectURL(c._file); e.target.previousElementSibling.src = c._preview; }
});
$('#coresBody').addEventListener('click', async e => {
  if (!e.target.closest('[data-rmcor]')) return;
  const i = Number(e.target.closest('[data-i]').dataset.i), c = coresEdit[i];
  if (c.id) {
    if (!confirm(`Excluir a cor "${c.cor}" deste produto?\nO estoque e o histórico dessa cor serão apagados.\n\nSe ela já foi vendida, não será possível excluir — desmarque "Ativa" para escondê-la.`)) return;
    const { error } = await sb.from('produto_cores').delete().eq('id', c.id);
    if (error) return toast(erro(error), 'erro');
    toast(`Cor "${c.cor}" excluída`, 'ok');
    carregarProdutos();
  }
  coresEdit.splice(i, 1); renderCores();
});
$('#btnAddCor').onclick = () => {
  coresEdit.push({ cor: '', cor_hex: '#222222', cor_lente: '', sku: '', estoque: 0, estoque_minimo: 2, ativo: true });
  renderCores();
};

$('#formProduto').foto.onchange = e => {
  fotoArquivo = e.target.files[0] || null;
  if (fotoArquivo) $('#fotoPrev').src = URL.createObjectURL(fotoArquivo);
};
['preco_custo', 'preco_venda', 'preco_promocional'].forEach(k => $('#formProduto')[k].addEventListener('input', calcMargem));

function calcMargem() {
  const f = $('#formProduto');
  const custo = Number(f.preco_custo.value) || 0;
  const venda = Number(f.preco_promocional.value) || Number(f.preco_venda.value) || 0;
  if (!venda) { $('#margemInfo').textContent = 'Informe custo e venda para ver a margem.'; return; }
  const lucro = venda - custo;
  $('#margemInfo').innerHTML = `Vendendo a <b>${fmt(venda)}</b>: lucro bruto de <b>${fmt(lucro)}</b> por peça · margem <b>${(lucro / venda * 100).toFixed(1)}%</b>` +
    (custo ? ` · markup <b>${(venda / custo).toFixed(2)}x</b>` : '');
}

async function uploadFoto(file, prefixo) {
  const ext = (file.name.split('.').pop() || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '');
  const caminho = `${prefixo}-${Date.now()}-${Math.random().toString(36).slice(2, 7)}.${ext}`;
  const { error } = await sb.storage.from('produtos').upload(caminho, file, { cacheControl: '31536000', contentType: file.type });
  if (error) throw error;
  return sb.storage.from('produtos').getPublicUrl(caminho).data.publicUrl;
}

$('#formProduto').onsubmit = async e => {
  e.preventDefault();
  const f = e.target, btn = $('#btnSalvarProd');
  const num = v => v === '' || v == null ? null : Number(v);
  const txt = v => (v || '').trim() || null;

  const cores = coresEdit.map((c, i) => ({ ...c, cor: (c.cor || '').trim(), sku: (c.sku || '').trim() || `${f.sku.value.trim()}-${i + 1}` }));
  if (!cores.length) return toast('Cadastre pelo menos uma cor', 'erro');
  if (cores.some(c => !c.cor)) return toast('Preencha o nome de todas as cores', 'erro');
  const promo = num(f.preco_promocional.value);
  if (promo != null && promo >= Number(f.preco_venda.value)) return toast('O preço promocional deve ser menor que o preço de venda', 'erro');

  const payload = {
    nome: f.nome.value.trim(), sku: f.sku.value.trim(), descricao: txt(f.descricao.value),
    categoria_id: num(f.categoria_id.value), marca_id: num(f.marca_id.value), genero: f.genero.value,
    formato: txt(f.formato.value), material_armacao: txt(f.material_armacao.value), material_lente: txt(f.material_lente.value),
    tipo_lente: txt(f.tipo_lente.value), protecao_uv: txt(f.protecao_uv.value), polarizado: f.polarizado.checked,
    largura_lente_mm: num(f.largura_lente_mm.value), ponte_mm: num(f.ponte_mm.value), haste_mm: num(f.haste_mm.value),
    altura_lente_mm: num(f.altura_lente_mm.value), peso_g: num(f.peso_g.value), garantia_meses: num(f.garantia_meses.value),
    ncm: txt(f.ncm.value), preco_custo: num(f.preco_custo.value) || 0, preco_venda: num(f.preco_venda.value),
    preco_promocional: promo || null, destaque: f.destaque.checked, ativo: f.ativo.checked,
  };

  btn.disabled = true; btn.textContent = 'Salvando…';
  try {
    let id = editId;
    if (id) {
      const { error } = await sb.from('produtos').update(payload).eq('id', id);
      if (error) throw error;
    } else {
      const { data: novo, error } = await sb.from('produtos').insert(payload).select('id').single();
      if (error) throw error;
      id = editId = novo.id;
    }
    if (fotoArquivo) {
      const url = await uploadFoto(fotoArquivo, `produto-${id}`);
      const { error } = await sb.from('produtos').update({ imagem_url: url }).eq('id', id);
      if (error) throw error;
      fotoArquivo = null;
    }
    for (const c of cores) {
      let imagem_url = c.imagem_url || null;
      if (c._file) imagem_url = await uploadFoto(c._file, `produto-${id}-cor`);
      const base = { produto_id: id, cor: c.cor, cor_hex: hex(c.cor_hex), cor_lente: txt(c.cor_lente), sku: c.sku,
                     estoque_minimo: Number(c.estoque_minimo) || 0, ativo: !!c.ativo, imagem_url };
      const { error } = c.id
        ? await sb.from('produto_cores').update(base).eq('id', c.id)
        : await sb.from('produto_cores').insert({ ...base, estoque: Math.max(0, Number(c.estoque) || 0) });
      if (error) throw error;
    }
    $('#dlgProduto').close();
    toast('Produto salvo!', 'ok');
    carregarProdutos();
  } catch (err) {
    toast(erro(err), 'erro');
    if (editId) carregarProdutos().then(() => { // recarrega para não duplicar cores já salvas
      const p = produtos.find(x => x.id === editId);
      if (p) coresEdit = coresEdit.map(c => c.id ? c : (p.produto_cores.find(pc => pc.sku === c.sku) ? { ...p.produto_cores.find(pc => pc.sku === c.sku) } : c));
      renderCores();
    });
  } finally {
    btn.disabled = false; btn.textContent = 'Salvar produto';
  }
};

// ------------------------- estoque -------------------------
$('#soBaixo').onchange = carregarEstoque;

async function carregarEstoque() {
  const [{ data: cores, error }, { data: movs }] = await Promise.all([
    sb.from('produto_cores').select('*, produtos(nome, sku, preco_custo, ativo)').order('produto_id').order('id'),
    sb.from('movimentacoes_estoque').select('*, produto_cores(cor, sku, produtos(nome))').order('criado_em', { ascending: false }).limit(60),
  ]);
  if (error) return toast(erro(error), 'erro');
  const lista = $('#soBaixo').checked ? cores.filter(c => c.estoque <= c.estoque_minimo) : cores;

  $('#tblEstoque').innerHTML = lista.length ? `
    <thead><tr><th>Produto / cor</th><th>SKU</th><th class="num">Estoque</th><th class="num">Mínimo</th><th class="num">Valor a custo</th><th></th></tr></thead>
    <tbody>${lista.map(c => `<tr style="${c.ativo && c.produtos?.ativo ? '' : 'opacity:.55'}">
      <td><span class="dot" style="display:inline-block;vertical-align:middle;background:${hex(c.cor_hex)}"></span>
          <b>${esc(c.produtos?.nome)}</b> — ${esc(c.cor)}</td>
      <td>${esc(c.sku)}</td>
      <td class="num ${c.estoque <= c.estoque_minimo ? 'baixo' : ''}">${c.estoque}</td>
      <td class="num">${c.estoque_minimo}</td>
      <td class="num">${fmt(c.estoque * (c.produtos?.preco_custo || 0))}</td>
      <td class="row-actions" style="justify-content:flex-end">
        <button class="btn btn-ok btn-sm" data-mov="entrada" data-cor="${c.id}">+ Entrada</button>
        <button class="btn btn-ghost btn-sm" data-mov="saida" data-cor="${c.id}">− Saída</button>
      </td></tr>`).join('')}</tbody>`
    : '<tr><td class="vazio">Nada para mostrar.</td></tr>';

  const tipos = { entrada: 'Entrada', saida: 'Saída (pedido)', ajuste: 'Saída manual', estorno: 'Estorno' };
  $('#tblMov').innerHTML = (movs || []).length ? `
    <thead><tr><th>Data</th><th>Produto / cor</th><th>Tipo</th><th class="num">Qtd</th><th>Observação</th></tr></thead>
    <tbody>${movs.map(m => `<tr><td>${data(m.criado_em)}</td>
      <td>${esc(m.produto_cores?.produtos?.nome)} — ${esc(m.produto_cores?.cor)}</td>
      <td>${tipos[m.tipo] || m.tipo}</td>
      <td class="num" style="color:${m.quantidade > 0 ? 'var(--ok)' : 'var(--bad)'}">${m.quantidade > 0 ? '+' : ''}${m.quantidade}</td>
      <td>${esc(m.observacao || '')}${m.pedido_id ? ` (pedido #${m.pedido_id})` : ''}</td></tr>`).join('')}</tbody>`
    : '<tr><td class="vazio">Sem movimentações ainda.</td></tr>';
}

$('#tblEstoque').addEventListener('click', async e => {
  const b = e.target.closest('[data-mov]'); if (!b) return;
  const entrada = b.dataset.mov === 'entrada';
  const qtd = parseInt(prompt(entrada ? 'Quantas peças chegaram?' : 'Quantas peças saíram? (avaria, brinde, venda no balcão...)'), 10);
  if (!qtd || qtd <= 0) return;
  const obs = prompt('Observação (opcional):', entrada ? 'Compra de fornecedor' : 'Venda no balcão') ?? '';
  const { error } = await sb.rpc('ajustar_estoque', { p_cor_id: Number(b.dataset.cor), p_delta: entrada ? qtd : -qtd, p_obs: obs });
  if (error) return toast(erro(error), 'erro');
  toast('Estoque atualizado', 'ok');
  carregarEstoque();
});

// ------------------------- categorias e marcas -------------------------
function renderCategorias() {
  const qtd = (campo, id) => produtos.filter(p => p[campo] === id).length;
  $('#tblCat').innerHTML = categorias.length ? `
    <thead><tr><th>Nome</th><th title="Ordem no menu da loja">Ordem</th><th>Status</th><th></th></tr></thead>
    <tbody>${categorias.map(c => `<tr>
      <td><input value="${esc(c.nome)}" data-tab="categorias" data-id="${c.id}" data-k="nome"></td>
      <td style="width:84px"><input type="number" value="${c.ordem}" data-tab="categorias" data-id="${c.id}" data-k="ordem"></td>
      <td>${badgeStatus(c.ativo)}</td>
      <td>${botoesStatus('categorias', c.id, c.ativo)}</td>
    </tr>`).join('')}</tbody>` : '<tr><td class="muted">Nenhuma categoria.</td></tr>';
  $('#tblMarca').innerHTML = marcas.length ? `
    <thead><tr><th>Nome</th><th>Status</th><th></th></tr></thead>
    <tbody>${marcas.map(m => `<tr>
      <td><input value="${esc(m.nome)}" data-tab="marcas" data-id="${m.id}" data-k="nome"></td>
      <td>${badgeStatus(m.ativo)}</td>
      <td>${botoesStatus('marcas', m.id, m.ativo)}</td>
    </tr>`).join('')}</tbody>` : '<tr><td class="muted">Nenhuma marca.</td></tr>';
  renderOpcoes();
}

function renderOpcoes() {
  $$('[data-opcao-tbl]').forEach(tbl => {
    const lista = opcoes.filter(o => o.tipo === tbl.dataset.opcaoTbl);
    tbl.innerHTML = lista.length ? `
      <thead><tr><th>Nome</th><th>Ordem</th><th>Status</th><th></th></tr></thead>
      <tbody>${lista.map(o => `<tr>
        <td><input value="${esc(o.nome)}" data-tab="opcoes" data-id="${o.id}" data-k="nome"></td>
        <td style="width:84px"><input type="number" value="${o.ordem}" data-tab="opcoes" data-id="${o.id}" data-k="ordem"></td>
        <td>${badgeStatus(o.ativo)}</td>
        <td>${botoesStatus('opcoes', o.id, o.ativo)}</td>
      </tr>`).join('')}</tbody>` : '<tr><td class="muted">Nenhuma opção.</td></tr>';
  });
}
$$('[data-opcao-form]').forEach(form => form.onsubmit = async e => {
  e.preventDefault();
  const tipo = form.dataset.opcaoForm, nome = form.nome.value.trim();
  const ordem = Math.max(0, ...opcoes.filter(o => o.tipo === tipo).map(o => o.ordem)) + 1;
  const { error } = await sb.from('opcoes').insert({ tipo, nome, ordem });
  if (error) return toast(erro(error), 'erro');
  form.reset(); await carregarBase(); renderCategorias();
});

$('[data-pane="categorias"]').addEventListener('change', async e => {
  const el = e.target; if (!el.dataset.tab) return;
  const v = el.type === 'checkbox' ? el.checked : el.type === 'number' ? Number(el.value) : el.value.trim();
  const { error } = await sb.from(el.dataset.tab).update({ [el.dataset.k]: v }).eq('id', Number(el.dataset.id));
  if (error) return toast(erro(error), 'erro');
  toast(el.dataset.tab === 'opcoes' && el.dataset.k === 'nome' ? 'Salvo — produtos com essa opção foram atualizados' : 'Salvo', 'ok');
  carregarBase();
});
$('#formCat').onsubmit = async e => {
  e.preventDefault();
  const { error } = await sb.from('categorias').insert({ nome: e.target.nome.value.trim(), ordem: categorias.length + 1 });
  if (error) return toast(erro(error), 'erro');
  e.target.reset(); await carregarBase(); renderCategorias();
};
$('#formMarca').onsubmit = async e => {
  e.preventDefault();
  const { error } = await sb.from('marcas').insert({ nome: e.target.nome.value.trim() });
  if (error) return toast(erro(error), 'erro');
  e.target.reset(); await carregarBase(); renderCategorias();
};

// ------------------------- configurações -------------------------
async function carregarConfig() {
  const [{ data: cfg }] = await Promise.all([sb.from('configuracoes').select('*').eq('id', 1).maybeSingle(), carregarBase()]);
  const f = $('#formConfig');
  const m = cfg?.mostrar_precos || 'sempre';
  $$('[name=mostrar_precos]', f).forEach(r => r.checked = r.value === m);
  f.texto_sem_preco.value = cfg?.texto_sem_preco || 'Consulte o preço';
  renderFormas();
}
$('#formConfig').onsubmit = async e => {
  e.preventDefault();
  const f = e.target;
  const dados = { mostrar_precos: f.querySelector('[name=mostrar_precos]:checked')?.value || 'sempre',
                  texto_sem_preco: f.texto_sem_preco.value.trim() || 'Consulte o preço', atualizado_em: new Date().toISOString() };
  const { error } = await sb.from('configuracoes').update(dados).eq('id', 1);
  if (error) return toast(erro(error), 'erro');
  toast('Exibição de preços salva', 'ok');
};

function simulacao(f, valor = 300) {
  const max = U.maxParcelas(valor, f), c1 = U.calcPagamento(valor, f, 1), cm = U.calcPagamento(valor, f, max);
  const avista = Number(f.desconto_percentual) ? `${fmt(c1.total)} à vista` : `${fmt(valor)} à vista`;
  return max > 1 ? `${avista} ou ${max}x de ${fmt(cm.parcela)}${cm.semJuros ? ' sem juros' : ` (total ${fmt(cm.total)})`}` : avista;
}
function renderFormas() {
  const num = (f, k, step, min, max) => `<input type="number" step="${step}" min="${min}" ${max ? `max="${max}"` : ''} value="${Number(f[k])}" data-tab="formas_pagamento" data-id="${f.id}" data-k="${k}" style="width:66px">`;
  $('#tblFormas').innerHTML = formas.length ? `
    <thead><tr><th>Nome</th><th>Descrição</th><th title="Desconto sobre o total">Desc. %</th><th>Máx. parc.</th>
      <th title="Até quantas parcelas sem juros">Sem juros até</th><th title="Juros ao mês a partir da primeira parcela com juros">Juros % a.m.</th>
      <th title="Valor mínimo de cada parcela">Parc. mín. R$</th><th>Ordem</th><th>Simulação (R$ 300)</th><th>Status</th><th></th></tr></thead>
    <tbody>${formas.map(f => `<tr>
      <td><input value="${esc(f.nome)}" data-tab="formas_pagamento" data-id="${f.id}" data-k="nome" style="min-width:110px;width:120px"></td>
      <td><input value="${esc(f.descricao || '')}" data-tab="formas_pagamento" data-id="${f.id}" data-k="descricao" style="min-width:100px;width:110px"></td>
      <td>${num(f, 'desconto_percentual', '0.5', 0, 100)}</td>
      <td>${num(f, 'max_parcelas', '1', 1, 24)}</td>
      <td>${num(f, 'parcelas_sem_juros', '1', 1, 24)}</td>
      <td>${num(f, 'juros_mes', '0.01', 0)}</td>
      <td>${num(f, 'parcela_minima', '1', 0)}</td>
      <td>${num(f, 'ordem', '1', 0)}</td>
      <td style="font-size:12px;min-width:150px">${simulacao(f)}</td>
      <td>${badgeStatus(f.ativo)}</td>
      <td>${botoesStatus('formas_pagamento', f.id, f.ativo)}</td>
    </tr>`).join('')}</tbody>` : '<tr><td class="muted">Nenhuma forma de pagamento. Sem formas cadastradas, o pedido fica "a combinar".</td></tr>';
}
$('[data-pane="config"]').addEventListener('change', async e => {
  const el = e.target; if (el.dataset.tab !== 'formas_pagamento') return;
  let v = el.type === 'number' ? Number(el.value) : el.value.trim() || null;
  if (el.dataset.k === 'nome' && !v) return toast('O nome não pode ficar vazio', 'erro');
  const f = formas.find(x => x.id === Number(el.dataset.id));
  const novo = { ...f, [el.dataset.k]: v };
  if (Number(novo.parcelas_sem_juros) > Number(novo.max_parcelas)) {
    if (el.dataset.k === 'max_parcelas') novo.parcelas_sem_juros = v; else { novo.parcelas_sem_juros = novo.max_parcelas; v = novo.max_parcelas; }
  }
  const dados = { [el.dataset.k]: v };
  if (novo.parcelas_sem_juros !== f.parcelas_sem_juros) dados.parcelas_sem_juros = novo.parcelas_sem_juros;
  const { error } = await sb.from('formas_pagamento').update(dados).eq('id', f.id);
  if (error) { toast(erro(error), 'erro'); return carregarConfig(); }
  toast('Salvo', 'ok');
  await carregarBase(); renderFormas();
});
$('#formForma').onsubmit = async e => {
  e.preventDefault();
  const ordem = Math.max(0, ...formas.map(f => f.ordem)) + 1;
  const { error } = await sb.from('formas_pagamento').insert({ nome: e.target.nome.value.trim(), ordem });
  if (error) return toast(erro(error), 'erro');
  e.target.reset(); await carregarBase(); renderFormas();
};

// ------------------------- clientes -------------------------
$('#buscaCli').oninput = renderClientes;
$('#fStatusCli').onchange = renderClientes;

async function carregarClientes() {
  const { data: lista, error } = await sb.from('clientes').select('*, pedidos(count)').order('criado_em', { ascending: false });
  if (error) return toast(erro(error), 'erro');
  clientes = lista; renderClientes();
}

function renderClientes() {
  const b = norm($('#buscaCli').value);
  const st = $('#fStatusCli').value;
  const lista = clientes.filter(c => (!st || String(!c.bloqueado) === st) && (!b || norm([c.nome, c.email, c.cidade, c.telefone, c.cpf].join(' ')).includes(b)));
  $('#tblClientes').innerHTML = lista.length ? `
    <thead><tr><th>Nome</th><th>Contato</th><th>CPF</th><th>Cidade</th><th class="num">Pedidos</th><th>Desde</th><th>Status</th><th></th></tr></thead>
    <tbody>${lista.map(c => `<tr>
      <td><b>${esc(c.nome)}</b>${c.possui_login === false ? '<br><small class="muted" title="Cadastrado por planilha. Quando criar a conta na loja com este e-mail, o cadastro é ligado automaticamente.">sem login ainda</small>' : ''}</td>
      <td>${esc(c.email)}<br><small class="muted">${esc(c.telefone || '')}</small></td>
      <td>${esc(c.cpf || '—')}</td>
      <td>${esc([c.cidade, c.uf].filter(Boolean).join('/') || '—')}</td>
      <td class="num">${c.pedidos?.[0]?.count ?? 0}</td>
      <td>${new Date(c.criado_em).toLocaleDateString('pt-BR')}</td>
      <td>${badgeStatus(!c.bloqueado)}</td>
      <td>${botoesStatus('clientes', c.id, !c.bloqueado)}</td>
    </tr>`).join('')}</tbody>`
    : '<tr><td class="vazio">Nenhum cliente.</td></tr>';
}


// ------------------------- geral -------------------------
$$('dialog').forEach(d => d.addEventListener('click', e => {
  if (e.target.closest('[data-close]')) d.close();
}));
U.marca($('#logoAdmin'), esc(CFG.nomeLoja));
document.title = `Painel — ${CFG.nomeLoja}`;
verificarAcesso();
