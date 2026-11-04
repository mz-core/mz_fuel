MZFuelNozzle = MZFuelNozzle or {}

local State = {
  pending = false,
  phase = 'none', -- 'none' | 'held' | 'docked'
  pump = nil,
  claimToken = nil,
  vehicle = 0,
  tank = nil,
  nozzle = 0,
  nozzleModel = nil,
  nozzleModelDiagnostics = nil,
  handBone = 0,
  animation = 'none',
  hoseStart = nil,
  hoseEnd = nil,
  rope = 0,
  animGeneration = 0,
  lastCancelReason = nil
}

local PendingClaims = {}
local TankOffsetHashes = {}
local TankBoneOffsetHashes = {}
local RuntimeTankOverrides = {}
local RopeTexturesReady = false
local EXPECTED_NOZZLE_HASH = -1937636863
local EXPECTED_NOZZLE_HASH_U = 2357330433

local function refuelConfig()
  return type(Config.Refuel) == 'table' and Config.Refuel or {}
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

local function hashEntityModel(entity)
  return normalizeHash(GetEntityModel(entity))
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

local function nativeTrue(value)
  return value == true or value == 1
end

local function probeModel(name)
  local hash = hashString(name)
  local validRaw = nil
  local inCdRaw = nil

  if type(IsModelValid) == 'function' then
    local ok, result = pcall(IsModelValid, hash)
    if ok then
      validRaw = result
    end
  end

  if type(IsModelInCdimage) == 'function' then
    local ok, result = pcall(IsModelInCdimage, hash)
    if ok then
      inCdRaw = result
    end
  end

  local joaatHash = nil
  if type(joaat) == 'function' then
    local ok, result = pcall(joaat, name)
    if ok then
      joaatHash = normalizeHash(result)
    end
  end

  return {
    name = name,
    hash = hash,
    joaat_hash = joaatHash,
    valid_raw = validRaw,
    in_cdimage_raw = inCdRaw,
    valid = nativeTrue(validRaw),
    in_cdimage = nativeTrue(inCdRaw)
  }
end

local function logModelProbe(probe, requested, loaded, created, exists, reason)
  local hash = tonumber(probe and probe.hash or 0) or 0
  local expectedMatch = hash == EXPECTED_NOZZLE_HASH or hash == EXPECTED_NOZZLE_HASH_U
  print(('[mz_fuel][nozzle_model] name=%s hash=%s joaat=%s expected_match=%s valid=%s in_cdimage=%s requested=%s loaded=%s created=%s exists=%s reason=%s'):format(
    tostring(probe and probe.name or 'none'),
    tostring(probe and probe.hash or 'none'),
    tostring(probe and probe.joaat_hash or 'none'),
    tostring(expectedMatch),
    tostring(probe and probe.valid_raw or 'none'),
    tostring(probe and probe.in_cdimage_raw or 'none'),
    tostring(requested == true),
    tostring(loaded == true),
    tostring(created == true),
    tostring(exists == true),
    tostring(reason or 'none')
  ))
end

local function requestModel(hash, timeoutMs)
  if not hash or hash == 0 then
    return false
  end

  if type(RequestModel) ~= 'function' then
    return false
  end

  if nativeTrue(HasModelLoaded(hash)) then
    return true
  end

  local requestOk = pcall(RequestModel, hash)
  if not requestOk then
    return false
  end

  local expiresAt = GetGameTimer() + (tonumber(timeoutMs) or 4000)

  while not nativeTrue(HasModelLoaded(hash)) and GetGameTimer() < expiresAt do
    Wait(0)
  end

  return nativeTrue(HasModelLoaded(hash))
end

local function isVector3(value)
  return type(value) == 'vector3' or type(value) == 'table'
end

local function buildTankOffsetHashes()
  TankOffsetHashes = {}
  TankBoneOffsetHashes = {}

  for model, offset in pairs(refuelConfig().tankOffsets or {}) do
    if type(model) == 'string' and isVector3(offset) then
      TankOffsetHashes[hashString(model)] = {
        name = model,
        offset = offset
      }
    end
  end

  for model, offset in pairs(refuelConfig().tankBoneOffsets or {}) do
    if type(model) == 'string' and isVector3(offset) then
      TankBoneOffsetHashes[hashString(model)] = {
        name = model,
        offset = offset
      }
    end
  end
end

local function getPedHandBone(ped)
  local boneId = tonumber(refuelConfig().nozzleBoneId) or 18905
  if boneId > 0 and type(GetPedBoneIndex) == 'function' then
    local index = GetPedBoneIndex(ped, boneId)
    if index and index > 0 then
      return index, 'id:' .. tostring(boneId)
    end
  end

  if type(GetEntityBoneIndexByName) == 'function' then
    local index = GetEntityBoneIndexByName(ped, tostring(refuelConfig().nozzleBone or 'SKEL_L_Hand'))
    if index and index > 0 then
      return index, 'name:' .. tostring(refuelConfig().nozzleBone or 'SKEL_L_Hand')
    end
  end

  return 0, 'none'
end

local function attachNozzleToHand(nozzle, ped)
  local bone, source = getPedHandBone(ped)
  if bone == 0 then
    debugPrint('nozzle_hand_bone_missing', {
      bone_id = tostring(refuelConfig().nozzleBoneId or 18905),
      bone_name = tostring(refuelConfig().nozzleBone or 'SKEL_L_Hand')
    })
    return false
  end

  local offset = refuelConfig().nozzleHandOffset or vec3(0.0, 0.0, 0.0)
  local rotation = refuelConfig().nozzleHandRotation or vec3(0.0, 0.0, 0.0)
  State.handBone = bone

  AttachEntityToEntity(
    nozzle,
    ped,
    bone,
    offset.x, offset.y, offset.z,
    rotation.x, rotation.y, rotation.z,
    false, true, false, true, 0, true
  )

  debugPrint('nozzle_hand_attach', {
    bone = bone,
    bone_source = source,
    offset = ('%.2f,%.2f,%.2f'):format(offset.x, offset.y, offset.z),
    rotation = ('%.2f,%.2f,%.2f'):format(rotation.x, rotation.y, rotation.z)
  })

  return true
