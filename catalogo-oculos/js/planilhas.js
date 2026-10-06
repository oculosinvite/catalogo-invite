// =====================================================================
//  PLANILHAS — exportar e importar (.xlsx / .xls / .csv) em todas as telas
//  Usa a biblioteca SheetJS (carregada no admin.html)
// =====================================================================

const simNao = v => v === true ? 'Sim' : v === false ? 'Não' : v;
const hoje = () => new Date().toLocaleDateString('sv-SE'); // AAAA-MM-DD no fuso local
const chave = s => norm(s).replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');

// Cada coluna: [chave interna, título na planilha, obrigatório?, explicação, somente leitura?]
const COLS = {
  produtos: [
    ['sku', 'SKU produto', 'Sim', 'Código do modelo. É ele que identifica o produto: se já existir, atualiza; se não, cadastra.'],
    ['nome', 'Nome', 'Novo', 'Nome do modelo (obrigatório para produto novo).'],
    ['descricao', 'Descrição', '', 'Texto que aparece na página do produto.'],
    ['categoria', 'Categoria', '', 'Nome da categoria. Se não existir, é criada.'],
    ['marca', 'Marca', '', 'Nome da marca. Se não existir, é criada.'],
    ['genero', 'Gênero', '', 'Masculino, Feminino, Unissex ou Infantil.'],
    ['formato', 'Formato', '', 'Aviador, Redondo, Quadrado, Gatinho...'],
    ['material_armacao', 'Material armação', '', 'Acetato, Metal, TR90...'],
    ['material_lente', 'Material lente', '', 'Policarbonato, Nylon, Cristal...'],
    ['tipo_lente', 'Tipo lente', '', 'Solar, Receituário (grau), Luz azul...'],
    ['polarizado', 'Polarizado', '', 'Sim ou Não.'],
    ['protecao_uv', 'Proteção UV', '', 'Ex.: UV400.'],
    ['largura_lente_mm', 'Largura lente mm', '', 'Número.'],
    ['ponte_mm', 'Ponte mm', '', 'Número.'],
    ['haste_mm', 'Haste mm', '', 'Número.'],
    ['altura_lente_mm', 'Altura lente mm', '', 'Número.'],
    ['peso_g', 'Peso g', '', 'Número.'],
    ['garantia_meses', 'Garantia meses', '', 'Número.'],
    ['ncm', 'NCM', '', 'Código fiscal (sol: 9004.10.00 / armação: 9003.11.00).'],
    ['preco_custo', 'Preço custo', '', 'Ex.: 45,00'],
    ['preco_venda', 'Preço venda', 'Novo', 'Ex.: 189,90 (obrigatório para produto novo).'],
    ['preco_promocional', 'Preço promocional', '', 'Menor que o preço de venda. Coloque 0 para tirar a promoção.'],
    ['destaque', 'Destaque', '', 'Sim ou Não.'],
    ['ativo', 'Ativo', '', 'Sim (aparece na loja) ou Não.'],
    ['imagem_url', 'Foto URL', '', 'Endereço da foto principal (opcional).'],
    ['cor', 'Cor', '', 'Nome da cor. Uma linha por cor; repita o SKU produto em cada linha.'],
    ['cor_hex', 'Cor hex', '', 'Código da cor para a bolinha. Ex.: #1F5168'],
    ['cor_lente', 'Cor lente', '', 'Ex.: Verde G15, Fumê.'],
    ['sku_cor', 'SKU cor', '', 'Código da cor. Se vazio, é gerado automaticamente.'],
    ['estoque', 'Estoque', '', 'Quantidade atual. Se mudar, o ajuste fica registrado no histórico.'],
    ['estoque_minimo', 'Estoque mínimo', '', 'Avisa no painel quando chegar nesse número.'],
    ['cor_ativa', 'Cor ativa', '', 'Sim ou Não.'],
    ['imagem_cor_url', 'Foto cor URL', '', 'Endereço da foto desta cor (opcional).'],
  ],
  estoque: [
    ['sku_cor', 'SKU cor', 'Sim', 'Identifica a cor do produto. Não altere.'],
    ['produto', 'Produto', '', 'Apenas informativo.', true],
    ['cor', 'Cor', '', 'Apenas informativo.', true],
    ['estoque', 'Estoque', 'Sim', 'Quantidade CONTADA. O sistema calcula a diferença e registra no histórico.'],
    ['estoque_minimo', 'Estoque mínimo', '', 'Avisa no painel quando chegar nesse número.'],
    ['custo', 'Custo unitário', '', 'Apenas informativo.', true],
    ['valor', 'Valor em estoque', '', 'Apenas informativo.', true],
    ['observacao', 'Observação', '', 'Motivo do ajuste (ex.: Inventário outubro).'],
  ],
  clientes: [
    ['nome', 'Nome', 'Novo', 'Obrigatório para cliente novo.'],
    ['email', 'E-mail', 'Sim', 'Identifica o cliente: se já existir, atualiza; se não, cadastra.'],
    ['telefone', 'Telefone', '', ''],
    ['cpf', 'CPF', '', 'Formate a coluna como Texto no Excel para não perder o zero do início.'],
    ['data_nascimento', 'Nascimento', '', 'DD/MM/AAAA'],
    ['cep', 'CEP', '', ''],
    ['endereco', 'Endereço', '', ''],
    ['numero', 'Número', '', ''],
    ['complemento', 'Complemento', '', ''],
    ['bairro', 'Bairro', '', ''],
    ['cidade', 'Cidade', '', ''],
    ['uf', 'UF', '', 'Sigla do estado. Ex.: GO'],
    ['ativo', 'Ativo', '', 'Sim ou Não (inativo não consegue fazer pedidos).'],
    ['possui_login', 'Possui login', '', 'Apenas informativo. Cliente importado cria o login na loja com o mesmo e-mail.', true],
    ['pedidos', 'Pedidos', '', 'Apenas informativo.', true],
    ['criado_em', 'Cadastrado em', '', 'Apenas informativo.', true],
  ],
  categorias: [
    ['id', 'ID', '', 'Deixe vazio para cadastrar nova. Preenchido = atualiza essa categoria (permite renomear).'],
    ['nome', 'Nome', 'Sim', ''],
    ['ordem', 'Ordem', '', 'Posição no menu da loja.'],
    ['descricao', 'Descrição', '', ''],
    ['ativo', 'Ativo', '', 'Sim ou Não.'],
    ['produtos', 'Produtos', '', 'Apenas informativo.', true],
  ],
  marcas: [
    ['id', 'ID', '', 'Deixe vazio para cadastrar nova. Preenchido = atualiza essa marca (permite renomear).'],
    ['nome', 'Nome', 'Sim', ''],
    ['ativo', 'Ativo', '', 'Sim ou Não.'],
    ['produtos', 'Produtos', '', 'Apenas informativo.', true],
  ],
  atributos: [
    ['tipo', 'Tipo', 'Novo', 'Formato, Material da armação, Material da lente ou Tipo de lente.'],
    ['id', 'ID', '', 'Deixe vazio para cadastrar nova. Preenchido = atualiza essa opção (permite renomear; os produtos acompanham).'],
    ['nome', 'Nome', 'Sim', ''],
    ['ordem', 'Ordem', '', 'Posição na lista.'],
    ['ativo', 'Ativo', '', 'Sim ou Não.'],
    ['produtos', 'Produtos', '', 'Apenas informativo.', true],
  ],
  formas: [
    ['nome', 'Nome'], ['descricao', 'Descrição'], ['desconto_percentual', 'Desconto %'], ['max_parcelas', 'Máx. parcelas'],
    ['parcelas_sem_juros', 'Sem juros até'], ['juros_mes', 'Juros % a.m.'], ['parcela_minima', 'Parcela mínima'],
    ['ordem', 'Ordem'], ['ativo', 'Ativo'], ['simulacao', 'Simulação R$ 300'],
  ],
  pedidos: [
    ['pedido', 'Pedido'], ['data', 'Data'], ['status', 'Status'], ['cliente', 'Cliente'], ['email', 'E-mail'],
    ['telefone', 'Telefone'], ['cidade', 'Cidade/UF'], ['pagamento', 'Pagamento'], ['parcelas', 'Parcelas'], ['item', 'Item'],
    ['qtd', 'Qtd'], ['preco', 'Preço unitário'], ['custo', 'Custo unitário'], ['total_item', 'Total item'],
    ['lucro_item', 'Lucro item'], ['subtotal', 'Subtotal pedido'], ['desconto', 'Desconto'], ['juros', 'Juros'], ['total_pedido', 'Total pedido'], ['rastreio', 'Rastreio'], ['obs', 'Observação'],
  ],
};

