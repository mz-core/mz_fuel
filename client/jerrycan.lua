MZFuelJerryCan = MZFuelJerryCan or {}

local JerryCanState = {
  active = false,
  vehicle = 0,
  token = nil,
  liters = 0.0
}

local function notifyKey(key, notifyType, fallback)
  if MZFuelNotify and MZFuelNotify.NotifyKey then
    MZFuelNotify.NotifyKey(key, notifyType, fallback)
  end
end

local function stopProgress()
  if MZFuelNotify and MZFuelNotify.StopProgress then
    MZFuelNotify.StopProgress('jerrycan')
  end
end

local function startProgress(durationMs)
  if MZFuelNotify and MZFuelNotify.StartProgress then
    MZFuelNotify.StartProgress('jerrycan', MZFuelNotify.Message('jerrycanStarted', 'Usando galao de combustivel.'), durationMs)
  end
end

local function jerryConfig()
  return type(Config.JerryCan) == 'table' and Config.JerryCan or {}
end

local function isEnabled()
  return jerryConfig().enabled == true
end

local function findNearestVehicle(maxDistance)
  local ped = PlayerPedId()
  local pedCoords = GetEntityCoords(ped)
  local closestVehicle = 0
  local closestDistance = tonumber(maxDistance) or 3.0

  local vehicles = GetGamePool('CVehicle')
  for _, vehicle in ipairs(vehicles) do
    if vehicle ~= 0 and DoesEntityExist(vehicle) then
      local distance = #(pedCoords - GetEntityCoords(vehicle))
      if distance <= closestDistance then
        closestVehicle = vehicle
        closestDistance = distance
      end
    end
  end

  return closestVehicle
end

local function getCandidateVehicle()
  if jerryConfig().requireOutsideVehicle ~= true then
    local currentVehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if currentVehicle ~= 0 then
      return currentVehicle
    end
  end

  return findNearestVehicle(tonumber(jerryConfig().maxDistance) or 3.0)
end

local function isPlayerDead()
  local ped = PlayerPedId()
  return not ped or ped == 0 or IsEntityDead(ped)
end

local function isNearVehicle(vehicle)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return false
  end

  local maxDistance = tonumber(jerryConfig().maxDistance) or 3.0
  return #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(vehicle)) <= maxDistance
end

local function isVehicleFull(vehicle)
  local fuel = MZFuel.GetFuel(vehicle) or 0.0
  return fuel >= (tonumber(Config.MaxFuel) or 100.0)
end

function MZFuelJerryCan.CanUse(vehicle)
  if not isEnabled() or JerryCanState.active == true then
    return false, 'disabled'
  end

  if jerryConfig().requireOutsideVehicle == true and IsPedInAnyVehicle(PlayerPedId(), false) then
    return false, 'outside_required'
  end

  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return false, 'vehicle_invalid'
  end

  if not MZFuel.IsVehicleSupported(vehicle) then
    return false, 'vehicle_not_supported'
  end

  if not isNearVehicle(vehicle) then
    return false, 'too_far'
  end

  if isVehicleFull(vehicle) then
    return false, 'vehicle_full'
  end

  return true
end

function MZFuelJerryCan.IsUsing()
  return JerryCanState.active == true
end

local function clearState()
  JerryCanState.active = false
  JerryCanState.vehicle = 0
  JerryCanState.token = nil
  JerryCanState.liters = 0.0
  stopProgress()
  ClearPedTasks(PlayerPedId())
end

local function cancel(reason)
  if JerryCanState.active ~= true then
    return
  end

  clearState()
  if reason == 'vehicle_full' then
    notifyKey('vehicleFull', 'inform', 'O veiculo ja esta cheio.')
  else
    notifyKey('jerrycanCanceled', 'inform', 'Uso do galao cancelado.')
  end
end

local function validateActive()
  local vehicle = JerryCanState.vehicle
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    cancel('vehicle_missing')
    return false
  end

  if isPlayerDead() then
    cancel('player_dead')
    return false
  end

  if jerryConfig().requireOutsideVehicle == true and IsPedInAnyVehicle(PlayerPedId(), false) then
    cancel('outside_required')
    return false
  end

  if not isNearVehicle(vehicle) then
    cancel('too_far')
    return false
  end

  if not MZFuel.IsVehicleSupported(vehicle) then
    cancel('vehicle_not_supported')
    return false
  end

  if isVehicleFull(vehicle) then
    cancel('vehicle_full')
    return false
  end

  return true
