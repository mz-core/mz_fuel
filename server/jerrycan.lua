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

local function jerryConfig()
  return type(Config.JerryCan) == 'table' and Config.JerryCan or {}
end

local function isEnabled()
  return jerryConfig().enabled == true
end

local function getNetVehicle(netId)
  netId = tonumber(netId) or 0
  if netId <= 0 or type(NetworkGetEntityFromNetworkId) ~= 'function' then
    return 0
  end

  local entity = NetworkGetEntityFromNetworkId(netId)
  if not entity or entity == 0 then
    return 0
  end

  if type(DoesEntityExist) == 'function' then
    local ok, exists = pcall(DoesEntityExist, entity)
    if not ok or exists ~= true then
      return 0
    end
  end

  return entity
end

local function getPlate(entity)
  if not entity or entity == 0 or type(GetVehicleNumberPlateText) ~= 'function' then
    return ''
  end

  local ok, plate = pcall(GetVehicleNumberPlateText, entity)
  if not ok then
    return ''
  end

  return normalizePlate(plate)
end

local function getVehicleFuel(entity, plate)
  if entity and entity ~= 0 and type(Entity) == 'function' then
    local ok, state = pcall(function()
      return Entity(entity).state
    end)

    if ok and state then
      local fuel = tonumber(state.fuel)
      if fuel ~= nil then
        return clampFuel(fuel)
      end
    end
  end

  if entity and entity ~= 0 and type(GetVehicleFuelLevel) == 'function' then
    local ok, fuel = pcall(GetVehicleFuelLevel, entity)
    if ok and tonumber(fuel) ~= nil then
      return clampFuel(fuel)
    end
  end

  return MZFuelPersistence.GetStoredFuelByPlate(plate)
end

local function isPlayerOutsideVehicle(source)
  local ped = GetPlayerPed(source)
  if not ped or ped == 0 or type(GetVehiclePedIsIn) ~= 'function' then
    return true
  end

  local ok, vehicle = pcall(GetVehiclePedIsIn, ped, false)
  return not ok or not vehicle or vehicle == 0
end

local function isNearVehicle(source, entity)
  local ped = GetPlayerPed(source)
  if not ped or ped == 0 or not entity or entity == 0 then
    return false
  end

  local maxDistance = tonumber(jerryConfig().maxDistance) or 3.0
  return #(GetEntityCoords(ped) - GetEntityCoords(entity)) <= maxDistance
end

local function isSupportedVehicle(entity)
  if not entity or entity == 0 then
    return false
  end

  if type(GetVehicleClass) == 'function' then
    local ok, class = pcall(GetVehicleClass, entity)
    if ok and Config.DisableOnBicycles == true and tonumber(class) == 13 then
      return false
    end
  end

  return true
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

local function validateVehicle(source, netId, expectedPlate)
  local entity = getNetVehicle(netId)
  local plate = normalizePlate(expectedPlate)
  if entity == 0 or plate == '' then
    return false, 'invalid_vehicle'
  end

  if getPlate(entity) ~= plate then
    return false, 'plate_mismatch'
  end

  if not isSupportedVehicle(entity) then
    return false, 'vehicle_not_supported'
  end

  if jerryConfig().requireOutsideVehicle == true and not isPlayerOutsideVehicle(source) then
    return false, 'outside_required'
  end

  if not isNearVehicle(source, entity) then
    return false, 'too_far'
  end

  local fuel = getVehicleFuel(entity, plate)
  if fuel and fuel >= (tonumber(Config.MaxFuel) or 100.0) then
    return false, 'vehicle_full'
  end

  return true, entity, plate, fuel
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

  if not isEnabled() then
    sendAuthorizeResult(src, { ok = false, error = 'disabled' })
    return
  end

  if isRateLimited(src) then
    sendAuthorizeResult(src, { ok = false, error = 'rate_limited' })
    return
  end

  local okVehicle, entity, plate, currentFuel = validateVehicle(src, payload.net_id or payload.netId, payload.plate)
  if okVehicle ~= true then
    sendAuthorizeResult(src, { ok = false, error = entity })
    return
  end

  local hasItem, itemError = hasJerryCanItem(src)
  if hasItem ~= true then
    sendAuthorizeResult(src, { ok = false, error = itemError or 'item_missing' })
    return
  end

  local maxFuel = tonumber(Config.MaxFuel) or 100.0
  local configuredLiters = normalizeLiters(jerryConfig().litersPerUse) or 10.0
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

  local okVehicle, entity, plate, currentFuel = validateVehicle(src, session.netId, session.plate)
  if okVehicle ~= true then
    sendFinishResult(src, { ok = false, error = entity })
    return
  end

  local maxFuel = tonumber(Config.MaxFuel) or 100.0
  local liters = normalizeLiters(session.liters)
  if currentFuel then
    liters = math.min(liters or 0.0, math.max(0.0, maxFuel - currentFuel))
  end

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

  if MZFuelServer.AddAuthorizedFuelCredit(src, plate, liters, jerryConfig().authorizedCreditTtlMs, 'jerrycan') ~= true then
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