// ------------------------- buscar dados para exportar -------------------------
const LINHAS = {
  async produtos() {
    const { data, error } = await sb.from('produtos').select('*, produto_cores(*), categorias(nome), marcas(nome)').order('nome');
    if (error) throw error;
    return data.flatMap(p => {
      const base = { ...p, categoria: p.categorias?.nome, marca: p.marcas?.nome };
      const cores = [...p.produto_cores].sort((a, b) => a.id - b.id);
      if (!cores.length) return [base];
      // dados do produto só na 1ª linha de cada modelo; as linhas seguintes têm só o SKU e a cor
      return cores.map((c, i) => ({ ...(i === 0 ? base : { sku: p.sku }), cor: c.cor, cor_hex: c.cor_hex, cor_lente: c.cor_lente, sku_cor: c.sku,
        estoque: c.estoque, estoque_minimo: c.estoque_minimo, cor_ativa: c.ativo, imagem_cor_url: c.imagem_url }));
    });
  },
  async estoque() {
    const { data, error } = await sb.from('produto_cores').select('*, produtos(nome, preco_custo)').order('produto_id').order('id');
    if (error) throw error;
    return data.map(c => ({ sku_cor: c.sku, produto: c.produtos?.nome, cor: c.cor, estoque: c.estoque,
      estoque_minimo: c.estoque_minimo, custo: c.produtos?.preco_custo, valor: c.estoque * (c.produtos?.preco_custo || 0) }));
  },
  async clientes() {
    const { data, error } = await sb.from('clientes').select('*, pedidos(count)').order('nome');
    if (error) throw error;
    return data.map(c => ({ ...c, ativo: !c.bloqueado, pedidos: c.pedidos?.[0]?.count ?? 0,
      data_nascimento: c.data_nascimento ? c.data_nascimento.split('-').reverse().join('/') : '',
      criado_em: new Date(c.criado_em).toLocaleDateString('pt-BR') }));
  },
  async categorias() {
    const [{ data, error }, { data: ps }] = await Promise.all([
      sb.from('categorias').select('*').order('ordem'), sb.from('produtos').select('categoria_id')]);
    if (error) throw error;
    return data.map(c => ({ ...c, produtos: (ps || []).filter(p => p.categoria_id === c.id).length }));
  },
  async marcas() {
    const [{ data, error }, { data: ps }] = await Promise.all([
      sb.from('marcas').select('*').order('nome'), sb.from('produtos').select('marca_id')]);
    if (error) throw error;
    return data.map(m => ({ ...m, produtos: (ps || []).filter(p => p.marca_id === m.id).length }));
  },
  async atributos() {
    const NOMES = { formato: 'Formato', material_armacao: 'Material da armação', material_lente: 'Material da lente', tipo_lente: 'Tipo de lente' };
    const [{ data, error }, { data: ps }] = await Promise.all([
      sb.from('opcoes').select('*').order('tipo').order('ordem').order('nome'),
      sb.from('produtos').select('formato, material_armacao, material_lente, tipo_lente')]);
    if (error) throw error;
    return data.map(o => ({ ...o, tipo: NOMES[o.tipo], produtos: (ps || []).filter(p => p[o.tipo] === o.nome).length }));
  },
  async formas() {
    const { data, error } = await sb.from('formas_pagamento').select('*').order('ordem');
    if (error) throw error;
    return data.map(f => ({ ...f, simulacao: simulacao(f).replace(/\u00a0/g, ' ') }));
  },
  async pedidos() {
    const st = $('#fStatus').value;
    let q = sb.from('pedidos').select('*, clientes(nome, email, telefone), itens_pedido(*)').order('criado_em', { ascending: false });
    if (st) q = q.eq('status', st);
    const { data, error } = await q;
    if (error) throw error;
    return data.flatMap(p => p.itens_pedido.map(i => ({
      pedido: p.id, data: new Date(p.criado_em).toLocaleString('pt-BR'), status: statusLabel(p.status),
      cliente: p.clientes?.nome, email: p.clientes?.email, telefone: p.clientes?.telefone,
      cidade: [p.endereco_entrega?.cidade, p.endereco_entrega?.uf].filter(Boolean).join('/'),
      pagamento: p.forma_pagamento, parcelas: p.parcelas, subtotal: p.subtotal, desconto: p.desconto, juros: p.juros, item: i.descricao, qtd: i.quantidade, preco: i.preco_unitario, custo: i.preco_custo,
      total_item: i.preco_unitario * i.quantidade, lucro_item: (i.preco_unitario - i.preco_custo) * i.quantidade,
      total_pedido: p.valor_total, rastreio: p.codigo_rastreio, obs: p.observacao })));
  },
};

