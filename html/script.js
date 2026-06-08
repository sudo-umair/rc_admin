(function () {
    'use strict';

    const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'rc_admin';

    async function post(name, data) {
        try {
            const res = await fetch(`https://${RES}/${name}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(data || {}),
            });
            return await res.json();
        } catch (e) {
            return null;
        }
    }

    const $ = (sel, root = document) => root.querySelector(sel);
    const el = (tag, cls, html) => {
        const n = document.createElement(tag);
        if (cls) n.className = cls;
        if (html != null) n.innerHTML = html;
        return n;
    };
    const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) =>
        ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

    // ---- state ----
    const state = {
        elevated: false,
        modules: [],
        active: null,
        // weapon spawner working state
        target: { mode: 'self', id: null, radius: 20 },
        tab: 'weapons',
        search: '',
        category: 'All',
    };

    // ============================ open / close ============================

    function openUI(ctx) {
        state.elevated = !!ctx.elevated;
        state.modules = ctx.modules || [];
        state.active = state.modules[0] ? state.modules[0].id : null;
        state.target = { mode: 'self', id: null, radius: 20 };

        $('#roleBadge').textContent = state.elevated ? 'Elevated' : 'Admin';
        buildNav();
        renderActive();
        $('#app').classList.remove('hidden');
    }

    function closeUI() {
        $('#app').classList.add('hidden');
        closeModal();
    }

    function requestClose() {
        post('close', {});
        closeUI();
    }

    function buildNav() {
        const nav = $('#nav');
        nav.innerHTML = '';
        state.modules.forEach((m) => {
            const item = el('button', 'nav-item' + (m.id === state.active ? ' active' : ''));
            item.innerHTML = `<span class="nav-icon">${esc(m.icon || '•')}</span><span>${esc(m.label)}</span>`;
            item.onclick = () => { state.active = m.id; buildNav(); renderActive(); };
            nav.appendChild(item);
        });
    }

    function moduleById(id) { return state.modules.find((m) => m.id === id); }

    function renderActive() {
        const content = $('#content');
        content.innerHTML = '';
        const m = moduleById(state.active);
        if (!m) { content.appendChild(el('div', 'empty', 'No modules available.')); return; }

        const renderer = RENDERERS[m.id];
        if (renderer) renderer(content, m);
        else content.appendChild(el('div', 'empty', `No UI for module "${esc(m.id)}".`));
    }

    // Renderers keyed by module id — add new modules here as they ship.
    const RENDERERS = {};

    // Shared target selector (Myself / Player ID / Nearby / Everyone) used by
    // every module. Manages state.target and appends the bar to `body`.
    // opts: { label?: string, radius?: number (default for nearby) }
    function buildTargetBar(body, opts) {
        opts = opts || {};
        const defRadius = opts.radius || 20;
        if (!state.target.radius) state.target.radius = defRadius;

        const bar = el('div', 'target-bar');
        bar.appendChild(el('span', 'tb-label', opts.label || 'Apply to'));

        const seg = el('div', 'seg');
        const modes = [
            { id: 'self', label: 'Myself', elevated: false },
            { id: 'id', label: 'Player ID', elevated: false },
            { id: 'nearby', label: 'Nearby', elevated: true },
            { id: 'everyone', label: 'Everyone', elevated: true },
        ];
        const extra = el('div', 'target-extra hidden');

        function refreshExtra() {
            extra.innerHTML = '';
            extra.classList.add('hidden');
            if (state.target.mode === 'id') {
                extra.classList.remove('hidden');
                const inp = el('input');
                inp.type = 'number'; inp.placeholder = 'Server ID'; inp.style.width = '110px';
                inp.className = 'search'; inp.style.padding = '7px 10px';
                inp.value = state.target.id || '';
                const nameTag = el('span', 'target-name');
                let t;
                inp.oninput = () => {
                    state.target.id = inp.value ? parseInt(inp.value, 10) : null;
                    nameTag.textContent = ''; nameTag.className = 'target-name';
                    clearTimeout(t);
                    if (!state.target.id) return;
                    t = setTimeout(async () => {
                        const r = await post('resolvePlayer', { id: state.target.id });
                        if (r && r.name) { nameTag.textContent = r.name; nameTag.className = 'target-name ok'; }
                        else { nameTag.textContent = 'offline'; nameTag.className = 'target-name bad'; }
                    }, 280);
                };
                extra.appendChild(inp);
                extra.appendChild(nameTag);
            } else if (state.target.mode === 'nearby') {
                extra.classList.remove('hidden');
                const inp = el('input');
                inp.type = 'number'; inp.placeholder = 'Radius (m)'; inp.style.width = '120px';
                inp.className = 'search'; inp.style.padding = '7px 10px';
                inp.value = state.target.radius;
                inp.oninput = () => { state.target.radius = parseInt(inp.value, 10) || defRadius; };
                extra.appendChild(inp);
                extra.appendChild(el('span', 'target-name', 'metres'));
            }
        }

        modes.forEach((m) => {
            if (m.elevated && !state.elevated) return;
            const b = el('button', state.target.mode === m.id ? 'active' : '', m.label);
            b.onclick = () => {
                state.target.mode = m.id;
                Array.from(seg.children).forEach((c) => c.classList.remove('active'));
                b.classList.add('active');
                refreshExtra();
            };
            seg.appendChild(b);
        });
        bar.appendChild(seg);
        bar.appendChild(extra);
        body.appendChild(bar);
        refreshExtra();
    }

    // ======================= weapon spawner module =======================

    RENDERERS.weapon_spawner = function (root, mod) {
        const data = mod.data || {};
        const limits = data.limits || {};
        const defaults = data.defaults || {};
        state.target.radius = defaults.radius || 20;

        // header
        const head = el('div', 'content-head');
        head.innerHTML = `<h1>Weapon Spawner</h1><p>Give weapons, ammo &amp; attachments to players.</p>`;
        root.appendChild(head);

        const body = el('div', 'content-body');
        root.appendChild(body);

        buildTargetBar(body, { label: 'Give to', radius: defaults.radius || 20 });

        // ---- tabs ----
        const tabs = el('div', 'tabs');
        [['weapons', 'Weapons'], ['ammo', 'Ammo']].forEach(([id, label]) => {
            const t = el('button', 'tab' + (state.tab === id ? ' active' : ''), label);
            t.onclick = () => { state.tab = id; state.search = ''; renderList(); refreshTabs(); };
            t.dataset.tab = id;
            tabs.appendChild(t);
        });
        body.appendChild(tabs);
        function refreshTabs() {
            Array.from(tabs.children).forEach((c) =>
                c.classList.toggle('active', c.dataset.tab === state.tab));
        }

        // ---- toolbar ----
        const toolbar = el('div', 'toolbar');
        const search = el('input', 'search');
        search.type = 'text';
        search.placeholder = 'Search…';
        search.oninput = () => { state.search = search.value.toLowerCase(); renderList(); };
        toolbar.appendChild(search);

        const chips = el('div', 'chips');
        toolbar.appendChild(chips);
        body.appendChild(toolbar);

        function renderChips() {
            chips.innerHTML = '';
            if (state.tab !== 'weapons') return;
            const cats = ['All'].concat(data.categories || []);
            cats.forEach((c) => {
                const chip = el('button', 'chip' + (state.category === c ? ' active' : ''), c);
                chip.onclick = () => { state.category = c; renderChips(); renderList(); };
                chips.appendChild(chip);
            });
        }

        // ---- list ----
        const grid = el('div', 'grid');
        body.appendChild(grid);

        function renderList() {
            renderChips();
            grid.innerHTML = '';
            const items = (state.tab === 'weapons' ? data.weapons : data.ammo) || [];
            const filtered = items.filter((it) => {
                if (state.tab === 'weapons' && state.category !== 'All' && it.category !== state.category) return false;
                if (!state.search) return true;
                return (it.label || '').toLowerCase().includes(state.search) ||
                       (it.name || '').toLowerCase().includes(state.search);
            });

            if (!filtered.length) {
                grid.appendChild(el('div', 'empty', 'Nothing found.'));
                return;
            }

            filtered.forEach((it) => {
                const card = el('div', 'card');
                card.innerHTML =
                    `<div class="card-thumb">
                        ${it.image ? `<img src="${esc(it.image)}" onerror="this.style.display='none'" />` : ''}
                    </div>
                    <div class="card-info">
                        <div class="card-label">${esc(it.label)}</div>
                        <div class="card-name">${esc(it.name)}</div>
                    </div>
                    <span class="card-give">+</span>`;
                card.onclick = () => (state.tab === 'weapons')
                    ? openWeaponModal(it, data, limits, defaults)
                    : openAmmoModal(it, limits, defaults);
                grid.appendChild(card);
            });
        }

        renderList();
    };

    // ============================ job setter module ============================

    RENDERERS.job_setter = function (root, mod) {
        const data = mod.data || {};
        const jobs = data.jobs || [];
        const radiusCfg = data.radius || {};
        state.target.radius = radiusCfg.default || 20;

        const head = el('div', 'content-head');
        head.innerHTML = `<h1>Set Job</h1><p>Assign an ESX job &amp; grade to players.</p>`;
        root.appendChild(head);

        const body = el('div', 'content-body');
        root.appendChild(body);

        buildTargetBar(body, { label: 'Set for', radius: radiusCfg.default || 20 });

        // ---- toolbar (search) ----
        const toolbar = el('div', 'toolbar');
        const search = el('input', 'search');
        search.type = 'text';
        search.placeholder = 'Search jobs…';
        let query = '';
        search.oninput = () => { query = search.value.toLowerCase(); renderList(); };
        toolbar.appendChild(search);
        body.appendChild(toolbar);

        // ---- list ----
        const grid = el('div', 'grid');
        body.appendChild(grid);

        function renderList() {
            grid.innerHTML = '';
            const filtered = jobs.filter((j) => !query ||
                (j.label || '').toLowerCase().includes(query) ||
                (j.name || '').toLowerCase().includes(query));

            if (!filtered.length) {
                grid.appendChild(el('div', 'empty', 'No jobs found.'));
                return;
            }

            filtered.forEach((j) => {
                const n = (j.grades || []).length;
                const card = el('div', 'card');
                card.innerHTML =
                    `<div class="card-info">
                        <div class="card-label">${esc(j.label)}</div>
                        <div class="card-name">${esc(j.name)} · ${n} grade${n === 1 ? '' : 's'}</div>
                    </div>
                    <span class="card-give">+</span>`;
                card.onclick = () => openJobModal(j);
                grid.appendChild(card);
            });
        }

        renderList();
    };

    function openJobModal(job) {
        if (!validateTarget()) return;
        const grades = job.grades || [];
        const opts = grades.map((g) => {
            const salary = (g.salary != null) ? ` ($${esc(String(g.salary))})` : '';
            return `<option value="${esc(String(g.grade))}">${esc(String(g.grade))} — ${esc(g.label)}${salary}</option>`;
        }).join('');

        const m = el('div');
        m.innerHTML = `
            <div class="modal-head">
                <div><h2>${esc(job.label)}</h2><div class="sub">${esc(job.name)}</div></div>
            </div>
            <div class="field">
                <label>Grade</label>
                <select id="j_grade" class="select">${opts || '<option value="0">0</option>'}</select>
            </div>`;

        const actions = el('div', 'modal-actions');
        const cancel = el('button', 'btn btn-ghost', 'Cancel');
        cancel.onclick = closeModal;
        const setBtn = el('button', 'btn btn-primary', 'Set Job');
        setBtn.onclick = async () => {
            setBtn.disabled = true;
            const grade = parseInt($('#j_grade', m).value, 10) || 0;
            const r = await post('jobs:set', { target: targetPayload(), job: job.name, grade });
            if (r && r.success) { toast('success', r.message || 'Done.'); closeModal(); }
            else { toast('error', (r && r.message) || 'Failed.'); setBtn.disabled = false; }
        };
        actions.appendChild(cancel); actions.appendChild(setBtn);
        m.appendChild(actions);
        showModal(m);
    }

    // ----------------------- give weapon modal -----------------------

    function targetPayload() {
        const m = state.target.mode;
        if (m === 'id') return { mode: 'id', id: state.target.id };
        if (m === 'nearby') return { mode: 'nearby', radius: state.target.radius };
        return { mode: m };
    }

    function validateTarget() {
        if (state.target.mode === 'id' && !state.target.id) {
            toast('error', 'Enter a server ID first.');
            return false;
        }
        return true;
    }

    function openWeaponModal(weapon, data, limits, defaults) {
        if (!validateTarget()) return;
        const lim = limits || {};
        const qLim = lim.quantity || { min: 1, max: 10 };
        const aLim = lim.ammo || { min: 0, max: 9999 };
        const dLim = lim.durability || { min: 1, max: 100 };

        const selected = new Set();

        const m = el('div');
        m.innerHTML = `
            <div class="modal-head">
                <div class="modal-thumb">${weapon.image ? `<img src="${esc(weapon.image)}" onerror="this.style.display='none'" />` : ''}</div>
                <div><h2>${esc(weapon.label)}</h2><div class="sub">${esc(weapon.name)}</div></div>
            </div>
            <div class="field">
                <label>Quantity</label>
                <input type="number" id="m_qty" value="${defaults.quantity || 1}" min="${qLim.min}" max="${qLim.max}">
            </div>
            ${weapon.takesAmmo ? `
            <div class="field">
                <label>Ammo</label>
                <input type="number" id="m_ammo" value="${defaults.ammo || 0}" min="${aLim.min}" max="${aLim.max}">
            </div>` : ''}
            <div class="field">
                <label>Durability</label>
                <div class="range-row">
                    <input type="range" id="m_dur" value="${defaults.durability || 100}" min="${dLim.min}" max="${dLim.max}">
                    <span class="range-val" id="m_dur_val">${defaults.durability || 100}%</span>
                </div>
            </div>`;

        // attachments
        const comps = data.components || [];
        if (comps.length) {
            const f = el('div', 'field');
            f.innerHTML = `<label>Attachments <span style="color:var(--text-dim);font-weight:500">(optional)</span></label>`;
            const cs = el('input', 'attach-search');
            cs.type = 'text'; cs.placeholder = 'Filter attachments…';
            const list = el('div', 'attach-list');
            function drawComps(q) {
                list.innerHTML = '';
                const fil = comps.filter((c) => !q ||
                    (c.label || '').toLowerCase().includes(q) || (c.name || '').toLowerCase().includes(q));
                if (!fil.length) { list.appendChild(el('div', 'attach-empty', 'No attachments.')); return; }
                fil.forEach((c) => {
                    const row = el('label', 'attach-item');
                    const cb = el('input'); cb.type = 'checkbox'; cb.checked = selected.has(c.name);
                    cb.onchange = () => cb.checked ? selected.add(c.name) : selected.delete(c.name);
                    row.appendChild(cb);
                    row.appendChild(el('span', '', esc(c.label)));
                    list.appendChild(row);
                });
            }
            cs.oninput = () => drawComps(cs.value.toLowerCase());
            drawComps('');
            f.appendChild(cs); f.appendChild(list);
            m.appendChild(f);
        }

        const actions = el('div', 'modal-actions');
        const cancel = el('button', 'btn btn-ghost', 'Cancel');
        cancel.onclick = closeModal;
        const give = el('button', 'btn btn-primary', 'Give Weapon');
        give.onclick = async () => {
            give.disabled = true;
            const payload = {
                target: targetPayload(),
                weapon: weapon.name,
                quantity: parseInt($('#m_qty', m).value, 10) || 1,
                ammo: weapon.takesAmmo ? (parseInt($('#m_ammo', m).value, 10) || 0) : 0,
                durability: parseInt($('#m_dur', m).value, 10) || 100,
                components: Array.from(selected),
            };
            const r = await post('weapons:give', payload);
            if (r && r.success) { toast('success', r.message || 'Done.'); closeModal(); }
            else { toast('error', (r && r.message) || 'Failed.'); give.disabled = false; }
        };
        actions.appendChild(cancel); actions.appendChild(give);
        m.appendChild(actions);

        showModal(m);
        const dur = $('#m_dur', m), durVal = $('#m_dur_val', m);
        if (dur) dur.oninput = () => { durVal.textContent = dur.value + '%'; };
    }

    // ----------------------- give ammo modal -----------------------

    function openAmmoModal(ammo, limits, defaults) {
        if (!validateTarget()) return;
        const aLim = (limits && limits.ammo) || { min: 0, max: 9999 };
        const m = el('div');
        m.innerHTML = `
            <div class="modal-head">
                <div class="modal-thumb">${ammo.image ? `<img src="${esc(ammo.image)}" onerror="this.style.display='none'" />` : ''}</div>
                <div><h2>${esc(ammo.label)}</h2><div class="sub">${esc(ammo.name)}</div></div>
            </div>
            <div class="field">
                <label>Amount</label>
                <input type="number" id="a_amt" value="${defaults.ammo || 0}" min="1" max="${aLim.max}">
            </div>`;
        const actions = el('div', 'modal-actions');
        const cancel = el('button', 'btn btn-ghost', 'Cancel');
        cancel.onclick = closeModal;
        const give = el('button', 'btn btn-primary', 'Give Ammo');
        give.onclick = async () => {
            give.disabled = true;
            const r = await post('weapons:giveAmmo', {
                target: targetPayload(),
                ammo: ammo.name,
                amount: parseInt($('#a_amt', m).value, 10) || 0,
            });
            if (r && r.success) { toast('success', r.message || 'Done.'); closeModal(); }
            else { toast('error', (r && r.message) || 'Failed.'); give.disabled = false; }
        };
        actions.appendChild(cancel); actions.appendChild(give);
        m.appendChild(actions);
        showModal(m);
    }

    // ============================ modal host ============================

    function showModal(node) {
        const body = $('#modalBody');
        body.innerHTML = '';
        body.appendChild(node);
        $('#modal').classList.remove('hidden');
    }
    function closeModal() { $('#modal').classList.add('hidden'); $('#modalBody').innerHTML = ''; }

    // ============================ toasts ============================

    function toast(type, message) {
        const t = el('div', 'toast ' + (type || 'inform'), esc(message));
        $('#toasts').appendChild(t);
        setTimeout(() => { t.style.opacity = '0'; t.style.transition = 'opacity .25s'; }, 3200);
        setTimeout(() => t.remove(), 3500);
    }

    // ============================ events ============================

    window.addEventListener('message', (e) => {
        const { action, data } = e.data || {};
        if (action === 'open') openUI(data);
        else if (action === 'close') closeUI();
        else if (action === 'toast') toast(data.type, data.message);
    });

    document.addEventListener('click', (e) => {
        if (e.target.closest('[data-close]')) requestClose();
        else if (e.target.closest('[data-modal-close]')) closeModal();
    });

    document.addEventListener('keydown', (e) => {
        if (e.key !== 'Escape') return;
        if (!$('#modal').classList.contains('hidden')) closeModal();
        else if (!$('#app').classList.contains('hidden')) requestClose();
    });
})();
