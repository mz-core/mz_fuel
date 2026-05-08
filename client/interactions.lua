MZFuelInteractions = MZFuelInteractions or {}

local RegisteredInteractPoints = {}
local ActiveMode = 'resolving'
local TargetApiStatus = 'not_checked'
local removeInteractPoints

local function interactionConfig()
  return Config.Interaction or {}
end

local function normalizeMode(value)
  value = tostring(value or 'auto'):lower()
  if value == 'target' or value == 'interact' or value == 'marker' or value == 'none' or value == 'auto' then
    return value
  end
  return 'auto'
end

local function findNearestVehicle(maxDistance)
  local ped = PlayerPedId()
  local pedCoords = GetEntityCoords(ped)
  local nearestVehicle = 0
  local nearestDistance = tonumber(maxDistance) or 6.0

  if Config.Refuel and Config.Refuel.allowInsideVehicle ~= false then
    local currentVehicle = GetVehiclePedIsIn(ped, false)
    if currentVehicle ~= 0 then
      return currentVehicle
    end
  end

  for _, vehicle in ipairs(GetGamePool('CVehicle')) do
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
      local distance = #(pedCoords - GetEntityCoords(vehicle))
      if distance <= nearestDistance then
        nearestVehicle = vehicle
        nearestDistance = distance
      end
    end
  end

  return nearestVehicle
end

local function startRefuelAtStation(station)
  if not station then
    return false
  end

  local vehicle = findNearestVehicle(tonumber(Config.Refuel and Config.Refuel.maxDistance) or 6.0)
  if vehicle == 0 or not MZFuelRefuel.CanRefuel(vehicle) then
    return false
  end

  if Config.Refuel and Config.Refuel.useMenu == true and MZFuelMenu and MZFuelMenu.Open then
    return MZFuelMenu.Open(vehicle, station)
  end

  return MZFuelRefuel.Start(vehicle, station)
end

local function canUseTarget()
  local cfg = interactionConfig()
  local mode = normalizeMode(cfg.mode)
  if mode ~= 'auto' and mode ~= 'target' then
    return false
  end

  if GetResourceState('mz_target') ~= 'started' then
    TargetApiStatus = 'resource_not_started'
    return false
  end

  -- mz_target 0.2.0 does not expose a public export/event for external point registration.
  TargetApiStatus = 'no_public_point_api'
  return false
end

local function canUseInteract()
  local cfg = interactionConfig()
  local mode = normalizeMode(cfg.mode)
  if mode ~= 'auto' and mode ~= 'interact' then
    return false
  end

  return GetResourceState('mz_interact') == 'started'
end

local function addInteractPoints()
  if not canUseInteract() then
    return false
  end

  removeInteractPoints()

  local marker = Config.Stations and Config.Stations.marker or {}
  local drawDistance = tonumber(marker.drawDistance) or 18.0
  local interactDistance = tonumber(marker.radius) or tonumber(Config.Refuel and Config.Refuel.maxDistance) or 4.0

  for index, station in ipairs(Config.Stations and Config.Stations.locations or {}) do
    local id = ('mz_fuel_station_%s'):format(index)
    local ok, success, result = pcall(function()
      return exports['mz_interact']:AddPoint({
        id = id,
        coords = station,
        drawDistance = drawDistance,
        interactDistance = interactDistance,
        key = 38,
        marker = {
          enabled = true,
          type = marker.type or 1,
          size = vec3(interactDistance, interactDistance, 0.35),
          color = marker.color or { r = 57, g = 229, b = 140, a = 110 }
        },
        text = {
          enabled = true,
          label = '[E] Abastecer'
        },
        event = {
          type = 'client',
          name = 'mz_fuel:client:interactRefuelStation',
          args = { index }
        }
      })
    end)

    if ok and success == true then
      RegisteredInteractPoints[#RegisteredInteractPoints + 1] = tostring(result or id)
    end
  end

  return #RegisteredInteractPoints > 0
end

function removeInteractPoints()
  if GetResourceState('mz_interact') ~= 'started' then
    RegisteredInteractPoints = {}
    return
  end

  for _, id in ipairs(RegisteredInteractPoints) do
    pcall(function()
      exports['mz_interact']:RemovePoint(id)
    end)
  end

  RegisteredInteractPoints = {}
end

function MZFuelInteractions.ResolveMode()
  local cfg = interactionConfig()
  local mode = normalizeMode(cfg.mode)
  local prefer = tostring(cfg.prefer or 'target'):lower()

  if mode == 'none' then
    return 'none'
  end

  if mode == 'marker' then
    return 'marker'
  end

  if mode == 'target' then
    return canUseTarget() and 'target' or ((cfg.fallbackMarker == true) and 'marker' or 'none')
  end

  if mode == 'interact' then
    return canUseInteract() and 'interact' or ((cfg.fallbackMarker == true) and 'marker' or 'none')
  end

  if prefer == 'interact' then
    if canUseInteract() then return 'interact' end
    if canUseTarget() then return 'target' end
  else
    if canUseTarget() then return 'target' end
    if canUseInteract() then return 'interact' end
  end

  return cfg.fallbackMarker == true and 'marker' or 'none'
end

function MZFuelInteractions.ShouldUseMarker()
  return ActiveMode == 'marker'
end

function MZFuelInteractions.GetActiveMode()
  return ActiveMode
end

function MZFuelInteractions.GetTargetApiStatus()
  return TargetApiStatus
end

function MZFuelInteractions.IsResolved()
  return ActiveMode ~= 'resolving'
end

function MZFuelInteractions.Refresh()
  if not Config.Stations or Config.Stations.enabled ~= true then
    removeInteractPoints()
    ActiveMode = 'none'
    return ActiveMode
  end

  removeInteractPoints()
  ActiveMode = MZFuelInteractions.ResolveMode()

  if ActiveMode == 'interact' then
    if addInteractPoints() ~= true then
      ActiveMode = interactionConfig().fallbackMarker == true and 'marker' or 'none'
    end
  end

  return ActiveMode
end

RegisterNetEvent('mz_fuel:client:interactRefuelStation', function(index)
  index = tonumber(index) or 0
  local station = Config.Stations and Config.Stations.locations and Config.Stations.locations[index] or nil
  startRefuelAtStation(station)
end)

CreateThread(function()
  if not Config.Stations or Config.Stations.enabled ~= true then
    ActiveMode = 'none'
    return
  end

  Wait(1000)
  MZFuelInteractions.Refresh()
end)

AddEventHandler('onClientResourceStart', function(resourceName)
  if resourceName ~= 'mz_interact' and resourceName ~= 'mz_target' then
    return
  end

  CreateThread(function()
    Wait(500)
    MZFuelInteractions.Refresh()
  end)
end)

AddEventHandler('onClientResourceStop', function(resourceName)
  if resourceName ~= 'mz_interact' and resourceName ~= 'mz_target' then
    return
  end

  if resourceName == 'mz_interact' then
    RegisteredInteractPoints = {}
  end

  CreateThread(function()
    Wait(500)
    MZFuelInteractions.Refresh()
  end)
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then
    return
  end

  removeInteractPoints()
end)