// ------------------------- como importar cada tipo -------------------------
const IMPORTAR = {
  produtos:   l => sb.rpc('admin_importar_produtos', { p_linhas: l }),
  estoque:    l => sb.rpc('admin_importar_estoque', { p_linhas: l }),
  clientes:   l => sb.rpc('admin_importar_clientes', { p_linhas: l }),
  categorias: l => sb.rpc('admin_importar_cadastro', { p_tabela: 'categorias', p_linhas: l }),
  marcas:     l => sb.rpc('admin_importar_cadastro', { p_tabela: 'marcas', p_linhas: l }),
  atributos:  l => sb.rpc('admin_importar_opcoes', { p_linhas: l }),
};
const RESULTADO = {
  produtos:   r => `${r.produtos_novos} produto(s) novo(s), ${r.produtos_atualizados} atualizado(s), ${r.cores_novas} cor(es) nova(s), ${r.cores_atualizadas} cor(es) atualizada(s), ${r.ajustes_estoque} ajuste(s) de estoque.`,
  estoque:    r => `${r.estoque_alterado} item(ns) com estoque ajustado, ${r.sem_alteracao} sem alteração.`,
  clientes:   r => `${r.clientes_novos} cliente(s) novo(s), ${r.clientes_atualizados} atualizado(s).`,
  categorias: r => `${r.novos} categoria(s) nova(s), ${r.atualizados} atualizada(s).`,
  marcas:     r => `${r.novos} marca(s) nova(s), ${r.atualizados} atualizada(s).`,
  atributos:  r => `${r.novos} opção(ões) nova(s), ${r.atualizados} atualizada(s).`,
};
const RECARREGAR = {
  produtos: () => { carregarBase(); return carregarProdutos(); },
  estoque: () => carregarEstoque(),
  clientes: () => carregarClientes(),
  categorias: async () => { await carregarBase(); renderCategorias(); },
  marcas: async () => { await carregarBase(); renderCategorias(); },
  atributos: async () => { await carregarBase(); renderCategorias(); },
};
const TITULO = { atributos: 'Atributos do produto', formas: 'Formas de pagamento', produtos: 'Produtos', estoque: 'Estoque', clientes: 'Clientes', categorias: 'Categorias', marcas: 'Marcas', pedidos: 'Pedidos' };

