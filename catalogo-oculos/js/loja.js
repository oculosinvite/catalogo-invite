// =====================================================================
//  LOJA — catálogo, carrinho, cadastro e pedidos do cliente
// =====================================================================
const { $, $$, fmt, esc, hex, norm, img, erro, toast, data, statusLabel } = U;
const CFG = window.APP_CONFIG;

let produtos = [];
let categorias = [];
let usuario = null;
let cliente = null;
let cfgLoja = { mostrar_precos: 'sempre', texto_sem_preco: 'Consulte o preço' };
let formas = [];   // formas de pagamento ativas
const filtro = { cat: null, busca: '', genero: '', formato: '', ordem: 'destaque', polarizado: false };

// ------------------------- carrinho (salvo no navegador) -------------------------
let carrinho = [];
try { carrinho = JSON.parse(localStorage.getItem('carrinho_oculos') || '[]'); } catch { carrinho = []; }
const salvarCarrinho = () => { try { localStorage.setItem('carrinho_oculos', JSON.stringify(carrinho)); } catch {} atualizarContador(); };

// ------------------------- início -------------------------
async function init() {
  document.title = `${CFG.nomeLoja} — Catálogo de Óculos`;
  U.marca($('#logo'), esc(CFG.nomeLoja) + '<span>.</span>');
  $('#rodapeNome').textContent = CFG.nomeLoja;

  ligarEventos();
  atualizarContador();

  const [c, cfg, fp] = await Promise.all([
    sb.from('categorias').select('*').order('ordem').order('nome'),
    sb.from('configuracoes').select('*').eq('id', 1).maybeSingle(),
    sb.from('formas_pagamento').select('*').eq('ativo', true).order('ordem').order('nome'),
  ]);
  if (c.error) {
    $('#grid').innerHTML = `<p class="vazio" style="grid-column:1/-1">Não foi possível carregar o catálogo.<br><small>${esc(erro(c.error))}</small></p>`;
    return;
  }
  categorias = c.data;
  if (cfg.data) cfgLoja = cfg.data;
  formas = fp.data || [];
  $('#cartForma').innerHTML = formas.map(f => `<option value="${f.id}">${esc(f.nome)}${Number(f.desconto_percentual) ? ` (${Number(f.desconto_percentual)}% de desconto)` : ''}</option>`).join('');
  $('#lblForma').classList.toggle('hidden', !formas.length);
  if (!await carregarCatalogo()) return;

  const formatos = [...new Set(produtos.map(x => x.formato).filter(Boolean))].sort();
  $('#fFormato').innerHTML += formatos.map(f => `<option>${esc(f)}</option>`).join('');

  renderCategorias();
  render();

  // abrir produto direto pelo link (#produto-12)
  const m = location.hash.match(/produto-(\d+)/);
  if (m) abrirProduto(Number(m[1]));
}

// Carrega (ou recarrega) os produtos. Os preços vêm do servidor conforme a configuração.
async function carregarCatalogo() {
  const { data, error } = await sb.from('vw_catalogo').select('*');
  if (error) {
    $('#grid').innerHTML = `<p class="vazio" style="grid-column:1/-1">Não foi possível carregar o catálogo.<br><small>${esc(erro(error))}</small></p>`;
    return false;
  }
  produtos = data;
  const comPreco = produtos.some(p => p.preco_final != null);
  $$('#fOrdem option[value=menor], #fOrdem option[value=maior]').forEach(o => o.hidden = !comPreco);
  if (!comPreco && ['menor', 'maior'].includes(filtro.ordem)) { filtro.ordem = 'destaque'; $('#fOrdem').value = 'destaque'; }
  sincronizarCarrinho();
  return true;
}

