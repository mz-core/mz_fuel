MZFuelMenu = MZFuelMenu or {}

local MenuState = {
  open = false,
  vehicle = 0,
  station = nil,
  pending = false,
  requestId = nil
}

local function notifyKey(key, notifyType, fallback)
  if MZFuelNotify and MZFuelNotify.NotifyKey then
    MZFuelNotify.NotifyKey(key, notifyType, fallback)
  end
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

local function getVehiclePayload()
  local vehicle = MenuState.vehicle
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return nil
  end

  local netId = MZFuel.GetVehicleNetId(vehicle)
  netId = tonumber(netId) or 0

  return {
    plate = MZFuel.GetPlate(vehicle),
    net_id = netId,
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
    request_id = MenuState.requestId
  })
end

local function requestMenuRefuel(mode, value)
  if MenuState.open ~= true or MenuState.pending == true then
    return false
  end

  local vehiclePayload = getVehiclePayload()
  local station = stationPayload(MenuState.station)
  if not vehiclePayload or not station then
    notifyKey('invalidVehicle', 'error', 'Veiculo invalido.')
    closeMenu()
    return false
  end

  MenuState.pending = true
  MenuState.requestId = ('%s:%s'):format(GetGameTimer(), math.random(100000, 999999))
  TriggerServerEvent('mz_fuel:server:requestMenuRefuel', {
    mode = mode,
    value = value,
    request_id = MenuState.requestId,
    plate = vehiclePayload.plate,
    net_id = vehiclePayload.net_id,
    fuel_before = vehiclePayload.fuel,
    station = station
  })

  return true
end

function MZFuelMenu.Open(vehicle, station)
  if Config.Refuel and Config.Refuel.useMenu ~= true then
    return MZFuelRefuel.Start(vehicle, station)
  end

  if MenuState.open == true or MZFuelRefuel.IsRefueling() then
    return false
  end

  station = normalizeStation(station)
  local ok, reason = MZFuelRefuel.CanRefuel(vehicle)
  if not ok or not station then
    notifyRefuelError(reason)
    return false
  end

  MenuState.open = true
  MenuState.vehicle = vehicle
  MenuState.station = station
  MenuState.pending = false

  SetNuiFocus(true, true)
  SendNUIMessage({
    action = 'open',
    fuel = MZFuel.GetFuel(vehicle) or 0.0,
    pricePerLiter = tonumber(Config.Refuel and Config.Refuel.pricePerLiter) or 0,
    allowFillTank = Config.Refuel and Config.Refuel.allowFillTank == true,
    allowMoneyAmount = Config.Refuel and Config.Refuel.allowMoneyAmount == true,
    allowLiterAmount = Config.Refuel and Config.Refuel.allowLiterAmount == true
  })

  return true
end

function MZFuelMenu.IsBusy()
  return MenuState.open == true or MenuState.pending == true
end

RegisterNetEvent('mz_fuel:client:openRefuelMenu', function(vehicleOrNetId, station)
  local vehicle = MZFuel.ResolveEventVehicle(vehicleOrNetId)
  if vehicle == 0 then
    vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
  end

  MZFuelMenu.Open(vehicle, station)
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
  closeMenu()

  if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
    MZFuelRefuel.Start(vehicle, station, {
      targetLiters = tonumber(result.liters) or 0.0,
      menuSession = result.session
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