// ------------------------- EXPORTAR -------------------------
async function exportar(tipo, modelo = false) {
  if (!window.XLSX) return toast('Biblioteca de planilhas não carregou. Verifique a internet e recarregue a página.', 'erro');
  try {
    const cols = COLS[tipo];
    const linhas = modelo ? [] : await LINHAS[tipo]();
    const wb = XLSX.utils.book_new();
    const aoa = [cols.map(c => c[1]), ...linhas.map(l => cols.map(c => simNao(l[c[0]]) ?? ''))];
    const ws = XLSX.utils.aoa_to_sheet(aoa);
    ws['!cols'] = cols.map(c => ({ wch: Math.max(12, c[1].length + 2) }));
    ws['!autofilter'] = { ref: XLSX.utils.encode_range({ s: { r: 0, c: 0 }, e: { r: Math.max(aoa.length - 1, 1), c: cols.length - 1 } }) };
    XLSX.utils.book_append_sheet(wb, ws, 'Dados');

    if (IMPORTAR[tipo]) {
      const ajuda = [
        [`Como importar ${TITULO[tipo]}`], [],
        ['1. Preencha/edite a aba "Dados" (não mude os títulos da primeira linha).'],
        ['2. No painel, clique em "Importar" e escolha este arquivo.'],
        ['3. Confira a prévia e confirme. Se alguma linha tiver erro, nada é gravado e o sistema diz qual linha corrigir.'],
        ['Célula vazia = mantém o valor atual. Colunas que você não precisa podem ser apagadas (menos as obrigatórias).'],
        ...(tipo === 'produtos' ? [['Uma linha por COR. Os dados do produto (nome, preços, categoria...) ficam na 1ª linha do modelo; nas linhas das outras cores repita só o SKU produto.']] : []),
        [],
        ['Coluna', 'Obrigatória', 'Como preencher'],
        ...cols.map(c => [c[1], c[2] === 'Novo' ? 'Só para novos' : c[2] || '', c[3] || '']),
      ];
      const wa = XLSX.utils.aoa_to_sheet(ajuda);
      wa['!cols'] = [{ wch: 22 }, { wch: 14 }, { wch: 90 }];
      XLSX.utils.book_append_sheet(wb, wa, 'Instruções');
    }
    XLSX.writeFile(wb, `${tipo}${modelo ? '-modelo' : ''}-${hoje()}.xlsx`);
    toast(modelo ? 'Modelo baixado' : `${linhas.length} linha(s) exportada(s)`, 'ok');
  } catch (e) { toast(erro(e), 'erro'); }
}