// Bloco de preço do card e da página do produto
function blocoPreco(p) {
  if (p.preco_final == null) {
    const entrar = cfgLoja.mostrar_precos === 'logados' && !usuario
      ? `<span class="parcela"><button class="link" data-entrar>Entre para ver o preço</button></span>` : '';
    return `<div class="preco"><span class="sem-preco">${esc(cfgLoja.texto_sem_preco)}</span></div>${entrar}`;
  }
  const preco = Number(p.preco_final);
  const parc = U.melhorParcelamento(preco, formas), desc = U.melhorDesconto(preco, formas);
  return `<div class="preco">${p.preco_promocional != null ? `<s>${fmt(p.preco_venda)}</s>` : ''}<strong>${fmt(preco)}</strong></div>
    ${parc ? `<span class="parcela">ou ${parc.n}x de ${fmt(parc.parcela)} sem juros</span>` : ''}
    ${desc ? `<span class="parcela pix">${fmt(desc.total)} no ${esc(desc.forma)} (${desc.pct}% off)</span>` : ''}`;
}

// Sessão do usuário
sb.auth.onAuthStateChange((evento, session) => {
  const antes = !!usuario;
  usuario = session?.user || null;
  // com "preço só para logados", entrar/sair muda o que aparece
  if (antes !== !!usuario && cfgLoja.mostrar_precos === 'logados' && produtos.length)
    setTimeout(async () => { if (await carregarCatalogo()) { render(); renderCarrinho(); } }, 0);
  cliente = null;
  $('#btnConta').textContent = usuario ? 'Minha conta' : 'Entrar';
  if (evento === 'PASSWORD_RECOVERY') setTimeout(trocarSenha, 0);
  if (usuario) setTimeout(carregarCliente, 0); // fora do callback (recomendação do Supabase)
});

async function carregarCliente() {
  const { data: c } = await sb.from('clientes').select('*').eq('id', usuario.id).maybeSingle();
  cliente = c;
}

async function trocarSenha() {
  const nova = prompt('Digite sua nova senha (mínimo 6 caracteres):');
  if (!nova) return;
  const { error } = await sb.auth.updateUser({ password: nova });
  error ? toast(erro(error), 'erro') : toast('Senha alterada com sucesso!', 'ok');
}

// ------------------------- catálogo -------------------------
function renderCategorias() {
  const usadas = new Set(produtos.map(p => p.categoria_id));
  const lista = categorias.filter(c => usadas.has(c.id));
  $('#categorias').innerHTML =
    `<button class="chip ${filtro.cat === null ? 'on' : ''}" data-cat="">Todos</button>` +
    lista.map(c => `<button class="chip ${filtro.cat === c.id ? 'on' : ''}" data-cat="${c.id}">${esc(c.nome)}</button>`).join('');
}

const fotoProduto = p => p.imagem_url || p.cores.find(c => c.imagem_url)?.imagem_url || '';
const estoqueTotal = p => p.cores.reduce((s, c) => s + c.estoque, 0);

function filtrados() {
  const b = norm(filtro.busca);
  let lista = produtos.filter(p =>
    (filtro.cat === null || p.categoria_id === filtro.cat) &&
    (!filtro.genero || p.genero === filtro.genero) &&
    (!filtro.formato || p.formato === filtro.formato) &&
    (!filtro.polarizado || p.polarizado) &&
    (!b || norm([p.nome, p.marca, p.categoria, p.formato, p.sku, p.material_armacao, ...p.cores.map(c => c.cor)].join(' ')).includes(b))
  );
  const ord = {
    destaque: (a, z) => (z.destaque - a.destaque) || (estoqueTotal(z) > 0) - (estoqueTotal(a) > 0) || a.nome.localeCompare(z.nome),
    novos:    (a, z) => new Date(z.criado_em) - new Date(a.criado_em),
    menor:    (a, z) => a.preco_final - z.preco_final,
    maior:    (a, z) => z.preco_final - a.preco_final,
    nome:     (a, z) => a.nome.localeCompare(z.nome),
  }[filtro.ordem];
  return lista.sort(ord);
}

