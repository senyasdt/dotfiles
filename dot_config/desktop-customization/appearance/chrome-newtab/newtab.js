'use strict';
const $ = id => document.getElementById(id);
const KEY = 'coldGreyShortcuts';
const MAX = 24;
let current, defaults, editingId = null, pendingImport = null, busy = false;

function validate(data) {
  if (!data || data.version !== 1 || !Array.isArray(data.shortcuts) || data.shortcuts.length > MAX) {
    throw new Error('Нужен файл экспорта Cold Grey: версия 1, до 24 ярлыков.');
  }
  const ids = new Set();
  return {version: 1, shortcuts: data.shortcuts.map(item => {
    if (!item || typeof item.name !== 'string' || !item.name.trim() || item.name.trim().length > 40 ||
        typeof item.url !== 'string' || item.url.length > 2048 ||
        typeof item.id !== 'string' || !/^[a-zA-Z0-9_-]{1,80}$/.test(item.id) || ids.has(item.id)) {
      throw new Error('В файле есть некорректный или повторяющийся ярлык.');
    }
    let url;
    try { url = new URL(item.url); } catch { throw new Error('Укажи полный адрес: https://example.com'); }
    if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password) {
      throw new Error('Разрешены только адреса http:// и https:// без логина и пароля.');
    }
    ids.add(item.id);
    return {id: item.id, name: item.name.trim(), url: url.href};
  })};
}

async function read() {
  const data = await chrome.storage.local.get(KEY);
  return data[KEY] === undefined ? structuredClone(defaults) : validate(data[KEY]);
}

async function change(transform) {
  if (busy) throw new Error('Дождись сохранения предыдущего изменения.');
  busy = true;
  try {
    const latest = await read();
    const next = validate(transform(latest));
    await chrome.storage.local.set({[KEY]: next});
    current = next;
    render();
  } finally { busy = false; }
}

function status(error, target = 'settings-status') { $(target).textContent = error.message || String(error); }
function button(text, title, className, callback) {
  const node = document.createElement('button');
  node.type = 'button'; node.textContent = text; node.title = title;
  node.setAttribute('aria-label', title); node.className = className;
  node.addEventListener('click', callback);
  return node;
}
function openEditor(item) {
  editingId = item?.id || null;
  $('editor-title').textContent = item ? 'Изменить ярлык' : 'Добавить ярлык';
  $('shortcut-name').value = item?.name || '';
  $('shortcut-url').value = item?.url || '';
  $('editor-status').textContent = '';
  $('editor').showModal(); $('shortcut-name').focus();
}
function render() {
  $('shortcuts').replaceChildren(); $('shortcut-list').replaceChildren();
  for (const [index, item] of current.shortcuts.entries()) {
    const link = document.createElement('a');
    link.href = item.url; link.className = 'shortcut'; link.title = `${item.name}\n${item.url}`;
    const icon = document.createElement('span'); icon.className = 'shortcut-icon';
    icon.setAttribute('aria-hidden', 'true');
    icon.textContent = Array.from(item.name).slice(0, 2).join('').toUpperCase();
    const label = document.createElement('span'); label.className = 'shortcut-label'; label.textContent = item.name;
    link.append(icon, label); $('shortcuts').append(link);
    const row = document.createElement('div'); row.className = 'shortcut-row';
    row.append(button(item.name, `Изменить ${item.name}`, 'row-name', () => openEditor(item)));
    for (const [delta, symbol, verb] of [[-1, '↑', 'Выше'], [1, '↓', 'Ниже']]) {
      const move = button(symbol, `${verb}: ${item.name}`, 'row-action', async () => {
        try { await change(data => {
          const i = data.shortcuts.findIndex(s => s.id === item.id), j = i + delta;
          if (i >= 0 && j >= 0 && j < data.shortcuts.length) {
            [data.shortcuts[i], data.shortcuts[j]] = [data.shortcuts[j], data.shortcuts[i]];
          }
          return data;
        }); } catch (error) { status(error); }
      });
      move.disabled = index + delta < 0 || index + delta >= current.shortcuts.length;
      row.append(move);
    }
    row.append(button('×', `Удалить ${item.name}`, 'row-action', async () => {
      try { await change(data => ({...data, shortcuts: data.shortcuts.filter(s => s.id !== item.id)})); }
      catch (error) { status(error); }
    }));
    $('shortcut-list').append(row);
  }
  if (!current.shortcuts.length) {
    const empty = document.createElement('p'); empty.className = 'empty';
    empty.textContent = 'Добавь свои сайты через «Настроить».'; $('shortcuts').append(empty);
  }
  $('shortcuts').setAttribute('aria-busy', 'false');
  $('add').disabled = current.shortcuts.length >= MAX;
}

