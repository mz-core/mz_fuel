local SaveThrottle = {}
local RefuelPayThrottle = {}
local PaidFuelCredits = {}
local AuthorizedFuelCredits = {}

local function debugPrint(tag, fields)
  if Config.Debug ~= true then
    return
  end

  local parts = {}
  for key, value in pairs(fields or {}) do
    parts[#parts + 1] = ('%s=%s'):format(tostring(key), tostring(value))
  end

  print(('[mz_fuel][%s] %s'):format(tostring(tag), table.concat(parts, ' ')))
end

local function normalizePlate(plate)
  return MZFuelPersistence.NormalizePlate(plate)
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

local function normalizeFuel(fuel)
  fuel = tonumber(fuel)
  if fuel == nil or fuel ~= fuel then
    return nil
  end

  return MZFuelPersistence.ClampFuel(fuel)
end

local function plateMatchesNetworkVehicle(plate, netId)
  netId = tonumber(netId) or 0
  if netId <= 0 or type(NetworkGetEntityFromNetworkId) ~= 'function' then
    return true
  end

  local entity = NetworkGetEntityFromNetworkId(netId)
  if not entity or entity == 0 then
    return true
  end

  if type(DoesEntityExist) == 'function' then
    local existsOk, exists = pcall(DoesEntityExist, entity)
    if not existsOk or exists ~= true then
      return true
    end
  end

  if type(GetVehicleNumberPlateText) ~= 'function' then
    return true
  end

  local ok, vehiclePlate = pcall(GetVehicleNumberPlateText, entity)
  if not ok then
    return true
  end

  local normalizedVehiclePlate = normalizePlate(vehiclePlate)
  if normalizedVehiclePlate == '' or normalizedVehiclePlate == plate then
    return true
  end

  -- mz_vehicles pode usar uma placa lógica em state bag. Nesse caso a placa
  -- nativa pode ser apenas a placa visual do modelo.
  local stateOk, statePlate = pcall(function()
    local state = Entity(entity).state
    return state and state.mz_plate or nil
  end)

  if stateOk and statePlate then
    local normalizedStatePlate = normalizePlate(statePlate)
    if normalizedStatePlate ~= '' and normalizedStatePlate == plate then
      return true
    end
  end

  return false
end

local function isThrottled(source, plate, force)
  if force == true then
    return false
  end

  local now = GetGameTimer()
  local interval = tonumber(Config.SaveIntervalMs) or 15000
  local key = ('%s:%s'):format(tostring(source), plate)
  local last = tonumber(SaveThrottle[key]) or 0
  if last > 0 and now - last < interval then
    return true
  end

  SaveThrottle[key] = now
  return false
end

local function creditKey(source, key)
  return ('%s:%s'):format(tostring(source or 0), tostring(key or ''))
end

local function refuelCreditKey(source, payload, vehicleKey)
  local sessionKey = tostring(payload.session_key or payload.sessionKey or '')
  if sessionKey ~= '' then
    return sessionKey
  end

  local plate = normalizePlate(payload.plate)
  if plate ~= '' then
    return plate
  end

  if vehicleKey and vehicleKey ~= '' then
    return vehicleKey
  end

  return ('TEMP:%s'):format(tostring(source or 0))
end

local function cleanupPaidFuelCredits(now)
  now = tonumber(now) or GetGameTimer()

  for key, credit in pairs(PaidFuelCredits) do
    local liters = type(credit) == 'table' and tonumber(credit.liters) or tonumber(credit)
    local expiresAt = type(credit) == 'table' and tonumber(credit.expiresAt) or nil
    if not liters or liters <= 0.0 or (expiresAt and expiresAt <= now) then
      PaidFuelCredits[key] = nil
    end
  end
end

local function addPaidFuelCredit(source, creditKeyValue, liters)
  creditKeyValue = tostring(creditKeyValue or '')
  liters = tonumber(liters) or 0.0
  if creditKeyValue == '' or liters <= 0.0 then
    return
  end

  local now = GetGameTimer()
  cleanupPaidFuelCredits(now)

  local key = creditKey(source, creditKeyValue)
  local current = PaidFuelCredits[key]
  local available = type(current) == 'table' and tonumber(current.liters) or tonumber(current)
  local ttl = tonumber(Config.Refuel and Config.Refuel.paidCreditTtlMs) or 120000

  PaidFuelCredits[key] = {
    liters = (available or 0.0) + liters,
    expiresAt = now + math.max(1000, ttl)
  }
end

local function consumePaidFuelCredit(source, creditKeyValue, increase)
  increase = tonumber(increase) or 0.0
  if increase <= 0.0 then
    return true
  end

  cleanupPaidFuelCredits(GetGameTimer())

  local key = creditKey(source, creditKeyValue)
  local credit = PaidFuelCredits[key]
  local available = type(credit) == 'table' and tonumber(credit.liters) or tonumber(credit) or 0.0
  local tolerance = 0.25
  if increase > available + tolerance then
    return false
  end

  local remaining = math.max(0.0, available - increase)
  if remaining <= 0.0 then
    PaidFuelCredits[key] = nil
  elseif type(credit) == 'table' then
    credit.liters = remaining
  else
    PaidFuelCredits[key] = remaining
  end

  return true
end

local function cleanupAuthorizedFuelCredits(now)
  now = tonumber(now) or GetGameTimer()

  for key, credit in pairs(AuthorizedFuelCredits) do
    local liters = type(credit) == 'table' and tonumber(credit.liters) or tonumber(credit)
    local expiresAt = type(credit) == 'table' and tonumber(credit.expiresAt) or nil
    if not liters or liters <= 0.0 or (expiresAt and expiresAt <= now) then
      AuthorizedFuelCredits[key] = nil
    end
  end
end

local function addAuthorizedFuelCredit(source, plate, liters, ttlMs, reason)
  plate = normalizePlate(plate)
  liters = tonumber(liters) or 0.0
  if plate == '' or liters <= 0.0 then
    return false
  end

  local now = GetGameTimer()
  cleanupAuthorizedFuelCredits(now)

  local key = creditKey(source, plate)
  local current = AuthorizedFuelCredits[key]
  local available = type(current) == 'table' and tonumber(current.liters) or tonumber(current)

  AuthorizedFuelCredits[key] = {
    liters = (available or 0.0) + liters,
    expiresAt = now + math.max(1000, tonumber(ttlMs) or 120000),
    reason = tostring(reason or 'authorized')
  }

  return true
end

local function consumeAuthorizedFuelCredit(source, plate, increase)
  increase = tonumber(increase) or 0.0
  if increase <= 0.0 then
    return true
  end

  cleanupAuthorizedFuelCredits(GetGameTimer())

  local key = creditKey(source, plate)
  local credit = AuthorizedFuelCredits[key]
  local available = type(credit) == 'table' and tonumber(credit.liters) or tonumber(credit) or 0.0
  local tolerance = 0.25
  if increase > available + tolerance then
    return false
  end

  local remaining = math.max(0.0, available - increase)
  if remaining <= 0.0 then
    AuthorizedFuelCredits[key] = nil
  elseif type(credit) == 'table' then
    credit.liters = remaining
  else
    AuthorizedFuelCredits[key] = remaining
  end

  return true
end

local function canPersistFuelChange(source, plate, nextFuel, context)
  local currentFuel = MZFuelPersistence.GetStoredFuelByPlate(plate)
  context = type(context) == 'table' and context or {}
  local creditKeyValue = tostring(context.session_key or context.sessionKey or '')
  if creditKeyValue == '' then
    creditKeyValue = plate
  end

  -- Sem baseline persistido nao e possivel provar que o aumento veio de
  -- abastecimento. Exigimos credito pago/autorizado em vez de liberar fuel
  -- gratuito para uma placa sem historico.
  if currentFuel == nil then
    if (tonumber(nextFuel) or 0.0) <= (tonumber(Config.MinFuel) or 0.0) + 0.25 then
      return true
    end

    return consumePaidFuelCredit(source, creditKeyValue, tonumber(nextFuel) or 0.0)
      or (creditKeyValue ~= plate and consumePaidFuelCredit(source, plate, tonumber(nextFuel) or 0.0))
      or consumeAuthorizedFuelCredit(source, creditKeyValue, tonumber(nextFuel) or 0.0)
      or (creditKeyValue ~= plate and consumeAuthorizedFuelCredit(source, plate, tonumber(nextFuel) or 0.0))
  end

  local increase = (tonumber(nextFuel) or 0.0) - currentFuel
  if increase <= 0.25 then
    return true
  end

  return consumePaidFuelCredit(source, creditKeyValue, increase)
    or (creditKeyValue ~= plate and consumePaidFuelCredit(source, plate, increase))
    or consumeAuthorizedFuelCredit(source, creditKeyValue, increase)
    or (creditKeyValue ~= plate and consumeAuthorizedFuelCredit(source, plate, increase))
end

CreateThread(function()
  while true do
    local ttl = tonumber(Config.Refuel and Config.Refuel.paidCreditTtlMs) or 120000
    Wait(math.max(60000, ttl))
    cleanupPaidFuelCredits(GetGameTimer())
    cleanupAuthorizedFuelCredits(GetGameTimer())
  end
end)

MZFuelServer = MZFuelServer or {}

function MZFuelServer.AddAuthorizedFuelCredit(source, plate, liters, ttlMs, reason)
  source = tonumber(source) or 0
  if source <= 0 then
    return false
  end

  return addAuthorizedFuelCredit(source, plate, liters, ttlMs, reason)
end

local function normalizeLiters(value)
  local liters = tonumber(value)
  if liters == nil or liters ~= liters or liters <= 0.0 then
    return nil
  end

  local maxTick = tonumber(Config.Refuel and Config.Refuel.litersPerTick) or 1.0
  if maxTick <= 0.0 or maxTick ~= maxTick then
    return nil
  end

  local maxFuel = tonumber(Config.MaxFuel) or 100.0
  maxTick = math.min(maxTick, maxFuel)

  if liters > maxTick then
    liters = maxTick
  end

  return liters + 0.0
end

local function validateRefuelConfig()
  local cfg = Config.Refuel or {}
  local errors = {}

  local function isPositiveNumber(value)
    value = tonumber(value)
    return value ~= nil and value == value and value > 0.0 and value ~= math.huge
  end

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

local function isRefuelPaymentRateLimited(source)
  source = tonumber(source) or 0
  if source <= 0 then
    return true
  end

  local now = GetGameTimer()
  local tickMs = tonumber(Config.Refuel and Config.Refuel.tickMs) or 1000
  local interval = math.max(100, math.floor(tickMs * 0.5))
  local last = tonumber(RefuelPayThrottle[source]) or 0

  if last > 0 and now - last < interval then
    return true
  end

  RefuelPayThrottle[source] = now
  return false
end

local function validateRefuelDistance(source, station, pump, stationId)
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

  local coords = GetEntityCoords(ped)
  if stationCoords then
    local maxDistance = tonumber(Config.Refuel and Config.Refuel.maxDistance) or 6.0
    if hasPump then
      maxDistance = math.max(
        maxDistance,
        (tonumber(Config.Refuel and Config.Refuel.pumpStationRadius) or 40.0)
          + (tonumber(Config.Refuel and Config.Refuel.maxPumpDistance) or 10.0)
      )
    end

    if #(coords - stationCoords) > maxDistance then
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

local function canUseDebugCommand(source)
  if Config.DebugCommands ~= true then
    return false
  end

  local ace = tostring(Config.DebugAce or '')
  if ace == '' then
    return true
  end

  if type(IsPlayerAceAllowed) ~= 'function' then
    return false
  end

  return IsPlayerAceAllowed(source, ace) == true
end

RegisterNetEvent('mz_fuel:server:saveFuel', function(plate, fuel, context)
  local src = source
  if not fuelActionAllowed(src) then return end
  context = type(context) == 'table' and context or {}
  plate = normalizePlate(plate)
  fuel = normalizeFuel(fuel)

  if not isValidSource(src) or plate == '' or fuel == nil then
    return
  end

  -- Placa e apenas metadado. Veiculos NPC/alugados/importados nao precisam
  -- existir em mz_vehicles; nesse caso o client atualiza somente a entidade.
  if not MZFuelPersistence.IsRegisteredPlate(plate) then
    return
  end

  if isThrottled(src, plate, context.force == true) then
    return
  end

  if not canPersistFuelChange(src, plate, fuel, context) then
    if Config.Debug == true then
      print(('[mz_fuel] denied unpaid fuel increase source=%s plate=%s fuel=%.2f'):format(src, plate, fuel))
    end
    return
  end

  MZFuelPersistence.SaveFuelByPlate(plate, fuel, context)
end)

RegisterNetEvent('mz_fuel:server:debugSetFuel', function(netId, plate, fuel)
  local src = source
  netId = tonumber(netId) or 0
  plate = normalizePlate(plate)
  fuel = normalizeFuel(fuel)

  if not isValidSource(src) or not canUseDebugCommand(src) or netId <= 0 or plate == '' or fuel == nil then
    return
  end

  if not plateMatchesNetworkVehicle(plate, netId) then
    return
  end

  MZFuelPersistence.SaveFuelByPlate(plate, fuel, {
    net_id = netId,
    source = 'debug_command'
  })

  TriggerClientEvent('mz_fuel:client:setFuel', src, netId, fuel)
end)

RegisterNetEvent('mz_fuel:server:payRefuel', function(payload)
  local src = source
  if not fuelActionAllowed(src) then return end
  payload = type(payload) == 'table' and payload or {}

  local plate = normalizePlate(payload.plate)
  local netId = tonumber(payload.net_id or payload.netId) or 0
  local vehicleKey = tostring(payload.vehicle_key or payload.vehicleKey or '')
  if vehicleKey == '' then
    vehicleKey = ('source:%s'):format(src)
  end

  local sessionKey = tostring(payload.session_key or payload.sessionKey or '')
  if sessionKey == '' then
    sessionKey = vehicleKey
  end

  local liters = normalizeLiters(payload.liters)
  local creditKeyValue = refuelCreditKey(src, payload, vehicleKey)

  debugPrint('server_pay_received', {
    src = src,
    plate = plate,
    netId = netId,
    vehicleKey = vehicleKey,
    sessionKey = sessionKey,
    liters = payload.liters,
    stationId = payload.station_id or payload.stationId,
    physical = payload.physical == true,
    pump = payload.pump_key or payload.pumpKey,
    useMenu = Config.Refuel and Config.Refuel.useMenu
  })

  if not isValidSource(src) or not liters then
    debugPrint('server_pay_denied', {
      src = src,
      reason = 'invalid_amount',
      plate = plate,
      liters = payload.liters
    })
    return
  end

  if RefuelConfigOk ~= true then
    debugPrint('server_pay_denied', {
      src = src,
      plate = plate,
      reason = 'config_invalid'
    })

    TriggerClientEvent('mz_fuel:client:refuelPaid', src, {
      ok = false,
      error = 'config_invalid'
    })
    return
  end

  if isRefuelPaymentRateLimited(src) then
    debugPrint('server_pay_denied', {
      src = src,
      plate = plate,
      reason = 'rate_limited'
    })

    TriggerClientEvent('mz_fuel:client:refuelPaid', src, {
      ok = false,
      error = 'rate_limited'
    })
    return
  end

  local physical = payload.physical == true
  if physical and (not Config.Refuel or Config.Refuel.physical ~= true) then
    TriggerClientEvent('mz_fuel:client:refuelPaid', src, {
      ok = false,
      error = 'physical_disabled'
    })
    return
  end

  if physical and netId > 0 and type(NetworkGetEntityFromNetworkId) == 'function' then
    local entityOk, entity = pcall(NetworkGetEntityFromNetworkId, netId)
    if not entityOk or not entity or entity == 0 then
      TriggerClientEvent('mz_fuel:client:refuelPaid', src, {
        ok = false,
        error = 'vehicle_entity_invalid'
      })
      return
    end

    if type(GetEntityType) == 'function' then
      local typeOk, entityType = pcall(GetEntityType, entity)
      if typeOk and tonumber(entityType) ~= nil and tonumber(entityType) ~= 2 then
        TriggerClientEvent('mz_fuel:client:refuelPaid', src, {
          ok = false,
          error = 'vehicle_entity_invalid'
        })
        return
      end
    end
  end

  if physical and (not MZFuelPumpsServer or MZFuelPumpsServer.IsLockedBy(src, payload.pump_key or payload.pumpKey) ~= true) then
    debugPrint('server_pay_denied', {
      src = src,
      plate = plate,
      reason = 'pump_not_claimed',
      pump = payload.pump_key or payload.pumpKey
    })

    TriggerClientEvent('mz_fuel:client:refuelPaid', src, {
      ok = false,
      error = 'pump_not_claimed'
    })
    return
  end

  if physical and type(payload.pump) ~= 'table' then
    TriggerClientEvent('mz_fuel:client:refuelPaid', src, {
      ok = false,
      error = 'pump_distance_invalid'
    })
    return
  end

  if validateRefuelDistance(src, payload.station, physical and (payload.pump or payload.pumpCoords) or nil, payload.station_id or payload.stationId) ~= true then
    debugPrint('server_pay_denied', {
      src = src,
      plate = plate,
      reason = 'station_distance_invalid',
      stationId = payload.station_id or payload.stationId
    })

    TriggerClientEvent('mz_fuel:client:refuelPaid', src, {
      ok = false,
      error = 'station_distance_invalid'
    })
    return
  end

  if Config.Refuel and Config.Refuel.useMenu == true then
    if not MZFuelMenu or type(MZFuelMenu.GetSessionLiters) ~= 'function' then
      debugPrint('server_pay_denied', {
        src = src,
        plate = plate,
        reason = 'invalid_menu_session'
      })

      TriggerClientEvent('mz_fuel:client:refuelPaid', src, {
        ok = false,
        error = 'invalid_menu_session'
      })
      return
    end

    local sessionLiters = MZFuelMenu.GetSessionLiters(src, vehicleKey, payload.menu_session or payload.menuSession, liters, netId)
    if not sessionLiters then
      debugPrint('server_pay_denied', {
        src = src,
        plate = plate,
        reason = 'invalid_menu_session'
      })

      TriggerClientEvent('mz_fuel:client:refuelPaid', src, {
        ok = false,
        error = 'invalid_menu_session'
      })
      return
    end

    liters = sessionLiters
  end

  local pricePerLiter = tonumber(Config.Refuel and Config.Refuel.pricePerLiter) or 0
  if (not Config.Payment or Config.Payment.enabled ~= false) and pricePerLiter <= 0 then
    debugPrint('server_pay_denied', {
      src = src,
      plate = plate,
      reason = 'config_invalid'
    })

    TriggerClientEvent('mz_fuel:client:refuelPaid', src, {
      ok = false,
      error = 'config_invalid'
    })
    return
  end

  local price = math.max(0, math.floor((liters * pricePerLiter) + 0.5))
  if price > 0 then
    local paid, payment = MZFuelPayment.Charge(src, price, {
      plate = plate,
      liters = liters
    })

    if paid ~= true then
      debugPrint('server_pay_denied', {
        src = src,
        plate = plate,
        reason = 'payment_failed',
        payment = payment
      })

      TriggerClientEvent('mz_fuel:client:refuelPaid', src, {
        ok = false,
        error = payment
      })
      return
    end
  end

  MZFuelLogs.Refuel(src, {
    plate = plate,
    liters = liters,
    price = price,
    account = Config.Refuel and Config.Refuel.paymentAccount or 'cash'
  })

  addPaidFuelCredit(src, creditKeyValue, liters)

  if Config.Refuel and Config.Refuel.useMenu == true and MZFuelMenu and type(MZFuelMenu.CommitSessionLiters) == 'function' then
    MZFuelMenu.CommitSessionLiters(src, vehicleKey, payload.menu_session or payload.menuSession, liters)
  end

  TriggerClientEvent('mz_fuel:client:refuelPaid', src, {
    ok = true,
    liters = liters,
    price = price
  })
end)
