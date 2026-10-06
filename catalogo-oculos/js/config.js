// =====================================================================
//  CONFIGURAÇÃO — edite só este arquivo
//  Pegue os valores em: Supabase > Project Settings > API Keys / Data API
// =====================================================================
window.APP_CONFIG = {
  SUPABASE_URL: 'https://pfxjfklcmccnfxxmhtod.supabase.co',
  SUPABASE_KEY: 'sb_publishable_Kcwaz6wOx86NnMhcaT5uxw__wNTFJ3s',   // "anon" ou "publishable" (NUNCA a service_role/secret)

  nomeLoja: 'Invite',
  logo: 'logo.png',               // arquivo da logomarca (mesma pasta do index.html). Sem o arquivo, mostra o nome

  whatsapp: '5562999999999',      // DDI+DDD+número, só dígitos. Deixe '' para esconder
  // Formas de pagamento, parcelamento e exibição de preços agora ficam no painel: Configurações
};

window.sb = window.supabase.createClient(APP_CONFIG.SUPABASE_URL, APP_CONFIG.SUPABASE_KEY);

// ---- utilidades compartilhadas (loja e admin) ----
window.U = {
  $:  (s, el = document) => el.querySelector(s),
  $$: (s, el = document) => [...el.querySelectorAll(s)],
  fmt: v => Number(v || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' }),
  data: d => d ? new Date(d).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' }) : '',
  esc: s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
  hex: h => /^#[0-9a-f]{3,8}$/i.test(h || '') ? h : '#cccccc',
  norm: s => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase(),
  img: url => url || 'data:image/svg+xml;utf8,' + encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300"><rect width="400" height="300" fill="#f1eee8"/>' +
    '<g fill="none" stroke="#b9b2a6" stroke-width="10"><circle cx="135" cy="160" r="55"/><circle cx="265" cy="160" r="55"/>' +
    '<path d="M190 155q10-14 20 0M80 150 40 120M320 150l40-30"/></g></svg>'),
  erro: e => {
    const m = e?.message || String(e);
    if (/Invalid login/i.test(m)) return 'E-mail ou senha incorretos';
    if (/Email not confirmed/i.test(m)) return 'Confirme seu e-mail antes de entrar (veja sua caixa de entrada)';
    if (/already registered/i.test(m)) return 'Este e-mail já tem cadastro. Use "Entrar".';
    if (/Password should be/i.test(m)) return 'A senha precisa ter pelo menos 6 caracteres';
    if (/foreign key|violates.*constraint.*itens_pedido/i.test(m)) return 'Não é possível excluir: já existem pedidos com este item. Use "Inativar" para tirá-lo da loja sem perder o histórico.';
    if (/duplicate key.*sku/i.test(m)) return 'Já existe um produto/cor com esse SKU';
    if (/duplicate key/i.test(m)) return 'Registro duplicado (nome ou código já existe)';
    if (/Failed to fetch|NetworkError/i.test(m)) return 'Sem conexão com o servidor. Verifique o js/config.js';
    return m;
  },
  toast: (msg, tipo = '') => {
    let t = document.getElementById('toast');
    if (!t) { t = document.createElement('div'); t.id = 'toast'; document.body.appendChild(t); }
    t.textContent = msg; t.className = 'show ' + tipo;
    clearTimeout(t._h); t._h = setTimeout(() => t.className = '', 3800);
  },
  statusLabel: s => ({ pendente: 'Aguardando aprovação', aprovado: 'Aprovado', recusado: 'Recusado',
                       enviado: 'Enviado', entregue: 'Entregue', cancelado: 'Cancelado' }[s] || s),
  // Mostra a logomarca (ou o nome da loja, se o arquivo não existir) e usa como ícone da aba
  marca: (el, textoHtml, logo = APP_CONFIG.logo, nome = APP_CONFIG.nomeLoja) => {
    const vez = el._marcaVez = (el._marcaVez || 0) + 1;   // ignora carregamentos antigos
    if (!el.querySelector('img') || !logo) el.innerHTML = textoHtml;
    if (!logo) return;
    const im = new Image();
    im.onerror = () => { if (vez === el._marcaVez) el.innerHTML = textoHtml; };
    im.onload = () => {
      if (vez !== el._marcaVez) return;
      im.className = 'logo-img'; im.alt = nome;
      el.replaceChildren(im);
      let fav = document.querySelector('link[rel=icon]');
      if (!fav) { fav = document.createElement('link'); fav.rel = 'icon'; document.head.appendChild(fav); }
      fav.href = im.src;
    };
    im.src = /^(data:|https?:)/.test(logo) && logo.includes('/storage/') ? logo : logo + (logo.includes('?') ? '&' : '?') + 'v=' + Date.now().toString().slice(0, 7);
  },
  // Aplica a aparência salva no painel (Configurações → Aparência da loja)
  aparencia: cfg => {
    const r = document.documentElement.style;
    if (/^#[0-9a-f]{6}$/i.test(cfg?.cor_principal || '')) {
      r.setProperty('--accent', cfg.cor_principal);
      r.setProperty('--ink', `color-mix(in srgb, ${cfg.cor_principal} 50%, #0b0f12)`);   // tom escuro da mesma cor
    }
    if (/^#[0-9a-f]{6}$/i.test(cfg?.cor_destaque || '')) r.setProperty('--gold', cfg.cor_destaque);
    return {
      nome: cfg?.nome_loja || APP_CONFIG.nomeLoja,
      logo: cfg?.logo_url || APP_CONFIG.logo,
      whatsapp: cfg?.whatsapp || APP_CONFIG.whatsapp,
    };
  },
  // Mesmo cálculo do servidor (calcular_pagamento). O valor oficial é sempre o do servidor.
  calcPagamento: (subtotal, f, n = 1) => {
    const r2 = x => Math.round(Number((x * 100).toFixed(6))) / 100; // arredonda igual ao banco
    n = Math.max(1, Math.min(Number(n) || 1, f.max_parcelas));
    const desconto = r2(subtotal * Number(f.desconto_percentual) / 100);
    const base = subtotal - desconto;
    let parcela, total;
    if (n <= f.parcelas_sem_juros || Number(f.juros_mes) === 0) { parcela = r2(base / n); total = base; }
    else { const i = Number(f.juros_mes) / 100; parcela = r2(base * i / (1 - Math.pow(1 + i, -n))); total = r2(parcela * n); }
    return { n, desconto, juros: r2(total - base), total, parcela, semJuros: total === base,
             ok: n === 1 || parcela >= Number(f.parcela_minima) };
  },
  // Maior número de parcelas permitido para esse valor
  maxParcelas: (subtotal, f) => {
    for (let n = f.max_parcelas; n > 1; n--) if (U.calcPagamento(subtotal, f, n).ok) return n;
    return 1;
  },
  // Melhor "Nx sem juros" entre as formas ativas (para mostrar no catálogo)
  melhorParcelamento: (preco, formas) => {
    let melhor = null;
    for (const f of formas) {
      for (let n = Math.min(f.max_parcelas, f.parcelas_sem_juros); n > 1; n--) {
        const c = U.calcPagamento(preco, f, n);
        if (c.ok) { if (!melhor || n > melhor.n) melhor = { ...c, forma: f.nome }; break; }
      }
    }
    return melhor;
  },
  // Maior desconto à vista (ex.: Pix 5%)
  melhorDesconto: (preco, formas) => {
    const f = formas.filter(f => Number(f.desconto_percentual) > 0).sort((a, b) => b.desconto_percentual - a.desconto_percentual)[0];
    return f ? { ...U.calcPagamento(preco, f, 1), forma: f.nome, pct: Number(f.desconto_percentual) } : null;
  },
  // "Rua X, 10 - Apto 2 - Centro, Goiânia/GO - CEP 74000-000"
  enderecoTexto: o => {
    if (!o) return '';
    const rua = [o.endereco, o.numero].filter(Boolean).join(', ');
    const cid = [o.cidade, o.uf].filter(Boolean).join('/');
    return [rua, o.complemento, [o.bairro, cid].filter(Boolean).join(', '), o.cep ? 'CEP ' + o.cep : '']
      .filter(Boolean).join(' - ');
  },
  linkMapa: o => 'https://www.google.com/maps/search/?api=1&query=' +
    encodeURIComponent([o.endereco, o.numero, o.bairro, o.cidade, o.uf, o.cep].filter(Boolean).join(', ')),
  linkZap: tel => { const n = String(tel || '').replace(/\D/g, ''); return n.length >= 10 ? 'https://wa.me/' + (n.startsWith('55') ? n : '55' + n) : ''; },
  // Preenche endereço pelo CEP (ViaCEP)
  bindCep: form => {
    const cep = form.elements.cep; if (!cep) return;
    cep.addEventListener('blur', async () => {
      const n = cep.value.replace(/\D/g, ''); if (n.length !== 8) return;
      try {
        const r = await (await fetch(`https://viacep.com.br/ws/${n}/json/`)).json();
        if (r.erro) return;
        form.elements.endereco.value = r.logradouro || form.elements.endereco.value;
        form.elements.bairro.value   = r.bairro     || form.elements.bairro.value;
        form.elements.cidade.value   = r.localidade || form.elements.cidade.value;
        form.elements.uf.value       = r.uf         || form.elements.uf.value;
        form.elements.numero.focus();
      } catch { /* sem internet: ignora */ }
    });
  },
};