async function start() {
  try {
    defaults = validate(await (await fetch('defaults.json')).json());
    current = await read(); render();
  } catch (error) {
    status(new Error(`Не удалось загрузить ярлыки. ${error.message}`), 'status');
    $('manage').disabled = true;
    return;
  }
  $('manage').addEventListener('click', () => { $('settings-status').textContent = ''; $('settings').showModal(); });
  $('close-settings').addEventListener('click', () => $('settings').close());
  $('add').addEventListener('click', () => openEditor(null));
  for (const id of ['close-editor', 'cancel-editor']) $(id).addEventListener('click', () => $('editor').close());
  for (const id of ['settings', 'editor', 'import-confirm']) {
    $(id).addEventListener('click', event => {
      const r = $(id).getBoundingClientRect();
      if (event.target === $(id) && (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom)) $(id).close();
    });
  }
  $('shortcut-form').addEventListener('submit', async event => {
    event.preventDefault(); $('save').disabled = true;
    try {
      const item = {id: editingId || crypto.randomUUID(), name: $('shortcut-name').value, url: $('shortcut-url').value};
      validate({version: 1, shortcuts: [item]});
      await change(data => {
        if (editingId) {
          const index = data.shortcuts.findIndex(s => s.id === editingId);
          if (index < 0) throw new Error('Ярлык уже удалён в другой вкладке.');
          data.shortcuts[index] = item;
        } else data.shortcuts.push(item);
        return data;
      });
      $('editor').close();
    } catch (error) { status(error, 'editor-status'); }
    finally { $('save').disabled = false; }
  });
  $('export').addEventListener('click', async () => {
    try {
      const data = await read();
      const url = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2) + '\n'], {type: 'application/json'}));
      const a = document.createElement('a'); a.href = url; a.download = 'cold-grey-shortcuts.json'; a.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (error) { status(error); }
  });
  $('import').addEventListener('click', () => $('import-file').click());
  $('import-file').addEventListener('change', async () => {
    const file = $('import-file').files[0]; $('import-file').value = '';
    if (!file) return;
    try {
      if (file.size > 65536) throw new Error('Файл слишком большой: максимум 64 КБ.');
      pendingImport = validate(JSON.parse(await file.text()));
      $('import-summary').textContent = `Заменить текущий список? В файле ${pendingImport.shortcuts.length} ярлыков.`;
      $('import-confirm').showModal();
    } catch (error) { pendingImport = null; status(error); }
  });
  $('cancel-import').addEventListener('click', () => $('import-confirm').close());
  $('confirm-import').addEventListener('click', async () => {
    if (!pendingImport) return;
    $('confirm-import').disabled = true;
    try {
      await change(() => pendingImport); pendingImport = null; $('import-confirm').close();
      $('settings-status').textContent = 'Ярлыки импортированы.';
    } catch (error) { $('import-confirm').close(); status(error); }
    finally { $('confirm-import').disabled = false; }
  });
  $('search').addEventListener('submit', event => {
    $('query').value = $('query').value.trim();
    if (!$('query').value) { event.preventDefault(); $('query').focus(); }
  });
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== 'local' || !changes[KEY]) return;
    try { current = changes[KEY].newValue === undefined ? structuredClone(defaults) : validate(changes[KEY].newValue); render(); }
    catch (error) { status(error, 'status'); }
  });
}
start();