function render() {
  const lista = filtrados();
  $('#totalProdutos').textContent = `${lista.length} ${lista.length === 1 ? 'modelo' : 'modelos'}`;
  if (!lista.length) {
    $('#grid').innerHTML = `<p class="vazio" style="grid-column:1/-1">Nenhum óculos encontrado com esses filtros.</p>`;
    return;
  }
  $('#grid').innerHTML = lista.map(p => {
    const promo = p.preco_promocional != null;
    const esgotado = estoqueTotal(p) <= 0;
    return `
      <article class="card" data-id="${p.id}">
        <div class="card-img">
          <img loading="lazy" src="${esc(img(fotoProduto(p)))}" alt="${esc(p.nome)}">
          ${promo ? `<span class="tag">-${Math.round((1 - p.preco_promocional / p.preco_venda) * 100)}%</span>` : ''}
          ${esgotado ? '<span class="tag dark">Esgotado</span>' : ''}
        </div>
        <div class="card-body">
          <small>${esc(p.marca || p.categoria || '')}</small>
          <h3>${esc(p.nome)}</h3>
          <div class="dots">${p.cores.map(c => `<span class="dot" style="background:${hex(c.cor_hex)}" title="${esc(c.cor)}"></span>`).join('')}</div>
          ${blocoPreco(p)}
        </div>
      </article>`;
  }).join('');
}

// ------------------------- detalhe do produto -------------------------
function abrirProduto(id) {
  const p = produtos.find(x => x.id === id);
  if (!p) return;
  let cor = p.cores.find(c => c.estoque > 0) || p.cores[0];
  let qtd = 1;

  const medidas = p.largura_lente_mm ? `${p.largura_lente_mm}□${p.ponte_mm ?? '-'} ${p.haste_mm ?? ''}`.trim() : null;
  const specs = [
    ['Marca', p.marca], ['Categoria', p.categoria], ['Gênero', p.genero], ['Formato', p.formato],
    ['Material da armação', p.material_armacao], ['Material da lente', p.material_lente],
    ['Tipo de lente', p.tipo_lente], ['Polarizado', p.polarizado ? 'Sim' : 'Não'], ['Proteção UV', p.protecao_uv],
    ['Medidas (lente□ponte haste)', medidas ? medidas + ' mm' : null],
    ['Altura da lente', p.altura_lente_mm ? p.altura_lente_mm + ' mm' : null],
    ['Peso', p.peso_g ? p.peso_g + ' g' : null],
    ['Garantia', p.garantia_meses ? `${p.garantia_meses} meses` : null], ['Referência', p.sku],
  ].filter(([, v]) => v);

  $('#pCategoria').textContent = [p.categoria, p.marca].filter(Boolean).join(' · ');
  const desenhar = () => {
    const disp = cor ? cor.estoque : 0;
    if (qtd > disp) qtd = Math.max(1, disp);
    $('#pConteudo').innerHTML = `
      <div class="produto">
        <div class="foto"><img src="${esc(img(cor?.imagem_url || fotoProduto(p)))}" alt="${esc(p.nome)}"></div>
        <div>
          <h2>${esc(p.nome)}</h2>
          <div class="bloco-preco">${blocoPreco(p)}</div>

          <p style="margin:18px 0 0"><b>Cor:</b> ${esc(cor?.cor || '—')}${cor?.cor_lente ? ` <span class="muted">· lente ${esc(cor.cor_lente)}</span>` : ''}</p>
          <div class="swatches">
            ${p.cores.map(c => `<button class="sw ${c.id === cor?.id ? 'on' : ''} ${c.estoque <= 0 ? 'off' : ''}"
               style="background:${hex(c.cor_hex)}" data-cor="${c.id}" title="${esc(c.cor)}${c.estoque <= 0 ? ' (esgotada)' : ''}"></button>`).join('')}
          </div>
          <div class="estoque-info ${disp <= 0 ? 'baixo' : 'muted'}">
            ${disp <= 0 ? 'Esta cor está esgotada' : disp <= 3 ? `Últimas ${disp} unidades!` : 'Em estoque'}
          </div>

          <div class="add-row">
            <div class="qtd"><button data-q="-1">−</button><span>${qtd}</span><button data-q="1">+</button></div>
            <button class="btn btn-accent" id="btnAdd" ${disp <= 0 ? 'disabled' : ''}>Adicionar ao carrinho</button>
          </div>

          ${p.descricao ? `<p style="white-space:pre-line">${esc(p.descricao)}</p>` : ''}
          <table class="specs">${specs.map(([k, v]) => `<tr><td>${esc(k)}</td><td>${esc(v)}</td></tr>`).join('')}</table>
        </div>
      </div>`;
  };
  desenhar();

  $('#pConteudo').onclick = e => {
    const sw = e.target.closest('[data-cor]');
    if (sw) { cor = p.cores.find(c => c.id === Number(sw.dataset.cor)); qtd = 1; return desenhar(); }
    const q = e.target.closest('[data-q]');
    if (q) { qtd = Math.min(Math.max(1, qtd + Number(q.dataset.q)), Math.max(1, cor?.estoque || 1)); return desenhar(); }
    if (e.target.closest('[data-entrar]')) { $('#dlgProduto').close(); return abrirAuth('Entre na sua conta para ver os preços.'); }
    if (e.target.id === 'btnAdd') {
      adicionar(p, cor, qtd);
      $('#dlgProduto').close();
      abrirCarrinho();
    }
  };
  history.replaceState(null, '', '#produto-' + p.id);
  $('#dlgProduto').showModal();
}