end

local function attachNozzleToVehicle(nozzle, vehicle, tank)
  local rotation = (tank and tank.rotation) or refuelConfig().nozzleVehicleRotation or vec3(0.0, 0.0, 0.0)
  local extraOffset = refuelConfig().nozzleVehicleOffset or vec3(0.0, 0.0, 0.0)

  if tank and tonumber(tank.bone) and tonumber(tank.bone) > 0 then
    local boneOffset = tank.offset or vec3(0.0, 0.0, 0.0)
    AttachEntityToEntity(
      nozzle,
      vehicle,
      tank.bone,
      boneOffset.x + extraOffset.x, boneOffset.y + extraOffset.y, boneOffset.z + extraOffset.z,
      rotation.x, rotation.y, rotation.z,
      true, true, false, false, 2, true
    )
    return true
  end

  if not tank or not tank.coords then
    return false
  end

  local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, tank.coords.x, tank.coords.y, tank.coords.z)
  AttachEntityToEntity(
    nozzle,
    vehicle,
    0,
    offset.x + extraOffset.x, offset.y + extraOffset.y, offset.z + extraOffset.z,
    rotation.x, rotation.y, rotation.z,
    true, true, false, false, 2, true
  )

  return true
end

local function findTankBone(vehicle)
  for _, boneName in ipairs(refuelConfig().tankBones or {}) do
    if type(GetEntityBoneIndexByName) == 'function' then
      local boneIndex = GetEntityBoneIndexByName(vehicle, tostring(boneName))
      if boneIndex and boneIndex > 0 then
        return boneIndex, tostring(boneName)
      end
    end
  end

  return nil, nil
end

function MZFuelNozzle.GetTankWorldPosition(vehicle)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return nil
  end

  local cfg = refuelConfig()
  local model = hashEntityModel(vehicle)
  local boneIndex, boneName = findTankBone(vehicle)

  -- 0) Override de calibracao em runtime, por hash de modelo.
  local runtime = RuntimeTankOverrides[model]
  if runtime then
    if runtime.bone_relative and boneIndex then
      local boneCoords = GetWorldPositionOfEntityBone(vehicle, boneIndex)
      local forwardVector, rightVector, upVector = GetEntityMatrix(vehicle)
      local coords = boneCoords
        + (forwardVector * runtime.offset.y)
        + (rightVector * runtime.offset.x)
        + (upVector * runtime.offset.z)

      return {
        coords = coords,
        bone = boneIndex,
        boneName = boneName,
        offset = runtime.offset,
        rotation = runtime.rotation,
        source = 'runtime_model_bone',
        confident = true
      }
    elseif not runtime.bone_relative then
      local coords = GetOffsetFromEntityInWorldCoords(vehicle, runtime.offset.x, runtime.offset.y, runtime.offset.z)
      return {
        coords = coords,
        bone = 0,
        boneName = nil,
        offset = runtime.offset,
        rotation = runtime.rotation,
        source = 'runtime_model_entity',
        confident = true
      }
    end
  end

  -- 1) Offset por modelo relativo ao bone de entrada (referencia lc_fuel).
  local boneOffset = TankBoneOffsetHashes[model]
  if boneOffset and boneIndex then
    local boneCoords = GetWorldPositionOfEntityBone(vehicle, boneIndex)
    local forwardVector, rightVector, upVector = GetEntityMatrix(vehicle)
    local coords = boneCoords
      + (forwardVector * boneOffset.offset.y)
      + (rightVector * boneOffset.offset.x)
      + (upVector * boneOffset.offset.z)

    return {
      coords = coords,
      bone = boneIndex,
      boneName = boneName,
      offset = boneOffset.offset,
      source = 'model_bone_offset',
      model = boneOffset.name,
      confident = true
    }
  end

  -- 2) Excecao explicita por modelo em coordenadas locais da entidade.
  local modelOffset = TankOffsetHashes[model]
  if modelOffset then
    local coords = GetOffsetFromEntityInWorldCoords(vehicle, modelOffset.offset.x, modelOffset.offset.y, modelOffset.offset.z)
    return {
      coords = coords,
      bone = 0,
      boneName = nil,
      offset = modelOffset.offset,
      source = 'model_offset',
      model = modelOffset.name,
      confident = true
    }
  end

  -- 3) Bones reais de abertura do tanque. `petroltank` nao entra: e o tanque
  -- interno, nao necessariamente a tampa de abastecimento.
  if boneIndex then
    return {
      coords = GetWorldPositionOfEntityBone(vehicle, boneIndex),
      bone = boneIndex,
      boneName = boneName,
      source = 'bone',
      confident = true
    }
  end

  -- 4) Fallback por classe, em coordenadas locais da entidade.
  local class = GetVehicleClass(vehicle)
  local classOffset = (cfg.tankClassOffsets or {})[class]
  if isVector3(classOffset) then
    local coords = GetOffsetFromEntityInWorldCoords(vehicle, classOffset.x, classOffset.y, classOffset.z)
    return {
      coords = coords,
      bone = 0,
      boneName = nil,
      offset = classOffset,
      source = 'class_offset',
      class = class,
      confident = false
    }
  end

  -- 5) Ultimo fallback: dimensoes do modelo.
  if type(GetModelDimensions) == 'function' then
    local min, max = GetModelDimensions(model)
    if min and max then
      local side = tostring(cfg.tankFallbackSide or 'left'):lower() == 'right' and 1 or -1
      local x = side < 0 and (min.x + 0.15) or (max.x - 0.15)
      local y = min.y + 0.25
      local z = min.z + ((max.z - min.z) * 0.55)
      local offset = vec3(x, y, z)
      local coords = GetOffsetFromEntityInWorldCoords(vehicle, x, y, z)

      return {
        coords = coords,
        bone = 0,
        boneName = nil,
        offset = offset,
        source = 'dimensions',
        class = class,
        confident = false
      }
    end
  end

  return nil
end

