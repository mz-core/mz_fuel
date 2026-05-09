MZFuel = MZFuel or {}

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

local function isVehicleEntity(vehicle)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return false
  end

  if type(GetEntityType) == 'function' then
    local entityType = GetEntityType(vehicle)
    if tonumber(entityType) == 2 then
      return true
    end

    if tonumber(entityType) and tonumber(entityType) > 0 then
      return false
    end
  end

  if type(IsEntityAVehicle) == 'function' then
    local ok, isVehicle = pcall(IsEntityAVehicle, vehicle)
    if ok then
      return isVehicle == true
    end
  end

  if type(GetVehicleClass) == 'function' then
    local ok, class = pcall(GetVehicleClass, vehicle)
    if ok and tonumber(class) ~= nil then
      return true
    end
  end

  return false
end

local function requestControl(vehicle, timeoutMs)
  if not isVehicleEntity(vehicle) then
    return false
  end

  if NetworkHasControlOfEntity(vehicle) then
    return true
  end

  local expiresAt = GetGameTimer() + (tonumber(timeoutMs) or 800)
  repeat
    NetworkRequestControlOfEntity(vehicle)
    Wait(0)
  until NetworkHasControlOfEntity(vehicle) or GetGameTimer() >= expiresAt

  return NetworkHasControlOfEntity(vehicle)
end

local function getStateFuel(vehicle)
  if Config.UseStateBag ~= true or not isVehicleEntity(vehicle) then
    return nil
  end

  local state = Entity(vehicle).state
  if not state then
    return nil
  end

  local fuel = tonumber(state.fuel)
  if fuel ~= nil then
    return clampFuel(fuel)
  end

  local condition = type(state.mz_world_condition) == 'table' and state.mz_world_condition or nil
  if condition and tonumber(condition.fuel) ~= nil then
    return clampFuel(condition.fuel)
  end

  return nil
end

local function setStateFuel(vehicle, fuel, replicated)
  if Config.UseStateBag ~= true or not isVehicleEntity(vehicle) then
    return
  end

  local state = Entity(vehicle).state
  if not state then
    return
  end

  pcall(function()
    state:set('fuel', clampFuel(fuel), replicated == true)
  end)
end

function MZFuel.NormalizePlate(plate)
  return normalizePlate(plate)
end

function MZFuel.ClampFuel(value)
  return clampFuel(value)
end

function MZFuel.IsVehicleSupported(vehicle)
  if not isVehicleEntity(vehicle) then
    return false
  end

  local class = GetVehicleClass(vehicle)
  if Config.DisableOnBicycles == true and class == 13 then
    return false
  end

  if Config.DisableOnElectric == true then
    local model = string.lower(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)) or '')
    if Config.ElectricModels and Config.ElectricModels[model] == true then
      return false
    end
  end

  return true
end

function MZFuel.GetPlate(vehicle)
  if not isVehicleEntity(vehicle) then
    return ''
  end

  local state = Entity(vehicle).state
  if state and state.mz_plate then
    local plate = normalizePlate(state.mz_plate)
    if plate ~= '' then
      return plate
    end
  end

  return normalizePlate(GetVehicleNumberPlateText(vehicle))
end

function MZFuel.GetFuel(vehicle)
  if not isVehicleEntity(vehicle) then
    return nil
  end

  local stateFuel = getStateFuel(vehicle)
  if stateFuel ~= nil then
    return stateFuel
  end

  if Config.UseNativeFuelLevel == true then
    return clampFuel(GetVehicleFuelLevel(vehicle))
  end

  return clampFuel(Config.DefaultFuel)
end