// ------------------------- IMPORTAR -------------------------
let importacao = null;

function escolherArquivo() {
  return new Promise(res => {
    const inp = document.createElement('input');
    inp.type = 'file'; inp.accept = '.xlsx,.xls,.csv,.ods';
    inp.onchange = () => res(inp.files[0] || null);
    inp.click();
  });
}

function valorCelula(v, k) {
  if (v instanceof Date) {
    if (isNaN(v)) return '';
    const d = new Date(v.getTime() - v.getTimezoneOffset() * 60000);
    return d.toISOString().slice(0, 10);
  }
  if (typeof v === 'boolean') return v ? 'Sim' : 'Não';
  if (typeof v === 'number') {
    if (k === 'cpf' && Number.isInteger(v)) return String(v).padStart(11, '0');
    if (k === 'cep' && Number.isInteger(v)) return String(v).padStart(8, '0');
    return String(v);
  }
  return String(v ?? '').trim();
}

async function importar(tipo) {
  if (!window.XLSX) return toast('Biblioteca de planilhas não carregou. Verifique a internet e recarregue a página.', 'erro');
  const arq = await escolherArquivo();
  if (!arq) return;
  try {
    const wb = XLSX.read(await arq.arrayBuffer(), { type: 'array', cellDates: true });
    const nomeAba = wb.SheetNames.find(n => chave(n) === 'dados') || wb.SheetNames[0];
    const brutas = XLSX.utils.sheet_to_json(wb.Sheets[nomeAba], { defval: '', raw: true, blankrows: true });
    if (!brutas.length) return toast('A planilha está vazia', 'erro');

    // reconhece os títulos (aceita o título ou o nome interno, sem acento/maiúscula)
    const mapaTitulos = {};
    COLS[tipo].forEach(([k, label, , , ro]) => { if (!ro) { mapaTitulos[chave(label)] = k; mapaTitulos[chave(k)] = k; } });
    const titulos = Object.keys(brutas[0]);
    const reconhecidas = [], ignoradas = [];
    titulos.forEach(t => (mapaTitulos[chave(t)] ? reconhecidas : ignoradas).push(t));

    const linhas = brutas.map(b => {
      const o = {};
      for (const t of reconhecidas) {
        const k = mapaTitulos[chave(t)], v = valorCelula(b[t], k);
        if (v !== '') o[k] = v;
      }
      return o;
    });
    // remove linhas totalmente vazias do final, mas mantém a numeração das linhas do meio
    while (linhas.length && !Object.keys(linhas[linhas.length - 1]).length) linhas.pop();

    const obrig = COLS[tipo].filter(c => c[2] === 'Sim').map(c => c[0]);
    const faltando = obrig.filter(k => !reconhecidas.some(t => mapaTitulos[chave(t)] === k))
                          .map(k => COLS[tipo].find(c => c[0] === k)[1]);

    const conflitos = tipo === 'produtos' ? conflitosProduto(linhas) : [];
    importacao = { tipo, linhas };
    abrirPrevia(arq.name, tipo, linhas, reconhecidas, ignoradas, faltando, nomeAba, conflitos);
  } catch (e) { toast('Não consegui ler o arquivo: ' + erro(e), 'erro'); }
}