local function ensureRopeTextures()
  if RopeTexturesReady
    and (type(RopeAreTexturesLoaded) ~= 'function' or nativeTrue(RopeAreTexturesLoaded())) then
    return true
  end

  if type(RopeAreTexturesLoaded) == 'function' and nativeTrue(RopeAreTexturesLoaded()) then
    RopeTexturesReady = true
    return true
  end

  if type(RopeLoadTextures) ~= 'function' then
    return false
  end

  RopeLoadTextures()
  local expiresAt = GetGameTimer() + 2000
  while type(RopeAreTexturesLoaded) == 'function' and not nativeTrue(RopeAreTexturesLoaded()) and GetGameTimer() < expiresAt do
    Wait(0)
  end

  RopeTexturesReady = type(RopeAreTexturesLoaded) ~= 'function' or nativeTrue(RopeAreTexturesLoaded())
  return RopeTexturesReady
end

local function createHose(pump, nozzle)
  local cfg = refuelConfig()
  if cfg.enableHose ~= true or not pump or not nozzle or nozzle == 0 then
    return 0
  end

  if type(AddRope) ~= 'function' then
    return 0
  end

  if not ensureRopeTextures() then
    debugPrint('hose_skip', { reason = 'textures_unavailable' })
    return 0
  end

  local pumpEntity = pump.entity
  local pumpCoords = GetEntityCoords(pumpEntity)
  local offset = (cfg.hosePumpOffsets or {})[pump.model] or cfg.hoseStartOffset or vec3(0.0, 0.0, 2.3)

  local forwardVector, rightVector, upVector = GetEntityMatrix(pumpEntity)
  local hoseStart = pumpCoords + (forwardVector * offset.y) + (rightVector * offset.x) + (upVector * offset.z)

  local nozzleOffset = cfg.hoseNozzleOffset or vec3(0.0, -0.033, -0.195)
  local maxLength = math.max(1.0, tonumber(cfg.hoseRopeMaxLength) or 4.0)
  local initialLength = math.max(1.0, tonumber(cfg.hoseRopeInitialLength) or 10.0)
  local attachLength = math.max(1.0, tonumber(cfg.hoseAttachLength) or 30.0)

  local ok, rope = pcall(function()
    return AddRope(
      hoseStart.x, hoseStart.y, hoseStart.z,
      0.0, 0.0, 0.0,
      maxLength,
      tonumber(cfg.hoseType) or 1,
      initialLength,
      0.0,
      1.0,
      false,
      false,
      false,
      1.0,
      false,
      0
    )
  end)

  if not ok or not rope or rope == 0 or (type(DoesRopeExist) == 'function' and not DoesRopeExist(rope)) then
    debugPrint('hose_skip', { reason = 'add_rope_failed' })
    return 0
  end

  pcall(function()
    ActivatePhysics(rope)
    -- Igual ao lc_fuel: espera a matriz do prop/anexo estabilizar antes de
    -- converter o offset local do bico para coordenadas mundiais.
    Wait(100)
  end)

  local hoseEnd = GetOffsetFromEntityInWorldCoords(nozzle, nozzleOffset.x, nozzleOffset.y, nozzleOffset.z)

  pcall(function()
    AttachEntitiesToRope(
      rope,
      pumpEntity,
      nozzle,
      hoseStart.x, hoseStart.y, hoseStart.z,
      hoseEnd.x, hoseEnd.y, hoseEnd.z,
      attachLength,
      false,
      false,
      nil,
      nil
    )
  end)

  State.hoseStart = hoseStart
  State.hoseEnd = hoseEnd

  debugPrint('hose_created', {
    pump = pump.pumpKey,
    model = pump.model,
    start = ('%.2f,%.2f,%.2f'):format(hoseStart.x, hoseStart.y, hoseStart.z),
    finish = ('%.2f,%.2f,%.2f'):format(hoseEnd.x, hoseEnd.y, hoseEnd.z),
    max_length = maxLength,
    initial_length = initialLength,
    attach_length = attachLength
  })

  return rope
end

local function deleteHose(rope)
  if not rope or rope == 0 then
    return
  end

  if type(DoesRopeExist) == 'function' and not DoesRopeExist(rope) then
    return
  end

  pcall(function()
    DeleteRope(rope)
    if type(RopeUnloadTextures) == 'function' then
      RopeUnloadTextures()
      RopeTexturesReady = false
    end
  end)

  State.hoseStart = nil
  State.hoseEnd = nil
end

local function deleteNozzle()
  if State.nozzle ~= 0 and DoesEntityExist(State.nozzle) then
    pcall(function()
      DetachEntity(State.nozzle, true, true)
      SetEntityAsMissionEntity(State.nozzle, false, true)
      DeleteEntity(State.nozzle)
    end)
  end

  State.nozzle = 0
end

local function stopAnimation()
  State.animGeneration = State.animGeneration + 1
  State.animation = 'none'
  local ped = PlayerPedId()
  if ped and ped ~= 0 and not IsEntityDead(ped) then
    ClearPedTasks(ped)
  end
end

local function loadAnimDict(dict, timeoutMs)
  dict = tostring(dict or '')
  if dict == '' then
    return false
  end

  if type(HasAnimDictLoaded) == 'function' and nativeTrue(HasAnimDictLoaded(dict)) then
    return true
  end

  if type(RequestAnimDict) ~= 'function' then
    return false
  end

  RequestAnimDict(dict)
  local expiresAt = GetGameTimer() + (tonumber(timeoutMs) or 2000)
  while type(HasAnimDictLoaded) == 'function'
    and not nativeTrue(HasAnimDictLoaded(dict))
    and GetGameTimer() < expiresAt do
    Wait(0)
  end

  return type(HasAnimDictLoaded) ~= 'function' or nativeTrue(HasAnimDictLoaded(dict))
end

