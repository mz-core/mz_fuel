local Current = {
  vehicle = 0,
  plate = '',
  lastFuel = nil,
  lastSaveAt = 0,
  lastSavedFuel = nil,
  lastTickAt = 0
}

local function debugPrint(message)
  if Config.Debug == true then
    print(('[mz_fuel] %s'):format(tostring(message)))
  end
end

local function shouldSaveFuel(plate, fuel, force)
  if plate == '' then
    return false
  end

  if force == true then
    return true
  end

  local now = GetGameTimer()
  local interval = tonumber(Config.SaveIntervalMs) or 15000
  if now - (tonumber(Current.lastSaveAt) or 0) < interval then
    return false
  end

  local minimumDelta = tonumber(Config.MinimumSaveDelta) or 0.2
  if Current.lastSavedFuel ~= nil and math.abs((tonumber(fuel) or 0.0) - Current.lastSavedFuel) < minimumDelta then
    return false
  end

  return true
end

local function saveVehicleFuel(vehicle, force)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return false
  end

  local plate = MZFuel.GetPlate(vehicle)
  if plate == '' then
    return false
  end

  local fuel = MZFuel.GetFuel(vehicle)
  if fuel == nil or not shouldSaveFuel(plate, fuel, force == true) then
    return false
  end

  Current.lastSaveAt = GetGameTimer()
  Current.lastSavedFuel = fuel

  local netId = NetworkGetNetworkIdFromEntity(vehicle)
  TriggerServerEvent('mz_fuel:server:saveFuel', plate, fuel, {
    net_id = netId,
    engine = GetVehicleEngineHealth(vehicle),
    body = GetVehicleBodyHealth(vehicle),
    force = force == true
  })

  debugPrint(('save requested plate=%s fuel=%.2f force=%s'):format(plate, fuel, tostring(force == true)))
  return true
end

local function requestDebugSetFuel(vehicle, amount)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return false
  end

  local plate = MZFuel.GetPlate(vehicle)
  if plate == '' then
    return false
  end

  local netId = NetworkGetNetworkIdFromEntity(vehicle)
  TriggerServerEvent('mz_fuel:server:debugSetFuel', netId, plate, amount)
  return true
end

local function getConsumptionMultiplier(vehicle)
  local class = GetVehicleClass(vehicle)
  local classMultiplier = Config.ConsumptionByClass and tonumber(Config.ConsumptionByClass[class]) or 1.0
  return (classMultiplier or 1.0) * (tonumber(Config.ConsumptionMultiplier) or 1.0)
end

local function consumeFuel(vehicle, deltaSeconds)
  if not MZFuel.IsVehicleSupported(vehicle) then
    return
  end

  local ped = PlayerPedId()
  if GetPedInVehicleSeat(vehicle, -1) ~= ped then
    return
  end

  if not GetIsVehicleEngineRunning(vehicle) then
    return
  end

  local fuel = MZFuel.GetFuel(vehicle) or Config.DefaultFuel
  if fuel <= (tonumber(Config.MinFuel) or 0.0) then
    if Config.StopEngineWhenEmpty == true then
      SetVehicleEngineOn(vehicle, false, true, true)
      SetVehicleUndriveable(vehicle, true)
    end
    MZFuel.SetFuel(vehicle, Config.MinFuel or 0.0)
    return
  end

  local rpm = tonumber(GetVehicleCurrentRpm(vehicle)) or 0.0
  local speedKmh = (tonumber(GetEntitySpeed(vehicle)) or 0.0) * 3.6
  local speedFactor = math.min(speedKmh / 220.0, 1.25)
  local baseUse = 0.002 + (rpm * 0.012) + (speedFactor * 0.006)
  local usedFuel = baseUse * getConsumptionMultiplier(vehicle) * math.max(deltaSeconds, 0.1)
  local nextFuel = MZFuel.ClampFuel(fuel - usedFuel)

  MZFuel.SetFuel(vehicle, nextFuel, { control = false })
  Current.lastFuel = nextFuel
end

local function applyInitialVehicleFuel(vehicle)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return
  end

  local fuel = MZFuel.GetFuel(vehicle)
  if fuel == nil then
    fuel = Config.DefaultFuel
  end

  MZFuel.SetFuel(vehicle, fuel, { control = false })
end