// Mesmo produto (SKU) em várias linhas com valores diferentes para o mesmo campo → bloqueia
const CAMPOS_PRODUTO = COLS.produtos.slice(1, COLS.produtos.findIndex(c => c[0] === 'cor')).map(c => c[0]);
const valorComparavel = v => /^[R$\s\d.,-]+$/.test(v) && /\d/.test(v)
  ? String(Number(v.replace(/[R$\s]/g, '').replace(/\.(?=\d{3}(\D|$))/g, '').replace(',', '.')))
  : norm(v);
function conflitosProduto(linhas) {
  const visto = {}, msgs = [];
  linhas.forEach((l, i) => {
    if (!l.sku) return;
    const reg = visto[l.sku] ||= {};
    for (const k of CAMPOS_PRODUTO) {
      if (l[k] == null) continue;
      if (reg[k] && valorComparavel(reg[k].v) !== valorComparavel(l[k])) {
        const nome = COLS.produtos.find(c => c[0] === k)[1];
        msgs.push(`SKU <b>${esc(l.sku)}</b>: “${esc(nome)}” está <b>${esc(reg[k].v)}</b> na linha ${reg[k].linha} e <b>${esc(l[k])}</b> na linha ${i + 2}.`);
      } else if (!reg[k]) reg[k] = { v: l[k], linha: i + 2 };
    }
  });
  return msgs;
}