// ------------------------- carrinho -------------------------
function adicionar(p, cor, qtd) {
  const item = carrinho.find(i => i.cor_id === cor.id);
  if (item) item.qtd = Math.min(item.qtd + qtd, cor.estoque);
  else carrinho.push({ cor_id: cor.id, produto_id: p.id, nome: p.nome, cor: cor.cor,
                       preco: p.preco_final, imagem: cor.imagem_url || fotoProduto(p), qtd, max: cor.estoque });
  salvarCarrinho();
  toast(`${p.nome} (${cor.cor}) adicionado ao carrinho`, 'ok');
}

// Atualiza preços/estoque do carrinho com o catálogo atual
function sincronizarCarrinho() {
  carrinho = carrinho.filter(i => {
    const p = produtos.find(x => x.id === i.produto_id);
    const c = p?.cores.find(x => x.id === i.cor_id);
    if (!c || c.estoque <= 0) return false;
    i.preco = p.preco_final; i.max = c.estoque; i.qtd = Math.min(i.qtd, c.estoque);
    return true;
  });
  salvarCarrinho();
}

function atualizarContador() {
  $('#cartCount').textContent = carrinho.reduce((s, i) => s + i.qtd, 0) || '';
}

const precoItem = v => v == null ? esc(cfgLoja.texto_sem_preco) : fmt(v);

function renderCarrinho() {
  $('#cartFoot').classList.toggle('hidden', !carrinho.length);
  renderPagamento();
  $('#cartLista').innerHTML = carrinho.length ? carrinho.map((i, n) => `
    <div class="cart-item">
      <img src="${esc(img(i.imagem))}" alt="">
      <div>
        <div class="nome">${esc(i.nome)}</div>
        <div class="muted" style="font-size:13px">Cor: ${esc(i.cor)} · ${precoItem(i.preco)}</div>
        <div class="qtd" style="margin-top:6px"><button data-n="${n}" data-q="-1">−</button><span>${i.qtd}</span><button data-n="${n}" data-q="1">+</button></div>
      </div>
      <div style="text-align:right">
        <b>${i.preco == null ? '' : fmt(i.preco * i.qtd)}</b><br>
        <button class="link" data-rm="${n}" style="font-size:13px">remover</button>
      </div>
    </div>`).join('')
    : '<p class="vazio">Seu carrinho está vazio.</p>';
}

