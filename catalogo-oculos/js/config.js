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
  parcelasSemJuros: 3,            // mostra "ou 3x de R$ ..." no catálogo
  formasPagamento: ['Pix', 'Cartão de crédito', 'Cartão de débito', 'Boleto', 'A combinar'],
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
  marca: (el, textoHtml) => {
    el.innerHTML = textoHtml;
    if (!APP_CONFIG.logo) return;
    const im = new Image();
    im.onload = () => {
      im.className = 'logo-img'; im.alt = APP_CONFIG.nomeLoja;
      el.replaceChildren(im);
      let fav = document.querySelector('link[rel=icon]');
      if (!fav) { fav = document.createElement('link'); fav.rel = 'icon'; document.head.appendChild(fav); }
      fav.href = im.src;
    };
    im.src = APP_CONFIG.logo + '?v=' + Date.now().toString().slice(0, 7);
  },
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
