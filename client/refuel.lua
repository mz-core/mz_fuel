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
  netId = 0,
  stationId = nil,
  lastStopReason = nil
}

local RefuelConfigOk = true

local function notifyKey(key, notifyType, fallback)
  if MZFuelNotify and MZFuelNotify.NotifyKey then
    MZFuelNotify.NotifyKey(key, notifyType, fallback)
  end
end

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

local function isPositiveNumber(value)
  value = tonumber(value)
  return value ~= nil and value == value and value > 0.0 and value ~= math.huge
end

local function validateRefuelConfig()
  local cfg = Config.Refuel or {}
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

  if #errors > 0 then
    RefuelConfigOk = false
    for _, errorMessage in ipairs(errors) do
      print(('[mz_fuel] config invalida: %s'):format(errorMessage))
    end
  end
end

local function getVehicleNetId(vehicle)
  return MZFuel.GetVehicleNetId(vehicle)
end

local function getStationId(station)
  if not station then
    return nil
  end

  for index, configuredStation in ipairs(Config.Stations and Config.Stations.locations or {}) do
    if #(station - configuredStation) <= 1.5 then
      return index
    end
  end

  return nil
end

local function debugVehicleSnapshot(tag, vehicle, extra)
  if Config.Debug ~= true then
    return
  end

  local exists = vehicle and vehicle ~= 0 and DoesEntityExist(vehicle)
  local ped = PlayerPedId()
  local plate = ''
  local fuel = nil
  local isDriver = false
  local netId = 0

  if exists then
    plate = MZFuel.NormalizePlate(GetVehicleNumberPlateText(vehicle))
    fuel = GetVehicleFuelLevel(vehicle)
    isDriver = GetPedInVehicleSeat(vehicle, -1) == ped
    netId = NetworkGetNetworkIdFromEntity(vehicle)
  end

  local fields = {
    vehicle = vehicle or 0,
    exists = exists == true,
    netId = netId,
    plate = plate,
    isDriver = isDriver,
    fuel = fuel,
    useMenu = Config.Refuel and Config.Refuel.useMenu,
    allowInsideVehicle = Config.Refuel and Config.Refuel.allowInsideVehicle,
    requireDriver = Config.Refuel and Config.Refuel.requireDriver
  }

  for key, value in pairs(extra or {}) do
    fields[key] = value
  end

  debugPrint(tag, fields)
end

local function notifyRefuelError(reason)
  reason = tostring(reason or '')

  if reason == 'not_enough_money' then
    notifyKey('noMoney', 'error', 'Dinheiro insuficiente.')
  elseif reason == 'driver_required' or reason == 'left_driver_seat' or reason == 'not_driver' then
    notifyKey('driverRequired', 'error', 'Entre no banco do motorista para abastecer.')
  elseif reason == 'too_far' or reason == 'station_distance_invalid' then
    notifyKey('tooFar', 'error', 'Voce esta longe demais do posto.')
  elseif reason == 'vehicle_full' then
    notifyKey('vehicleFull', 'inform', 'O veiculo ja esta cheio.')
  elseif reason == 'payment_unavailable' or reason == 'invalid_price' or reason == 'config_invalid' or reason == 'payment_failed' then
    notifyKey('paymentUnavailable', 'error', 'Pagamento indisponivel.')
  elseif reason == 'rate_limited' then
    notifyKey('rateLimited', 'inform', 'Aguarde um instante para tentar novamente.')
  else
    notifyKey('invalidVehicle', 'error', 'Veiculo invalido.')
  end
end

local function getPedVehicle()
  local ped = PlayerPedId()
  local vehicle = GetVehiclePedIsIn(ped, false)
  if vehicle ~= 0 and DoesEntityExist(vehicle) then
    return vehicle
  end

  return 0
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
  local ped = PlayerPedId()

  if Config.Refuel and Config.Refuel.allowInsideVehicle == false and IsPedInAnyVehicle(PlayerPedId(), false) then
    return false, 'inside_vehicle_blocked'
  end

  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return false, 'vehicle_invalid'
  end

  if not MZFuel.IsVehicleSupported(vehicle) then
    return false, 'vehicle_not_supported'
  end

  if Config.Refuel and Config.Refuel.requireDriver == true and GetPedInVehicleSeat(vehicle, -1) ~= ped then
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
  RefuelState.netId = 0
  RefuelState.stationId = nil
  RefuelState.lastStopReason = tostring(reason or 'stopped')
  stopProgress()

  if Config.Refuel and Config.Refuel.saveOnComplete ~= false and vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
    TriggerServerEvent('mz_fuel:server:saveFuel', MZFuel.GetPlate(vehicle), MZFuel.GetFuel(vehicle), {
      net_id = getVehicleNetId(vehicle),
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

  RefuelState.netId = getVehicleNetId(vehicle)

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
  local netId = getVehicleNetId(vehicle)
  RefuelState.netId = netId
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

  debugPrint('client_pay_tick', {
    vehicle = vehicle,
    exists = DoesEntityExist(vehicle),
    netId = netId,
    plate = MZFuel.GetPlate(vehicle),
    fuelBefore = currentFuel,
    litersRequested = liters,
    stationId = RefuelState.stationId
  })

  TriggerServerEvent('mz_fuel:server:payRefuel', {
    plate = MZFuel.GetPlate(vehicle),
    liters = liters,
    net_id = netId,
    station_id = RefuelState.stationId,
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
  if RefuelState.active == true or RefuelState.pendingPayment == true then
    return false, 'already_refueling'
  end

  if MZFuelMenu and MZFuelMenu.IsBusy and MZFuelMenu.IsBusy() then
    return false, 'already_refueling'
  end

  if RefuelConfigOk ~= true then
    notifyRefuelError('invalid_price')
    return false, 'invalid_config'
  end

  options = type(options) == 'table' and options or {}
  vehicle = vehicle or getRefuelVehicle()
  debugVehicleSnapshot('client_start', vehicle)

  local ok, reason = isValidRefuelVehicle(vehicle)
  if not ok then
    notifyRefuelError(reason)
    return false, reason
  end

  local netId = getVehicleNetId(vehicle)

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
  RefuelState.netId = netId
  RefuelState.stationId = tonumber(options.stationId) or getStationId(station)
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
    notifyRefuelError(result.error)
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

validateRefuelConfig()
