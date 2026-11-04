MZFuelPumps = MZFuelPumps or {}

local PumpModelNames = {}
local PumpModelHashes = {}
local PumpModelValid = {}
local TargetRegistered = false
local FallbackMode = nil
local FallbackGeneration = 0
local DynamicPointId = nil
local DynamicPointPumpKey = nil
local DynamicPointLabel = nil

local function refuelConfig()
  return type(Config.Refuel) == 'table' and Config.Refuel or {}
end

local function interactionConfig()
  return type(Config.Interaction) == 'table' and Config.Interaction or {}
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

local function normalizeHash(value)
  value = tonumber(value)
  if value and value > 2147483647 then
    value = value - 4294967296
  end
  return value
end

local function hashString(value)
  if type(value) == 'number' then
    return normalizeHash(value)
  end

  if type(GetHashKey) == 'function' then
    local ok, hash = pcall(GetHashKey, value)
    if ok and hash then
      return normalizeHash(hash)
    end
  end

  if type(joaat) == 'function' then
    local ok, hash = pcall(joaat, value)
    if ok and hash then
      return normalizeHash(hash)
    end
  end

  return value
end

local function hashEntityModel(entity)
  return normalizeHash(GetEntityModel(entity))
end

local function nativeTrue(value)
  return value == true or value == 1
end

local function modelExists(name)
  local hash = hashString(name)

  local validOk, valid = pcall(function()
    return type(IsModelValid) == 'function' and nativeTrue(IsModelValid(hash))
  end)

  local cdOk, inCd = pcall(function()
    return type(IsModelInCdimage) == 'function' and nativeTrue(IsModelInCdimage(hash))
  end)

  if validOk == false and cdOk == false then
    return true, 'validation_unavailable'
  end

  if (validOk == true and valid == true) or (cdOk == true and inCd == true) then
    return true, 'valid'
  end

  return false, 'invalid'
end

