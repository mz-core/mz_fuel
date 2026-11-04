MZFuelInteractions = MZFuelInteractions or {}

local ActiveMode = 'resolving'
local TargetApiStatus = 'starting'

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

local function targetModeAllowed()
  local cfg = interactionConfig()
  local mode = normalizeMode(cfg.mode)
  return mode == 'auto' or mode == 'target'
end

local function interactModeAllowed()
  local cfg = interactionConfig()
  local mode = normalizeMode(cfg.mode)
  return mode == 'auto' or mode == 'interact'
end

local function canUseTarget()
  if not targetModeAllowed() then
    TargetApiStatus = 'mode_disabled'
    return false
  end

  if GetResourceState('mz_target') ~= 'started' then
    TargetApiStatus = 'resource_not_started'
    return false
  end

  return true
end

local function canUseInteract()
  if not interactModeAllowed() then
    return false
  end

  return GetResourceState('mz_interact') == 'started'
end

function MZFuelInteractions.ResolveMode()
  local cfg = interactionConfig()
  local mode = normalizeMode(cfg.mode)

  if mode == 'none' then
    return 'none'
  end

  -- Sem abastecimento fisico nao existe bomba interativa. Preservamos o
  -- comportamento legado de posto no modo marker.
  if Config.Refuel and Config.Refuel.physical ~= true then
    return 'marker'
  end

  local prefer = tostring(cfg.prefer or 'target'):lower()

  if mode == 'marker' then
    return 'marker'
  end

  if mode == 'target' then
    if canUseTarget() then
      return 'target'
    end

    TargetApiStatus = TargetApiStatus == 'mode_disabled' and 'mode_disabled' or 'resource_not_started'
    return (cfg.fallbackMarker == true) and 'marker' or 'none'
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

local function stopFallback()
  if MZFuelPumps and MZFuelPumps.StopFallback then
    MZFuelPumps.StopFallback()
  end

  if MZFuelStations and MZFuelStations.StopLegacyMarker then
    MZFuelStations.StopLegacyMarker()
  end
end

local function removeTarget()
  if MZFuelPumps and MZFuelPumps.RemoveTarget then
    MZFuelPumps.RemoveTarget()
  end
end

function MZFuelInteractions.Refresh()
  if not Config.Stations or Config.Stations.enabled ~= true then
    stopFallback()
    removeTarget()
    ActiveMode = 'none'
    return ActiveMode
  end

  stopFallback()
  removeTarget()

  ActiveMode = MZFuelInteractions.ResolveMode()

  if ActiveMode == 'target' then
    local ok, reason = MZFuelPumps.RegisterTarget()
    if ok == true then
      TargetApiStatus = 'registered'
    else
      TargetApiStatus = tostring(reason or 'register_failed')
      if canUseInteract() then
        ActiveMode = 'interact'
      elseif interactionConfig().fallbackMarker == true then
        ActiveMode = 'marker'
      else
        ActiveMode = 'none'
      end
    end
  end

  if ActiveMode == 'interact' then
    if MZFuelPumps.StartFallback('interact') ~= true then
      ActiveMode = interactionConfig().fallbackMarker == true and 'marker' or 'none'
    end
  end

  if ActiveMode == 'marker' then
    if Config.Refuel and Config.Refuel.physical == true then
      if MZFuelStations and MZFuelStations.StopLegacyMarker then
        MZFuelStations.StopLegacyMarker()
      end
      MZFuelPumps.StartFallback('marker')
    elseif MZFuelStations and MZFuelStations.StartLegacyMarker then
      MZFuelStations.StartLegacyMarker()
    end
  else
    if MZFuelStations and MZFuelStations.StopLegacyMarker then
      MZFuelStations.StopLegacyMarker()
    end
  end

  if ActiveMode == 'none' then
    stopFallback()
  end

  if Config.Debug == true then
    print(('[mz_fuel][interactions] mode=%s target_api=%s'):format(tostring(ActiveMode), tostring(TargetApiStatus)))
  end

  return ActiveMode
end

CreateThread(function()
  if not Config.Stations or Config.Stations.enabled ~= true then
    ActiveMode = 'none'
    return
  end

  Wait(250)
  MZFuelInteractions.Refresh()
  Wait(1000)
  MZFuelInteractions.Refresh()
end)

AddEventHandler('onClientResourceStart', function(resourceName)
  if resourceName ~= 'mz_interact' and resourceName ~= 'mz_target' then
    return
  end

  CreateThread(function()
    Wait(750)
    MZFuelInteractions.Refresh()
  end)
end)

AddEventHandler('onClientResourceStop', function(resourceName)
  if resourceName ~= 'mz_interact' and resourceName ~= 'mz_target' then
    return
  end

  CreateThread(function()
    Wait(750)
    MZFuelInteractions.Refresh()
  end)
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then
    return
  end

  stopFallback()
  removeTarget()
end)