function MZFuel.GetVehicleNetId(vehicle, timeoutMs)
  if not isVehicleEntity(vehicle) then
    return 0
  end

  local netId = NetworkGetNetworkIdFromEntity(vehicle)
  netId = tonumber(netId) or 0
  if netId > 0 and (type(NetworkDoesNetworkIdExist) ~= 'function' or NetworkDoesNetworkIdExist(netId)) then
    return netId
  end

  if type(NetworkRegisterEntityAsNetworked) ~= 'function' then
    return 0
  end

  NetworkRegisterEntityAsNetworked(vehicle)
  local expiresAt = GetGameTimer() + (tonumber(timeoutMs) or 500)
  repeat
    Wait(0)
    netId = tonumber(NetworkGetNetworkIdFromEntity(vehicle)) or 0
  until (netId > 0 and (type(NetworkDoesNetworkIdExist) ~= 'function' or NetworkDoesNetworkIdExist(netId))) or GetGameTimer() >= expiresAt

  if netId > 0 and (type(NetworkDoesNetworkIdExist) ~= 'function' or NetworkDoesNetworkIdExist(netId)) then
    return netId
  end

  return 0
end

function MZFuel.SetFuel(vehicle, amount, options)
  if not isVehicleEntity(vehicle) then
    return false
  end

  local fuel = clampFuel(amount)
  options = type(options) == 'table' and options or {}

  if options.control ~= false then
    requestControl(vehicle, options.controlTimeoutMs or 800)
  end

  if Config.UseNativeFuelLevel == true then
    SetVehicleFuelLevel(vehicle, fuel)
  end

  setStateFuel(vehicle, fuel, options.replicate ~= false)
  return true, fuel
end

function MZFuel.AddFuel(vehicle, amount)
  if not isVehicleEntity(vehicle) then
    return false
  end

  return MZFuel.SetFuel(vehicle, (MZFuel.GetFuel(vehicle) or Config.DefaultFuel) + (tonumber(amount) or 0.0))
end

function MZFuel.RemoveFuel(vehicle, amount)
  if not isVehicleEntity(vehicle) then
    return false
  end

  return MZFuel.SetFuel(vehicle, (MZFuel.GetFuel(vehicle) or Config.DefaultFuel) - (tonumber(amount) or 0.0))
end

function MZFuel.ResolveEventVehicle(vehicleOrNetId)
  local value = tonumber(vehicleOrNetId) or 0
  if value <= 0 then
    return 0
  end

  if NetworkDoesNetworkIdExist(value) then
    local vehicle = NetworkGetEntityFromNetworkId(value)
    if isVehicleEntity(vehicle) then
      return vehicle
    end
  end

  if isVehicleEntity(value) then
    return value
  end

  return 0
end

exports('GetFuel', function(vehicle)
  return MZFuel.GetFuel(vehicle)
end)

exports('SetFuel', function(vehicle, amount)
  return MZFuel.SetFuel(vehicle, amount)
end)

exports('AddFuel', function(vehicle, amount)
  return MZFuel.AddFuel(vehicle, amount)
end)

exports('RemoveFuel', function(vehicle, amount)
  return MZFuel.RemoveFuel(vehicle, amount)
end)

exports('GetVehicleNetId', function(vehicle)
  return MZFuel.GetVehicleNetId(vehicle)
end)

RegisterNetEvent('mz_fuel:client:setFuel', function(vehicleOrNetId, amount)
  local vehicle = MZFuel.ResolveEventVehicle(vehicleOrNetId)
  if vehicle == 0 then
    return
  end

  MZFuel.SetFuel(vehicle, amount)
end)

RegisterNetEvent('mz_fuel:client:syncFuel', function(vehicleOrNetId, amount)
  local vehicle = MZFuel.ResolveEventVehicle(vehicleOrNetId)
  if vehicle == 0 then
    return
  end

  MZFuel.SetFuel(vehicle, amount, { replicate = false, control = false })
end)

if Config.UseStateBag == true then
  AddStateBagChangeHandler('fuel', nil, function(bagName, _, value)
    local vehicle = GetEntityFromStateBagName(bagName)
    if not isVehicleEntity(vehicle) then
      return
    end

    if Config.UseNativeFuelLevel == true then
      SetVehicleFuelLevel(vehicle, clampFuel(value))
    end
  end)
end
