MZFuelJerryCan = MZFuelJerryCan or {}

local ActiveJerryCan = {}
local JerryCanThrottle = {}

local function normalizePlate(plate)
  return MZFuelPersistence.NormalizePlate(plate)
end

local function clampFuel(value)
  return MZFuelPersistence.ClampFuel(value)
end

local function isValidSource(source)
  source = tonumber(source) or 0
  return source > 0 and GetPlayerName(source) ~= nil
end

local function jerryCanActionAllowed(source)
  local ok, allowed, result = pcall(function()
    return exports['mz_core']:CanPlayerPerformAction(source, 'inventory.use')
  end)
  return ok and allowed == true and type(result) == 'table' and result.allowed == true
end

local function jerryConfig()
  return type(Config.JerryCan) == 'table' and Config.JerryCan or {}
end

local function isEnabled()
  return jerryConfig().enabled == true
end

local function normalizeLiters(value)
  local liters = tonumber(value)
  if not liters or liters ~= liters or liters <= 0.0 then
    return nil
  end

  local maxFuel = tonumber(Config.MaxFuel) or 100.0
  if liters > maxFuel then
    liters = maxFuel
  end

  return liters + 0.0
end

local function refuelPlate(source, plate)
  plate = normalizePlate(plate)
  if plate ~= '' then
    return plate
  end

  return ('TEMP:%s'):format(tostring(source or 0))
end

