const app = document.getElementById('app');
const progress = document.getElementById('progress');
const title = document.getElementById('title');
const subtitle = document.getElementById('subtitle');
const currentFuelLabel = document.getElementById('currentFuelLabel');
const priceLabel = document.getElementById('priceLabel');
const capacityLabel = document.getElementById('capacityLabel');
const fuel = document.getElementById('fuel');
const price = document.getElementById('price');
const capacity = document.getElementById('capacity');
const physicalHint = document.getElementById('physicalHint');
const fill = document.getElementById('fill');
const moneyField = document.getElementById('moneyField');
const moneyLabel = document.getElementById('moneyLabel');
const money = document.getElementById('money');
const moneyBtn = document.getElementById('moneyBtn');
const litersField = document.getElementById('litersField');
const litersLabel = document.getElementById('litersLabel');
const liters = document.getElementById('liters');
const litersBtn = document.getElementById('litersBtn');
const estimateLabel = document.getElementById('estimateLabel');
const estimate = document.getElementById('estimate');
const paymentLabel = document.getElementById('paymentLabel');
const closeBtn = document.getElementById('close');
const progressLabel = document.getElementById('progressLabel');
const progressPercent = document.getElementById('progressPercent');
const progressDetail = document.getElementById('progressDetail');
const progressFill = document.getElementById('progressFill');
const progressBar = progress.querySelector('.bar');

const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'mz_fuel';

let pending = false;
let menuData = null;
let labels = {};

function setText(element, value) {
  if (!element) return;
  const text = value === undefined || value === null ? '' : String(value);
  if (element.textContent !== text) element.textContent = text;
}

function setPending(value) {
  pending = value === true;
  [fill, money, moneyBtn, liters, litersBtn].forEach((element) => {
    if (element) element.disabled = pending;
  });
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

function formatMoney(value) {
  const amount = Number(value);
  if (!Number.isFinite(amount)) return '0';
  return amount.toFixed(2);
}

function unit() {
  return labels.litersUnit || 'L';
}

function currency() {
  return labels.currency || 'R$';
}

function applyLabels() {
  setText(title, labels.title || 'Abastecimento');
  setText(subtitle, labels.subtitle || '');
  setText(currentFuelLabel, labels.currentFuel || 'Combustivel atual');
  setText(priceLabel, labels.pricePerLiter || 'Preco por litro');
  setText(capacityLabel, labels.capacity || 'Capacidade');
  setText(fill, labels.fill || 'Completar tanque');
  setText(moneyLabel, labels.money || 'Abastecer por valor');
  setText(moneyBtn, labels.confirm || 'Abastecer');
  setText(litersLabel, labels.liters || 'Abastecer por litros');
  setText(litersBtn, labels.confirm || 'Abastecer');
  setText(estimateLabel, labels.estimated || 'Total estimado');
  setText(paymentLabel, labels.payment || 'Pagamento via mz_economy');
  setText(closeBtn, labels.cancel || 'Cancelar');
  setText(progressLabel, labels.progress || 'Abastecendo');

  money.placeholder = labels.moneyPlaceholder || '';
  liters.placeholder = labels.litersPlaceholder || '';
}

function updateEstimate() {
  if (!menuData) return;

  const pricePerLiter = Number(menuData.pricePerLiter) || 0;
  let litersValue = 0;
  let total = 0;

  const moneyValue = Number(money.value);
  const litersTyped = Number(liters.value);

  if (money.value !== '' && Number.isFinite(moneyValue) && moneyValue > 0) {
    total = moneyValue;
    litersValue = pricePerLiter > 0 ? moneyValue / pricePerLiter : 0;
  } else if (liters.value !== '' && Number.isFinite(litersTyped) && litersTyped > 0) {
    litersValue = litersTyped;
    total = litersValue * pricePerLiter;
  }

  const detail = litersValue > 0
    ? ` (${litersValue.toFixed(1)} ${unit()})`
    : '';

  setText(estimate, `${currency()} ${formatMoney(total)}${detail}`);
}

function openMenu(data) {
  menuData = data || {};
  labels = menuData.labels || {};
  applyLabels();
  setPending(false);

  const maxFuel = Math.max(0, Number(menuData.maxFuel) || 100);
  const current = Math.max(0, Math.min(maxFuel, Number(menuData.fuel) || 0));
  const pricePerLiter = Math.max(0, Number(menuData.pricePerLiter) || 0);

  setText(fuel, `${current.toFixed(1)} / ${maxFuel.toFixed(1)}`);
  setText(price, `${currency()} ${formatMoney(pricePerLiter)}`);
  setText(capacity, `${maxFuel.toFixed(1)} ${unit()}`);

  const showFill = menuData.allowFillTank !== false && current < maxFuel;
  fill.style.display = showFill ? 'block' : 'none';
  moneyField.style.display = menuData.allowMoneyAmount === false || current >= maxFuel ? 'none' : 'block';
  litersField.style.display = menuData.allowLiterAmount === false || current >= maxFuel ? 'none' : 'block';

  physicalHint.textContent = menuData.physical === true ? (labels.physicalHint || '') : '';
  physicalHint.classList.toggle('hidden', menuData.physical !== true || !labels.physicalHint);

  money.value = '';
  liters.value = '';
  money.max = Math.max(0, Math.round((maxFuel - current) * pricePerLiter)).toString();
  liters.max = Math.max(0, maxFuel - current).toFixed(1);
  updateEstimate();

  app.classList.remove('hidden');
  app.setAttribute('aria-hidden', 'false');
}

function closeMenu() {
  setPending(false);
  menuData = null;
  app.classList.add('hidden');
  app.setAttribute('aria-hidden', 'true');
  hideProgress();
}

function showProgress(data) {
  const percent = Math.max(0, Math.min(1, Number(data.percent) || 0));
  const litersValue = Math.max(0, Number(data.liters) || 0);
  const targetValue = Math.max(0, Number(data.target) || 0);

  setText(progressLabel, data.label || labels.progress || 'Abastecendo');
  setText(progressPercent, `${Math.round(percent * 100)}%`);
  setText(
    progressDetail,
    (labels.progressDetail || '{liters} L de {target} L')
      .replace('{liters}', litersValue.toFixed(1))
      .replace('{target}', targetValue.toFixed(1))
  );

  progressFill.style.width = `${Math.round(percent * 100)}%`;
  progressBar.setAttribute('aria-valuenow', String(Math.round(percent * 100)));
  progress.classList.remove('hidden');
  progress.setAttribute('aria-hidden', 'false');
}

function hideProgress() {
  progress.classList.add('hidden');
  progress.setAttribute('aria-hidden', 'true');
  progressFill.style.width = '0%';
  progressBar.setAttribute('aria-valuenow', '0');
}

window.addEventListener('message', (event) => {
  const data = event.data || {};

  if (data.action === 'open') openMenu(data);
  if (data.action === 'close') closeMenu();
  if (data.action === 'progress') showProgress(data);
  if (data.action === 'progressHide') hideProgress();
});

fill.addEventListener('click', () => post('refuel_fill'));
moneyBtn.addEventListener('click', () => post('refuel_money', { value: money.value }));
litersBtn.addEventListener('click', () => post('refuel_liters', { value: liters.value }));
closeBtn.addEventListener('click', () => post('cancel'));
money.addEventListener('input', updateEstimate);
liters.addEventListener('input', updateEstimate);

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') post('cancel');
});