// Forma de pagamento, parcelas e resumo (mesmo cálculo do servidor)
function renderPagamento() {
  const semPreco = carrinho.some(i => i.preco == null);
  const subtotal = carrinho.reduce((s, i) => s + (i.preco || 0) * i.qtd, 0);
  const f = formas.find(x => x.id === Number($('#cartForma').value));
  const selP = $('#cartParcelas');
  if (!f) {
    $('#lblParcelas').classList.add('hidden');
    $('#cartResumo').innerHTML = '';
    $('#cartTotal').innerHTML = semPreco ? esc(cfgLoja.texto_sem_preco) : fmt(subtotal);
    return;
  }
  const max = semPreco ? f.max_parcelas : U.maxParcelas(subtotal, f);
  const escolhido = Math.min(Number(selP.value) || 1, max);
  selP.innerHTML = Array.from({ length: max }, (_, k) => {
    const n = k + 1;
    if (semPreco) return `<option value="${n}">${n}x${n <= f.parcelas_sem_juros || !Number(f.juros_mes) ? ' sem juros' : ' com juros'}</option>`;
    const c = U.calcPagamento(subtotal, f, n);
    return `<option value="${n}">${n === 1 ? 'À vista' : `${n}x`} de ${fmt(c.parcela)}${c.semJuros ? (n > 1 ? ' sem juros' : '') : ` (total ${fmt(c.total)})`}</option>`;
  }).join('');
  selP.value = escolhido;
  $('#lblParcelas').classList.toggle('hidden', max <= 1);

  if (semPreco) {
    $('#cartResumo').innerHTML = `<div class="muted" style="font-size:13px">Os valores serão informados pela loja ao confirmar o pedido.</div>`;
    $('#cartTotal').innerHTML = esc(cfgLoja.texto_sem_preco);
    return;
  }
  const c = U.calcPagamento(subtotal, f, escolhido);
  $('#cartResumo').innerHTML = (c.desconto || c.juros) ? `
    <div class="resumo-linha"><span>Subtotal</span><span>${fmt(subtotal)}</span></div>
    ${c.desconto ? `<div class="resumo-linha ok"><span>Desconto ${esc(f.nome)} (${Number(f.desconto_percentual)}%)</span><span>− ${fmt(c.desconto)}</span></div>` : ''}
    ${c.juros ? `<div class="resumo-linha"><span>Juros do parcelamento</span><span>+ ${fmt(c.juros)}</span></div>` : ''}` : '';
  $('#cartTotal').innerHTML = fmt(c.total) + (escolhido > 1 ? `<small class="muted" style="display:block;font-size:12px;font-weight:500;text-align:right">${escolhido}x de ${fmt(c.parcela)}</small>` : '');
}

function abrirCarrinho() { renderCarrinho(); $('#drawer').classList.add('on'); $('#overlay').classList.add('on'); }
function fecharCarrinho() { $('#drawer').classList.remove('on'); $('#overlay').classList.remove('on'); }