local function playOneShotAnimation(kind)
  local cfg = refuelConfig()
  local animations = type(cfg.nozzleAnim) == 'table' and cfg.nozzleAnim or {}
  local anim = animations[kind]
  if type(anim) ~= 'table' or anim.enabled == false then
    return false
  end

  local dict = tostring(anim.dict or '')
  local clip = tostring(anim.clip or '')
  if dict == '' or clip == '' then
    return false
  end

  local duration = math.max(100, tonumber(anim.duration) or 300)
  if not loadAnimDict(dict, 2000) then
    debugPrint('anim_skip', { kind = kind, dict = dict })
    return false
  end

  local ped = PlayerPedId()
  if not ped or ped == 0 or IsEntityDead(ped) then
    return false
  end

  State.animation = tostring(kind)
  TaskPlayAnim(
    ped,
    dict,
    clip,
    8.0,
    -8.0,
    duration,
    tonumber(anim.flag) or 49,
    0.0,
    false,
    false,
    false
  )

  Wait(duration)

  if State.animation == tostring(kind) then
    State.animation = 'none'
    if PlayerPedId() == ped and not IsEntityDead(ped) then
      ClearPedTasks(ped)
    end
  end

  return true
end

local function releasePump()
  if State.pump and State.claimToken then
    TriggerServerEvent('mz_fuel:server:releasePump', {
      pump_key = State.pump.pumpKey,
      token = State.claimToken
    })
  end
end

local function resetState()
  State.pending = false
  State.phase = 'none'
  State.pump = nil
  State.claimToken = nil
  State.vehicle = 0
  State.tank = nil
  State.rope = 0
  State.nozzleModel = nil
  State.handBone = 0
  State.animation = 'none'
  State.hoseStart = nil
  State.hoseEnd = nil
end

local function cancelReasonKey(reason)
  reason = tostring(reason or '')

  if reason == 'player_dead' then
    return 'playerDead', 'Abastecimento cancelado: jogador morreu.'
  elseif reason == 'pump_distance' or reason == 'pump_missing' then
    return 'pumpDistance', 'Abastecimento cancelado: voce se afastou da bomba.'
  elseif reason == 'vehicle_distance' then
    return 'vehicleDistance', 'Abastecimento cancelado: o veiculo se afastou.'
  elseif reason == 'vehicle_missing' then
    return 'invalidVehicle', 'Veiculo invalido.'
  elseif reason == 'inside_vehicle' then
    return 'insideVehicleBlocked', 'Saia do veiculo para abastecer.'
  elseif reason == 'engine_running' then
    return 'engineRunning', 'Desligue o motor antes de abastecer.'
  elseif reason == 'refuel_distance' then
    return 'tooFarFromVehicle', 'Aproxime-se da entrada do tanque do veiculo.'
  end

  return 'refuelCanceled', 'Abastecimento cancelado.'
end

function MZFuelNozzle.Cancel(reason, silent)
  reason = tostring(reason or 'canceled')
  if State.phase == 'none' and not State.pending then
    return false
  end

  State.lastCancelReason = reason

  if MZFuelMenu and MZFuelMenu.Close then
    MZFuelMenu.Close()
  end

  if MZFuelRefuel and MZFuelRefuel.IsRefueling and MZFuelRefuel.IsRefueling() then
    MZFuelRefuel.Stop(reason, true)
  end

  deleteHose(State.rope)
  State.rope = 0
  deleteNozzle()
  stopAnimation()
  releasePump()
  resetState()

  if silent ~= true then
    local key, fallback = cancelReasonKey(reason)
    notifyKey(key, reason == 'vehicle_full' and 'inform' or 'error', fallback)
  end

  debugPrint('nozzle_cancel', { reason = reason })
  return true
end

function MZFuelNozzle.IsHolding()
  return State.phase ~= 'none'
end

function MZFuelNozzle.IsDocked()
  return State.phase == 'docked'
end

function MZFuelNozzle.IsDockedTo(vehicle)
  return State.phase == 'docked' and State.vehicle ~= 0 and State.vehicle == vehicle
end

function MZFuelNozzle.GetPump()
  return State.pump
end

function MZFuelNozzle.GetVehicle()
  return State.vehicle
end

function MZFuelNozzle.Reattach()
  if State.nozzle == 0 or not DoesEntityExist(State.nozzle) then
    return false
  end

  local ped = PlayerPedId()
  if State.phase == 'held' then
    DetachEntity(State.nozzle, true, true)
    return attachNozzleToHand(State.nozzle, ped)
  end

  if State.phase == 'docked' and State.vehicle ~= 0 and DoesEntityExist(State.vehicle) then
    local tank = MZFuelNozzle.GetTankWorldPosition(State.vehicle) or State.tank
    if not tank then
      return false
    end
    DetachEntity(State.nozzle, true, true)
    local attached = attachNozzleToVehicle(State.nozzle, State.vehicle, tank)
    State.tank = tank
    return attached
  end

  return false
end

function MZFuelNozzle.SetModelTankOffset(vehicle, offset, rotation)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or not isVector3(offset) then
    return false, nil, nil
  end

  local model = hashEntityModel(vehicle)
  local boneIndex = findTankBone(vehicle)
  RuntimeTankOverrides[model] = {
    offset = offset,
    rotation = isVector3(rotation) and rotation or vec3(0.0, 0.0, 0.0),
    bone_relative = boneIndex ~= nil
  }

  return true, model, boneIndex
end

function MZFuelNozzle.RefreshHose()
  if State.rope ~= 0 then
    deleteHose(State.rope)
    State.rope = 0
  end

  if State.pump and State.nozzle ~= 0 and DoesEntityExist(State.nozzle) then
    State.rope = createHose(State.pump, State.nozzle)
    return State.rope ~= 0, State.rope
  end

  return false, 0
end

function MZFuelNozzle.SetHoseNozzleOffset(offset)
  if not isVector3(offset) then
    return false
  end

  Config.Refuel.hoseNozzleOffset = offset
  local ok, rope = MZFuelNozzle.RefreshHose()
  return ok, rope
end

function MZFuelNozzle.IsPending()
  return State.pending == true
end

function MZFuelNozzle.GetLastCancelReason()
  return State.lastCancelReason
end

local function vehicleFull(vehicle)
  if not MZFuel or not MZFuel.GetFuel then
    return false
  end

  return (MZFuel.GetFuel(vehicle) or 0.0) >= (tonumber(Config.MaxFuel) or 100.0)