local function updateCurrentVehicle()
  local ped = PlayerPedId()
  local vehicle = GetVehiclePedIsIn(ped, false)

  if vehicle ~= Current.vehicle then
    if Current.vehicle ~= 0 and Config.SaveOnExitVehicle == true then
      saveVehicleFuel(Current.vehicle, true)
    end

    Current.vehicle = vehicle
    Current.plate = vehicle ~= 0 and MZFuel.GetPlate(vehicle) or ''
    Current.lastFuel = nil
    Current.lastTickAt = GetGameTimer()

    if vehicle ~= 0 then
      applyInitialVehicleFuel(vehicle)
    end
  end
end

CreateThread(function()
  if Config.DisableNativeFuelConsumption == true and type(SetFuelConsumptionState) == 'function' then
    SetFuelConsumptionState(false)
  end

  while true do
    local waitMs = tonumber(Config.UpdateIntervalMs) or 1000
    updateCurrentVehicle()

    local vehicle = Current.vehicle
    if vehicle ~= 0 and DoesEntityExist(vehicle) then
      local now = GetGameTimer()
      local deltaSeconds = (now - (tonumber(Current.lastTickAt) or now)) / 1000.0
      Current.lastTickAt = now

      consumeFuel(vehicle, deltaSeconds)

      if Config.SaveWhenDriver == true and GetPedInVehicleSeat(vehicle, -1) == PlayerPedId() then
        saveVehicleFuel(vehicle, false)
      end
    end

    Wait(math.max(250, waitMs))
  end
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then
    return
  end

  if Current.vehicle ~= 0 then
    saveVehicleFuel(Current.vehicle, true)
  end
end)

RegisterCommand('mfuel_get', function()
  if Config.DebugCommands ~= true then
    return
  end

  local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
  if vehicle == 0 then
    print('[mz_fuel] voce nao esta em um veiculo')
    return
  end

  print(('[mz_fuel] plate=%s fuel=%.2f'):format(MZFuel.GetPlate(vehicle), MZFuel.GetFuel(vehicle) or 0.0))
end, false)

RegisterCommand('mfuel_set', function(_, args)
  if Config.DebugCommands ~= true then
    return
  end

  local amount = tonumber(args and args[1])
  if amount == nil then
    print('[mz_fuel] uso: /mfuel_set [valor]')
    return
  end

  local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
  if vehicle == 0 then
    print('[mz_fuel] voce nao esta em um veiculo')
    return
  end

  requestDebugSetFuel(vehicle, amount)
end, false)

RegisterCommand('mfuel_refill', function()
  if Config.DebugCommands ~= true then
    return
  end

  local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
  if vehicle == 0 then
    return
  end

  requestDebugSetFuel(vehicle, Config.MaxFuel or 100.0)
end, false)

local function printDiagnosticsTable(title, data)
  print(('[mz_fuel][diag] %s'):format(tostring(title)))
  for key, value in pairs(data or {}) do
    print(('  %s=%s'):format(tostring(key), tostring(value)))
  end
end

RegisterCommand('mfuel_diag', function()
  if Config.Debug ~= true then
    return
  end

  local ped = PlayerPedId()
  local vehicle = GetVehiclePedIsIn(ped, false)
  if vehicle == 0 then
    vehicle = MZFuelNozzle and MZFuelNozzle.GetVehicle and MZFuelNozzle.GetVehicle() or 0
  end

  printDiagnosticsTable('interactions', {
    mode = MZFuelInteractions and MZFuelInteractions.GetActiveMode and MZFuelInteractions.GetActiveMode() or 'unknown',
    target_api = MZFuelInteractions and MZFuelInteractions.GetTargetApiStatus and MZFuelInteractions.GetTargetApiStatus() or 'unknown',
    locale = MZFuelLocale and MZFuelLocale.GetCode and MZFuelLocale.GetCode() or 'unknown'
  })

  if MZFuelPumps and MZFuelPumps.GetDiagnostics then
    printDiagnosticsTable('pumps', MZFuelPumps.GetDiagnostics())
  end

  if MZFuelNozzle and MZFuelNozzle.GetDiagnostics then
    printDiagnosticsTable('nozzle', MZFuelNozzle.GetDiagnostics())
  end

  if MZFuelRefuel and MZFuelRefuel.GetDiagnostics then
    printDiagnosticsTable('refuel', MZFuelRefuel.GetDiagnostics())
  end

  if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
    local tank = MZFuelNozzle and MZFuelNozzle.GetTankWorldPosition and MZFuelNozzle.GetTankWorldPosition(vehicle) or nil
    printDiagnosticsTable('vehicle', {
      entity = vehicle,
      plate = MZFuel.GetPlate(vehicle),
      fuel = MZFuel.GetFuel(vehicle) or 0.0,
      engine_running = GetIsVehicleEngineRunning(vehicle) == true or GetIsVehicleEngineRunning(vehicle) == 1,
      class = GetVehicleClass(vehicle),
      tank_source = tank and tank.source or 'none',
      tank_bone = tank and (tank.boneName or tostring(tank.bone)) or 'none',
      tank_confidence = tank and tank.confident == true or false,
      tank_x = tank and tank.coords.x or 0.0,
      tank_y = tank and tank.coords.y or 0.0,
      tank_z = tank and tank.coords.z or 0.0
    })
  end
end, false)

