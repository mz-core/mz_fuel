MZFuelRefuel = MZFuelRefuel or {}

local RefuelState = {
  active = false,
  vehicle = 0,
  station = nil,
  plate = '',
  pendingPayment = false,
  targetLiters = nil,
  usedLiters = 0.0,
  menuSession = nil,
  lastStopReason = nil
}

local function notifyKey(key, notifyType, fallback)
  if MZFuelNotify and MZFuelNotify.NotifyKey then
    MZFuelNotify.NotifyKey(key, notifyType, fallback)
  end
end

local function stopProgress()
  if MZFuelNotify and MZFuelNotify.StopProgress then
    MZFuelNotify.StopProgress('refuel')
  end
end

local function startProgress(durationMs)
  if MZFuelNotify and MZFuelNotify.StartProgress then
    MZFuelNotify.StartProgress('refuel', MZFuelNotify.Message('refuelStarted', 'Abastecimento iniciado.'), durationMs)
  end
end

local function getPedVehicle()
  local ped = PlayerPedId()

  return GetVehiclePedIsIn(ped, false)
end

local function isPlayerDead()
  local ped = PlayerPedId()
  return not ped or ped == 0 or IsEntityDead(ped)
end

local function distanceToStation(station)
  if not station then
    return nil
  end

  return #(GetEntityCoords(PlayerPedId()) - station)
end

local function normalizeLiters(value)
  local liters = tonumber(value) or 0.0
  if liters < 0.0 then
    liters = 0.0
  end
  return liters + 0.0
end

local function isValidRefuelVehicle(vehicle)
  if Config.Refuel and Config.Refuel.allowInsideVehicle == false and IsPedInAnyVehicle(PlayerPedId(), false) then
    return false, 'inside_vehicle_blocked'
  end

  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return false, 'vehicle_invalid'
  end

  if not MZFuel.IsVehicleSupported(vehicle) then
    return false, 'vehicle_not_supported'
  end

  if Config.Refuel and Config.Refuel.requireDriver == true and GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId() then
    return false, 'driver_required'
  end

  local fuel = MZFuel.GetFuel(vehicle) or 0.0
  if fuel >= (tonumber(Config.MaxFuel) or 100.0) then
    return false, 'vehicle_full'
  end

  return true
end

local function getRefuelVehicle()
  local vehicle = getPedVehicle()
  if vehicle ~= 0 then
    return vehicle
  end

  if RefuelState.vehicle ~= 0 then
    return RefuelState.vehicle
  end

  return 0
end

function MZFuelRefuel.IsRefueling()
  return RefuelState.active == true
end

function MZFuelRefuel.CanRefuel(vehicle)
  return isValidRefuelVehicle(vehicle)
end

function MZFuelRefuel.Stop(reason, silent)
  if RefuelState.active ~= true then
    return false
  end

  local vehicle = RefuelState.vehicle
  RefuelState.active = false
  RefuelState.pendingPayment = false
  RefuelState.targetLiters = nil
  RefuelState.usedLiters = 0.0
  RefuelState.menuSession = nil
  RefuelState.lastStopReason = tostring(reason or 'stopped')
  stopProgress()

  if Config.Refuel and Config.Refuel.saveOnComplete ~= false and vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
    TriggerServerEvent('mz_fuel:server:saveFuel', MZFuel.GetPlate(vehicle), MZFuel.GetFuel(vehicle), {
      net_id = NetworkGetNetworkIdFromEntity(vehicle),
      engine = GetVehicleEngineHealth(vehicle),
      body = GetVehicleBodyHealth(vehicle),
      force = true
    })
  end

  if silent ~= true then
    notifyKey('refuelCanceled', 'inform', 'Abastecimento cancelado.')
  end

  return true
end

local function validateActiveState()
  if RefuelState.active ~= true then
    return false
  end

  local vehicle = RefuelState.vehicle
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    MZFuelRefuel.Stop('vehicle_missing')
    return false
  end

  if isPlayerDead() then
    MZFuelRefuel.Stop('player_dead')
    return false
  end

  if Config.Refuel and Config.Refuel.allowInsideVehicle == false and IsPedInAnyVehicle(PlayerPedId(), false) then
    MZFuelRefuel.Stop('inside_vehicle_blocked')
    return false
  end

  if Config.Refuel and Config.Refuel.allowInsideVehicle == true and GetVehiclePedIsIn(PlayerPedId(), false) ~= vehicle then
    MZFuelRefuel.Stop('left_vehicle')
    return false
  end

  if Config.Refuel and Config.Refuel.requireDriver == true and GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId() then
    MZFuelRefuel.Stop('left_driver_seat')
    return false
  end

  local distance = distanceToStation(RefuelState.station)
  if distance and distance > (tonumber(Config.Refuel and Config.Refuel.maxDistance) or 6.0) then
    MZFuelRefuel.Stop('too_far')
    return false
  end

  local ok, reason = isValidRefuelVehicle(vehicle)
  if not ok then
    MZFuelRefuel.Stop(reason, reason == 'vehicle_full')
    if reason == 'vehicle_full' then
      notifyKey('vehicleFull', 'inform', 'O veiculo ja esta cheio.')
    end
    return false
  end

  return true
