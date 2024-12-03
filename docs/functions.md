# Action Functions

The following functions are available for use in your actions. They are broken down by broad category, and they can all be used in both the `when` condition or in the actual action `commands` -- though some may make more sense in one versus the other.



## Ability Functions

These functions are related to the use of job abilities.

- `canUseAbility(name1, name2, ... , nameN)` - Results in the first usable ability from the list of provided abilities that is ready to be used, or nil if none are usable. Typically used in the `when` condition to determine if an ability can be used. The match will be saved to the context symbol `ability`, and subsequent calls to `useAbility` without an ability name will use this instead.
  - Will not trigger if you are asleep or suffering from amnesia.
  - Abilities that use TP (such as DNC waltzes or sambas) will only trigger if the required TP is available.
  - <!-- Need to investigate job abilities that use finishing moves, pet commands, others? -->
- `useAbility(target, ability)` - Use an ability on the specified target. If no target is specified, the current battle target will be used instead. If no ability is specified, the result of the most recent `canUseAbility` will be used.



## Item Functions

These functions are related to the use of items.

- `canUseItem(name1, name2, ... , nameN)` - Results in the first usable item from the list of provided items that is ready to be used, or nil if none are usable. Typically used in the `when` condition to determine if an item can be used. The match will be saved to the context symbol `item`, and subsequent calls to `useItem` without an item name will use this instead. 
  - Can be used with enchanted equipment, though it **does not** take item activation timers into account (i.e. the five second countdown after equipping a Capacity Ring). It **does** take into account reuse timers  (i.e. the two hour cooldown after using a Capacity Ring).
  - Can be used with food, and it will not trigger if you're already fed.
  - Will not trigger if you are asleep.
- `useAbility(target, ability)` - Use an ability on the specified target. If no target is specified, the current battle target will be used instead. If no ability is specified, the result of the most recent `canUseAbility` will be used.



## Spell Functions

- `canUseSpell(name1, name2, ... , nameN)` - Results in the first usable spell from the list of provided spells that is ready to be used, or nil if none are usable. Typically used in the `when` condition to determine if a spell can be used. The match will be saved to the context symbol `spell`, and subsequent calls to `useSpell` without a spell name will use this instead.
  - Will not trigger if you are asleep or silenced.
  - Will not trigger if you have insufficient MP.
  - Will not trigger if the spell is not applied (BLU magic)
- `useSpell(target, spell)` - Use a spell on the specified target. If no target is specified, the current battle target will be used instead. If no spell is specified, the result of the most recent `canUseSpell` will be used.



## **Combined: Abilities, Items, and Spells**

Sometimes, you may find yourself wanting to use the best option spanning spells, abilities, and items rather than limiting yourself to just one type. 

For example, let's say you want to pick the best healing option between the various Curing Waltz abilities and Cure spells. You can actually ask Gambit to figure that all out for you by omitting the category entirely from the *canUse* and *use* functions.

- `canUse(name1, name2, ... , nameN)` - Similar to `canUseAbility`, `canUseItem`, and `canUseSpell`, but not limited to just one type. Finds the first usable entry from the list, and applies that to the context.
- `use(target, name)` - Use an ability, item, or spell on the specified target. If no target is specified, the current battle target will be used instead. If no ability is specified, the result of the most recent `canUse` will be used instead.

Here's an example:

```json
{
    "when": "me.hpp < 50 and canUse('Curing Waltz IV', 'Cure IV', 'Curing Waltz III')",
    "commands": "use(me)"
}
```

In plain English, this says:

> When my HP is below 50%, use the best available of Curing Waltz IV, Cure IV, or Curing Waltz III



## Buffs, Debuffs, and Effects

- `hasEffect(effect1, effect2, ... , effectN)` - Determine which (if any) effects are currently applied to you. The match will be saved to the context as a variable named `effect`.
  - This is aliased as `hasBuff`, and the two can be used interchangeably. 
- `hasEffectOf(name1, name2, ... , nameN)` - Similar to `hasEffect`, but allows you to specify the spell or ability that *causes* the effect rather than the effect itself. For example, you can call this with `Dream Flower` and it will detect if you are asleep. If matched, the resulting effect will be stored to the `effect` variable.

Here's an example:

```json
{
    "when": "hasEffectOf('Silence') and canUse('Healing Waltz', 'Echo Drops')",
    "commands": "use(me)"
}
```

In plain English, this says:

> If I'm silenced, remove it with Healing Waltz (first choice) or some Echo Drops.