function abrirPrevia(nomeArq, tipo, linhas, reconhecidas, ignoradas, faltando, aba, conflitos = []) {
  const mostrar = linhas.slice(0, 8);
  const cols = [...new Set(mostrar.flatMap(Object.keys))];
  const label = k => COLS[tipo].find(c => c[0] === k)?.[1] || k;
  $('#impTitulo').textContent = `Importar ${TITULO[tipo]}`;
  $('#impCorpo').innerHTML = `
    <p style="margin-top:0"><b>${esc(nomeArq)}</b> <span class="muted">(aba “${esc(aba)}”)</span> — <b>${linhas.length}</b> linha(s) encontrada(s).</p>
    ${conflitos.length ? `<div class="msg erro" style="margin-bottom:10px"><b>Valores diferentes para o mesmo produto.</b> Os dados do produto (nome, preços, categoria...) valem para todas as cores. Deixe igual em todas as linhas do modelo, ou preencha só na primeira e deixe vazio nas outras:<ul style="margin:6px 0 0;padding-left:18px">${conflitos.slice(0, 10).map(m => `<li>${m}</li>`).join('')}</ul>${conflitos.length > 10 ? `<small>…e mais ${conflitos.length - 10}.</small>` : ''}</div>` : ''}
    ${faltando.length ? `<div class="msg erro">Faltam colunas obrigatórias: <b>${faltando.map(esc).join(', ')}</b>. Baixe o modelo para ver os títulos certos.</div>` : ''}
    <p style="font-size:14px"><b>Colunas reconhecidas:</b> ${reconhecidas.map(t => `<span class="st st-entregue">${esc(t)}</span>`).join(' ') || '—'}</p>
    ${ignoradas.length ? `<p style="font-size:14px"><b>Ignoradas</b> (informativas ou não reconhecidas): ${ignoradas.map(t => `<span class="st">${esc(t)}</span>`).join(' ')}</p>` : ''}
    <div class="tbl-wrap" style="max-height:300px;overflow:auto">
      <table class="tbl"><thead><tr><th>Linha</th>${cols.map(k => `<th>${esc(label(k))}</th>`).join('')}</tr></thead>
      <tbody>${mostrar.map((l, i) => `<tr><td class="muted">${i + 2}</td>${cols.map(k => `<td>${esc(l[k] ?? '')}</td>`).join('')}</tr>`).join('')}</tbody></table>
    </div>
    ${linhas.length > 8 ? `<p class="muted" style="font-size:13px">Mostrando as 8 primeiras de ${linhas.length} linhas.</p>` : ''}
    <p class="msg" style="margin-bottom:0">Célula vazia mantém o valor atual. Se alguma linha tiver erro, <b>nada é gravado</b> e você verá qual linha corrigir.</p>
    <div id="impResultado" style="margin-top:12px"></div>`;
  $('#btnImpConfirmar').disabled = !!faltando.length || !!conflitos.length || !linhas.length;
  $('#btnImpConfirmar').classList.remove('hidden');
  $('#dlgImport').showModal();
}

$('#btnImpConfirmar').onclick = async () => {
  if (!importacao) return;
  const { tipo, linhas } = importacao, btn = $('#btnImpConfirmar');
  btn.disabled = true; btn.textContent = 'Importando…';
  const { data: r, error } = await IMPORTAR[tipo](linhas);
  btn.textContent = 'Confirmar importação';
  if (error) {
    btn.disabled = false;
    $('#impResultado').innerHTML = `<div class="msg erro"><b>Nada foi gravado.</b> ${esc(erro(error))}<br>Corrija a planilha e importe de novo.</div>`;
    return;
  }
  importacao = null;
  btn.classList.add('hidden');
  $('#impResultado').innerHTML = `<div class="msg ok"><b>Importação concluída!</b> ${esc(RESULTADO[tipo](r))}</div>`;
  toast('Importação concluída', 'ok');
  RECARREGAR[tipo]();
};

// ------------------------- botões em todas as telas -------------------------
document.addEventListener('click', e => {
  const ex = e.target.closest('[data-exportar]'); if (ex) return exportar(ex.dataset.exportar);
  const mo = e.target.closest('[data-modelo]');   if (mo) return exportar(mo.dataset.modelo, true);
  const im = e.target.closest('[data-importar]'); if (im) return importar(im.dataset.importar);
});
