MZFuelPayment = MZFuelPayment or {}

local function normalizeAccount(account)
  account = tostring(account or Config.Refuel and Config.Refuel.paymentAccount or 'cash'):lower()
  local aliases = Config.Payment and Config.Payment.accountAliases or {}
  return tostring(aliases[account] or account)
end

local function normalizeAmount(amount)
  amount = tonumber(amount)
  if amount == nil or amount ~= amount or amount <= 0 then
    return nil
  end

  return math.floor(amount + 0.5)
end

local function buildLedgerMetadata(account, context)
  context = type(context) == 'table' and context or {}

  local data = {
    payment_method = account
  }

  if context.plate ~= nil then
    data.vehicle_plate = tostring(context.plate)
  end

  if context.liters ~= nil then
    data.liters = tonumber(context.liters) or context.liters
  end

  return {
    reason = 'fuel_purchase',
    category = 'vehicle_expense',
    source_resource = 'mz_fuel',
    source_type = 'resource_payment',
    counts_as_income = false,
    counts_as_expense = true,
    external_ref = nil,
    data = data
  }
end

function MZFuelPayment.Charge(source, amount, context)
  if Config.Payment and Config.Payment.enabled == false then
    return true, {
      paid = 0,
      account = 'disabled'
    }
  end

  amount = normalizeAmount(amount)
  if not amount then
    return false, 'invalid_amount'
  end

  if GetResourceState('mz_core') ~= 'started' then
    if Config.Payment and Config.Payment.allowFallbackWithoutMzCore == true then
      return true, {
        paid = 0,
        account = 'fallback'
      }
    end

    return false, 'payment_unavailable'
  end

  local account = normalizeAccount(Config.Refuel and Config.Refuel.paymentAccount or 'cash')
  local ok, success, err = pcall(function()
    return exports['mz_core']:RemoveMoney(source, account, amount, buildLedgerMetadata(account, context))
  end)

  if not ok then
    return false, 'payment_export_failed'
  end

  if success ~= true then
    return false, err or 'payment_failed'
  end

  return true, {
    paid = amount,
    account = account,
    context = context or {}
  }
end
