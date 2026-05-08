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

Observação: o `fxmanifest.lua` declara apenas `mz_core` como dependência dura porque `mz_fuel` deve iniciar antes da garagem para que a garagem consiga usar os exports de fuel. `mz_vehicles` e `mz_garagem` continuam obrigatórios no fluxo completo do ecossistema.

## Dependências opcionais

- `mz_interact`: usado como camada de interação quando iniciado e quando `Config.Interaction` permite.
- `mz_notify`: usado para notificações/progresso quando iniciado.
- `mz_target`: atualmente não possui API pública compatível para registrar pontos externos. O adapter detecta isso e cai para `mz_interact` ou marker.

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
- `paymentAccount`: conta usada no `mz_core`, normalmente `cash` ou `bank`.
- `tickMs`: intervalo do abastecimento progressivo.
- `litersPerTick`: litros por tick.
- `maxDistance`: distância máxima do posto.
- `paidCreditTtlMs`: tempo máximo do crédito pago.
- `requireDriver`: exige motorista no banco.
- `allowInsideVehicle`: permite iniciar dentro do veículo.
- `saveOnComplete`: salva ao terminar/cancelar quando necessário.
- `useMenu`: usa a UI simples de abastecimento.
- `menuMode`: modo do menu, atualmente `simple`.
- `maxLitersPerRequest`: limite máximo por pedido do menu.
- `allowFillTank`: permite completar tanque.
- `allowMoneyAmount`: permite abastecer por valor.
- `allowLiterAmount`: permite abastecer por litros.

### Config.Payment

Controla o adapter de pagamento:

- `enabled`: quando `false`, não cobra.
- `allowFallbackWithoutMzCore`: fallback de teste sem `mz_core`. Em produção deve ficar `false`.
- `accountAliases`: mapeia nomes como `cash` para contas reais do `mz_core`, como `wallet`.

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

1. `mz_target`, se um dia expuser API pública compatível.
2. `mz_interact`, via `exports['mz_interact']:AddPoint`.
3. Marker próprio do `mz_fuel`.

Com `mode = 'marker'`, somente marker é usado. Com `mode = 'none'`, nenhuma interação é criada.

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
- Placa é normalizada com trim e upper antes de salvar.
- Save vindo do client valida `source`, placa, fuel, net id quando disponível e permissão do veículo quando `mz_core` expõe acesso.
- Aumento de fuel vindo do client precisa de crédito pago/autorizado.
- Crédito pago de posto e crédito autorizado de galão possuem TTL.
- Server recalcula preço e litros autorizados.
- NUI envia apenas intenção: `fill`, `money` ou `liters`.
- Bicicletas/classe `13` não consomem e não abastecem.
- Pagamento fallback sem `mz_core` fica bloqueado por padrão.

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
- Posto com menu: `Config.Refuel.useMenu = true`, testar completar, dinheiro, litros e cancelar.
- Posto sem menu: `Config.Refuel.useMenu = false`, testar abastecimento direto.
- Pagamento: confirmar desconto por tick.
- Sem dinheiro: iniciar abastecimento e confirmar cancelamento sem tick grátis.
- Galão: habilitar `Config.JerryCan.enabled`, usar item perto de veículo válido.
- Cancelamentos: afastar, morrer, deletar veículo, sair do banco do motorista.
- mz_interact: iniciar com `mz_interact` started e confirmar pontos sem marker duplicado.
- Fallback marker: parar `mz_interact` e confirmar marker próprio.
- Debug com ACE: habilitar comandos e testar `/mfuel_get`, `/mfuel_set`, `/mfuel_refill`.
- Debug sem ACE: confirmar comandos bloqueados.

## Troubleshooting

### Fuel não salva

- Confira se `mz_core` está iniciado.
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
- Confirme se `mz_core` expõe `GetMoney` e `RemoveMoney`.

### Menu não abre

- Confira `Config.Refuel.useMenu = true`.
- Confira se o player está perto de um posto configurado.
- Confira se o veículo é válido, não é bicicleta e não está cheio.
- Confira `Config.Refuel.allowInsideVehicle` e `Config.Refuel.requireDriver`.

### NUI fica presa

- Use o callback `cancel`/ESC.
- Reinicie o resource `mz_fuel`; o `onResourceStop` remove foco.
- Verifique erros no console do client envolvendo `web/script.js`.

### Marker não aparece

- Confira `Config.Stations.enabled`.
- Confira `Config.Interaction.mode`.
- Se `mode = 'none'`, nenhum ponto é criado.
- Se `mode = 'auto'` com `mz_interact` ativo, o marker próprio não aparece para evitar duplicidade.

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

- Se `mz_core` não estiver iniciado e `allowFallbackWithoutMzCore = false`, o abastecimento é bloqueado.
- Para teste local controlado, habilite `allowFallbackWithoutMzCore = true`.
- Para produção, mantenha o fallback bloqueado.

## Status v1.0.0-dev/stable

- Fase 1: consumo, StateBag, native fuel e persistência.
- Fase 2: postos, pagamento server-side e hardening anti-exploit.
- Fase 3A: galão opcional com crédito autorizado.
- Fase 3B: feedback visual simples.
- Fase 3C: adapter real para `mz_interact` e fallback marker.
- Fase 3D: UI simples de abastecimento com sessões server-side.

## Pendências pós-1.0

- API pública compatível no `mz_target` para pontos externos.
- UI mais rica somente se necessário.
- Logs formais no `mz_core`, caso o core exponha export público.
- Metadata de galão parcial no inventário, se o inventário suportar capacidade por item.
