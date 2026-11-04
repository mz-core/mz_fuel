Config = Config or {}

Config.Debug = false
Config.DebugCommands = false
Config.DebugAce = 'mz_fuel.debug'
Config.DebugTankMarker = false
Config.UpdateIntervalMs = 1000
Config.SaveIntervalMs = 15000
Config.MinFuel = 0.0
Config.MaxFuel = 100.0
Config.DefaultFuel = 100.0
Config.UseStateBag = true
Config.UseNativeFuelLevel = true
Config.DisableOnBicycles = true
Config.DisableOnElectric = false
Config.ConsumptionMultiplier = 1.0
Config.SaveOnExitVehicle = true
Config.SaveWhenDriver = true

Config.DisableNativeFuelConsumption = true
Config.MinimumSaveDelta = 0.2
Config.StopEngineWhenEmpty = true

Config.Stations = {
  enabled = true,
  blips = {
    enabled = true,
    sprite = 361,
    color = 0,
    scale = 0.7,
    shortRange = true,
    name = 'Posto de combustivel'
  },
  marker = {
    type = 1,
    radius = 4.0,
    drawDistance = 18.0,
    color = { r = 57, g = 229, b = 140, a = 110 }
  },
  locations = {
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
}

Config.Refuel = {
  pricePerLiter = 5,
  paymentAccount = 'cash',
  tickMs = 1000,
  litersPerTick = 1.0,
  maxDistance = 6.0,
  paidCreditTtlMs = 120000,
  -- O fluxo fisico nao exige motorista e acontece fora do veiculo.
  requireDriver = false,
  allowInsideVehicle = false,
  saveOnComplete = true,
  useMenu = true,
  menuMode = 'simple',
  maxLitersPerRequest = 100.0,
  allowFillTank = true,
  allowMoneyAmount = true,
  allowLiterAmount = true,

  -- Abastecimento fisico: bico na mao, mangueira e encaixe no tanque.
  physical = true,
  enableNozzle = true,
  enableHose = true,
  requireEngineOff = true,

  -- `prop_cs_fuel_nozle` e o prop base do GTA V.
  -- Hash assinado: -1937636863 (0x8C820201). O nome e o hash sao registrados
  -- no F8 durante a tentativa de carregamento; IsModelValid/IsModelInCdimage
  -- sao apenas diagnostico, nunca bloqueio isolado.
  nozzleModels = {
    'prop_cs_fuel_nozle'
  },
  nozzleBone = 'SKEL_L_Hand',
  nozzleBoneId = 18905,
  nozzleLoadTimeoutMs = 4000,
  -- Valores extraidos de ref/lc_fuel (attachNozzleToPed):
  -- bone 18905, 0.13/0.04/0.01, -42/-115/-63.42.
  nozzleHandOffset = vec3(0.13, 0.04, 0.01),
  nozzleHandRotation = vec3(-42.0, -115.0, -63.42),
  nozzleVehicleOffset = vec3(0.0, 0.0, 0.0),
  nozzleVehicleRotation = vec3(-45.0, 0.0, -90.0),

  -- Transicoes extraidas de ref/lc_fuel: pickup curto e refuel de 1s com
  -- weapons@misc@jerrycan@/fire. Nao existe loop de pose durante a caminhada.
  nozzleAnim = {
    pickup = {
      dict = 'anim@am_hold_up@male',
      clip = 'shoplift_high',
      duration = 300,
      flag = 50
    },
    dock = {
      dict = 'weapons@misc@jerrycan@',
      clip = 'fire',
      duration = 1000,
      flag = 50
    }
  },

  -- Props originais de bomba do GTA V. Sao validados em runtime; nao criamos
  -- props duplicados sobre os objetos do mapa.
  pumpModels = {
    'prop_gas_pump_1a',
    'prop_gas_pump_1b',
    'prop_gas_pump_1c',
    'prop_gas_pump_1d',
    'prop_vintage_pump',
    'prop_gas_pump_old2',
    'prop_gas_pump_old3'
  },
  pumpStationRadius = 40.0,
  pumpTargetDistance = 2.6,
  pumpDrawDistance = 15.0,
  maxPumpDistance = 10.0,
  pumpLockTtlMs = 300000,
  undockKey = 74,
  cancelKey = 177,

  -- Mangueira baseada em ref/lc_fuel. ropeType 1 = RopeWire6.
  hoseLength = 12.0,
  hoseType = 1,
  hoseStartOffset = vec3(0.0, 0.0, 2.3),
  hoseRopeMaxLength = 4.0,
  hoseRopeInitialLength = 10.0,
  hoseAttachLength = 30.0,
  hoseNozzleOffset = vec3(0.0, -0.033, -0.195),
  hosePumpOffsets = {
    prop_gas_pump_1a = vec3(0.0, 0.0, 2.3),
    prop_gas_pump_1b = vec3(0.0, 0.0, 2.3),
    prop_gas_pump_1c = vec3(0.0, 0.0, 2.3),
    prop_gas_pump_1d = vec3(0.0, 0.0, 2.3),
    prop_vintage_pump = vec3(0.0, 0.0, 1.8),
    prop_gas_pump_old2 = vec3(0.0, 0.0, 1.6),
    prop_gas_pump_old3 = vec3(0.0, 0.0, 1.6)
  },

  tankAttachDistance = 2.8,
  refuelKeepDistance = 5.0,
  vehicleTargetDistance = 3.0,
  tankBones = {
    'petrolcap',
    'petrolcap_l',
    'petrolcap_r',
    'fuelcap'
  },
  -- Offsets por modelo em coordenadas locais da entidade, prioridade depois
  -- dos offsets relativos ao bone. Use este formato quando o veiculo nao
  -- tiver `petrolcap`.
  tankOffsets = {},
  -- Offsets por modelo relativos ao bone de entrada, extraidos de
  -- ref/lc_fuel e convertidos de forward/right/up para x/y/z locais do bone.
  tankBoneOffsets = {
    kuruma = vec3(-0.19, -0.50, 0.40),
    kuruma2 = vec3(-0.19, -0.50, 0.40),
    zentorno = vec3(-0.29, 0.35, 0.35),
    bati = vec3(-0.25, -0.15, 0.20),
    bati2 = vec3(-0.24, -0.15, 0.20),
    akuma = vec3(-0.20, 0.01, 0.20)
  },
  -- Fallback por classe GTA quando o bone `petrolcap` nao existe.
  tankClassOffsets = {
    [0] = vec3(-0.42, -1.35, 0.45), -- compact
    [1] = vec3(-0.52, -1.75, 0.5), -- sedan
    [2] = vec3(-0.58, -2.0, 0.62), -- suv
    [3] = vec3(-0.52, -1.65, 0.48), -- coupe
    [4] = vec3(-0.55, -1.9, 0.5), -- muscle
    [5] = vec3(-0.52, -1.75, 0.45), -- sports
    [6] = vec3(-0.5, -1.7, 0.5), -- sport classic
    [7] = vec3(-0.52, -1.8, 0.42), -- super
    [8] = vec3(0.0, 0.05, 0.78), -- motorcycle: topo do tanque
    [9] = vec3(-0.58, -1.95, 0.62), -- offroad
    [10] = vec3(-0.7, -2.1, 0.7), -- industrial
    [11] = vec3(-0.65, -2.0, 0.62), -- utility
    [12] = vec3(-0.62, -2.2, 0.65), -- van
    [14] = vec3(-0.7, -2.2, 0.48), -- boat
    [15] = vec3(-0.7, -2.0, 0.55), -- helicopter
    [16] = vec3(-0.8, -2.4, 0.55), -- plane
    [17] = vec3(-0.6, -2.0, 0.6), -- service
    [18] = vec3(-0.6, -2.0, 0.6), -- emergency
    [19] = vec3(-0.7, -2.1, 0.65), -- military
    [20] = vec3(-0.7, -2.4, 0.7) -- commercial
  },
  -- Lado usado quando o bone e o offset por classe nao existem.
  tankFallbackSide = 'left',
  nativeUnitsPerLiter = 1.0,
  tankCapacityLiters = 100.0
}

Config.JerryCan = {
  enabled = true,
  item = 'WEAPON_PETROLCAN',
  inventoryItem = 'jerrycan',
  litersPerUse = 10.0,
  useTimeMs = 6000,
  maxDistance = 3.0,
  consumeItem = false,
  requireOutsideVehicle = true,
  authorizedCreditTtlMs = 120000,
  allowWithoutInventory = false
}

Config.Notify = {
  enabled = true,
  resource = 'mz_notify',
  fallback = true,
  messages = {
    refuelStarted = 'Abastecimento iniciado.',
    refuelFinished = 'Veiculo abastecido.',
    refuelCanceled = 'Abastecimento cancelado.',
    noMoney = 'Dinheiro insuficiente.',
    vehicleFull = 'O veiculo ja esta cheio.',
    invalidVehicle = 'Veiculo invalido.',
    driverRequired = 'Entre no banco do motorista para abastecer.',
    tooFar = 'Voce esta longe demais do posto.',
    paymentUnavailable = 'Pagamento indisponivel.',
    rateLimited = 'Aguarde um instante para tentar novamente.',
    jerrycanStarted = 'Usando galao de combustivel.',
    jerrycanFinished = 'Combustivel adicionado.',
    jerrycanCanceled = 'Uso do galao cancelado.',
    noJerrycan = 'Voce nao possui um galao.',
    engineRunning = 'Desligue o motor antes de abastecer.',
    pumpBusy = 'Esta bomba ja esta em uso por outro jogador.',
    pumpNotFound = 'Nenhuma bomba valida por perto.',
    nozzleTaken = 'Voce ja esta com o bico de combustivel.',
    nozzlePicked = 'Bico de combustivel em maos.',
    nozzleDocked = 'Bico encaixado no tanque.',
    nozzleReturned = 'Bico devolvido a bomba.',
    nozzleDropped = 'O bico foi desconectado.',
    nozzleUnavailable = 'O modelo do bico de combustivel nao esta disponivel.',
    tankNotFound = 'Nao foi possivel localizar a entrada do tanque.',
    tooFarFromVehicle = 'Aproxime-se da entrada do tanque do veiculo.',
    vehicleBusy = 'Este veiculo ja esta sendo abastecido por outro jogador.',
    physicalRequired = 'Pegue o bico da bomba e encaixe no tanque primeiro.',
    insideVehicleBlocked = 'Saia do veiculo para abastecer.',
    playerDead = 'Abastecimento cancelado: jogador morreu.',
    pumpDistance = 'Abastecimento cancelado: voce se afastou da bomba.',
    vehicleDistance = 'Abastecimento cancelado: o veiculo se afastou.',
    paymentTimeout = 'Pagamento nao respondeu. Tente novamente.'
  }
}

Config.Payment = {
  enabled = true,
  accountAliases = {
    cash = 'wallet',
    wallet = 'wallet',
    bank = 'bank',
    dirty = 'dirty'
  }
}

Config.Interaction = {
  mode = 'auto', -- 'auto', 'target', 'interact', 'marker', 'none'
  prefer = 'target',
  fallbackMarker = true
}

Config.ConsumptionByClass = {
  [0] = 0.55,
  [1] = 0.55,
  [2] = 0.65,
  [3] = 0.60,
  [4] = 0.85,
  [5] = 0.75,
  [6] = 0.80,
  [7] = 1.00,
  [8] = 0.45,
  [9] = 0.90,
  [10] = 1.10,
  [11] = 1.05,
  [12] = 1.00,
  [13] = 0.0,
  [14] = 0.25,
  [15] = 1.30,
  [16] = 1.50,
  [17] = 0.75,
  [18] = 0.85,
  [19] = 1.20,
  [20] = 1.15,
  [21] = 1.40,
  [22] = 0.65
}

Config.ConsumptionByCategory = {
  compact = 0.55,
  sedan = 0.55,
  suv = 0.65,
  coupe = 0.65,
  muscle = 0.85,
  sport = 0.85,
  super = 1.0,
  motorcycle = 0.45,
  offroad = 0.90,
  industrial = 1.10,
  utility = 1.05,
  van = 1.0,
  cycle = 0.0,
  boat = 0.25,
  helicopter = 1.30,
  plane = 1.50,
  service = 0.75,
  emergency = 0.85,
  military = 1.20,
  commercial = 1.15,
  train = 1.40,
  openwheel = 0.65
}

Config.ElectricModels = {
  airtug = true,
  caddy = true,
  caddy2 = true,
  caddy3 = true,
  cyclone = true,
  dilettante = true,
  imorgon = true,
  khamelion = true,
  neon = true,
  omnisegt = true,
  raiden = true,
  surge = true,
  tezeract = true,
  virtue = true,
  voltic = true,
  voltic2 = true
}
