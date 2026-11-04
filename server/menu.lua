MZFuelMenu = MZFuelMenu or {}

local Sessions = {}
local RequestThrottle = {}
local CanceledRequests = {}

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

local function fuelActionAllowed(source)
  local ok, allowed, result = pcall(function()
    return exports['mz_core']:CanPlayerPerformAction(source, 'vehicle.drive')
  end)
  return ok and allowed == true and type(result) == 'table' and result.allowed == true
end

local function normalizeNumber(value, maxValue)
  local number = tonumber(value)
  if not number or number ~= number or number <= 0.0 then
    return nil
  end

  if number == math.huge or number == -math.huge then
    return nil
  end

  maxValue = tonumber(maxValue)
  if maxValue and number > maxValue then
    return nil
  end

  return number + 0.0
end

local function refuelConfig()
  return type(Config.Refuel) == 'table' and Config.Refuel or {}
end

local function isPositiveNumber(value)
  value = tonumber(value)
  return value ~= nil and value == value and value > 0.0 and value ~= math.huge
end

local function validateRefuelConfig()
  local cfg = refuelConfig()
  local errors = {}

  if Config.Payment and Config.Payment.enabled ~= false and not isPositiveNumber(cfg.pricePerLiter) then
    errors[#errors + 1] = 'Config.Refuel.pricePerLiter precisa ser maior que 0 quando Config.Payment.enabled=true'
  end

  if not isPositiveNumber(cfg.litersPerTick) then
    errors[#errors + 1] = 'Config.Refuel.litersPerTick precisa ser maior que 0'
  end

  if not isPositiveNumber(cfg.tickMs) then
    errors[#errors + 1] = 'Config.Refuel.tickMs precisa ser maior que 0'
  end

  if not isPositiveNumber(cfg.maxLitersPerRequest) then
    errors[#errors + 1] = 'Config.Refuel.maxLitersPerRequest precisa ser maior que 0'
  end

  for _, errorMessage in ipairs(errors) do
    print(('[mz_fuel] config invalida: %s'):format(errorMessage))
  end

  return #errors == 0
end

local RefuelConfigOk = validateRefuelConfig()

local function normalizeAccount(account)
  account = tostring(account or refuelConfig().paymentAccount or 'cash'):lower()
  local aliases = Config.Payment and Config.Payment.accountAliases or {}
  return tostring(aliases[account] or account)
end

local function validateStationDistance(source, station, pump, stationId)
  local ped = GetPlayerPed(source)
  if not ped or ped == 0 then
    return false
  end

  local hasPump = type(pump) == 'table'
  local stationCoords = nil

  if type(station) == 'table' then
    local x = tonumber(station.x)
    local y = tonumber(station.y)
    local z = tonumber(station.z)
    if x and y and z then
      stationCoords = vector3(x, y, z)
    end
  end

  if not stationCoords and not hasPump then
    return false
  end

  if stationCoords then
    local maxDistance = tonumber(refuelConfig().maxDistance) or 6.0
    if hasPump then
      maxDistance = math.max(
        maxDistance,
        (tonumber(refuelConfig().pumpStationRadius) or 40.0)
          + (tonumber(refuelConfig().maxPumpDistance) or 10.0)
      )
    end

    if #(GetEntityCoords(ped) - stationCoords) > maxDistance then
      return false
    end

    local matched = false
    for _, configuredStation in ipairs(Config.Stations and Config.Stations.locations or {}) do
      if #(stationCoords - configuredStation) <= 1.5 then
        matched = true
        break
      end
    end

    if not matched and not hasPump then
      return false
    end
  end

  if hasPump then
    if not MZFuelPumpsServer or not MZFuelPumpsServer.ValidatePump then
      return false
    end

    if MZFuelPumpsServer.ValidatePump(source, pump, stationId, station) ~= true then
      return false
    end
  end

  return true
end

local function getPlayerBalance(source)
  if Config.Payment and Config.Payment.enabled == false then
    return math.huge
  end

  if GetResourceState('mz_economy') ~= 'started' then
    return nil, 'payment_unavailable'
  end

  local ok, money = pcall(function()
    return exports['mz_economy']:GetMoney(source)
  end)

  if not ok or type(money) ~= 'table' then
    return nil, 'payment_unavailable'
  end

  return math.floor(tonumber(money[normalizeAccount(refuelConfig().paymentAccount or 'cash')]) or 0)
end

local function estimatePrice(liters)
  local pricePerLiter = tonumber(refuelConfig().pricePerLiter) or 0
  if (not Config.Payment or Config.Payment.enabled ~= false) and pricePerLiter <= 0 then
    return nil
  end

  return math.max(0, math.floor(((tonumber(liters) or 0.0) * pricePerLiter) + 0.5))
end

local function normalizeVehicleKey(value, source)
  value = tostring(value or '')
  if value ~= '' then
    return value
  end

  return ('source:%s'):format(tostring(source or 0))
end

local function makeSessionToken(source, vehicleKey)
  return ('%s:%s:%s:%s'):format(source, normalizeVehicleKey(vehicleKey, source), GetGameTimer(), math.random(100000, 999999))
end

local function sessionKey(source, vehicleKey, token)
  return ('%s:%s:%s'):format(tostring(source or 0), normalizeVehicleKey(vehicleKey, source), tostring(token or ''))
end

local function requestKey(source, vehicleKey, requestId)
  return ('%s:%s:%s'):format(tostring(source or 0), normalizeVehicleKey(vehicleKey, source), tostring(requestId or ''))
end

local function cleanupSessions()
  local now = GetGameTimer()
  for key, session in pairs(Sessions) do
    if type(session) ~= 'table'
      or (tonumber(session.expiresAt) and tonumber(session.expiresAt) <= now)
      or (tonumber(session.litersRemaining) or 0.0) <= 0.0 then
      Sessions[key] = nil
    end
  end

  for key, expiresAt in pairs(CanceledRequests) do
    if (tonumber(expiresAt) or 0) <= now then
      CanceledRequests[key] = nil
    end
  end
end

local function clearSessionsForSourceVehicle(source, vehicleKey)
  source = tonumber(source) or 0
  vehicleKey = normalizeVehicleKey(vehicleKey, source)

  for key, session in pairs(Sessions) do
    if type(session) ~= 'table'
      or (tonumber(session.source) == source and normalizeVehicleKey(session.vehicleKey, source) == vehicleKey) then
      Sessions[key] = nil
    end
  end
end

local function clearSessionsForSource(source)
  source = tonumber(source) or 0
  for key, session in pairs(Sessions) do
    if type(session) ~= 'table' or tonumber(session.source) == source then
      Sessions[key] = nil
    end
  end
end

local function isRequestRateLimited(source)
  source = tonumber(source) or 0
  if source <= 0 then
    return true
  end

  local now = GetGameTimer()
  local last = tonumber(RequestThrottle[source]) or 0
  if last > 0 and now - last < 1000 then
    return true
  end

  RequestThrottle[source] = now
  return false
end

local function findActiveSessionForVehicle(source, vehicleKey)
  cleanupSessions()
  vehicleKey = normalizeVehicleKey(vehicleKey, source)
  source = tonumber(source) or 0

  for _, session in pairs(Sessions) do
    if type(session) == 'table'
      and normalizeVehicleKey(session.vehicleKey, source) == vehicleKey
      and tonumber(session.source) ~= source
      and (tonumber(session.expiresAt) or 0) > GetGameTimer() then
      return session
    end
  end

  return nil
end

local function createSession(source, vehicleKey, netId, liters, plate)
  vehicleKey = normalizeVehicleKey(vehicleKey, source)
  local busy = findActiveSessionForVehicle(source, vehicleKey)
  if busy then
    return nil, 'vehicle_busy'
  end

  clearSessionsForSourceVehicle(source, vehicleKey)

  local token = makeSessionToken(source, vehicleKey)
  local key = sessionKey(source, vehicleKey, token)
  Sessions[key] = {
    source = tonumber(source) or 0,
    vehicleKey = vehicleKey,
    plate = normalizePlate(plate),
    netId = tonumber(netId) or 0,
    litersRemaining = tonumber(liters) or 0.0,
    expiresAt = GetGameTimer() + math.max(60000, tonumber(refuelConfig().paidCreditTtlMs) or 120000)
  }

  return token
end

local function isRequestCanceled(source, vehicleKey, requestId)
  requestId = tostring(requestId or '')
  if requestId == '' then
    return false
  end

  cleanupSessions()
  return CanceledRequests[requestKey(source, vehicleKey, requestId)] ~= nil
end

function MZFuelMenu.GetSessionLiters(source, vehicleKey, token, requestedLiters, netId)
  cleanupSessions()

  requestedLiters = normalizeNumber(requestedLiters, tonumber(refuelConfig().litersPerTick) or 1.0)
  if not requestedLiters then
    return nil
  end

  token = tostring(token or '')
  if token == '' then
    return nil
  end

  local session = Sessions[sessionKey(source, vehicleKey, token)]
  if type(session) ~= 'table' then
    return nil
  end

  if tonumber(session.source) ~= tonumber(source)
    or normalizeVehicleKey(session.vehicleKey, source) ~= normalizeVehicleKey(vehicleKey, source) then
    return nil
  end

  local remaining = tonumber(session.litersRemaining) or 0.0
  if remaining <= 0.0 then
    return nil
  end

  return math.min(requestedLiters, remaining)
end

function MZFuelMenu.CommitSessionLiters(source, vehicleKey, token, liters)
  local key = sessionKey(source, vehicleKey, token)
  local session = Sessions[key]
  if type(session) ~= 'table' then
    return false
  end

  session.litersRemaining = math.max(0.0, (tonumber(session.litersRemaining) or 0.0) - (tonumber(liters) or 0.0))
  if session.litersRemaining <= 0.0 then
    Sessions[key] = nil
  end

  return true
end

RegisterNetEvent('mz_fuel:server:requestMenuRefuel', function(payload)
  local src = source
  if not fuelActionAllowed(src) then
    return TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, { ok = false, error = 'player_state_blocked' })
  end
  payload = type(payload) == 'table' and payload or {}

  if not isValidSource(src) or refuelConfig().useMenu ~= true then
    return
  end

  if RefuelConfigOk ~= true then
    TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, { ok = false, error = 'invalid_price' })
    return
  end

  if isRequestRateLimited(src) then
    TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, { ok = false, error = 'rate_limited' })
    return
  end

  local mode = tostring(payload.mode or ''):lower()
  local plate = normalizePlate(payload.plate)
  local netId = tonumber(payload.net_id or payload.netId) or 0
  local vehicleKey = normalizeVehicleKey(payload.vehicle_key or payload.vehicleKey, src)
  local requestId = tostring(payload.request_id or payload.requestId or '')
  local stationId = tonumber(payload.station_id or payload.stationId) or 0
  local physical = payload.physical == true
  local pump = physical and (payload.pump or payload.pumpCoords) or nil
  local pumpKey = tostring(payload.pump_key or payload.pumpKey or '')

  if physical and refuelConfig().physical ~= true then
    TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, { ok = false, error = 'physical_disabled' })
    return
  end

  if physical and (pumpKey == '' or not MZFuelPumpsServer or MZFuelPumpsServer.IsLockedBy(src, pumpKey) ~= true) then
    TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, { ok = false, error = 'pump_not_claimed' })
    return
  end

  if physical and type(pump) ~= 'table' then
    TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, { ok = false, error = 'pump_distance_invalid' })
    return
  end

  if isRequestCanceled(src, vehicleKey, requestId) then
    TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, { ok = false, error = 'canceled' })
    return
  end

  if validateStationDistance(src, payload.station, pump, stationId) ~= true then
    TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, { ok = false, error = 'too_far' })
    return
  end

  -- O servidor usa o menor valor entre o fuel persistido e o informado pelo
  -- client. Isso evita travar o menu com um cache antigo e nunca permite que o
  -- client alegue um tanque maior para receber combustivel indevido.
  local storedFuel = plate ~= '' and MZFuelPersistence.GetStoredFuelByPlate(plate) or nil
  local payloadFuel = clampFuel(payload.fuel_before or payload.fuelBefore or 0.0)
  local currentFuel = storedFuel ~= nil and math.min(storedFuel, payloadFuel) or payloadFuel
  local missing = math.max(0.0, (tonumber(Config.MaxFuel) or 100.0) - currentFuel)
  local maxRequest = math.min(tonumber(refuelConfig().maxLitersPerRequest) or 100.0, tonumber(Config.MaxFuel) or 100.0)
  if maxRequest <= 0.0 or maxRequest ~= maxRequest or maxRequest == math.huge then
    TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, { ok = false, error = 'invalid_amount' })
    return
  end

  local requestedLiters = nil

  if mode == 'fill' and refuelConfig().allowFillTank == true then
    requestedLiters = missing
  elseif mode == 'liters' and refuelConfig().allowLiterAmount == true then
    requestedLiters = normalizeNumber(payload.value, 1000000.0)
  elseif mode == 'money' and refuelConfig().allowMoneyAmount == true then
    local moneyAmount = normalizeNumber(payload.value, 1000000.0)
    local pricePerLiter = tonumber(refuelConfig().pricePerLiter) or 0
    if not moneyAmount or pricePerLiter <= 0 then
      TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, { ok = false, error = 'invalid_amount' })
      return
    end
    requestedLiters = moneyAmount / pricePerLiter
  else
    TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, { ok = false, error = 'invalid_mode' })
    return
  end

  requestedLiters = normalizeNumber(requestedLiters, 1000000.0)
  if not requestedLiters then
    TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, { ok = false, error = 'invalid_amount' })
    return
  end

  local liters = math.min(requestedLiters, missing, maxRequest)
  if liters <= 0.0 then
    TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, { ok = false, error = 'vehicle_full' })
    return
  end

  local price = estimatePrice(liters)
  if price == nil then
    TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, { ok = false, error = 'invalid_price' })
    return
  end

  local balance, balanceErr = getPlayerBalance(src)
  if not balance then
    TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, { ok = false, error = balanceErr or 'payment_unavailable' })
    return
  end

  if price > balance then
    TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, { ok = false, error = 'not_enough_money' })
    return
  end

  cleanupSessions()
  if isRequestCanceled(src, vehicleKey, requestId) then
    TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, { ok = false, error = 'canceled' })
    return
  end

  local sessionToken, sessionError = createSession(src, vehicleKey, netId, liters, plate)
  if not sessionToken then
    TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, {
      ok = false,
      error = sessionError or 'vehicle_busy'
    })
    return
  end

  TriggerClientEvent('mz_fuel:client:refuelMenuAuthorized', src, {
    ok = true,
    session = sessionToken,
    vehicle_key = vehicleKey,
    liters = liters,
    price = price,
    net_id = netId
  })
end)

RegisterNetEvent('mz_fuel:server:endRefuel', function(payload)
  local src = source
  payload = type(payload) == 'table' and payload or {}
  if not isValidSource(src) then
    return
  end

  local vehicleKey = normalizeVehicleKey(payload.vehicle_key or payload.vehicleKey, src)
  clearSessionsForSourceVehicle(src, vehicleKey)
end)

RegisterNetEvent('mz_fuel:server:cancelMenuRefuel', function(payload)
  local src = source
  payload = type(payload) == 'table' and payload or {}

  if not isValidSource(src) then
    return
  end

  local vehicleKey = normalizeVehicleKey(payload.vehicle_key or payload.vehicleKey, src)
  local requestId = tostring(payload.request_id or payload.requestId or '')

  clearSessionsForSourceVehicle(src, vehicleKey)
  if requestId ~= '' then
    CanceledRequests[requestKey(src, vehicleKey, requestId)] = GetGameTimer() + 5000
  end
end)

AddEventHandler('playerDropped', function()
  clearSessionsForSource(source)
end)

CreateThread(function()
  while true do
    Wait(60000)
    cleanupSessions()
  end
end)
