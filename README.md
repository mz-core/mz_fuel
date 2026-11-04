# mz_fuel

`mz_fuel` é o resource modular de combustível do ecossistema MZ. Ele centraliza consumo, abastecimento, persistência e sincronização de fuel sem colocar lógica dentro do `mz_core`.

Versão: `1.0.0-dev/stable`

## Objetivo

- Controlar fuel de veículos entre `0` e `100`.
- Consumir combustível somente quando o jogador está dirigindo.
- Persistir fuel por placa normalizada (`trim + upper`).
- Integrar com `mz_core`, `mz_vehicles` e `mz_garagem`.
- Manter posto, menu simples, pagamento, galão e feedback visual dentro do `mz_fuel`.
- Usar `mz_interact`, `mz_notify` e `mz_target` apenas como adapters opcionais.

## Dependências obrigatórias

- `mz_core`
- `mz_vehicles`
- `mz_garagem`

Observação: o `fxmanifest.lua` declara `mz_core`, `mz_vehicles` e `mz_inventory` como dependências duras. `mz_garagem` depende de `mz_fuel`, portanto inicia depois dele.

## Dependências opcionais

- `mz_interact`: usado como fallback de interação quando `mz_target` não estiver disponível.
- `mz_notify`: usado para notificações/progresso quando iniciado.
- `mz_target`: usado via `AddTargetModel`/`AddGlobalVehicle` nas bombas e no veículo. Quando não está iniciado, o `mz_fuel` cai para `mz_interact` ou para a tecla E no marker.

## Ordem recomendada no server.cfg

```cfg
ensure mz_core
ensure mz_vehicles
ensure mz_fuel
ensure mz_garagem
ensure mz_interact
ensure mz_notify
```

`mz_interact` e `mz_notify` podem iniciar antes ou depois; o `mz_fuel` usa `GetResourceState` e faz fallback quando eles não existem.

## Config principal

### Config.Debug

Ativa logs simples no console do resource. Padrão: `false`.

### Config.DebugCommands

Habilita comandos administrativos:

- `/mfuel_get`
- `/mfuel_set [valor]`
- `/mfuel_refill`

Padrão: `false`.

### Config.DebugAce

Permissão ACE exigida para comandos debug. Padrão: `mz_fuel.debug`.

```cfg
add_ace group.mz_owner mz_fuel.debug allow
```

### Config.Refuel

Controla abastecimento em postos:

- `pricePerLiter`: preço por litro.
- `paymentAccount`: conta usada no `mz_economy`, normalmente `cash` ou `bank`.
- `tickMs`: intervalo do abastecimento progressivo.
- `litersPerTick`: litros por tick.
- `maxDistance`: distância máxima do posto.
- `paidCreditTtlMs`: tempo máximo do crédito pago.
- `requireDriver`: exige motorista no banco (padrão `false` no fluxo físico).
- `allowInsideVehicle`: permite iniciar dentro do veículo (padrão `false` no fluxo físico).
- `saveOnComplete`: salva ao terminar/cancelar quando necessário.
- `useMenu`: usa a UI simples de abastecimento.
- `menuMode`: modo do menu, atualmente `simple`.
- `maxLitersPerRequest`: limite máximo por pedido do menu.
- `allowFillTank`: permite completar tanque.
- `allowMoneyAmount`: permite abastecer por valor.
- `allowLiterAmount`: permite abastecer por litros.

### Fluxo físico (`Config.Refuel.physical`)

Com `physical = true` (padrão), o abastecimento usa as bombas reais do mapa:

1. O jogador sai do veículo e desliga o motor.
2. Mira na bomba com `mz_target` e escolhe **Pegar bico de combustível**.
3. O prop `prop_cs_fuel_nozle` é anexado à mão; a mangueira usa rope natives quando disponíveis.
4. Ao se aproximar do tanque, o target do veículo oferece **Encaixar bico no tanque**.
5. O menu de abastecimento abre; o bico permanece preso ao veículo.
6. O pagamento é feito por tick no servidor; o combustível só sobe após confirmação.
7. O jogador retira o bico e o devolve à bomba.

Campos principais:

- `enableNozzle`, `enableHose`, `nozzleModels`, `nozzleAnim`
- `pumpModels`, `pumpStationRadius`, `pumpTargetDistance`, `pumpDrawDistance`
- `maxPumpDistance`, `hoseLength`, `tankAttachDistance`, `refuelKeepDistance`
- `tankBones`, `tankOffsets` (por modelo), `tankClassOffsets`, `tankFallbackSide`
- `requireEngineOff`, `pumpLockTtlMs`, `undockKey`

O servidor valida estação, bomba, lock da bomba, placa, `net_id`, proximidade, litros, preço e créditos pagos. O modelo nativo de combustível continua em `0..100`; por padrão `1 unidade = 1 litro` (`nativeUnitsPerLiter = 1.0`).

### Calibração visual

Com `Config.Debug = true`:

- `/mfuel_diag` mostra mão, animação, origem do tanque, offset/rotação e mangueira.
- `/mfuel_calibrate marker` liga/desliga o marker do ponto calculado do tanque.
- `/mfuel_calibrate hand x y z rx ry rz` ajusta o bico na mão em runtime.
- `/mfuel_calibrate tank x y z rx ry rz` ajusta o offset/rotação global no veículo.
- `/mfuel_calibrate model x y z rx ry rz` ajusta somente o modelo do veículo atual; use o hash/display impresso para copiar a exceção para `tankBoneOffsets` ou `tankOffsets`.
- `/mfuel_calibrate hose x y z` ajusta o ponto de conexão da mangueira no bico e recria a rope em runtime; copie o valor para `hoseNozzleOffset`.

Os ajustes são apenas em memória para calibração; depois copie os valores para `Config.Refuel`.

### Config.Payment

Controla o adapter de pagamento:

- `enabled`: quando `false`, não cobra.
- O pagamento depende de `mz_economy` e falha fechado quando a autoridade financeira não está disponível.
- `accountAliases`: mapeia nomes como `cash` para contas reais do `mz_economy`, como `wallet`.

O client nunca define preço final confiável. O server recalcula com `Config.Refuel.pricePerLiter`.

### Config.JerryCan

Controla galão de combustível:

- `enabled`: habilita/desabilita o fluxo.
- `item`: arma visual/conceitual, ex: `WEAPON_PETROLCAN`.
- `inventoryItem`: item real validado no inventário.
- `litersPerUse`: litros adicionados por uso.
- `useTimeMs`: tempo da ação.
- `maxDistance`: distância máxima do veículo.
- `consumeItem`: remove item apenas quando o uso termina com sucesso.
- `requireOutsideVehicle`: exige jogador fora do veículo.
- `authorizedCreditTtlMs`: TTL do crédito autorizado do galão.
- `allowWithoutInventory`: fallback de teste. Em produção deve ficar `false`.

### Config.Interaction

Controla a camada de interação:

```lua
Config.Interaction = {
  mode = 'auto', -- 'auto', 'target', 'interact', 'marker', 'none'
  prefer = 'target',
  fallbackMarker = true
}
```

Prioridade real:

1. `mz_target` em cada prop de bomba (`AddTargetModel`) e no veículo (`AddGlobalVehicle`).
2. `mz_interact`, com um ponto dinâmico apenas na bomba mais próxima.
3. Marker próprio pequeno na bomba e tecla contextual E/H.

Com `mode = 'marker'`, somente marker é usado. Com `mode = 'none'`, nenhuma interação é criada. Com `physical = false`, o comportamento legado de posto no marker é preservado.

### Config.Notify

Controla feedback visual:

- `enabled`: liga/desliga camada visual.
- `resource`: resource preferencial, padrão `mz_notify`.
- `fallback`: usa notificação nativa quando `mz_notify` não está iniciado.
- `messages`: textos usados para início, fim, cancelamento e erros.

Essa camada não altera fuel, não calcula pagamento e não persiste nada.

### Config.Stations

Controla postos:

- `enabled`: liga/desliga postos.
- `blips`: sprite, cor, escala e nome.
- `marker`: tipo, raio, distância de desenho e cor.
- `locations`: lista de coordenadas `vec3`.

### Config.ConsumptionByClass

Multiplicadores de consumo por classe GTA. Classe `13` representa bicicletas e fica com `0.0`.

## Exports client