end

local function isPlayerInVehicle()
  return IsPedInAnyVehicle(PlayerPedId(), false)
end

local function isPlayerDead()
  local ped = PlayerPedId()
  return not ped or ped == 0 or IsEntityDead(ped)
end

local function isEngineRunning(vehicle)
  local value = GetIsVehicleEngineRunning(vehicle)
  return value == true or value == 1
end

local function engineOff(vehicle)
  if refuelConfig().requireEngineOff == false then
    return true
  end

  return not isEngineRunning(vehicle)
end

local function distanceToTank(vehicle, tank)
  if not tank or not tank.coords then
    return nil
  end

  return #(GetEntityCoords(PlayerPedId()) - tank.coords)
end

local function canTakeNow(pump)
  if not pump then
    return false, 'pump_not_found'
  end

  if refuelConfig().physical ~= true or refuelConfig().enableNozzle ~= true then
    return false, 'physical_disabled'
  end

  if State.pending or State.phase ~= 'none' then
    return false, 'nozzle_taken'
  end

  if MZFuelRefuel and MZFuelRefuel.IsRefueling and MZFuelRefuel.IsRefueling() then
    return false, 'refueling'
  end

  if MZFuelMenu and MZFuelMenu.IsBusy and MZFuelMenu.IsBusy() then
    return false, 'menu_busy'
  end

  if isPlayerDead() then
    return false, 'player_dead'
  end

  if isPlayerInVehicle() then
    return false, 'inside_vehicle'
  end

  local distance = #(GetEntityCoords(PlayerPedId()) - pump.coords)
  if distance > (tonumber(refuelConfig().pumpTargetDistance) or 2.6) + 0.75 then
    return false, 'too_far'
  end

  return true
end

function MZFuelNozzle.CanTake(entity)
  local pump = MZFuelPumps.GetPumpInfo(entity)
  return canTakeNow(pump)
end

local function notificationForTakeFailure(reason)
  if reason == 'nozzle_taken' then
    notifyKey('nozzleTaken', 'inform', 'Voce ja esta com o bico de combustivel.')
  elseif reason == 'inside_vehicle' then
    notifyKey('insideVehicleBlocked', 'error', 'Saia do veiculo para abastecer.')
  elseif reason == 'refueling' or reason == 'menu_busy' then
    notifyKey('rateLimited', 'inform', 'Aguarde um instante para tentar novamente.')
  elseif reason == 'physical_disabled' then
    notifyKey('physicalRequired', 'error', 'Pegue o bico da bomba e encaixe no tanque primeiro.')
  elseif reason == 'player_dead' then
    notifyKey('playerDead', 'error', 'Abastecimento cancelado: jogador morreu.')
  else
    notifyKey('pumpNotFound', 'error', 'Nenhuma bomba valida por perto.')
  end
end

local function claimPump(pump, callback)
  local requestId = ('%s:%s'):format(GetGameTimer(), math.random(100000, 999999))
  PendingClaims[requestId] = {
    callback = callback,
    createdAt = GetGameTimer()
  }

  TriggerServerEvent('mz_fuel:server:claimPump', {
    request_id = requestId,
    pump_key = pump.pumpKey,
    station_id = pump.stationIndex,
    coords = {
      x = pump.coords.x,
      y = pump.coords.y,
      z = pump.coords.z
    }
  })

  CreateThread(function()
    Wait(2500)
    local pending = PendingClaims[requestId]
    if pending then
      PendingClaims[requestId] = nil
      pending.callback(false, 'lock_timeout', nil)
    end
  end)
end

RegisterNetEvent('mz_fuel:client:pumpClaimResult', function(result)
  result = type(result) == 'table' and result or {}
  local requestId = tostring(result.request_id or '')
  local pending = PendingClaims[requestId]
  if not pending then
    return
  end

  PendingClaims[requestId] = nil
  pending.callback(result.ok == true, tostring(result.error or ''), result.token)
end)

