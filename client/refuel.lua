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
  lastStopReason = nil,
  physical = false,
  pump = nil,
  stationCenter = nil,
  vehicleKey = nil,
  sessionKey = nil,
  pendingPaymentAt = nil,
  progressTarget = nil
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

local function text(key, fallback)
  if type(MZFuelText) == 'function' then
    local value = MZFuelText(key, nil)
    if value and value ~= key then
      return value
    end
  end

  return fallback or key
end

local function stopProgress()
  if MZFuelNotify and MZFuelNotify.StopProgress then
    MZFuelNotify.StopProgress('refuel')
  end
end

local function startProgress(durationMs)
  -- O fluxo com menu usa o overlay da NUI. O progresso nativo fica para o
  -- caminho legado sem menu e para outros consumidores.
  if Config.Refuel and Config.Refuel.useMenu == true then
    return
  end

  if MZFuelNotify and MZFuelNotify.StartProgress then
    MZFuelNotify.StartProgress('refuel', MZFuelNotify.Message('refuelStarted', 'Abastecimento iniciado.'), durationMs)
  end
end

local function drawHelp(message)
  BeginTextCommandDisplayHelp('STRING')
  AddTextComponentSubstringPlayerName(message)
  EndTextCommandDisplayHelp(0, false, true, 1)
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

  if reason == 'not_enough_money' or reason == 'insufficient_funds' or reason == 'insufficient_balance' then
    notifyKey('noMoney', 'error', 'Dinheiro insuficiente.')
  elseif reason == 'driver_required' or reason == 'left_driver_seat' or reason == 'not_driver' then
    notifyKey('driverRequired', 'error', 'Entre no banco do motorista para abastecer.')
  elseif reason == 'too_far' or reason == 'station_distance_invalid' or reason == 'pump_distance_invalid' then
    notifyKey('tooFar', 'error', 'Voce esta longe demais do posto.')
  elseif reason == 'vehicle_full' then
    notifyKey('vehicleFull', 'inform', 'O veiculo ja esta cheio.')
  elseif reason == 'engine_running' then
    notifyKey('engineRunning', 'error', 'Desligue o motor antes de abastecer.')
  elseif reason == 'physical_required' or reason == 'nozzle_not_docked' or reason == 'pump_not_claimed' then
    notifyKey('physicalRequired', 'error', 'Pegue o bico da bomba e encaixe no tanque primeiro.')
  elseif reason == 'inside_vehicle_blocked' then
    notifyKey('insideVehicleBlocked', 'error', 'Saia do veiculo para abastecer.')
  elseif reason == 'vehicle_busy' or reason == 'pump_busy' then
    notifyKey('vehicleBusy', 'inform', 'Este veiculo ja esta sendo abastecido por outro jogador.')
  elseif reason == 'payment_unavailable' or reason == 'invalid_price' or reason == 'config_invalid' or reason == 'payment_failed' then
    notifyKey('paymentUnavailable', 'error', 'Pagamento indisponivel.')
  elseif reason == 'payment_timeout' then
    notifyKey('paymentTimeout', 'inform', 'Pagamento nao respondeu. Tente novamente.')
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

local function isEngineRunning(vehicle)
  local value = GetIsVehicleEngineRunning(vehicle)
  return value == true or value == 1
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

local function isValidRefuelVehicle(vehicle, options)
  options = type(options) == 'table' and options or {}
  local physical = options.physical == true
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

  if Config.Refuel and Config.Refuel.requireEngineOff == true and isEngineRunning(vehicle) then
    return false, 'engine_running'
  end

  if physical then
    if not MZFuelNozzle or not MZFuelNozzle.IsDockedTo(vehicle) then
      return false, 'nozzle_not_docked'
    end

    local vehicleCoords = GetEntityCoords(vehicle)
    local playerCoords = GetEntityCoords(ped)
    local keepDistance = tonumber(Config.Refuel and Config.Refuel.refuelKeepDistance) or 5.0
    if #(playerCoords - vehicleCoords) > keepDistance + 1.5 then
      return false, 'too_far'
    end
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

function MZFuelRefuel.CanRefuel(vehicle, physical)
  return isValidRefuelVehicle(vehicle, { physical = physical == true })
end

