// Unit conversion through a base unit per quantity; temperature uses formulas.
const UNITS = {
  'Длина': { 'м': 1, 'км': 1000, 'см': 0.01, 'мм': 0.001, 'миля': 1609.344, 'фут': 0.3048, 'дюйм': 0.0254 },
  'Масса': { 'кг': 1, 'г': 0.001, 'т': 1000, 'фунт': 0.45359237, 'унция': 0.028349523125 },
  'Объём': { 'л': 1, 'мл': 0.001, 'м³': 1000, 'галлон (США)': 3.785411784 },
  'Температура': { '°C': null, '°F': null, 'K': null },
};

const toCelsius = { '°C': (v) => v, '°F': (v) => (v - 32) * 5 / 9, 'K': (v) => v - 273.15 };
const fromCelsius = { '°C': (v) => v, '°F': (v) => v * 9 / 5 + 32, 'K': (v) => v + 273.15 };

const kind = document.getElementById('kind');
const from = document.getElementById('from');
const to = document.getElementById('to');
const value = document.getElementById('value');
const result = document.getElementById('result');
const STORAGE_KEY = 'converter:v1';

function fill(select, options, selected) {
  select.replaceChildren(...options.map((o) => new Option(o, o, false, o === selected)));
}

function convert() {
  const v = Number.parseFloat(value.value.replace(',', '.'));
  if (!Number.isFinite(v)) {
    result.textContent = 'Введите число';
    return;
  }
  const k = kind.value;
  const out = k === 'Температура'
    ? fromCelsius[to.value](toCelsius[from.value](v))
    : (v * UNITS[k][from.value]) / UNITS[k][to.value];
  result.textContent = `${Number(out.toPrecision(10))} ${to.value}`;
  localStorage.setItem(STORAGE_KEY, JSON.stringify({ kind: k, from: from.value, to: to.value, value: value.value }));
}

function selectKind(k, saved) {
  const units = Object.keys(UNITS[k]);
  fill(from, units, saved?.from ?? units[0]);
  fill(to, units, saved?.to ?? units[1]);
  convert();
}

let saved = null;
try { saved = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? 'null'); } catch { saved = null; }
fill(kind, Object.keys(UNITS), saved?.kind ?? 'Длина');
if (saved?.value) value.value = saved.value;
selectKind(kind.value, saved);

kind.addEventListener('change', () => selectKind(kind.value, null));
[from, to].forEach((s) => s.addEventListener('change', convert));
value.addEventListener('input', convert);
document.getElementById('swap').addEventListener('click', () => {
  [from.value, to.value] = [to.value, from.value];
  convert();
});
