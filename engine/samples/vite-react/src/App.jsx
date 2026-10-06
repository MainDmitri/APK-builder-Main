import { useEffect, useState } from 'react';
import { Link, Route, Routes, useNavigate, useParams } from 'react-router-dom';
import { loadState, saveState, streak, todayKey } from './storage.js';

function useHabits() {
  const [state, setState] = useState(loadState);
  useEffect(() => saveState(state), [state]);
  const update = (fn) => setState((s) => ({ ...s, habits: fn(s.habits) }));
  return {
    habits: state.habits,
    add: (name) => update((h) => [...h, { id: crypto.randomUUID(), name, done: [] }]),
    remove: (id) => update((h) => h.filter((x) => x.id !== id)),
    toggleToday: (id) =>
      update((h) =>
        h.map((x) => {
          if (x.id !== id) return x;
          const day = todayKey();
          const done = x.done.includes(day) ? x.done.filter((d) => d !== day) : [...x.done, day];
          return { ...x, done };
        }),
      ),
  };
}

function HabitList({ habits, add, toggleToday }) {
  const [name, setName] = useState('');
  const submit = (event) => {
    event.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) return;
    add(trimmed);
    setName('');
  };
  return (
    <div className="mx-auto max-w-xl p-4">
      <form onSubmit={submit} className="mb-4 flex gap-2">
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Новая привычка"
          className="min-h-12 flex-1 rounded-2xl border border-gray-300 px-4 text-base"
        />
        <button className="min-h-12 rounded-2xl bg-green-700 px-5 font-semibold text-white">Добавить</button>
      </form>
      {habits.length === 0 && <p className="mt-12 text-center text-gray-500">Добавьте первую привычку.</p>}
      <ul className="grid gap-3">
        {habits.map((habit) => {
          const doneToday = habit.done.includes(todayKey());
          return (
            <li key={habit.id} className="flex items-center gap-3 rounded-2xl bg-white p-4 shadow">
              <button
                onClick={() => {
                  toggleToday(habit.id);
                  if (!doneToday) navigator.vibrate?.(40);
                }}
                aria-label="Отметить сегодня"
                className={`h-12 w-12 rounded-full border-2 text-xl ${doneToday ? 'border-green-700 bg-green-700 text-white' : 'border-gray-300'}`}
              >
                {doneToday ? '✓' : ''}
              </button>
              <Link to={`/habit/${habit.id}`} className="flex-1">
                <div className="font-semibold">{habit.name}</div>
                <div className="text-sm text-gray-500">Серия: {streak(habit)} дн.</div>
              </Link>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

function HabitDetails({ habits, remove }) {
  const { id } = useParams();
  const navigate = useNavigate();
  const habit = habits.find((h) => h.id === id);
  if (!habit) return <p className="p-4">Привычка не найдена.</p>;
  const last = [...habit.done].sort().reverse().slice(0, 30);
  return (
    <div className="mx-auto max-w-xl p-4">
      <button onClick={() => navigate(-1)} className="mb-4 min-h-12 text-green-700">← Назад</button>
      <h2 className="text-2xl font-bold">{habit.name}</h2>
      <p className="mt-1 text-gray-600">Всего отметок: {habit.done.length}, текущая серия: {streak(habit)} дн.</p>
      <ul className="mt-4 grid gap-1 text-gray-700">
        {last.map((day) => (
          <li key={day}>{new Date(day).toLocaleDateString('ru-RU', { dateStyle: 'long' })}</li>
        ))}
      </ul>
      <button
        onClick={() => {
          if (confirm('Удалить привычку?')) {
            remove(habit.id);
            navigate('/');
          }
        }}
        className="mt-6 min-h-12 rounded-2xl px-4 font-semibold text-red-700"
      >
        Удалить привычку
      </button>
    </div>
  );
}

export default function App() {
  const habits = useHabits();
  return (
    <div className="min-h-screen bg-gray-50">
      <header className="sticky top-0 bg-green-700 px-4 py-3 text-white">
        <h1 className="text-xl font-semibold">Привычки</h1>
      </header>
      <Routes>
        <Route path="/" element={<HabitList {...habits} />} />
        <Route path="/habit/:id" element={<HabitDetails {...habits} />} />
      </Routes>
    </div>
  );
}
