MZFuelPersistence = MZFuelPersistence or {}

local FuelCache = {}

local function clampFuel(value)
  local fuel = tonumber(value)
  if fuel == nil then
    return tonumber(Config.DefaultFuel) or 100.0
  end

  local minFuel = tonumber(Config.MinFuel) or 0.0
  local maxFuel = tonumber(Config.MaxFuel) or 100.0
  if fuel < minFuel then fuel = minFuel end
  if fuel > maxFuel then fuel = maxFuel end
  return fuel + 0.0
end

local function normalizePlate(plate)
  return tostring(plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
end

local function vehicleDomainStarted()
  return GetResourceState('mz_vehicles') == 'started'
end

local function getVehicle(plate)
  if not vehicleDomainStarted() then
    return nil
  end

  local ok, success, result = pcall(function()
    return exports['mz_vehicles']:GetVehicleByPlate(plate)
  end)

  if ok and success == true and type(result) == 'table' then
    return result
  end

  return nil
end

local function saveCondition(plate, fuel, vehicle)
  if not vehicleDomainStarted() then
    return false, 'mz_vehicles_unavailable'
  end

  vehicle = type(vehicle) == 'table' and vehicle or getVehicle(plate)
  if not vehicle then
    return false, 'vehicle_not_found'
  end

  local engine = tonumber(vehicle.engine) or 1000.0
  local body = tonumber(vehicle.body) or 1000.0

  local ok, success, result = pcall(function()
    return exports['mz_vehicles']:SetVehicleCondition(plate, fuel, engine, body)
  end)

  if not ok then
    return false, result
  end

  if success ~= true then
    return false, result or 'set_condition_failed'
  end

  return true
end

local function debugPersistenceSkip(plate, err)
  if Config.Debug == true then
    print(('[mz_fuel] fuel not persisted for %s: %s'):format(plate, tostring(err)))
  end
end

function MZFuelPersistence.NormalizePlate(plate)
  return normalizePlate(plate)
end

function MZFuelPersistence.ClampFuel(fuel)
  return clampFuel(fuel)
end

function MZFuelPersistence.GetCachedFuelByPlate(plate)
  plate = normalizePlate(plate)
  if plate == '' then
    return nil
  end

  return FuelCache[plate]
end

function MZFuelPersistence.GetStoredFuelByPlate(plate)
  plate = normalizePlate(plate)
  if plate == '' then
    return nil
  end

  if FuelCache[plate] ~= nil then
    return FuelCache[plate]
  end

  local vehicle = getVehicle(plate)
  if vehicle and tonumber(vehicle.fuel) ~= nil then
    return clampFuel(vehicle.fuel)
  end

  return nil
end

function MZFuelPersistence.IsRegisteredPlate(plate)
  plate = normalizePlate(plate)
  if plate == '' then
    return false
  end

  return getVehicle(plate) ~= nil
end

function MZFuelPersistence.SaveFuelByPlate(plate, fuel, context)
  plate = normalizePlate(plate)
  if plate == '' then
    return false, 'invalid_plate'
  end

  fuel = clampFuel(fuel)
  context = type(context) == 'table' and context or {}
  local vehicle = type(context.vehicle) == 'table' and context.vehicle or getVehicle(plate)
  if not vehicle then
    debugPersistenceSkip(plate, 'vehicle_not_found')
    return false, 'vehicle_not_found'
  end

  local ok, err = saveCondition(plate, fuel, vehicle)
  if ok == true then
    FuelCache[plate] = fuel
    return true
  end

  debugPersistenceSkip(plate, err or 'persistence_unavailable')

  return false, err or 'persistence_unavailable'
end