async function finalizar() {
  if (!carrinho.length) return;
  if (!usuario) {
    fecharCarrinho();
    abrirAuth('Entre ou crie sua conta para enviar o pedido. Seu carrinho fica guardado.');
    return;
  }
  const btn = $('#btnFinalizar');
  btn.disabled = true; btn.textContent = 'Enviando…';
  const { data: pedidoId, error } = await sb.rpc('criar_pedido', {
    p_itens: carrinho.map(i => ({ cor_id: i.cor_id, quantidade: i.qtd })),
    p_observacao: $('#cartObs').value,
    p_forma_id: formas.length ? Number($('#cartForma').value) : null,
    p_parcelas: Number($('#cartParcelas').value) || 1,
  });
  btn.disabled = false; btn.textContent = 'Enviar pedido';
  if (error) return toast(erro(error), 'erro');

  const resumo = carrinho.map(i => `${i.qtd}x ${i.nome} (${i.cor})`).join('\n');
  const semPreco = carrinho.some(i => i.preco == null);
  const totalTxt = semPreco ? '' : `\nTotal: ${$('#cartTotal').firstChild?.textContent || ''}`;
  const fNome = formas.find(x => x.id === Number($('#cartForma').value))?.nome;
  const pagTxt = fNome ? `\nPagamento: ${fNome}${Number($('#cartParcelas').value) > 1 ? ` em ${$('#cartParcelas').value}x` : ''}` : '';
  carrinho = []; salvarCarrinho(); $('#cartObs').value = '';
  $('#cartFoot').classList.add('hidden');

  const zap = CFG.whatsapp
    ? `<a class="btn btn-ok btn-block" target="_blank" rel="noopener" href="https://wa.me/${CFG.whatsapp}?text=${encodeURIComponent(
        `Olá! Acabei de fazer o pedido #${pedidoId} no site.\n${resumo}${pagTxt}${totalTxt}`)}">Avisar a loja pelo WhatsApp</a>` : '';
  $('#cartLista').innerHTML = `
    <div style="text-align:center;padding:40px 6px;display:grid;gap:14px">
      <h2>Pedido #${pedidoId} enviado!</h2>
      <p class="muted">A loja vai analisar e confirmar. Acompanhe o status em “Minha conta”.</p>
      ${zap}
      <button class="btn btn-ghost btn-block" id="verPedidos">Ver meus pedidos</button>
    </div>`;
}

// ------------------------- login / cadastro -------------------------
function abrirAuth(msg) {
  const m = $('#authMsg');
  m.textContent = msg || ''; m.className = 'msg' + (msg ? '' : ' hidden');
  $('#dlgAuth').showModal();
}
const authMsg = (texto, tipo) => { const m = $('#authMsg'); m.textContent = texto; m.className = 'msg ' + tipo; };

async function entrar(e) {
  e.preventDefault();
  const f = e.target, b = f.querySelector('button'); b.disabled = true;
  const { error } = await sb.auth.signInWithPassword({ email: f.email.value.trim(), password: f.senha.value });
  b.disabled = false;
  if (error) return authMsg(erro(error), 'erro');
  $('#dlgAuth').close(); toast('Bem-vindo(a)!', 'ok');
  if (carrinho.length) abrirCarrinho();
}

async function cadastrar(e) {
  e.preventDefault();
  const f = e.target, b = f.querySelector('button'); b.disabled = true;
  const dados = Object.fromEntries(['nome', 'telefone', 'cpf', 'cep', 'endereco', 'numero', 'complemento', 'bairro', 'cidade', 'uf']
    .map(k => [k, f[k].value.trim()]));
  dados.uf = dados.uf.toUpperCase();
  const { data: r, error } = await sb.auth.signUp({
    email: f.email.value.trim(), password: f.senha.value,
    options: { data: dados, emailRedirectTo: location.origin + location.pathname },
  });
  b.disabled = false;
  if (error) return authMsg(erro(error), 'erro');
  if (!r.session) {
    authMsg('Conta criada! Enviamos um link de confirmação para o seu e-mail. Clique nele e depois entre aqui.', 'ok');
    trocarAba('#dlgAuth', 'login');
    return;
  }
  $('#dlgAuth').close(); toast('Conta criada com sucesso!', 'ok');
  if (carrinho.length) abrirCarrinho();
}

async function esqueciSenha() {
  const email = $('#formLogin').email.value.trim() || prompt('Digite seu e-mail:');
  if (!email) return;
  const { error } = await sb.auth.resetPasswordForEmail(email, { redirectTo: location.origin + location.pathname });
  error ? authMsg(erro(error), 'erro') : authMsg('Enviamos um link para redefinir sua senha no seu e-mail.', 'ok');
}