end

local function requestPayment()
  if RefuelState.pendingPayment == true then
    return
  end

  local vehicle = RefuelState.vehicle
  local currentFuel = MZFuel.GetFuel(vehicle) or 0.0
  local missing = (tonumber(Config.MaxFuel) or 100.0) - currentFuel
  local liters = math.min(normalizeLiters(Config.Refuel and Config.Refuel.litersPerTick), missing)
  if RefuelState.targetLiters then
    liters = math.min(liters, math.max(0.0, (tonumber(RefuelState.targetLiters) or 0.0) - (tonumber(RefuelState.usedLiters) or 0.0)))
  end

  if liters <= 0.0 then
    notifyKey('refuelFinished', 'success', 'Veiculo abastecido.')
    MZFuelRefuel.Stop('target_reached', true)
    return
  end

  RefuelState.pendingPayment = true
  startProgress(math.max(250, tonumber(Config.Refuel and Config.Refuel.tickMs) or 1000))
  TriggerServerEvent('mz_fuel:server:payRefuel', {
    plate = MZFuel.GetPlate(vehicle),
    liters = liters,
    net_id = NetworkGetNetworkIdFromEntity(vehicle),
    fuel_before = currentFuel,
    menu_session = RefuelState.menuSession,
    station = RefuelState.station and {
      x = RefuelState.station.x,
      y = RefuelState.station.y,
      z = RefuelState.station.z
    } or nil
  })
end

local function runRefuelLoop()
  CreateThread(function()
    local tickMs = math.max(250, tonumber(Config.Refuel and Config.Refuel.tickMs) or 1000)

    while RefuelState.active == true do
      if validateActiveState() then
        requestPayment()
      end

      Wait(tickMs)
    end
  end)
end

function MZFuelRefuel.Start(vehicle, station, options)
  if RefuelState.active == true then
    return false, 'already_refueling'
  end

  options = type(options) == 'table' and options or {}
  vehicle = vehicle or getRefuelVehicle()
  local ok, reason = isValidRefuelVehicle(vehicle)
  if not ok then
    return false, reason
  end

  if station then
    local distance = distanceToStation(station)
    if distance and distance > (tonumber(Config.Refuel and Config.Refuel.maxDistance) or 6.0) then
      return false, 'too_far'
    end
  end

  RefuelState.active = true
  RefuelState.vehicle = vehicle
  RefuelState.station = station
  RefuelState.plate = MZFuel.GetPlate(vehicle)
  RefuelState.pendingPayment = false
  RefuelState.targetLiters = tonumber(options.targetLiters)
  RefuelState.usedLiters = 0.0
  RefuelState.menuSession = options.menuSession
  RefuelState.lastStopReason = nil

  notifyKey('refuelStarted', 'inform', 'Abastecimento iniciado.')
  startProgress(math.max(250, tonumber(Config.Refuel and Config.Refuel.tickMs) or 1000))
  runRefuelLoop()
  return true
end

RegisterNetEvent('mz_fuel:client:startRefuel', function(vehicleOrNetId, station)
  local vehicle = MZFuel.ResolveEventVehicle(vehicleOrNetId)
  if vehicle == 0 then
    vehicle = getRefuelVehicle()
  end

  MZFuelRefuel.Start(vehicle, station)
end)

RegisterNetEvent('mz_fuel:client:stopRefuel', function(reason)
  MZFuelRefuel.Stop(reason or 'event_stop')
end)

RegisterNetEvent('mz_fuel:client:refuelPaid', function(result)
  if RefuelState.active ~= true then
    return
  end

  RefuelState.pendingPayment = false
  result = type(result) == 'table' and result or {}

  if result.ok ~= true then
    if result.error == 'not_enough_money' then
      notifyKey('noMoney', 'error', 'Dinheiro insuficiente.')
    else
      notifyKey('invalidVehicle', 'error', 'Veiculo invalido.')
    end
    MZFuelRefuel.Stop(result.error or 'payment_failed', true)
    return
  end

  if not validateActiveState() then
    return
  end

  local vehicle = RefuelState.vehicle
  local liters = normalizeLiters(result.liters)
  if liters <= 0.0 then
    return
  end

  MZFuel.AddFuel(vehicle, liters)
  RefuelState.usedLiters = (tonumber(RefuelState.usedLiters) or 0.0) + liters
  if (MZFuel.GetFuel(vehicle) or 0.0) >= (tonumber(Config.MaxFuel) or 100.0)
    or (RefuelState.targetLiters and RefuelState.usedLiters >= (RefuelState.targetLiters - 0.01)) then
    notifyKey('refuelFinished', 'success', 'Veiculo abastecido.')
    MZFuelRefuel.Stop('vehicle_full', true)
  end
end)

exports('IsRefueling', function()
  return MZFuelRefuel.IsRefueling()
end)

exports('CanRefuel', function(vehicle)
  return MZFuelRefuel.CanRefuel(vehicle)
end)
