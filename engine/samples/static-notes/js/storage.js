// Persistent storage of notes in localStorage (JSON, versioned key).
const KEY = 'notes:v1';

export function loadNotes() {
  try {
    const raw = localStorage.getItem(KEY);
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    console.error('Повреждённые данные заметок', error);
    return [];
  }
}

export function saveNotes(notes) {
  localStorage.setItem(KEY, JSON.stringify(notes));
}