// ------------------------- minha conta -------------------------
async function abrirConta() {
  if (!usuario) return abrirAuth();
  trocarAba('#dlgConta', 'pedidos');
  $('#dlgConta').showModal();
  await carregarPedidos();
  if (!cliente) await carregarCliente();
  const f = $('#formDados');
  if (cliente) ['nome', 'telefone', 'cpf', 'cep', 'endereco', 'numero', 'complemento', 'bairro', 'cidade', 'uf']
    .forEach(k => f[k].value = cliente[k] || '');
}

// Com "não mostrar preços", o valor só aparece depois que a loja aprova
const ocultar = p => cfgLoja.mostrar_precos === 'nunca' && ['pendente', 'recusado', 'cancelado'].includes(p.status);

async function carregarPedidos() {
  const box = $('#contaPedidos');
  box.innerHTML = '<p class="muted">Carregando…</p>';
  const { data: lista, error } = await sb.from('pedidos').select('*, itens_pedido(*)').order('criado_em', { ascending: false });
  if (error) { box.innerHTML = `<p class="msg erro">${esc(erro(error))}</p>`; return; }
  if (!lista.length) { box.innerHTML = '<p class="vazio">Você ainda não fez pedidos.</p>'; return; }
  box.innerHTML = lista.map(p => `
    <div class="pedido">
      <div class="pedido-top">
        <b>Pedido #${p.id}</b>
        <span class="muted">${data(p.criado_em)}</span>
        <span class="st st-${p.status}">${statusLabel(p.status)}</span>
        <b>${ocultar(p) ? esc(cfgLoja.texto_sem_preco) : fmt(p.valor_total)}</b>
      </div>
      <ul>${p.itens_pedido.map(i => `<li>${i.quantidade}x ${esc(i.descricao)}${ocultar(p) ? '' : ` — ${fmt(i.preco_unitario)}`}</li>`).join('')}</ul>
      ${p.forma_pagamento ? `<div class="muted" style="font-size:13px">Pagamento: ${esc(p.forma_pagamento)}${p.parcelas > 1 && !ocultar(p) ? ` · ${p.parcelas}x de ${fmt(p.valor_parcela)}` : p.parcelas > 1 ? ` · ${p.parcelas}x` : ''}${!ocultar(p) && Number(p.desconto) ? ` · desconto de ${fmt(p.desconto)}` : ''}</div>` : ''}
      ${p.motivo_recusa ? `<div class="msg erro" style="margin-top:8px">Motivo: ${esc(p.motivo_recusa)}</div>` : ''}
      ${p.codigo_rastreio ? `<div class="msg" style="margin-top:8px">Código de rastreio: <b>${esc(p.codigo_rastreio)}</b></div>` : ''}
      ${p.status === 'pendente' ? `<button class="btn btn-bad btn-sm" style="margin-top:8px" data-cancelar="${p.id}">Cancelar pedido</button>` : ''}
    </div>`).join('');
}

async function salvarDados(e) {
  e.preventDefault();
  const f = e.target;
  const dados = Object.fromEntries(['nome', 'telefone', 'cpf', 'cep', 'endereco', 'numero', 'complemento', 'bairro', 'cidade', 'uf']
    .map(k => [k, f[k].value.trim() || null]));
  if (dados.uf) dados.uf = dados.uf.toUpperCase();
  const { error } = await sb.from('clientes').update(dados).eq('id', usuario.id);
  if (error) return toast(erro(error), 'erro');
  Object.assign(cliente || {}, dados);
  toast('Dados atualizados!', 'ok');
}

function trocarAba(dlg, aba) {
  $$(`${dlg} .tabs button`).forEach(b => b.classList.toggle('on', b.dataset.tab === aba));
  if (dlg === '#dlgAuth') {
    $('#formLogin').classList.toggle('hidden', aba !== 'login');
    $('#formCadastro').classList.toggle('hidden', aba !== 'cadastro');
  } else {
    $('#contaPedidos').classList.toggle('hidden', aba !== 'pedidos');
    $('#formDados').classList.toggle('hidden', aba !== 'dados');
  }
}

