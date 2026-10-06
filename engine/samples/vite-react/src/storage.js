// Habits and check-ins persisted in localStorage.
const KEY = 'habits:v1';

export function loadState() {
  try {
    const parsed = JSON.parse(localStorage.getItem(KEY) ?? 'null');
    if (parsed && Array.isArray(parsed.habits)) return parsed;
  } catch (error) {
    console.error('Повреждённые данные привычек', error);
  }
  return { habits: [] };
}

export function saveState(state) {
  localStorage.setItem(KEY, JSON.stringify(state));
}

export function todayKey(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

/** Number of consecutive days up to today with a check-in. */
export function streak(habit, today = new Date()) {
  const days = new Set(habit.done);
  let count = 0;
  const cursor = new Date(today);
  while (days.has(todayKey(cursor))) {
    count += 1;
    cursor.setDate(cursor.getDate() - 1);
  }
  return count;
}
