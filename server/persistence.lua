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

local function coreStarted()
  return GetResourceState('mz_core') == 'started'
end

local function getCoreVehicle(plate)
  if not coreStarted() then
    return nil
  end

  local ok, success, result = pcall(function()
    return exports['mz_core']:GetVehicleByPlate(plate)
  end)

  if ok and success == true and type(result) == 'table' then
    return result
  end

  return nil
end

local function saveWithCoreCondition(plate, fuel, vehicle)
  if not coreStarted() then
    return false, 'mz_core_unavailable'
  end

  vehicle = type(vehicle) == 'table' and vehicle or getCoreVehicle(plate)
  if not vehicle then
    return false, 'vehicle_not_found'
  end

  local engine = tonumber(vehicle.engine) or 1000.0
  local body = tonumber(vehicle.body) or 1000.0

  local ok, success, result = pcall(function()
    return exports['mz_core']:SetVehicleCondition(plate, fuel, engine, body)
  end)

  if not ok then
    return false, result
  end

  if success ~= true then
    return false, result or 'set_condition_failed'
  end

  return true
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

  local vehicle = getCoreVehicle(plate)
  if vehicle and tonumber(vehicle.fuel) ~= nil then
    return clampFuel(vehicle.fuel)
  end

  return nil
end

function MZFuelPersistence.SaveFuelByPlate(plate, fuel, context)
  plate = normalizePlate(plate)
  if plate == '' then
    return false, 'invalid_plate'
  end

  fuel = clampFuel(fuel)
  context = type(context) == 'table' and context or {}
  FuelCache[plate] = fuel

  local vehicle = type(context.vehicle) == 'table' and context.vehicle or nil
  local ok, err = saveWithCoreCondition(plate, fuel, vehicle)
  if ok == true then
    return true
  end

  if Config.Debug == true then
    print(('[mz_fuel] fuel cached only for %s: %s'):format(plate, tostring(err)))
  end

  return false, err or 'persistence_unavailable'
end
