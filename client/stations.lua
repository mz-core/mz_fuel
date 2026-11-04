MZFuelStations = MZFuelStations or {}

MZFuelStations.List = Config.Stations and Config.Stations.locations or {
  vec3(49.4187, 2778.793, 58.043),
  vec3(263.894, 2606.463, 44.983),
  vec3(1039.958, 2671.134, 39.550),
  vec3(1207.260, 2660.175, 37.899),
  vec3(2539.685, 2594.192, 37.944),
  vec3(2679.858, 3263.946, 55.240),
  vec3(2005.055, 3773.887, 32.403),
  vec3(1687.156, 4929.392, 42.078),
  vec3(1701.314, 6416.028, 32.763),
  vec3(179.857, 6602.839, 31.868),
  vec3(-94.4619, 6419.594, 31.489),
  vec3(-2554.996, 2334.40, 33.078),
  vec3(-1800.375, 803.661, 138.651),
  vec3(-1437.622, -276.747, 46.207),
  vec3(-2096.243, -320.286, 13.168),
  vec3(-724.619, -935.1631, 19.213),
  vec3(-526.019, -1211.003, 18.184),
  vec3(-70.2148, -1761.792, 29.534),
  vec3(265.648, -1261.309, 29.292),
  vec3(819.653, -1028.846, 26.403),
  vec3(1208.951, -1402.567, 35.224),
  vec3(1181.381, -330.847, 69.316),
  vec3(620.843, 269.100, 103.089),
  vec3(2581.321, 362.039, 108.468),
  vec3(176.631, -1562.025, 29.263),
  vec3(-319.292, -1471.715, 30.549),
  vec3(1784.324, 3330.55, 41.253)
}

function MZFuelStations.GetNearestStation()
  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)
  local nearest = nil
  local nearestDistance = nil

  for _, station in ipairs(MZFuelStations.List) do
    local distance = #(coords - station)
    if not nearestDistance or distance < nearestDistance then
      nearest = station
      nearestDistance = distance
    end
  end

  return nearest, nearestDistance
end

local function createStationBlips()
  local blips = Config.Stations and Config.Stations.blips or {}
  if blips.enabled ~= true then
    return
  end

  for _, station in ipairs(MZFuelStations.List) do
    local blip = AddBlipForCoord(station.x, station.y, station.z)
    SetBlipSprite(blip, tonumber(blips.sprite) or 361)
    SetBlipColour(blip, tonumber(blips.color) or 0)
    SetBlipScale(blip, tonumber(blips.scale) or 0.7)
    SetBlipAsShortRange(blip, blips.shortRange ~= false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(tostring(blips.name or 'Posto de combustivel'))
    EndTextCommandSetBlipName(blip)
  end
end

CreateThread(function()
  if not Config.Stations or Config.Stations.enabled ~= true then
    return
  end

  createStationBlips()
end)

local LegacyGeneration = 0

local function drawHelp(message)
  BeginTextCommandDisplayHelp('STRING')
  AddTextComponentSubstringPlayerName(message)
  EndTextCommandDisplayHelp(0, false, true, 1)
end

local function findNearestVehicle(maxDistance)
  local ped = PlayerPedId()
  local pedCoords = GetEntityCoords(ped)
  local nearestVehicle = 0
  local nearestDistance = tonumber(maxDistance) or 6.0

  for _, vehicle in ipairs(GetGamePool('CVehicle')) do
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and MZFuel.IsVehicleSupported(vehicle) then
      local distance = #(pedCoords - GetEntityCoords(vehicle))
      if distance <= nearestDistance then
        nearestVehicle = vehicle
        nearestDistance = distance
      end
    end
  end

  return nearestVehicle
end

function MZFuelStations.StopLegacyMarker()
  LegacyGeneration = LegacyGeneration + 1
end

function MZFuelStations.StartLegacyMarker()
  LegacyGeneration = LegacyGeneration + 1
  local generation = LegacyGeneration

  CreateThread(function()
    while LegacyGeneration == generation do
      local sleep = 500
      local ped = PlayerPedId()
      local markerCfg = (Config.Stations and Config.Stations.marker) or {}

      if not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) then
        local coords = GetEntityCoords(ped)
        local station, distance = MZFuelStations.GetNearestStation()

        if station and distance and distance <= (tonumber(markerCfg.drawDistance) or 18.0) then
          sleep = 0
          local color = markerCfg.color or {}

          DrawMarker(
            tonumber(markerCfg.type) or 1,
            station.x, station.y, station.z - 1.0,
            0.0, 0.0, 0.0,
            0.0, 0.0, 0.0,
            0.6, 0.6, 0.35,
            color.r or 57, color.g or 229, color.b or 140, color.a or 110,
            false, false, 2, false, nil, nil, false
          )

          if distance <= (tonumber(markerCfg.radius) or 4.0) then
            local vehicle = findNearestVehicle(tonumber(Config.Refuel and Config.Refuel.maxDistance) or 6.0)
            if vehicle ~= 0 then
              local canRefuel = MZFuelRefuel and MZFuelRefuel.CanRefuel and MZFuelRefuel.CanRefuel(vehicle)
              if canRefuel == true and not (MZFuelRefuel.IsRefueling and MZFuelRefuel.IsRefueling()) then
                local prompt = type(MZFuelText) == 'function' and MZFuelText('prompt.refuel', nil) or '[E] Abastecer'
                if prompt == 'prompt.refuel' then prompt = '[E] Abastecer' end
                drawHelp(prompt)
                if IsControlJustPressed(0, 38) then
                  if MZFuelMenu and MZFuelMenu.Open then
                    MZFuelMenu.Open(vehicle, station)
                  else
                    MZFuelRefuel.Start(vehicle, station)
                  end
                end
              end
            end
          end
        end
      end

      Wait(sleep)
    end
  end)
end

exports('GetNearestStation', function()
  return MZFuelStations.GetNearestStation()
end)
