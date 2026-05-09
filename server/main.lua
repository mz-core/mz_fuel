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
  return normalizedVehiclePlate == '' or normalizedVehiclePlate == plate
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

local function creditKey(source, plate)
  return ('%s:%s'):format(tostring(source or 0), normalizePlate(plate))
end

local function refuelCreditPlate(source, plate)
  plate = normalizePlate(plate)
  if plate ~= '' then
    return plate
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

local function addPaidFuelCredit(source, plate, liters)
  plate = normalizePlate(plate)
  liters = tonumber(liters) or 0.0
  if plate == '' or liters <= 0.0 then
    return
  end

  local now = GetGameTimer()
  cleanupPaidFuelCredits(now)

  local key = creditKey(source, plate)
  local current = PaidFuelCredits[key]
  local available = type(current) == 'table' and tonumber(current.liters) or tonumber(current)
  local ttl = tonumber(Config.Refuel and Config.Refuel.paidCreditTtlMs) or 120000

  PaidFuelCredits[key] = {
    liters = (available or 0.0) + liters,
    expiresAt = now + math.max(1000, ttl)
  }
end

local function consumePaidFuelCredit(source, plate, increase)
  increase = tonumber(increase) or 0.0
  if increase <= 0.0 then
    return true
  end

  cleanupPaidFuelCredits(GetGameTimer())

  local key = creditKey(source, plate)
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

local function canPersistFuelChange(source, plate, nextFuel)
  local currentFuel = MZFuelPersistence.GetStoredFuelByPlate(plate)
  if currentFuel == nil then
    return true
  end

  local increase = (tonumber(nextFuel) or 0.0) - currentFuel
  if increase <= 0.25 then
    return true
  end

  return consumePaidFuelCredit(source, plate, increase) or consumeAuthorizedFuelCredit(source, plate, increase)
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

local function validateRefuelDistance(source, station)
  if type(station) ~= 'table' then
    return false
  end

  local x = tonumber(station.x)
  local y = tonumber(station.y)
  local z = tonumber(station.z)
  if not x or not y or not z then
    return false
  end

  local ped = GetPlayerPed(source)
  if not ped or ped == 0 then
    return false
  end

  local coords = GetEntityCoords(ped)
  local stationCoords = vector3(x, y, z)
  local maxDistance = tonumber(Config.Refuel and Config.Refuel.maxDistance) or 6.0
  if #(coords - stationCoords) > maxDistance then
    return false
  end

  local locations = Config.Stations and Config.Stations.locations or {}
  for _, configuredStation in ipairs(locations) do
    if #(stationCoords - configuredStation) <= 1.5 then
      return true
    end
  end

  return false
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
  context = type(context) == 'table' and context or {}
  plate = normalizePlate(plate)
  fuel = normalizeFuel(fuel)

  if not isValidSource(src) or plate == '' or fuel == nil then
    return
  end

  if isThrottled(src, plate, context.force == true) then
    return
  end

  if not canPersistFuelChange(src, plate, fuel) then
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
  payload = type(payload) == 'table' and payload or {}

  local plate = normalizePlate(payload.plate)
  local liters = normalizeLiters(payload.liters)
  local creditPlate = refuelCreditPlate(src, plate)

  debugPrint('server_pay_received', {
    src = src,
    plate = plate,
    netId = payload.net_id or payload.netId,
    liters = payload.liters,
    stationId = payload.station_id or payload.stationId,
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

  if validateRefuelDistance(src, payload.station) ~= true then
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

    local sessionLiters = MZFuelMenu.GetSessionLiters(src, creditPlate, payload.menu_session or payload.menuSession, liters, payload.net_id or payload.netId)
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

  addPaidFuelCredit(src, creditPlate, liters)

  if Config.Refuel and Config.Refuel.useMenu == true and MZFuelMenu and type(MZFuelMenu.CommitSessionLiters) == 'function' then
    MZFuelMenu.CommitSessionLiters(src, creditPlate, payload.menu_session or payload.menuSession, liters)
  end

  TriggerClientEvent('mz_fuel:client:refuelPaid', src, {
    ok = true,
    liters = liters,
    price = price
  })
end)