function MZFuelRefuel.Stop(reason, silent)
  if RefuelState.active ~= true then
    return false
  end

  local vehicle = RefuelState.vehicle
  local plate = RefuelState.plate
  local menuSession = RefuelState.menuSession
  local vehicleKey = RefuelState.vehicleKey
  local sessionKey = RefuelState.sessionKey
  RefuelState.active = false
  RefuelState.pendingPayment = false
  RefuelState.pendingPaymentAt = nil
  RefuelState.targetLiters = nil
  RefuelState.usedLiters = 0.0
  RefuelState.menuSession = nil
  RefuelState.netId = 0
  RefuelState.stationId = nil
  RefuelState.physical = false
  RefuelState.pump = nil
  RefuelState.stationCenter = nil
  RefuelState.vehicleKey = nil
  RefuelState.sessionKey = nil
  RefuelState.progressTarget = nil
  RefuelState.lastStopReason = tostring(reason or 'stopped')
  stopProgress()

  if MZFuelMenu and MZFuelMenu.HideProgress then
    MZFuelMenu.HideProgress()
  end

  TriggerServerEvent('mz_fuel:server:endRefuel', {
    plate = plate,
    vehicle_key = vehicleKey,
    session_key = sessionKey or menuSession,
    menu_session = menuSession
  })

  if Config.Refuel and Config.Refuel.saveOnComplete ~= false and vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
    TriggerServerEvent('mz_fuel:server:saveFuel', MZFuel.GetPlate(vehicle), MZFuel.GetFuel(vehicle), {
      net_id = getVehicleNetId(vehicle),
      session_key = sessionKey,
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

  if RefuelState.physical == true then
    if not MZFuelNozzle or not MZFuelNozzle.IsDockedTo(vehicle) then
      MZFuelRefuel.Stop('nozzle_not_docked')
      return false
    end

    if Config.Refuel and Config.Refuel.requireEngineOff == true and isEngineRunning(vehicle) then
      MZFuelRefuel.Stop('engine_running')
      return false
    end

    local keepDistance = tonumber(Config.Refuel and Config.Refuel.refuelKeepDistance) or 5.0
    if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(vehicle)) > keepDistance + 1.5 then
      MZFuelRefuel.Stop('too_far')
      return false
    end
  end

  local distance = distanceToStation(RefuelState.station)
  local maxDistance = tonumber(Config.Refuel and Config.Refuel.maxDistance) or 6.0
  if RefuelState.physical == true then
    maxDistance = math.max(maxDistance, tonumber(Config.Refuel and Config.Refuel.maxPumpDistance) or 10.0)
  end

  if distance and distance > maxDistance then
    MZFuelRefuel.Stop('too_far')
    return false
  end

  local ok, reason = isValidRefuelVehicle(vehicle, { physical = RefuelState.physical == true })
  if not ok then
    MZFuelRefuel.Stop(reason, reason == 'vehicle_full')
    if reason == 'vehicle_full' then
      notifyKey('vehicleFull', 'inform', 'O veiculo ja esta cheio.')
    elseif reason == 'engine_running' then
      notifyKey('engineRunning', 'error', 'Desligue o motor antes de abastecer.')
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
  RefuelState.pendingPaymentAt = GetGameTimer()
  startProgress(math.max(250, tonumber(Config.Refuel and Config.Refuel.tickMs) or 1000))

  if MZFuelMenu and MZFuelMenu.SetProgress and RefuelState.progressTarget and RefuelState.progressTarget > 0.0 then
    MZFuelMenu.SetProgress(
      (tonumber(RefuelState.usedLiters) or 0.0) / RefuelState.progressTarget,
      RefuelState.usedLiters or 0.0,
      RefuelState.progressTarget
    )
  end

  debugPrint('client_pay_tick', {
    vehicle = vehicle,
    exists = DoesEntityExist(vehicle),
    netId = netId,
    plate = MZFuel.GetPlate(vehicle),
    fuelBefore = currentFuel,
    litersRequested = liters,
    stationId = RefuelState.stationId,
    physical = RefuelState.physical == true,
    pump = RefuelState.pump and RefuelState.pump.pumpKey or 'none'
  })

  local payloadStation = RefuelState.station
  if RefuelState.physical then
    payloadStation = RefuelState.stationCenter or (RefuelState.pump and RefuelState.pump.station) or RefuelState.station
  end

  TriggerServerEvent('mz_fuel:server:payRefuel', {
    plate = MZFuel.GetPlate(vehicle),
    liters = liters,
    net_id = netId,
    vehicle_key = RefuelState.vehicleKey,
    session_key = RefuelState.sessionKey,
    station_id = RefuelState.stationId,
    fuel_before = currentFuel,
    menu_session = RefuelState.menuSession,
    physical = RefuelState.physical == true,
    pump_key = RefuelState.pump and RefuelState.pump.pumpKey or nil,
    pump = RefuelState.pump and {
      x = RefuelState.pump.coords.x,
      y = RefuelState.pump.coords.y,
      z = RefuelState.pump.coords.z
    } or nil,
    station = payloadStation and {
      x = payloadStation.x,
      y = payloadStation.y,
      z = payloadStation.z
    } or nil
  })
end

local function runRefuelLoop()
  CreateThread(function()
    local tickMs = math.max(250, tonumber(Config.Refuel and Config.Refuel.tickMs) or 1000)
    local paymentTimeoutMs = math.max(5000, tickMs * 8)

    while RefuelState.active == true do
      local cancelKey = tonumber(Config.Refuel and Config.Refuel.cancelKey) or 177
      if IsControlJustPressed(0, cancelKey) then
        notifyKey('refuelCanceled', 'inform', 'Abastecimento cancelado.')
        MZFuelRefuel.Stop('user_canceled', true)
        break
      end

      drawHelp(text('prompt.cancelRefuel', '[BACKSPACE] Cancelar abastecimento'))

      if RefuelState.pendingPayment == true
        and RefuelState.pendingPaymentAt
        and (GetGameTimer() - RefuelState.pendingPaymentAt) > paymentTimeoutMs then
        MZFuelRefuel.Stop('payment_timeout', true)
        notifyRefuelError('payment_timeout')
        break
      end

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
  local physical = options.physical == true
  vehicle = vehicle or getRefuelVehicle()
  debugVehicleSnapshot('client_start', vehicle, {
    physical = physical,
    pump = options.pump and options.pump.pumpKey or 'none'
  })

  local ok, reason = isValidRefuelVehicle(vehicle, { physical = physical })
  if not ok then
    notifyRefuelError(reason)
    return false, reason
  end

  if physical and not options.pump then
    notifyRefuelError('physical_required')
    return false, 'physical_required'
  end

  local netId = getVehicleNetId(vehicle)
  local vehicleKey = tostring(options.vehicleKey or '')
  if vehicleKey == '' then
    vehicleKey = netId > 0 and ('net:%s'):format(netId) or ('local:%s:%s'):format(GetGameTimer(), math.random(100000, 999999))
  end
  local sessionKey = tostring(options.sessionKey or '')
  if sessionKey == '' then
    sessionKey = ('session:%s:%s'):format(GetGameTimer(), math.random(100000, 999999))
  end

  if station then
    local maxDistance = tonumber(Config.Refuel and Config.Refuel.maxDistance) or 6.0
    if physical then
      maxDistance = math.max(maxDistance, tonumber(Config.Refuel and Config.Refuel.maxPumpDistance) or 10.0)
    end

    local distance = distanceToStation(station)
    if distance and distance > maxDistance then
      return false, 'too_far'
    end
  end

  RefuelState.active = true
  RefuelState.vehicle = vehicle
  RefuelState.station = station
  RefuelState.plate = MZFuel.GetPlate(vehicle)
  RefuelState.pendingPayment = false
  RefuelState.pendingPaymentAt = nil
  RefuelState.targetLiters = tonumber(options.targetLiters)
  RefuelState.usedLiters = 0.0
  RefuelState.menuSession = options.menuSession
  RefuelState.netId = netId
  RefuelState.stationId = tonumber(options.stationId) or getStationId(station)
  RefuelState.physical = physical
  RefuelState.pump = options.pump
  RefuelState.stationCenter = options.stationCenter or (options.pump and options.pump.station) or nil
  RefuelState.vehicleKey = vehicleKey
  RefuelState.sessionKey = sessionKey
  RefuelState.progressTarget = RefuelState.targetLiters
    or math.max(0.0, (tonumber(Config.MaxFuel) or 100.0) - (MZFuel.GetFuel(vehicle) or 0.0))
  RefuelState.lastStopReason = nil

  notifyKey('refuelStarted', 'inform', 'Abastecimento iniciado.')
  startProgress(math.max(250, tonumber(Config.Refuel and Config.Refuel.tickMs) or 1000))
  if MZFuelMenu and MZFuelMenu.SetProgress and RefuelState.progressTarget and RefuelState.progressTarget > 0.0 then
    MZFuelMenu.SetProgress(0.0, 0.0, RefuelState.progressTarget)
  end
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
  RefuelState.pendingPaymentAt = nil
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

  if MZFuelMenu and MZFuelMenu.SetProgress and RefuelState.progressTarget and RefuelState.progressTarget > 0.0 then
    MZFuelMenu.SetProgress(
      RefuelState.usedLiters / RefuelState.progressTarget,
      RefuelState.usedLiters,
      RefuelState.progressTarget
    )
  end

  if (MZFuel.GetFuel(vehicle) or 0.0) >= (tonumber(Config.MaxFuel) or 100.0)
    or (RefuelState.targetLiters and RefuelState.usedLiters >= (RefuelState.targetLiters - 0.01)) then
    notifyKey('refuelFinished', 'success', 'Veiculo abastecido.')
    MZFuelRefuel.Stop('target_reached', true)
  end
end)

function MZFuelRefuel.GetDiagnostics()
  return {
    active = RefuelState.active == true,
    pending_payment = RefuelState.pendingPayment == true,
    vehicle = RefuelState.vehicle,
    plate = RefuelState.plate,
    station_id = RefuelState.stationId or 'none',
    physical = RefuelState.physical == true,
    pump = RefuelState.pump and RefuelState.pump.pumpKey or 'none',
    vehicle_key = RefuelState.vehicleKey or 'none',
    session_key = RefuelState.sessionKey or 'none',
    target_liters = RefuelState.targetLiters or 'fill',
    used_liters = RefuelState.usedLiters or 0.0,
    progress_target = RefuelState.progressTarget or 0.0,
    menu_session = RefuelState.menuSession and 'set' or 'none',
    last_stop = RefuelState.lastStopReason or 'none'
  }
end

exports('IsRefueling', function()
  return MZFuelRefuel.IsRefueling()
end)

exports('CanRefuel', function(vehicle, physical)
  return MZFuelRefuel.CanRefuel(vehicle, physical)
end)

validateRefuelConfig()