```lua
exports['mz_fuel']:GetFuel(vehicle)
exports['mz_fuel']:SetFuel(vehicle, amount)
exports['mz_fuel']:AddFuel(vehicle, amount)
exports['mz_fuel']:RemoveFuel(vehicle, amount)
exports['mz_fuel']:CanUseJerryCan(vehicle)
exports['mz_fuel']:IsUsingJerryCan()
```

Também existem exports auxiliares usados pela interação:

```lua
exports['mz_fuel']:IsRefueling()
exports['mz_fuel']:CanRefuel(vehicle)
exports['mz_fuel']:GetNearestStation()
```

## Exports server

```lua
exports['mz_fuel']:SaveFuelByPlate(plate, fuel)
exports['mz_fuel']:GetCachedFuelByPlate(plate)
```

## Eventos principais

### Persistência e sync

- `mz_fuel:server:saveFuel`
- `mz_fuel:client:setFuel`
- `mz_fuel:client:syncFuel`

### Postos

- `mz_fuel:server:payRefuel`
- `mz_fuel:server:claimPump`
- `mz_fuel:server:releasePump`
- `mz_fuel:server:endRefuel`
- `mz_fuel:client:pumpClaimResult`
- `mz_fuel:client:interactPump`
- `mz_fuel:client:startRefuel`
- `mz_fuel:client:stopRefuel`
- `mz_fuel:client:openRefuelMenu`
- `mz_fuel:client:closeRefuelMenu`

### Galão

- `mz_fuel:client:useJerryCan`
- `mz_fuel:server:authorizeJerryCan`
- `mz_fuel:server:finishJerryCan`

## Segurança

- Fuel sempre é normalizado entre `0` e `100`.
- O abastecimento é entity-first: a entidade real do veículo é a fonte de verdade; placa, proprietário e registro no banco não são requisitos.
- Veículos NPC, alugados, importados e sem registro em `mz_vehicles` podem ser abastecidos normalmente.
- `netId` é usado apenas para correlacionar a entidade de rede/sessão quando disponível; não é identidade persistente.
- Placa é metadado auxiliar normalizado com trim e upper quando existir.
- Persistência é opcional: se a placa existir em `mz_vehicles`, o save usa o owner existente; caso contrário, o client atualiza somente o fuel da entidade.
- Aumento de fuel persistido precisa de crédito pago/autorizado. A sessão usa `vehicle_key`/`session_key`, não a placa.
- Crédito pago de posto e crédito autorizado de galão possuem TTL.
- Server recalcula preço e litros autorizados e valida bomba/sessão/distância.
- NUI envia apenas intenção: `fill`, `money` ou `liters`.
- Bicicletas/classe `13` não consomem e não abastecem.
- Pagamento sem `mz_economy` é sempre bloqueado.

## Integração com mz_garagem

Ao spawnar/retirar:

```lua
if GetResourceState('mz_fuel') == 'started' then
  exports['mz_fuel']:SetFuel(vehicle, fuel)
end
```

Ao guardar:

```lua
local fuel = GetVehicleFuelLevel(vehicle)
if GetResourceState('mz_fuel') == 'started' then
  fuel = exports['mz_fuel']:GetFuel(vehicle)
end
```

A garagem deve enviar o fuel junto com engine/body para persistência já existente.

## Checklist de testes in-game

- Consumo: dirigir como motorista e confirmar queda gradual do fuel.
- Persistência: mudar fuel, aguardar save e reiniciar/respawnar veículo.
- Garagem: retirar, consumir, guardar e retirar novamente.
- Físico: mirar na bomba com `ALT`, pegar o bico, confirmar prop na mão e mangueira.
- Físico: encaixar no `petrolcap` (ou fallback configurado), abrir menu e abastecer.
- Físico: confirmar que o bico acompanha o veículo quando ele se move lentamente.
- Físico: devolver o bico e confirmar que prop, rope e lock são limpos.
- Físico: dois jogadores na mesma bomba/veículo; o segundo deve ser recusado.
- Físico: afastar, entrar no veículo, morrer, deletar veículo e reiniciar resource.
- Menu: completar tanque, valor em R$, litros e cancelar.
- Pagamento: confirmar desconto por tick e bloqueio sem dinheiro.
- Galão: habilitar `Config.JerryCan.enabled`, usar item perto de veículo válido.
- mz_target: iniciar/parar o resource e confirmar re-registro/limpeza.
- mz_interact: sem `mz_target`, confirmar ponto dinâmico por bomba.
- Marker: sem target/interact, confirmar marker pequeno e tecla E/H.
- Debug: com `Config.Debug=true`, usar `/mfuel_diag` para bomba, veículo, bone, offset, sessão e motivo de cancelamento.
- Debug com ACE: habilitar comandos e testar `/mfuel_get`, `/mfuel_set`, `/mfuel_refill`.