local function loadNozzleModel()
  local diagnostics = {}
  local timeoutMs = tonumber(refuelConfig().nozzleLoadTimeoutMs) or 4000

  for _, name in ipairs(refuelConfig().nozzleModels or {}) do
    if type(name) == 'string' and name ~= '' then
      local probe = probeModel(name)
      local loaded = requestModel(probe.hash, timeoutMs)
      probe.loaded = loaded
      diagnostics[#diagnostics + 1] = probe

      if loaded then
        State.nozzleModelDiagnostics = diagnostics
        return name, probe.hash, probe
      end

      logModelProbe(probe, true, false, false, false, 'request_or_load_failed')
      if type(SetModelAsNoLongerNeeded) == 'function' then
        SetModelAsNoLongerNeeded(probe.hash)
      end
    end
  end

  State.nozzleModelDiagnostics = diagnostics
  return nil, 0, nil
end

local function createNozzleProp(pump)
  local modelName, modelHash, probe = loadNozzleModel()
  if not modelName or not modelHash or modelHash == 0 then
    logModelProbe(probe or { name = 'none', hash = 0 }, true, false, false, false, 'no_model_selected')
    return 0
  end

  local coords = pump.coords + vec3(0.0, 0.0, 0.9)
  local createOk, nozzle = pcall(CreateObject, modelHash, coords.x, coords.y, coords.z, true, true, false)
  if not createOk then
    nozzle = 0
  end
  local created = nozzle ~= nil and nozzle ~= 0
  local exists = created and nativeTrue(DoesEntityExist(nozzle))

  if type(SetModelAsNoLongerNeeded) == 'function' then
    SetModelAsNoLongerNeeded(modelHash)
  end

  if created and not exists then
    local expiresAt = GetGameTimer() + 1500
    while not nativeTrue(DoesEntityExist(nozzle)) and GetGameTimer() < expiresAt do
      Wait(0)
    end
    exists = nativeTrue(DoesEntityExist(nozzle))
  end

  logModelProbe(probe, true, true, created, exists, created and exists and 'ok' or 'create_failed')

  if not created or not exists then
    return 0
  end

  SetEntityAsMissionEntity(nozzle, true, true)
  SetEntityInvincible(nozzle, true)
  SetEntityCanBeDamaged(nozzle, false)
  SetEntityCollision(nozzle, false, false)
  if type(SetEntityCompletelyDisableCollision) == 'function' then
    SetEntityCompletelyDisableCollision(nozzle, false, false)
  end

  State.nozzleModel = modelName
  return nozzle
end

function MZFuelNozzle.Take(entity)
  local pump = MZFuelPumps.GetPumpInfo(entity)
  local ok, reason = canTakeNow(pump)
  if not ok then
    notificationForTakeFailure(reason)
    return false, reason
  end

  State.pending = true
  State.lastCancelReason = nil

  claimPump(pump, function(claimed, claimReason, token)
    if State.pending ~= true then
      if claimed then
        TriggerServerEvent('mz_fuel:server:releasePump', {
          pump_key = pump.pumpKey,
          token = token
        })
      end
      return
    end

    State.pending = false

    if not claimed then
      if claimReason == 'pump_busy' then
        notifyKey('pumpBusy', 'inform', 'Esta bomba ja esta em uso por outro jogador.')
      elseif claimReason == 'rate_limited' then
        notifyKey('rateLimited', 'inform', 'Aguarde um instante para tentar novamente.')
      elseif claimReason == 'pump_not_found' or claimReason == 'station_invalid' then
        notifyKey('pumpNotFound', 'error', 'Nenhuma bomba valida por perto.')
      else
        notifyKey('pumpBusy', 'inform', 'Esta bomba ja esta em uso por outro jogador.')
      end
      return
    end

    local recheckOk, recheckReason = canTakeNow(pump)
    if not recheckOk then
      TriggerServerEvent('mz_fuel:server:releasePump', {
        pump_key = pump.pumpKey,
        token = token
      })
      notificationForTakeFailure(recheckReason)
      return
    end

    local nozzle = createNozzleProp(pump)
    if nozzle == 0 then
      TriggerServerEvent('mz_fuel:server:releasePump', {
        pump_key = pump.pumpKey,
        token = token
      })
      notifyKey('nozzleUnavailable', 'error', 'O modelo do bico de combustivel nao esta disponivel.')
      return
    end

    State.phase = 'held'
    State.pump = pump
    State.claimToken = token
    State.vehicle = 0
    State.tank = nil
    State.nozzle = nozzle
    State.lastCancelReason = nil

    local ped = PlayerPedId()
    playOneShotAnimation('pickup')

    if not attachNozzleToHand(nozzle, ped) then
      MZFuelNozzle.Cancel('hand_bone_missing', true)
      notifyKey('nozzleUnavailable', 'error', 'O modelo do bico de combustivel nao esta disponivel.')
      return
    end

    State.rope = createHose(pump, nozzle)

    notifyKey('nozzlePicked', 'inform', 'Bico de combustivel em maos.')
    debugPrint('nozzle_take', {
      pump = pump.pumpKey,
      station = pump.stationIndex,
      nozzle = nozzle,
      rope = State.rope,
      model = State.nozzleModel
    })
  end)

  return true
end

function MZFuelNozzle.CanReturn(entity)
  if State.pending or State.phase == 'none' or not State.pump then
    return false
  end

  if entity and entity ~= 0 and State.pump.entity ~= entity then
    return false
  end

  return true
end

function MZFuelNozzle.Return(entity)
  if not MZFuelNozzle.CanReturn(entity) then
    return false
  end

  if MZFuelMenu and MZFuelMenu.Close then
    MZFuelMenu.Close()
  end

  if MZFuelRefuel and MZFuelRefuel.IsRefueling and MZFuelRefuel.IsRefueling() then
    MZFuelRefuel.Stop('nozzle_returned', true)
  end

  if State.phase == 'docked' then
    MZFuelNozzle.Undock('return', true)
  end

  playOneShotAnimation('pickup')

  deleteHose(State.rope)
  State.rope = 0
  deleteNozzle()
  stopAnimation()
  releasePump()
  resetState()
  notifyKey('nozzleReturned', 'inform', 'Bico devolvido a bomba.')
  return true
end

local function nearbyVehicleForDock()
  local pedCoords = GetEntityCoords(PlayerPedId())
  local maxDistance = (tonumber(refuelConfig().tankAttachDistance) or 2.8) + 2.0
  local best, bestDistance = 0, nil

  for _, vehicle in ipairs(GetGamePool('CVehicle')) do
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and MZFuel.IsVehicleSupported(vehicle) then
      local distance = #(pedCoords - GetEntityCoords(vehicle))
      if distance <= maxDistance and (not bestDistance or distance < bestDistance) then
        best = vehicle
        bestDistance = distance
      end
    end
  end

  return best
end

function MZFuelNozzle.GetNearbyVehicleForDock()
  return nearbyVehicleForDock()
end

function MZFuelNozzle.CanDock(vehicle)
  if refuelConfig().physical ~= true or refuelConfig().enableNozzle ~= true then
    return false
  end

  if State.pending or State.phase ~= 'held' or not State.pump then
    return false
  end

  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return false
  end

  if not MZFuel.IsVehicleSupported(vehicle) then
    return false
  end

  if isPlayerInVehicle() or isPlayerDead() then
    return false
  end

  if not engineOff(vehicle) then
    return false
  end

  if vehicleFull(vehicle) then
    return false
  end

  if MZFuelRefuel and MZFuelRefuel.IsRefueling and MZFuelRefuel.IsRefueling() then
    return false
  end

  local tank = MZFuelNozzle.GetTankWorldPosition(vehicle)
  if not tank then
    return false
  end

  local distance = distanceToTank(vehicle, tank)
  return distance ~= nil and distance <= (tonumber(refuelConfig().tankAttachDistance) or 2.8)
end

function MZFuelNozzle.Dock(vehicle)
  local ok = MZFuelNozzle.CanDock(vehicle)
  if not ok then
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
      local tank = MZFuelNozzle.GetTankWorldPosition(vehicle)

      if not engineOff(vehicle) then
        notifyKey('engineRunning', 'error', 'Desligue o motor antes de abastecer.')
      elseif vehicleFull(vehicle) then
        notifyKey('vehicleFull', 'inform', 'O veiculo ja esta cheio.')
      elseif not tank then
        notifyKey('tankNotFound', 'error', 'Nao foi possivel localizar a entrada do tanque.')
      elseif distanceToTank(vehicle, tank) and
        distanceToTank(vehicle, tank) > (tonumber(refuelConfig().tankAttachDistance) or 2.8) then
        notifyKey('tooFarFromVehicle', 'error', 'Aproxime-se da entrada do tanque do veiculo.')
      else
        notifyKey('physicalRequired', 'error', 'Pegue o bico da bomba e encaixe no tanque primeiro.')
      end
    end
    return false
  end

  local tank = MZFuelNozzle.GetTankWorldPosition(vehicle)
  if not tank then
    notifyKey('tankNotFound', 'error', 'Nao foi possivel localizar a entrada do tanque.')
    return false
  end

  local ped = PlayerPedId()
  if ped and ped ~= 0 and not IsEntityDead(ped) then
    TaskTurnPedToFaceEntity(ped, vehicle, 500)
    Wait(120)
    playOneShotAnimation('dock')
  end

  DetachEntity(State.nozzle, true, true)
  if not attachNozzleToVehicle(State.nozzle, vehicle, tank) then
    if not attachNozzleToHand(State.nozzle, PlayerPedId()) then
      MZFuelNozzle.Cancel('hand_bone_missing', true)
      return false
    end
    notifyKey('tankNotFound', 'error', 'Nao foi possivel localizar a entrada do tanque.')
    return false
  end

  State.phase = 'docked'
  State.vehicle = vehicle
  State.tank = tank
  stopAnimation()

  notifyKey('nozzleDocked', 'success', 'Bico encaixado no tanque.')

  debugPrint('nozzle_dock', {
    pump = State.pump and State.pump.pumpKey or 'none',
    vehicle = vehicle,
    tank_source = tank.source,
    tank_bone = tank.boneName or 'none',
    tank_confidence = tank.confident == true,
    tank_x = tank.coords.x,
    tank_y = tank.coords.y,
    tank_z = tank.coords.z,
    hand_bone = State.handBone,
    vehicle_offset = (function()
      local offset = refuelConfig().nozzleVehicleOffset or vec3(0.0, 0.0, 0.0)
      return ('%.2f,%.2f,%.2f'):format(offset.x, offset.y, offset.z)
    end)(),
    vehicle_rotation = (function()
      local rotation = refuelConfig().nozzleVehicleRotation or vec3(0.0, 0.0, 0.0)
      return ('%.2f,%.2f,%.2f'):format(rotation.x, rotation.y, rotation.z)
    end)()
  })

  CreateThread(function()
    Wait(250)
    if State.phase ~= 'docked' or State.vehicle ~= vehicle then
      return
    end

    if MZFuelMenu and MZFuelMenu.Open then
      MZFuelMenu.Open(vehicle, State.pump and State.pump.coords or nil, {
        physical = true,
        pump = State.pump,
        stationId = State.pump and State.pump.stationIndex or nil
      })
    elseif MZFuelRefuel and MZFuelRefuel.Start then
      MZFuelRefuel.Start(vehicle, State.pump and State.pump.coords or nil, {
        physical = true,
        pump = State.pump,
        stationId = State.pump and State.pump.stationIndex or nil
      })
    end
  end)

  return true
end

function MZFuelNozzle.CanUndock(vehicle)
  return State.phase == 'docked'
    and State.vehicle ~= 0
    and (not vehicle or vehicle == 0 or vehicle == State.vehicle)
end

function MZFuelNozzle.Undock(reason, silent)
  if State.phase ~= 'docked' then
    return false
  end

  if MZFuelRefuel and MZFuelRefuel.IsRefueling and MZFuelRefuel.IsRefueling() then
    MZFuelRefuel.Stop(tostring(reason or 'nozzle_removed'), silent == true)
  end

  local ped = PlayerPedId()
  local attachedToHand = false
  if State.nozzle ~= 0 and DoesEntityExist(State.nozzle) then
    DetachEntity(State.nozzle, true, true)
    if ped and ped ~= 0 and not IsEntityDead(ped) and not isPlayerInVehicle() then
      attachedToHand = attachNozzleToHand(State.nozzle, ped)
    end
  end

  if not attachedToHand then
    MZFuelNozzle.Cancel('hand_bone_missing', true)
    return false
  end

  State.phase = 'held'
  State.vehicle = 0
  State.tank = nil

  if ped and ped ~= 0 and not IsEntityDead(ped) then
    stopAnimation()
  end

  if silent ~= true then
    notifyKey('nozzleDropped', 'inform', 'O bico foi desconectado.')
  end

  return true
end

function MZFuelNozzle.CanOpenMenu(vehicle)
  if State.phase ~= 'docked' or State.vehicle == 0 or State.vehicle ~= vehicle then
    return false
  end

  if MZFuelRefuel and MZFuelRefuel.IsRefueling and MZFuelRefuel.IsRefueling() then
    return false
  end

  if MZFuelMenu and MZFuelMenu.IsBusy and MZFuelMenu.IsBusy() then
    return false
  end

  if vehicleFull(vehicle) then
    return false
  end

  return engineOff(vehicle)
end

function MZFuelNozzle.OpenMenu(vehicle)
  if not MZFuelNozzle.CanOpenMenu(vehicle) then
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
      if not engineOff(vehicle) then
        notifyKey('engineRunning', 'error', 'Desligue o motor antes de abastecer.')
      elseif vehicleFull(vehicle) then
        notifyKey('vehicleFull', 'inform', 'O veiculo ja esta cheio.')
      end
    end
    return false
  end

  local pump = State.pump
  if MZFuelMenu and MZFuelMenu.Open then
    return MZFuelMenu.Open(vehicle, pump and pump.coords or nil, {
      physical = true,
      pump = pump,
      stationId = pump and pump.stationIndex or nil
    })
  end

  if MZFuelRefuel and MZFuelRefuel.Start then
    return MZFuelRefuel.Start(vehicle, pump and pump.coords or nil, {
      physical = true,
      pump = pump,
      stationId = pump and pump.stationIndex or nil
    })
  end

  return false
end

local function validateActiveState()
  if State.phase == 'none' then
    return true
  end

  if isPlayerDead() then
    MZFuelNozzle.Cancel('player_dead')
    return false
  end

  if not State.pump or not State.pump.entity or not DoesEntityExist(State.pump.entity) then
    MZFuelNozzle.Cancel('pump_missing')
    return false
  end

  local pedCoords = GetEntityCoords(PlayerPedId())
  if #(pedCoords - State.pump.coords) > (tonumber(refuelConfig().maxPumpDistance) or 10.0) then
    MZFuelNozzle.Cancel('pump_distance')
    return false
  end

  if isPlayerInVehicle() then
    MZFuelNozzle.Cancel('inside_vehicle')
    return false
  end

  if State.nozzle == 0 or not DoesEntityExist(State.nozzle) then
    MZFuelNozzle.Cancel('nozzle_missing')
    return false
  end

  if State.phase == 'docked' then
    local vehicle = State.vehicle
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
      MZFuelNozzle.Cancel('vehicle_missing')
      return false
    end

    if not engineOff(vehicle) then
      MZFuelNozzle.Cancel('engine_running')
      return false
    end

    if #(GetEntityCoords(vehicle) - State.pump.coords) > (tonumber(refuelConfig().hoseLength) or 12.0) then
      MZFuelNozzle.Cancel('vehicle_distance')
      return false
    end

    local tank = MZFuelNozzle.GetTankWorldPosition(vehicle) or State.tank
    if not tank then
      MZFuelNozzle.Cancel('tank_missing')
      return false
    end

    if distanceToTank(vehicle, tank) > (tonumber(refuelConfig().refuelKeepDistance) or 5.0) then
      MZFuelNozzle.Cancel('refuel_distance')
      return false
    end
  end

  return true
end

local function drawDebugTankMarker()
  if Config.DebugTankMarker ~= true then
    return
  end

  local vehicle = State.vehicle
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return
  end

  local tank = MZFuelNozzle.GetTankWorldPosition(vehicle) or State.tank
  if not tank then
    return
  end

  DrawMarker(
    1,
    tank.coords.x, tank.coords.y, tank.coords.z,
    0.0, 0.0, 0.0,
    0.0, 0.0, 0.0,
    0.25, 0.25, 0.25,
    255, 70, 70, 180,
    false, false, 2, false, nil, nil, false
  )
end

CreateThread(function()
  while true do
    local sleep = 500
    if State.phase ~= 'none' then
      sleep = 250
      validateActiveState()
      drawDebugTankMarker()
    elseif State.pending then
      sleep = 250
    end

    Wait(sleep)
  end
end)

buildTankOffsetHashes()

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then
    return
  end

  MZFuelNozzle.Cancel('resource_stop', true)
end)