local function getInventoryItem()
  return tostring(jerryConfig().inventoryItem or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function inventoryFallbackAllowed()
  return jerryConfig().allowWithoutInventory == true
end

local function hasJerryCanItem(source)
  local item = getInventoryItem()
  if item == '' then
    return inventoryFallbackAllowed(), inventoryFallbackAllowed() and nil or 'invalid_item'
  end

  if GetResourceState('mz_core') ~= 'started' then
    return inventoryFallbackAllowed(), inventoryFallbackAllowed() and nil or 'inventory_unavailable'
  end

  local ok, hasItem = pcall(function()
    return exports['mz_core']:HasPlayerItem(source, item, 1)
  end)

  if not ok then
    return false, 'inventory_export_failed'
  end

  return hasItem == true, hasItem == true and nil or 'item_missing'
end

local function consumeJerryCanItem(source)
  if jerryConfig().consumeItem ~= true then
    return hasJerryCanItem(source)
  end

  local item = getInventoryItem()
  if item == '' then
    return inventoryFallbackAllowed(), inventoryFallbackAllowed() and nil or 'invalid_item'
  end

  if GetResourceState('mz_core') ~= 'started' then
    return inventoryFallbackAllowed(), inventoryFallbackAllowed() and nil or 'inventory_unavailable'
  end

  local ok, success, err = pcall(function()
    return exports['mz_core']:RemovePlayerItem(source, item, 1)
  end)

  if not ok then
    return false, 'inventory_export_failed'
  end

  return success == true, success == true and nil or (err or 'item_missing')
end

local function isRateLimited(source)
  local now = GetGameTimer()
  local last = tonumber(JerryCanThrottle[source]) or 0
  if last > 0 and now - last < 1000 then
    return true
  end

  JerryCanThrottle[source] = now
  return false
end

local function makeToken(source, plate)
  return ('%s:%s:%s:%s'):format(source, plate, GetGameTimer(), math.random(100000, 999999))
end

local function sendAuthorizeResult(source, payload)
  TriggerClientEvent('mz_fuel:client:jerryCanAuthorized', source, payload)
end

local function sendFinishResult(source, payload)
  TriggerClientEvent('mz_fuel:client:jerryCanFinished', source, payload)
end

local function registerInventoryUseHandler()
  if not isEnabled() or GetResourceState('mz_core') ~= 'started' then
    return
  end

  local item = getInventoryItem()
  if item == '' then
    return
  end

  pcall(function()
    exports['mz_core']:RegisterItemUseHandler(item, function(payload)
      local src = tonumber(payload and payload.source)
      if not src then
        return { ok = false, error = 'invalid_source' }
      end

      return {
        ok = true,
        consume = false,
        afterCommit = function()
          TriggerClientEvent('mz_fuel:client:useJerryCan', src)
        end
      }
    end)
  end)
end

RegisterNetEvent('mz_fuel:server:authorizeJerryCan', function(payload)
  local src = source
  payload = type(payload) == 'table' and payload or {}

  if not isValidSource(src) then
    return
  end
  if not jerryCanActionAllowed(src) then
    return sendAuthorizeResult(src, { ok = false, error = 'player_state_blocked' })
  end

  if not isEnabled() then
    sendAuthorizeResult(src, { ok = false, error = 'disabled' })
    return
  end

  if isRateLimited(src) then
    sendAuthorizeResult(src, { ok = false, error = 'rate_limited' })
    return
  end

  local hasItem, itemError = hasJerryCanItem(src)
  if hasItem ~= true then
    sendAuthorizeResult(src, { ok = false, error = itemError or 'item_missing' })
    return
  end

  local maxFuel = tonumber(Config.MaxFuel) or 100.0
  local configuredLiters = normalizeLiters(jerryConfig().litersPerUse) or 10.0
  local currentFuel = clampFuel(payload.fuel_before or payload.fuelBefore or 0.0)
  local plate = refuelPlate(src, payload.plate)
  local missing = currentFuel and math.max(0.0, maxFuel - currentFuel) or configuredLiters
  local liters = math.min(configuredLiters, missing)
  if liters <= 0.0 then
    sendAuthorizeResult(src, { ok = false, error = 'vehicle_full' })
    return
  end

  local token = makeToken(src, plate)
  local useTime = math.max(1000, tonumber(jerryConfig().useTimeMs) or 6000)
  local ttl = math.max(useTime + 5000, tonumber(jerryConfig().authorizedCreditTtlMs) or 120000)

  ActiveJerryCan[src] = {
    token = token,
    plate = plate,
    netId = tonumber(payload.net_id or payload.netId) or 0,
    liters = liters,
    readyAt = GetGameTimer() + useTime,
    expiresAt = GetGameTimer() + ttl
  }

  sendAuthorizeResult(src, {
    ok = true,
    token = token,
    net_id = ActiveJerryCan[src].netId,
    liters = liters,
    useTimeMs = useTime
  })
end)

RegisterNetEvent('mz_fuel:server:finishJerryCan', function(payload)
  local src = source
  payload = type(payload) == 'table' and payload or {}

  if not isValidSource(src) then
    return
  end
  if not jerryCanActionAllowed(src) then
    ActiveJerryCan[src] = nil
    return sendFinishResult(src, { ok = false, error = 'player_state_blocked' })
  end

  if not isEnabled() then
    sendFinishResult(src, { ok = false, error = 'disabled' })
    return
  end

  if isRateLimited(src) then
    sendFinishResult(src, { ok = false, error = 'rate_limited' })
    return
  end

  local session = ActiveJerryCan[src]
  ActiveJerryCan[src] = nil
  if type(session) ~= 'table' or tostring(payload.token or '') ~= tostring(session.token or '') then
    sendFinishResult(src, { ok = false, error = 'invalid_session' })
    return
  end

  if tonumber(session.expiresAt) and tonumber(session.expiresAt) <= GetGameTimer() then
    sendFinishResult(src, { ok = false, error = 'session_expired' })
    return
  end

  if tonumber(session.readyAt) and tonumber(session.readyAt) > GetGameTimer() then
    sendFinishResult(src, { ok = false, error = 'use_not_finished' })
    return
  end

  local maxFuel = tonumber(Config.MaxFuel) or 100.0
  local liters = normalizeLiters(session.liters)
  liters = math.min(liters or 0.0, maxFuel)

  if not liters or liters <= 0.0 then
    sendFinishResult(src, { ok = false, error = 'vehicle_full' })
    return
  end

  if not MZFuelServer or type(MZFuelServer.AddAuthorizedFuelCredit) ~= 'function' then
    sendFinishResult(src, { ok = false, error = 'credit_unavailable' })
    return
  end

  local consumed, itemError = consumeJerryCanItem(src)
  if consumed ~= true then
    sendFinishResult(src, { ok = false, error = itemError or 'item_missing' })
    return
  end

  if MZFuelServer.AddAuthorizedFuelCredit(src, session.plate, liters, jerryConfig().authorizedCreditTtlMs, 'jerrycan') ~= true then
    sendFinishResult(src, { ok = false, error = 'credit_failed' })
    return
  end

  sendFinishResult(src, {
    ok = true,
    net_id = session.netId,
    liters = liters
  })
end)

CreateThread(function()
  Wait(0)
  registerInventoryUseHandler()

  while true do
    local now = GetGameTimer()
    for source, session in pairs(ActiveJerryCan) do
      if type(session) ~= 'table' or (tonumber(session.expiresAt) and tonumber(session.expiresAt) <= now) then
        ActiveJerryCan[source] = nil
      end
    end

    Wait(60000)
  end
end)
