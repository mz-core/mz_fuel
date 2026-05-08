const app = document.getElementById('app');
const fuel = document.getElementById('fuel');
const fill = document.getElementById('fill');
const money = document.getElementById('money');
const moneyBtn = document.getElementById('moneyBtn');
const liters = document.getElementById('liters');
const litersBtn = document.getElementById('litersBtn');
const closeBtn = document.getElementById('close');

const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'mz_fuel';

let pending = false;

function setPending(value) {
  pending = value === true;
  fill.disabled = pending;
  money.disabled = pending;
  moneyBtn.disabled = pending;
  liters.disabled = pending;
  litersBtn.disabled = pending;
}

function post(name, data = {}) {
  if (pending && name !== 'cancel') return;
  if (name !== 'cancel') setPending(true);

  fetch(`https://${resource}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data)
  }).catch(() => {
    setPending(false);
  });
}

function openMenu(data) {
  setPending(false);
  fuel.textContent = `${Math.max(0, Math.min(100, Number(data.fuel || 0))).toFixed(1)}%`;
  fill.style.display = data.allowFillTank === false ? 'none' : 'block';
  money.parentElement.parentElement.style.display = data.allowMoneyAmount === false ? 'none' : 'block';
  liters.parentElement.parentElement.style.display = data.allowLiterAmount === false ? 'none' : 'block';
  money.value = '';
  liters.value = '';
  app.classList.remove('hidden');
}

function closeMenu() {
  setPending(false);
  app.classList.add('hidden');
}

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action === 'open') openMenu(data);
  if (data.action === 'close') closeMenu();
});

fill.addEventListener('click', () => post('refuel_fill'));
moneyBtn.addEventListener('click', () => post('refuel_money', { value: money.value }));
litersBtn.addEventListener('click', () => post('refuel_liters', { value: liters.value }));
closeBtn.addEventListener('click', () => post('cancel'));

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') post('cancel');
});