AddEventHandler('playerSpawned', function()
  if State.phase ~= 'none' then
    MZFuelNozzle.Cancel('player_spawned', true)
  end
end)

function MZFuelNozzle.GetDiagnostics()
  local pump = State.pump
  local tank = State.tank

  return {
    phase = State.phase,
    pending = State.pending == true,
    pump_key = pump and pump.pumpKey or 'none',
    station = pump and pump.stationIndex or 'none',
    vehicle = State.vehicle,
    vehicle_model = State.vehicle ~= 0 and tostring(GetEntityModel(State.vehicle)) or 'none',
    tank_source = tank and tank.source or 'none',
    tank_bone = tank and (tank.boneName or tostring(tank.bone)) or 'none',
    tank_confident = tank and tank.confident == true or false,
    tank_offset = tank and tank.offset and ('%.2f,%.2f,%.2f'):format(tank.offset.x, tank.offset.y, tank.offset.z) or 'none',
    vehicle_offset = (function()
      local offset = refuelConfig().nozzleVehicleOffset or vec3(0.0, 0.0, 0.0)
      return ('%.2f,%.2f,%.2f'):format(offset.x, offset.y, offset.z)
    end)(),
    vehicle_rotation = (function()
      local rotation = refuelConfig().nozzleVehicleRotation or vec3(0.0, 0.0, 0.0)
      return ('%.2f,%.2f,%.2f'):format(rotation.x, rotation.y, rotation.z)
    end)(),
    hand_bone = State.handBone,
    animation = State.animation or 'none',
    nozzle = State.nozzle,
    nozzle_model = State.nozzleModel or 'none',
    nozzle_model_probes = (function()
      local parts = {}
      for _, probe in ipairs(State.nozzleModelDiagnostics or {}) do
        parts[#parts + 1] = ('%s(hash=%s,valid=%s,in_cd=%s,loaded=%s)'):format(
          tostring(probe.name),
          tostring(probe.hash),
          tostring(probe.valid_raw),
          tostring(probe.in_cdimage_raw),
          tostring(probe.loaded)
        )
      end
      return #parts > 0 and table.concat(parts, ';') or 'none'
    end)(),
    rope = State.rope,
    hose_nozzle_offset = (function()
      local offset = refuelConfig().hoseNozzleOffset or vec3(0.0, -0.033, -0.195)
      return ('%.3f,%.3f,%.3f'):format(offset.x, offset.y, offset.z)
    end)(),
    hose_start = State.hoseStart and ('%.2f,%.2f,%.2f'):format(State.hoseStart.x, State.hoseStart.y, State.hoseStart.z) or 'none',
    hose_end = State.hoseEnd and ('%.2f,%.2f,%.2f'):format(State.hoseEnd.x, State.hoseEnd.y, State.hoseEnd.z) or 'none',
    last_cancel = State.lastCancelReason or 'none'
  }
end

exports('IsHoldingNozzle', function()
  return MZFuelNozzle.IsHolding()
end)

exports('IsNozzleDocked', function(vehicle)
  return MZFuelNozzle.IsDockedTo(vehicle)
end)
