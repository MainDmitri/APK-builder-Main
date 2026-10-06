import { loadNotes, saveNotes } from './storage.js';

const list = document.getElementById('list');
const empty = document.getElementById('empty');
const search = document.getElementById('search');
const editor = document.getElementById('editor');
const form = document.getElementById('editor-form');
const titleInput = document.getElementById('title');
const bodyInput = document.getElementById('body');
const deleteButton = document.getElementById('delete');

let notes = loadNotes();
let editingId = null;

const dateFormat = new Intl.DateTimeFormat('ru-RU', { dateStyle: 'medium', timeStyle: 'short' });

function render() {
  const query = search.value.trim().toLowerCase();
  const visible = notes
    .filter((n) => !query || n.title.toLowerCase().includes(query) || n.body.toLowerCase().includes(query))
    .sort((a, b) => b.updatedAt - a.updatedAt);
  list.replaceChildren(...visible.map((note) => {
    const item = document.createElement('li');
    item.className = 'note';
    const h2 = document.createElement('h2');
    h2.textContent = note.title;
    const p = document.createElement('p');
    p.textContent = note.body;
    const time = document.createElement('time');
    time.textContent = dateFormat.format(new Date(note.updatedAt));
    item.append(h2, p, time);
    item.addEventListener('click', () => openEditor(note));
    return item;
  }));
  empty.hidden = notes.length > 0;
}

function openEditor(note) {
  editingId = note ? note.id : null;
  titleInput.value = note ? note.title : '';
  bodyInput.value = note ? note.body : '';
  deleteButton.hidden = !note;
  editor.showModal();
  titleInput.focus();
}

form.addEventListener('submit', () => {
  const title = titleInput.value.trim();
  const body = bodyInput.value.trim();
  if (!title) return;
  const now = Date.now();
  if (editingId) {
    notes = notes.map((n) => (n.id === editingId ? { ...n, title, body, updatedAt: now } : n));
  } else {
    notes.push({ id: crypto.randomUUID(), title, body, createdAt: now, updatedAt: now });
  }
  saveNotes(notes);
  render();
});

deleteButton.addEventListener('click', () => {
  if (editingId && confirm('Удалить заметку?')) {
    notes = notes.filter((n) => n.id !== editingId);
    saveNotes(notes);
    editor.close();
    render();
  }
});

document.getElementById('cancel').addEventListener('click', () => editor.close());
document.getElementById('add').addEventListener('click', () => openEditor(null));
search.addEventListener('input', render);

document.getElementById('export').addEventListener('click', () => {
  const blob = new Blob([JSON.stringify(notes, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `notes-${new Date().toISOString().slice(0, 10)}.json`;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
});

render();