## Troubleshooting

### Fuel não salva

- Confira se `mz_vehicles` está iniciado e `IsVehicleDomainReady` retorna sucesso.
- Confira se `Config.SaveIntervalMs` não está atrasando o save por throttle.
- Veja se a placa está chegando normalizada e se o veículo pertence/acessa o player.
- Para aumento de fuel vindo do client, confirme que houve crédito pago/autorizado.

### Fuel volta para 100

- Confira se a garagem está aplicando `exports['mz_fuel']:SetFuel(vehicle, fuel)` ao spawnar.
- Confira se o banco possui fuel salvo para a placa.
- Veja se `DefaultFuel` está sendo usado por ausência de dado persistido.

### Dinheiro não desconta

- Confira `Config.Payment.enabled`.
- Confira `Config.Refuel.pricePerLiter`.
- Confira `Config.Refuel.paymentAccount` e `Config.Payment.accountAliases`.
- Confirme se `mz_economy` expõe `GetMoney` e `RemoveMoney`.

### Menu não abre

- Confira `Config.Refuel.useMenu = true`.
- Confira se o player está perto de um posto configurado.
- Confira se o veículo é válido, não é bicicleta e não está cheio.
- Confira `Config.Refuel.allowInsideVehicle`, `Config.Refuel.requireDriver` e `Config.Refuel.physical`.

### NUI fica presa

- Use o callback `cancel`/ESC.
- Reinicie o resource `mz_fuel`; o `onResourceStop` remove foco.
- Verifique erros no console do client envolvendo `web/script.js`.

### Marker não aparece

- Confira `Config.Stations.enabled`.
- Confira `Config.Interaction.mode`.
- Se `mode = 'none'`, nenhum ponto é criado.
- Se `mode = 'auto'` com `mz_target` ativo, ele tem prioridade e o marker próprio não aparece.

### mz_interact não cria ponto

- Confira se `mz_interact` está `started`.
- Confira se o resource expõe `AddPoint` e `RemovePoint`.
- Use `Config.Interaction.mode = 'marker'` para testar o fallback próprio.

### Galão não funciona

- Confira `Config.JerryCan.enabled`.
- Confira se `Config.JerryCan.inventoryItem` existe no inventário.
- Confira se o item é usável no `mz_core`.
- Se `consumeItem = true`, confirme que `RemovePlayerItem` existe.
- Em produção, mantenha `allowWithoutInventory = false`.

### Comando debug não funciona

- Confira `Config.DebugCommands = true`.
- Confira a ACE:

```cfg
add_ace group.mz_owner mz_fuel.debug allow
```

- Confira se o jogador está no grupo correto.

### Pagamento bloqueado por Config.Payment

- Se `mz_economy` não estiver iniciado, o abastecimento pago é bloqueado sem fallback gratuito.
- Para produção, mantenha o fallback bloqueado.

## Status v1.0.0-dev/stable

- Fase 1: consumo, StateBag, native fuel e persistência.
- Fase 2: postos, pagamento server-side e hardening anti-exploit.
- Fase 3A: galão opcional com crédito autorizado.
- Fase 3B: feedback visual simples.
- Fase 3C: adapter real para `mz_interact` e fallback marker.
- Fase 3D: UI simples de abastecimento com sessões server-side.

## Pendências pós-1.0

- Validar em runtime FiveM os modelos de bomba, o bone `petrolcap` e os offsets de tanque em veículos importados/motos.
- Ajustar `nozzleHandOffset`/`nozzleHandRotation` e `nozzleVehicleOffset` visualmente se o prop não encostar perfeitamente na mão/tanque.
- Validar o rope/hose em builds e configurações de CEF/streaming diferentes.
- UI mais rica somente se necessário.
- Logs formais no `mz_core`, caso o core exponha export público.
- Metadata de galão parcial no inventário, se o inventário suportar capacidade por item.