RegisterCommand('mfuel_calibrate', function(_, args)
  if Config.Debug ~= true then
    return
  end

  local mode = tostring(args and args[1] or ''):lower()
  if mode == 'marker' then
    Config.DebugTankMarker = not Config.DebugTankMarker
    print(('[mz_fuel][calibrate] tank_marker=%s'):format(tostring(Config.DebugTankMarker)))
    return
  end

  local function number(index)
    return tonumber(args and args[index])
  end

  if mode == 'hose' then
    local hx, hy, hz = number(2), number(3), number(4)
    if not hx or not hy or not hz then
      local current = Config.Refuel.hoseNozzleOffset or vec3(0.0, -0.033, -0.195)
      print(('[mz_fuel][calibrate] hose_offset atual=%.3f,%.3f,%.3f'):format(current.x, current.y, current.z))
      print('[mz_fuel] uso: /mfuel_calibrate hose x y z')
      return
    end

    local ok, rope = MZFuelNozzle.SetHoseNozzleOffset(vec3(hx, hy, hz))
    print(('[mz_fuel][calibrate] hose_offset=%.3f,%.3f,%.3f rope=%s ok=%s'):format(hx, hy, hz, tostring(rope), tostring(ok)))
    return
  end

  local x, y, z = number(2), number(3), number(4)
  local rx, ry, rz = number(5), number(6), number(7)

  if mode == 'hand' and x and y and z and rx and ry and rz then
    Config.Refuel.nozzleHandOffset = vec3(x, y, z)
    Config.Refuel.nozzleHandRotation = vec3(rx, ry, rz)
    print(('[mz_fuel][calibrate] hand_offset=%.2f,%.2f,%.2f hand_rotation=%.2f,%.2f,%.2f'):format(x, y, z, rx, ry, rz))
  elseif mode == 'tank' and x and y and z and rx and ry and rz then
    Config.Refuel.nozzleVehicleOffset = vec3(x, y, z)
    Config.Refuel.nozzleVehicleRotation = vec3(rx, ry, rz)
    print(('[mz_fuel][calibrate] vehicle_offset=%.2f,%.2f,%.2f vehicle_rotation=%.2f,%.2f,%.2f'):format(x, y, z, rx, ry, rz))
  elseif mode == 'model' and x and y and z and rx and ry and rz then
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 and MZFuelNozzle then
      vehicle = MZFuelNozzle.GetVehicle() or 0
      if vehicle == 0 and MZFuelNozzle.GetNearbyVehicleForDock then
        vehicle = MZFuelNozzle.GetNearbyVehicleForDock() or 0
      end
    end

    if vehicle == 0 or not DoesEntityExist(vehicle) then
      print('[mz_fuel] /mfuel_calibrate model: nenhum veiculo proximo')
      return
    end

    local ok, modelHash, bone = MZFuelNozzle.SetModelTankOffset(vehicle, vec3(x, y, z), vec3(rx, ry, rz))
    local display = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    print(('[mz_fuel][calibrate] model_offset display=%s hash=%s bone=%s offset=%.2f,%.2f,%.2f rotation=%.2f,%.2f,%.2f ok=%s'):format(
      tostring(display), tostring(modelHash), tostring(bone), x, y, z, rx, ry, rz, tostring(ok)
    ))
  else
    print('[mz_fuel] uso: /mfuel_calibrate marker')
    print('[mz_fuel] uso: /mfuel_calibrate hand x y z rx ry rz')
    print('[mz_fuel] uso: /mfuel_calibrate tank x y z rx ry rz')
    print('[mz_fuel] uso: /mfuel_calibrate model x y z rx ry rz')
    print('[mz_fuel] uso: /mfuel_calibrate hose x y z')
    return
  end

  if MZFuelNozzle and MZFuelNozzle.Reattach then
    local ok = MZFuelNozzle.Reattach()
    print(('[mz_fuel][calibrate] reattach=%s'):format(tostring(ok)))
  end
end, false)
