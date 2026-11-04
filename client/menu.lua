MZFuelMenu = MZFuelMenu or {}

local MenuState = {
  open = false,
  vehicle = 0,
  station = nil,
  stationCenter = nil,
  stationId = nil,
  pump = nil,
  physical = false,
  localKey = nil,
  pending = false,
  requestId = nil
}

local function notifyKey(key, notifyType, fallback)
  if MZFuelNotify and MZFuelNotify.NotifyKey then
    MZFuelNotify.NotifyKey(key, notifyType, fallback)
  end
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

local function normalizeStation(station)
  if type(station) == 'vector3' then
    return station
  end

  if type(station) == 'table' then
    local x = tonumber(station.x or station[1])
    local y = tonumber(station.y or station[2])
    local z = tonumber(station.z or station[3])
    if x and y and z then
      return vec3(x, y, z)
    end
  end

  return nil
end

local function stationPayload(station)
  station = normalizeStation(station)
  if not station then
    return nil
  end

  return {
    x = station.x,
    y = station.y,
    z = station.z
  }
end

local function pumpPayload(pump)
  if type(pump) ~= 'table' or not pump.coords then
    return nil
  end

  return {
    x = pump.coords.x,
    y = pump.coords.y,
    z = pump.coords.z,
    key = pump.pumpKey,
    model = pump.model,
    station_id = pump.stationIndex
  }
end

local function getVehiclePayload()
  local vehicle = MenuState.vehicle
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return nil
  end

  local netId = MZFuel.GetVehicleNetId(vehicle)
  netId = tonumber(netId) or 0
  local vehicleKey = netId > 0 and ('net:%s'):format(netId) or ('local:%s'):format(MenuState.localKey or 'unknown')

  return {
    plate = MZFuel.GetPlate(vehicle),
    net_id = netId,
    vehicle_key = vehicleKey,
    fuel = MZFuel.GetFuel(vehicle) or 0.0
  }
end

local function closeMenu()
  if MenuState.open ~= true then
    return
  end

  MenuState.open = false
  MenuState.vehicle = 0
  MenuState.station = nil
  MenuState.stationCenter = nil
  MenuState.stationId = nil
  MenuState.pump = nil
  MenuState.physical = false
  MenuState.localKey = nil
  MenuState.pending = false
  MenuState.requestId = nil
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'close' })
end

local function cancelMenuRequest()
  if MenuState.requestId == nil then
    return
  end

  local vehiclePayload = getVehiclePayload()
  TriggerServerEvent('mz_fuel:server:cancelMenuRefuel', {
    plate = vehiclePayload and vehiclePayload.plate or '',
    vehicle_key = vehiclePayload and vehiclePayload.vehicle_key or nil,
    request_id = MenuState.requestId
  })
end

local function requestMenuRefuel(mode, value)
  if MenuState.open ~= true or MenuState.pending == true then
    return false
  end

  local vehiclePayload = getVehiclePayload()
  local stationData = stationPayload(MenuState.stationCenter or MenuState.station)
  local pumpData = pumpPayload(MenuState.pump)
  if not vehiclePayload or (not stationData and MenuState.physical ~= true) then
    notifyKey('invalidVehicle', 'error', 'Veiculo invalido.')
    closeMenu()
    return false
  end

  MenuState.pending = true
  MenuState.requestId = ('%s:%s'):format(GetGameTimer(), math.random(100000, 999999))
  local requestId = MenuState.requestId

  TriggerServerEvent('mz_fuel:server:requestMenuRefuel', {
    mode = mode,
    value = value,
    request_id = requestId,
    plate = vehiclePayload.plate,
    net_id = vehiclePayload.net_id,
    vehicle_key = vehiclePayload.vehicle_key,
    fuel_before = vehiclePayload.fuel,
    station = stationData,
    station_id = MenuState.stationId,
    pump = pumpData,
    pump_key = MenuState.pump and MenuState.pump.pumpKey or nil,
    physical = MenuState.physical == true
  })

  CreateThread(function()
    Wait(10000)
    if MenuState.open == true and MenuState.pending == true and MenuState.requestId == requestId then
      MenuState.pending = false
      TriggerServerEvent('mz_fuel:server:cancelMenuRefuel', {
        plate = vehiclePayload.plate,
        vehicle_key = vehiclePayload.vehicle_key,
        request_id = requestId
      })
      notifyKey('paymentTimeout', 'inform', 'Pagamento nao respondeu. Tente novamente.')
      closeMenu()
    end
  end)

  return true
end