// ------------------------- eventos -------------------------
function ligarEventos() {
  let t;
  $('#busca').addEventListener('input', e => { clearTimeout(t); t = setTimeout(() => { filtro.busca = e.target.value; render(); }, 200); });
  $('#categorias').addEventListener('click', e => {
    const b = e.target.closest('[data-cat]'); if (!b) return;
    filtro.cat = b.dataset.cat ? Number(b.dataset.cat) : null;
    renderCategorias(); render();
  });
  $('#fGenero').onchange = e => { filtro.genero = e.target.value; render(); };
  $('#fFormato').onchange = e => { filtro.formato = e.target.value; render(); };
  $('#fOrdem').onchange = e => { filtro.ordem = e.target.value; render(); };
  $('#fPolarizado').onchange = e => { filtro.polarizado = e.target.checked; render(); };

  $('#grid').addEventListener('click', e => {
    if (e.target.closest('[data-entrar]')) return abrirAuth('Entre na sua conta para ver os preços.');
    const c = e.target.closest('.card'); if (c) abrirProduto(Number(c.dataset.id));
  });
  $('#cartForma').onchange = () => { $('#cartParcelas').value = 1; renderPagamento(); };
  $('#cartParcelas').onchange = renderPagamento;

  // fechar diálogos (botão X e clique fora)
  $$('dialog').forEach(d => {
    d.addEventListener('click', e => { if (e.target === d || e.target.closest('[data-close]')) d.close(); });
  });
  $('#dlgProduto').addEventListener('close', () => history.replaceState(null, '', location.pathname));

  $('#btnCarrinho').onclick = abrirCarrinho;
  $('#fecharCarrinho').onclick = fecharCarrinho;
  $('#overlay').onclick = fecharCarrinho;
  $('#btnFinalizar').onclick = finalizar;
  $('#cartLista').addEventListener('click', e => {
    const q = e.target.closest('[data-q]');
    if (q) {
      const i = carrinho[Number(q.dataset.n)];
      i.qtd = Math.min(Math.max(1, i.qtd + Number(q.dataset.q)), i.max || 99);
      salvarCarrinho(); renderCarrinho();
    }
    const rm = e.target.closest('[data-rm]');
    if (rm) { carrinho.splice(Number(rm.dataset.rm), 1); salvarCarrinho(); renderCarrinho(); }
    if (e.target.id === 'verPedidos') { fecharCarrinho(); abrirConta(); }
  });

  $('#btnConta').onclick = () => usuario ? abrirConta() : abrirAuth();
  $$('#dlgAuth .tabs button').forEach(b => b.onclick = () => trocarAba('#dlgAuth', b.dataset.tab));
  $$('#dlgConta .tabs button').forEach(b => b.onclick = () => trocarAba('#dlgConta', b.dataset.tab));
  $('#formLogin').onsubmit = entrar;
  $('#formCadastro').onsubmit = cadastrar;
  $('#formDados').onsubmit = salvarDados;
  $('#btnEsqueci').onclick = esqueciSenha;
  U.bindCep($('#formCadastro'));
  U.bindCep($('#formDados'));

  $('#btnSair').onclick = async () => { await sb.auth.signOut(); $('#dlgConta').close(); toast('Você saiu da conta'); };
  $('#contaPedidos').addEventListener('click', async e => {
    const b = e.target.closest('[data-cancelar]'); if (!b) return;
    if (!confirm(`Cancelar o pedido #${b.dataset.cancelar}?`)) return;
    const { error } = await sb.rpc('cancelar_pedido', { p_pedido_id: Number(b.dataset.cancelar), p_motivo: 'Cancelado pelo cliente' });
    if (error) return toast(erro(error), 'erro');
    toast('Pedido cancelado'); carregarPedidos();
  });
}

init();