end

local function beginUse(payload)
  if JerryCanState.active ~= true or type(payload) ~= 'table' or payload.ok ~= true then
    return
  end

  JerryCanState.token = tostring(payload.token or '')
  JerryCanState.liters = tonumber(payload.liters) or 0.0
  if JerryCanState.token == '' or JerryCanState.liters <= 0.0 then
    cancel('invalid_authorization')
    return
  end

  local vehicle = JerryCanState.vehicle
  local ped = PlayerPedId()
  local useTime = math.max(1000, tonumber(payload.useTimeMs) or tonumber(jerryConfig().useTimeMs) or 6000)
  notifyKey('jerrycanStarted', 'inform', 'Usando galao de combustivel.')
  startProgress(useTime)
  TaskTurnPedToFaceEntity(ped, vehicle, 1000)
  Wait(350)
  TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_GARDENER_PLANT', 0, true)

  local expiresAt = GetGameTimer() + useTime
  while JerryCanState.active == true and GetGameTimer() < expiresAt do
    if not validateActive() then
      return
    end

    Wait(250)
  end

  if JerryCanState.active ~= true or not validateActive() then
    return
  end

  TriggerServerEvent('mz_fuel:server:finishJerryCan', {
    token = JerryCanState.token
  })
end

function MZFuelJerryCan.Start(vehicle)
  if JerryCanState.active == true then
    return false, 'already_using'
  end

  vehicle = vehicle or getCandidateVehicle()
  local ok, reason = MZFuelJerryCan.CanUse(vehicle)
  if not ok then
    if reason == 'vehicle_full' then
      notifyKey('vehicleFull', 'inform', 'O veiculo ja esta cheio.')
    else
      notifyKey('invalidVehicle', 'error', 'Veiculo invalido.')
    end
    return false, reason
  end

  JerryCanState.active = true
  JerryCanState.vehicle = vehicle
  JerryCanState.token = nil
  JerryCanState.liters = 0.0
  local netId = MZFuel.GetVehicleNetId(vehicle)

  TriggerServerEvent('mz_fuel:server:authorizeJerryCan', {
    plate = MZFuel.GetPlate(vehicle),
    net_id = netId,
    fuel_before = MZFuel.GetFuel(vehicle)
  })

  return true
end

RegisterNetEvent('mz_fuel:client:useJerryCan', function(vehicleOrNetId)
  local vehicle = MZFuel.ResolveEventVehicle(vehicleOrNetId)
  if vehicle == 0 then
    vehicle = getCandidateVehicle()
  end

  MZFuelJerryCan.Start(vehicle)
end)

RegisterNetEvent('mz_fuel:client:jerryCanAuthorized', function(result)
  result = type(result) == 'table' and result or {}
  if JerryCanState.active ~= true then
    return
  end

  if result.ok ~= true then
    clearState()
    if result.error == 'item_missing' then
      notifyKey('noJerrycan', 'error', 'Voce nao possui um galao.')
    else
      notifyKey('invalidVehicle', 'error', 'Veiculo invalido.')
    end
    return
  end

  beginUse(result)
end)

RegisterNetEvent('mz_fuel:client:jerryCanFinished', function(result)
  result = type(result) == 'table' and result or {}
  if JerryCanState.active ~= true then
    return
  end

  if result.ok ~= true then
    clearState()
    notifyKey('jerrycanCanceled', 'error', 'Uso do galao cancelado.')
    return
  end

  if not validateActive() then
    return
  end

  local vehicle = JerryCanState.vehicle
  local liters = tonumber(result.liters) or 0.0
  clearState()

  if vehicle ~= 0 and DoesEntityExist(vehicle) and liters > 0.0 then
    MZFuel.AddFuel(vehicle, liters)
    TriggerServerEvent('mz_fuel:server:saveFuel', MZFuel.GetPlate(vehicle), MZFuel.GetFuel(vehicle), {
      net_id = MZFuel.GetVehicleNetId(vehicle),
      engine = GetVehicleEngineHealth(vehicle),
      body = GetVehicleBodyHealth(vehicle),
      force = true
    })
    notifyKey('jerrycanFinished', 'success', 'Combustivel adicionado.')
  end
end)

exports('CanUseJerryCan', function(vehicle)
  return MZFuelJerryCan.CanUse(vehicle)
end)

exports('IsUsingJerryCan', function()
  return MZFuelJerryCan.IsUsing()
end)