function MZFuelMenu.Open(vehicle, station, options)
  options = type(options) == 'table' and options or {}
  local physical = options.physical == true

  if Config.Refuel and Config.Refuel.useMenu ~= true then
    return MZFuelRefuel.Start(vehicle, station, options)
  end

  if MenuState.open == true or MZFuelRefuel.IsRefueling() then
    return false
  end

  station = normalizeStation(station)
  local stationCenter = options.pump and options.pump.station or nil
  if not stationCenter and not physical then
    stationCenter = station
  end

  local ok, reason = MZFuelRefuel.CanRefuel(vehicle, physical)
  if not ok or (not station and not physical) then
    notifyRefuelError(reason)
    return false
  end

  local fuel = MZFuel.GetFuel(vehicle) or 0.0
  local maxFuel = tonumber(Config.MaxFuel) or 100.0
  local pricePerLiter = tonumber(Config.Refuel and Config.Refuel.pricePerLiter) or 0

  MenuState.open = true
  MenuState.vehicle = vehicle
  MenuState.station = station
  MenuState.stationCenter = stationCenter
  MenuState.stationId = tonumber(options.stationId) or (options.pump and options.pump.stationIndex) or nil
  MenuState.pump = options.pump
  MenuState.physical = physical
  MenuState.localKey = (tonumber(MZFuel.GetVehicleNetId(vehicle)) or 0) > 0
    and nil
    or ('%s:%s'):format(GetGameTimer(), math.random(100000, 999999))
  MenuState.pending = false

  SetNuiFocus(true, true)
  SendNUIMessage({
    action = 'open',
    fuel = fuel,
    maxFuel = maxFuel,
    pricePerLiter = pricePerLiter,
    allowFillTank = Config.Refuel and Config.Refuel.allowFillTank == true,
    allowMoneyAmount = Config.Refuel and Config.Refuel.allowMoneyAmount == true,
    allowLiterAmount = Config.Refuel and Config.Refuel.allowLiterAmount == true,
    physical = physical,
    labels = {
      title = text('menu.title', 'Abastecimento'),
      subtitle = text('menu.subtitle', 'Posto e bomba validados pelo servidor'),
      currentFuel = text('menu.currentFuel', 'Combustivel atual'),
      pricePerLiter = text('menu.pricePerLiter', 'Preco por litro'),
      capacity = text('menu.capacity', 'Capacidade'),
      estimated = text('menu.estimated', 'Total estimado'),
      fill = text('menu.fill', 'Completar tanque'),
      money = text('menu.money', 'Abastecer por valor'),
      moneyPlaceholder = text('menu.moneyPlaceholder', 'Ex: 250'),
      liters = text('menu.liters', 'Abastecer por litros'),
      litersPlaceholder = text('menu.litersPlaceholder', 'Ex: 20'),
      confirm = text('menu.confirm', 'Abastecer'),
      cancel = text('menu.cancel', 'Cancelar'),
      payment = text('menu.payment', 'Pagamento via mz_economy'),
      litersUnit = text('menu.litersUnit', 'L'),
      fuelUnit = text('menu.fuelUnit', 'un'),
      currency = text('menu.currency', 'R$'),
      max = text('menu.max', 'Maximo'),
      vehicleFull = text('menu.vehicleFull', 'Tanque cheio'),
      physicalHint = text('menu.physicalHint', 'Bico encaixado. Escolha quanto abastecer.'),
      progress = text('menu.progress', 'Abastecendo'),
      progressDetail = text('menu.progressDetail', '{liters} L de {target} L')
    }
  })

  return true
end

function MZFuelMenu.IsBusy()
  return MenuState.open == true or MenuState.pending == true
end

function MZFuelMenu.Close()
  cancelMenuRequest()
  closeMenu()
end

function MZFuelMenu.SetProgress(percent, liters, target)
  percent = math.max(0.0, math.min(1.0, tonumber(percent) or 0.0))
  liters = tonumber(liters) or 0.0
  target = tonumber(target) or 0.0

  SendNUIMessage({
    action = 'progress',
    percent = percent,
    liters = liters,
    target = target,
    label = text('menu.progress', 'Abastecendo')
  })
end

function MZFuelMenu.HideProgress()
  SendNUIMessage({ action = 'progressHide' })
end

RegisterNetEvent('mz_fuel:client:openRefuelMenu', function(vehicleOrNetId, station, options)
  local vehicle = MZFuel.ResolveEventVehicle(vehicleOrNetId)
  if vehicle == 0 then
    vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
  end

  MZFuelMenu.Open(vehicle, station, options)
end)

RegisterNetEvent('mz_fuel:client:closeRefuelMenu', function()
  closeMenu()
end)

RegisterNetEvent('mz_fuel:client:refuelMenuAuthorized', function(result)
  if MenuState.open ~= true then
    return
  end

  MenuState.pending = false
  result = type(result) == 'table' and result or {}
  if result.ok ~= true then
    notifyRefuelError(result.error)
    closeMenu()
    return
  end

  local vehicle = MenuState.vehicle
  local station = MenuState.station
  local stationCenter = MenuState.stationCenter
  local stationId = MenuState.stationId
  local pump = MenuState.pump
  local physical = MenuState.physical
  local vehicleKey = result.vehicle_key or result.vehicleKey
  local sessionKey = result.session or result.session_key or result.sessionKey
  closeMenu()

  if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
    MZFuelRefuel.Start(vehicle, station, {
      targetLiters = tonumber(result.liters) or 0.0,
      menuSession = result.session,
      sessionKey = sessionKey,
      vehicleKey = vehicleKey,
      physical = physical == true,
      pump = pump,
      stationId = stationId,
      stationCenter = stationCenter
    })
  end
end)

RegisterNUICallback('refuel_fill', function(_, cb)
  cb({ ok = requestMenuRefuel('fill') })
end)

RegisterNUICallback('refuel_money', function(data, cb)
  data = type(data) == 'table' and data or {}
  cb({ ok = requestMenuRefuel('money', data.value) })
end)

RegisterNUICallback('refuel_liters', function(data, cb)
  data = type(data) == 'table' and data or {}
  cb({ ok = requestMenuRefuel('liters', data.value) })
end)

RegisterNUICallback('cancel', function(_, cb)
  cancelMenuRequest()
  closeMenu()
  cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then
    return
  end

  cancelMenuRequest()
  closeMenu()
end)