local function buildPumpModels()
  PumpModelNames = {}
  PumpModelHashes = {}
  PumpModelValid = {}

  local configured = refuelConfig().pumpModels or {}
  for _, name in ipairs(configured) do
    if type(name) == 'string' and name ~= '' then
      local exists, reason = modelExists(name)
      PumpModelNames[#PumpModelNames + 1] = name
      PumpModelHashes[hashString(name)] = name
      PumpModelValid[name] = reason or (exists and 'valid' or 'invalid')
    end
  end

  if Config.Debug == true then
    local parts = {}
    for _, name in ipairs(PumpModelNames) do
      parts[#parts + 1] = ('%s=%s'):format(name, tostring(PumpModelValid[name]))
    end
    print(('[mz_fuel][pumps] modelos %s'):format(table.concat(parts, ' ')))
  end
end

local function stationList()
  return Config.Stations and Config.Stations.locations or {}
end

local function distanceSquared(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  local dz = a.z - b.z
  return (dx * dx) + (dy * dy) + (dz * dz)
end

function MZFuelPumps.GetStationForCoords(coords, radius)
  if not coords then
    return nil, nil, nil
  end

  radius = tonumber(radius) or tonumber(refuelConfig().pumpStationRadius) or 30.0
  local bestIndex, bestStation, bestDistance = nil, nil, nil
  local maxSquared = radius * radius

  for index, station in ipairs(stationList()) do
    local squared = distanceSquared(coords, station)
    if squared <= maxSquared and (not bestDistance or squared < bestDistance) then
      bestIndex = index
      bestStation = station
      bestDistance = squared
    end
  end

  return bestIndex, bestStation, bestDistance and math.sqrt(bestDistance) or nil
end

function MZFuelPumps.IsPumpEntity(entity)
  if not entity or entity == 0 or not DoesEntityExist(entity) then
    return false
  end

  return PumpModelHashes[hashEntityModel(entity)] ~= nil
end

function MZFuelPumps.GetPumpInfo(entity)
  if not MZFuelPumps.IsPumpEntity(entity) then
    return nil
  end

  local coords = GetEntityCoords(entity)
  local stationIndex, station = MZFuelPumps.GetStationForCoords(coords)
  local modelName = PumpModelHashes[hashEntityModel(entity)] or 'unknown'
  local pumpKey = ('%s:%.1f:%.1f:%.1f'):format(modelName, coords.x, coords.y, coords.z)

  return {
    entity = entity,
    coords = coords,
    model = modelName,
    pumpKey = pumpKey,
    stationIndex = stationIndex,
    station = station
  }
end

function MZFuelPumps.GetNearestPump(coords, maxDistance)
  coords = coords or GetEntityCoords(PlayerPedId())
  maxDistance = tonumber(maxDistance) or tonumber(refuelConfig().pumpDrawDistance) or 15.0

  local best, bestDistance = nil, nil
  local maxSquared = maxDistance * maxDistance

  for _, entity in ipairs(GetGamePool('CObject')) do
    if MZFuelPumps.IsPumpEntity(entity) then
      local pumpCoords = GetEntityCoords(entity)
      local squared = distanceSquared(coords, pumpCoords)
      if squared <= maxSquared and (not bestDistance or squared < bestDistance) then
        local info = MZFuelPumps.GetPumpInfo(entity)
        if info then
          best = info
          bestDistance = squared
        end
      end
    end
  end

  return best
end

local function targetLabels()
  return {
    take = text('pump.take', 'Pegar bico de combustivel'),
    takeIcon = text('pump.takeIcon', 'fuel'),
    returnNozzle = text('pump.return', 'Devolver bico a bomba'),
    returnIcon = text('pump.returnIcon', 'undo'),
    dock = text('tank.dock', 'Encaixar bico no tanque'),
    dockIcon = text('tank.dockIcon', 'fuel'),
    undock = text('tank.undock', 'Retirar bico do tanque'),
    undockIcon = text('tank.undockIcon', 'undo'),
    refuel = text('tank.refuel', 'Abastecer veiculo'),
    refuelIcon = text('tank.refuelIcon', 'credit-card')
  }
end

local function canUseTarget()
  return GetResourceState('mz_target') == 'started'
end

function MZFuelPumps.RegisterTarget()
  if refuelConfig().physical ~= true then
    TargetRegistered = false
    return false, 'physical_disabled'
  end

  if not canUseTarget() then
    TargetRegistered = false
    return false, 'target_unavailable'
  end

  if #PumpModelNames == 0 then
    TargetRegistered = false
    return false, 'no_pump_models'
  end

  if not MZFuelNozzle then
    TargetRegistered = false
    return false, 'nozzle_module_unavailable'
  end

  local labels = targetLabels()
  local distance = tonumber(refuelConfig().pumpTargetDistance) or 2.6
  local vehicleDistance = tonumber(refuelConfig().vehicleTargetDistance) or 3.0

  local ok = pcall(function()
    exports['mz_target']:AddTargetModel(PumpModelNames, {
      distance = distance,
      options = {
        {
          label = labels.take,
          icon = labels.takeIcon,
          distance = distance,
          canInteract = function(entity)
            return MZFuelNozzle.CanTake(entity) == true
          end,
          action = function(entity)
            MZFuelNozzle.Take(entity)
          end
        },
        {
          label = labels.returnNozzle,
          icon = labels.returnIcon,
          distance = distance,
          canInteract = function(entity)
            return MZFuelNozzle.CanReturn(entity) == true
          end,
          action = function(entity)
            MZFuelNozzle.Return(entity)
          end
        }
      }
    })
  end)

  if not ok then
    MZFuelPumps.RemoveTarget()
    TargetRegistered = false
    return false, 'register_failed'
  end

  ok = pcall(function()
    exports['mz_target']:AddGlobalVehicle({
      distance = vehicleDistance,
      options = {
        {
          label = labels.dock,
          icon = labels.dockIcon,
          distance = vehicleDistance,
          canInteract = function(vehicle)
            return MZFuelNozzle.CanDock(vehicle) == true
          end,
          action = function(vehicle)
            MZFuelNozzle.Dock(vehicle)
          end
        },
        {
          label = labels.undock,
          icon = labels.undockIcon,
          distance = vehicleDistance,
          canInteract = function(vehicle)
            return MZFuelNozzle.CanUndock(vehicle) == true
          end,
          action = function(vehicle)
            MZFuelNozzle.Undock('manual')
          end
        },
        {
          label = labels.refuel,
          icon = labels.refuelIcon,
          distance = vehicleDistance,
          canInteract = function(vehicle)
            return MZFuelNozzle.CanOpenMenu(vehicle) == true
          end,
          action = function(vehicle)
            MZFuelNozzle.OpenMenu(vehicle)
          end
        }
      }
    })
  end)

  if not ok then
    MZFuelPumps.RemoveTarget()
    TargetRegistered = false
    return false, 'register_failed'
  end

  TargetRegistered = true
  return true, 'registered'
end

function MZFuelPumps.RemoveTarget()
  if not canUseTarget() then
    TargetRegistered = false
    return false
  end

  local labels = targetLabels()
  local ok = pcall(function()
    exports['mz_target']:RemoveTargetModel(PumpModelNames, {
      labels.take,
      labels.returnNozzle
    })
    exports['mz_target']:RemoveGlobalVehicle({
      labels.dock,
      labels.undock,
      labels.refuel
    })
  end)

  TargetRegistered = false
  return ok == true
end

function MZFuelPumps.IsTargetRegistered()
  return TargetRegistered == true
end

local function pumpPromptLabel()
  if MZFuelNozzle and MZFuelNozzle.IsHolding() then
    return text('prompt.return', '[E] Devolver bico')
  end

  return text('prompt.take', '[E] Pegar bico')
end

local function removeDynamicPoint()
  if DynamicPointId and GetResourceState('mz_interact') == 'started' then
    pcall(function()
      exports['mz_interact']:RemovePoint(DynamicPointId)
    end)
  end

  DynamicPointId = nil
  DynamicPointPumpKey = nil
  DynamicPointLabel = nil
end

local function ensureDynamicPoint(pump)
  if not pump then
    removeDynamicPoint()
    return
  end

  local label = pumpPromptLabel()
  if DynamicPointPumpKey == pump.pumpKey and DynamicPointLabel == label then
    return
  end

  removeDynamicPoint()
  DynamicPointPumpKey = pump.pumpKey
  DynamicPointLabel = label
  DynamicPointId = ('mz_fuel_pump_%s'):format(pump.pumpKey:gsub('[^%w_%-]', '_'))

  pcall(function()
    exports['mz_interact']:AddPoint({
      id = DynamicPointId,
      coords = pump.coords,
      drawDistance = tonumber(refuelConfig().pumpDrawDistance) or 15.0,
      interactDistance = tonumber(refuelConfig().pumpTargetDistance) or 2.6,
      key = 38,
      marker = { enabled = false },
      blip = { enabled = false },
      text = {
        enabled = true,
        label = label
      },
      event = {
        type = 'client',
        name = 'mz_fuel:client:interactPump',
        args = { pump.coords.x, pump.coords.y, pump.coords.z }
      }
    })
  end)
end

local function drawSmallMarker(coords, color)
  DrawMarker(
    2,
    coords.x, coords.y, coords.z,
    0.0, 0.0, 0.0,
    0.0, 0.0, 0.0,
    0.18, 0.18, 0.18,
    color.r or 57, color.g or 229, color.b or 140, color.a or 150,
    false, false, 2, false, nil, nil, false
  )
end

local function drawHelp(message)
  BeginTextCommandDisplayHelp('STRING')
  AddTextComponentSubstringPlayerName(message)
  EndTextCommandDisplayHelp(0, false, true, 1)
end

local function runKeyFallback(generation, includePump)
  CreateThread(function()
    while (FallbackMode == 'marker' or FallbackMode == 'interact') and FallbackGeneration == generation do
      local sleep = 400
      local ped = PlayerPedId()

      if not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) then
        local coords = GetEntityCoords(ped)
        local handled = false

        if MZFuelNozzle and MZFuelNozzle.IsDocked() then
          local vehicle = MZFuelNozzle.GetVehicle()
          if vehicle ~= 0 and DoesEntityExist(vehicle) then
            local tank = MZFuelNozzle.GetTankWorldPosition(vehicle)
            if tank and #(coords - tank.coords) <= (tonumber(refuelConfig().vehicleTargetDistance) or 3.0) + 1.0 then
              handled = true
              sleep = 0
              drawSmallMarker(tank.coords, { r = 57, g = 229, b = 140, a = 170 })

              if MZFuelRefuel and MZFuelRefuel.IsRefueling() then
                drawHelp(text('menu.progress', 'Abastecendo'))
              else
                drawHelp(('%s  %s'):format(
                  text('prompt.openMenu', '[E] Abrir abastecimento'),
                  text('prompt.undock', '[H] Retirar bico')
                ))

                if IsControlJustPressed(0, 38) then
                  MZFuelNozzle.OpenMenu(vehicle)
                elseif IsControlJustPressed(0, tonumber(refuelConfig().undockKey) or 74) then
                  MZFuelNozzle.Undock('manual')
                end
              end
            end
          end
        elseif MZFuelNozzle and MZFuelNozzle.IsHolding() then
          local vehicle = MZFuelNozzle.GetNearbyVehicleForDock()
          local tank = vehicle ~= 0 and MZFuelNozzle.GetTankWorldPosition(vehicle) or nil

          if tank and #(coords - tank.coords) <= (tonumber(refuelConfig().tankAttachDistance) or 2.8) then
            handled = true
            sleep = 0
            drawSmallMarker(tank.coords, { r = 57, g = 229, b = 140, a = 170 })
            drawHelp(text('prompt.dock', '[E] Encaixar bico'))

            if IsControlJustPressed(0, 38) then
              MZFuelNozzle.Dock(vehicle)
            end
          end

          if not handled and includePump then
            local pump = MZFuelNozzle.GetPump()
            if pump and #(coords - pump.coords) <= (tonumber(refuelConfig().pumpTargetDistance) or 2.6) then
              handled = true
              sleep = 0
              drawSmallMarker(pump.coords + vec3(0.0, 0.0, 0.8), { r = 255, g = 210, b = 80, a = 170 })
              drawHelp(text('prompt.return', '[E] Devolver bico'))

              if IsControlJustPressed(0, 38) then
                MZFuelNozzle.Return(pump.entity)
              end
            end
          end
        else
          if includePump then
            local pump = MZFuelPumps.GetNearestPump(coords, tonumber(refuelConfig().pumpDrawDistance) or 15.0)
            if pump and #(coords - pump.coords) <= (tonumber(refuelConfig().pumpDrawDistance) or 15.0) then
              handled = true
              sleep = 0
              drawSmallMarker(pump.coords + vec3(0.0, 0.0, 0.8), { r = 57, g = 229, b = 140, a = 170 })

              if #(coords - pump.coords) <= (tonumber(refuelConfig().pumpTargetDistance) or 2.6) then
                drawHelp(text('prompt.take', '[E] Pegar bico'))
                if IsControlJustPressed(0, 38) then
                  MZFuelNozzle.Take(pump.entity)
                end
              end
            end
          end
        end

        if not handled then
          sleep = 500
        end
      end

      Wait(sleep)
    end
  end)
end

local function runInteractFallback(generation)
  CreateThread(function()
    while FallbackMode == 'interact' and FallbackGeneration == generation do
      local ped = PlayerPedId()
      local pump = nil

      if not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) and not (MZFuelNozzle and MZFuelNozzle.IsDocked()) then
        pump = MZFuelPumps.GetNearestPump(GetEntityCoords(ped), tonumber(refuelConfig().pumpDrawDistance) or 15.0)
      end

      ensureDynamicPoint(pump)
      Wait(500)
    end

    removeDynamicPoint()
  end)
end

function MZFuelPumps.StartFallback(mode)
  FallbackGeneration = FallbackGeneration + 1
  FallbackMode = mode
  removeDynamicPoint()

  if mode == 'interact' and GetResourceState('mz_interact') == 'started' then
    runInteractFallback(FallbackGeneration)
    runKeyFallback(FallbackGeneration, false)
    return true
  end

  if mode == 'marker' then
    runKeyFallback(FallbackGeneration, true)
    return true
  end

  return false
end

function MZFuelPumps.StopFallback()
  FallbackGeneration = FallbackGeneration + 1
  FallbackMode = nil
  removeDynamicPoint()
end

function MZFuelPumps.GetFallbackMode()
  return FallbackMode
end

function MZFuelPumps.ToggleAtPump(entity)
  if not MZFuelNozzle then
    return false
  end

  local info = MZFuelPumps.GetPumpInfo(entity)
  if not info then
    notifyKey('pumpNotFound', 'error', 'Nenhuma bomba valida por perto.')
    return false
  end

  if MZFuelNozzle.IsHolding() then
    return MZFuelNozzle.Return(entity)
  end

  return MZFuelNozzle.Take(entity)
end

function MZFuelPumps.GetDiagnostics()
  local playerCoords = GetEntityCoords(PlayerPedId())
  local nearest = MZFuelPumps.GetNearestPump(playerCoords, tonumber(refuelConfig().pumpDrawDistance) or 15.0)
  local modelStatus = {}

  for _, name in ipairs(PumpModelNames) do
    modelStatus[#modelStatus + 1] = ('%s:%s'):format(name, tostring(PumpModelValid[name] or 'unknown'))
  end

  return {
    target_registered = TargetRegistered == true,
    target_resource = GetResourceState('mz_target'),
    interact_resource = GetResourceState('mz_interact'),
    fallback_mode = FallbackMode,
    pump_models = table.concat(PumpModelNames, ','),
    pump_model_status = table.concat(modelStatus, ','),
    nearest_pump = nearest and nearest.pumpKey or 'none',
    nearest_station = nearest and (nearest.stationIndex or 'none') or 'none'
  }
end

RegisterNetEvent('mz_fuel:client:interactPump', function(x, y, z)
  local coords = vec3(tonumber(x) or 0.0, tonumber(y) or 0.0, tonumber(z) or 0.0)
  local pump = MZFuelPumps.GetNearestPump(coords, 4.0)
  if pump then
    MZFuelPumps.ToggleAtPump(pump.entity)
  end
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then
    return
  end

  MZFuelPumps.RemoveTarget()
  MZFuelPumps.StopFallback()
end)

buildPumpModels()

exports('GetNearestPump', function(coords, maxDistance)
  return MZFuelPumps.GetNearestPump(coords, maxDistance)
end)
