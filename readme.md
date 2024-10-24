# Gambit

## Overview

Gambit is an addon that allows you to define data-driven, customizable, scripted action sequences for use in FFXI.



## Settings

TBD



## Actions

*Actions* are used to control the steps that are taken when a given condition is met. The most important components of an action are the condition (driven via the `when` clause) and a set of commands that will be executed when the condition is met (the `commands` array).

Gambit uses an *action cycle* of 2 Hz (twice per second). In each cycle, Gambit will run down the list of actions  in order until it finds one whose `when` condition is satisfied. It will then execute the associated commands and end the current cycle. If no conditions are met, the cycle will end without any commands being executed.

Actions live in the following folder under the Gambit addon directory:

```bash
./settings/<character-name>/actions
```

By default, an action file named after your current job/sub job will be loaded. If you are signed in as a RDM50/BLM25 named Shrek, then actions would be loaded from:

```
./settings/Shrek/actions/rdm-blm.json
```

If no matching actions file can be found, default values will be loaded and saved. The default actions file is defined in the following location:

```
./settings/.lib/default-actions.json
```



#### Action Categories

Gambit actually supports three distinct *action categories*, and only actions within the current category will be evaluated in a given action cycle. The three categories are as follows:

- **Idle** - These are actions that will be performed when outside of battle. This could be used to recast buffs, remove status ailments, cycle Trusts, or allow for recovery of MP.
- **Pull** - These are actions that will be performed when no *Idle* actions remain and a mob is ready to be pulled. This could be used to move into position, or use a pulling spell/ability.
- **Battle** - These are actions that are executed in the heat of battle. Note that you will always transition out of idle/pull into battle if you get aggro.

In JSON, each of these categories is defined as an array of actions. The top-level definition would look like the following:

```json
{
    "idle": [],
    "pull": [],
    "battle": []
}
```



#### Action Definition

Now that we understand the concept of action categories and how they are separated out, let's look at how to actually define an action.

Let's start with a very basic action to cast the black magic spell *Fire* on the enemy.

``````json
{
    "when": "canUseSpell('Fire')",
    "commands": "useSpell()"
}
``````

In plain English, this action says:

> When I'm able to use the spell Fire, use it.

That's pretty straightforward. If you have this action defined in your *battle* action category, Fire will be cast continuously on the enemy until the battle is over.

As straightforward as this is, it may not be incredibly useful on its own. We'll just be casting Fire as often as the recast timers allow and will probably burn through our MP rather quickly (pun sort of intended). Let's space it out so we use the spell at most once every 10 seconds.

``````json
{
    "when": "canUseSpell('Fire')",
    "commands": "useSpell()",
    "frequency": 10
}
``````

The above is all fine and good, but we're RDM50 now and we want to start using Fire II instead. Once option is to just edit the condition to use Fire II, but we could actually turn it into something that's less level dependent:

``````json
{
    "when": "canUseSpell('Fire II', 'Fire')",
    "commands": "useSpell()",
    "frequency": 10
}
``````

The *canUseSpell* function actually allows us to specify any number of spells. It will stop at the first one it finds that is useable. In plain English, the above action says:

> Every 10 seconds, use Fire II on the enemy if available; otherwise, use Fire if that's available instead.

We can also change tack a bit here -- what if we want to cycle through several tier-2 black magic nuking spells, rather than just blasting with fire?



``````json
{
    "when": "canUseSpell(randomize('Thunder II', 'Blizzard II', 'Fire II'))",
    "commands": "useSpell()",
    "frequency": 10
}
``````

The *randomize* function picks a random item from the provided list and uses that. In plain English, the above action says:

> Every 10 seconds, pick a random spell from Thunder II, Blizzard II, or Fire II. If we're able to use it, cast it on the enemy.

The *action functions* section below will go into detail on all of the various tools available to you for crafting your perfect set of actions. Similarly, the *action library* section will cover some of the pre-defined actions that are ready for you to easily pull into your action set.

Here's the full list of fields you can apply to an action:

- **when** - The condition under which the action will be triggered.
- **commands** - The set of commands to execute if the *when* condition is met. This can be either a string (single command) or an array (multiple commands).
- **comment** - Optional. This is human-readable string that can be used to help describe what the action is doing.
- **delay** - Optional. This controls how long you must be in the current *action category* before this action is allowed to execute. For example, a *delay* value of 5 on our nuking action above would cause us to wait 5 seconds before starting to cast.
- **disabled** - Optional. This allows you to turn off the current action without deleting it.
- **import** - Optional. This allows you to pull in externally defined actions. Those actions will be inserted in place of the importing action. An **import** directive causes all other action properties to be ignored, with the exception of **disable** (which will cause the import to be skipped).
- **frequency** - Optional. The maximum frequency, in seconds, that this action is allowed to trigger. If omitted, it will be executed as often as the condition is met -- assuming no higher priority conditions are triggered first! 



#### Action Properties

The following properties are available for use in your actions, broken down by category.

##### Targets

These represent targetable mobs, players, and trusts on the map.

- `t`, `bt` - The current battle target. This is *not* necessarily the same as your current target `<t>` in-game. It is also not necessarily the same as your `<bt>` target, as it will be set prior to entering battle for use in idle/pull actions as well. If no target has been selected, it will be nil. Otherwise, each of the following properties will be available to you:
  - `name` - The mob display name.
  - `hpp` - The mob's remaining HP, expressed as a percent from 0 - 100.
  - `id` - The internal FFXI identifier for this mob.
  - `index` - The internal index within the zone for this mob (commonly known, somewhat misleadingly, as the "hex id").
  - `distance` - The distance between you and the mob. For those familiar with the Windower 4 Lua interface, this is the actual distance and not the distance squared.
  - `x`, `y`, `z` - The 3D position of the mob on the map.
- `p0`, `p1`, `p2`, `p3`, `p4`, `p5` - Members of your party, or nil if there is no party member in a given slot. All properties on `t` and `bt` above are available here, in addition to the following:
  - `hp`, `mp` - The party member's actual remaining HP and MP values.
  - `mpp` - The party member's remaining MP, expressed as a percent from 0 - 100.
  - `tp` - The party member's TP.
  - `isTrust` - Determine if this party member is a Trust.
  - `isPlayer` - Determine if this party member is a player.
- `a10 - a15`, `a20 - a25` - When in an alliance, these represent all members in alliance 1 (`a1`) and alliance 2 (`a2`). All of the properties available for party members also apply to alliance members.
- `me` - This represents yourself. All properties available to party members apply here, in addition to the following:
  - `max_hp`, `max_mp` - Your actual maximum HP and MP values.
  - `main_job`, `sub_job` - The three-letter shorthand name of your main job and sub job (if any).
  - `main_job_level`, `sub_job_level` - The level of your main job and sub job (if any).
  - `level` - Same as `main_job_level`, with less typing required.



##### Contextual

Contextual variables are those which are set when certain conditions are met, allowing them to be referenced more easily later on. They would typically be set in the `when`  clause and used in the `commands` list, but that's not strictly required.

- `ability` -  When `canUseAbility` finds a match (or when `canUse` matches on an ability), this will be set to the ability that triggered the match.
- `item` -  When `canUseItem` finds a match (or when `canUse` matches on an item), this will be set to the item that triggered the match.
- `spell` - When `canUseSpell` finds a match (or when `canUse` matches on a spell), this will be set to the spell that triggered the match.



#### Action Functions

The following functions are available for use in your actions. 

##### Abilities

- `canUseAbility(name1, name2, ... , nameN)` - Results in the first usable ability from the list of provided abilities that is ready to be used, or nil if none are usable. Typically used in the `when` condition to determine if an ability can be used. The match will be saved to the context as a variable named `ability`, and subsequent calls to `useAbility` without an ability name will use this instead.
  - Will not trigger if you are asleep or suffering from amnesia.
- `useAbility(target, ability)` - Use an ability on the specified target. If no target is specified, the current battle target will be used instead. If no ability is specified, the result of the most recent `canUseAbility` will be used.

##### Items

- `canUseItem(name1, name2, ... , nameN)` - Results in the first usable item from the list of provided items that is ready to be used, or nil if none are usable. Typically used in the `when` condition to determine if an item can be used. The match will be saved to the context as a variable named `item`, and subsequent calls to `useItem` without an ability name will use this instead. 
  - Can be used with enchanted equipment, though it **does not** take item activation timers into account (i.e. the five second countdown after equipping a Capacity Ring). It **does** take into account reuse timers  (i.e. the two hour cooldown after using a Capacity Ring).
  - Can be used with food, and it will not trigger if you're already fed.
  - Will not trigger if you are asleep.
- `useAbility(target, ability)` - Use an ability on the specified target. If no target is specified, the current battle target will be used instead. If no ability is specified, the result of the most recent `canUseAbility` will be used.

##### Spells

- `canUseSpell(name1, name2, ... , nameN)` - Results in the first usable spell from the list of provided spells that is ready to be used, or nil if none are usable. Typically used in the `when` condition to determine if a spell can be used. The match will be saved to the context as a variable named `spell`, and subsequent calls to `useSpell` without a spell name will use this instead.
  - Will not trigger if you are asleep or silenced.
- `useSpell(target, spell)` - Use a spell on the specified target. If no target is specified, the current battle target will be used instead. If no spell is specified, the result of the most recent `canUseSpell` will be used.

**Abilities, Items, and Spells Combined**

Sometimes, you may find yourself wanting to use the best option spanning spells, abilities, and items rather than limiting yourself to just one type. 

For example, let's say you want to pick the best healing option between the various Curing Waltz abilities and Cure spells. You can actually ask Gambit to figure that all out for you by omitting the category entirely from the *canUse* and *use* functions.

- `canUse(name1, name2, ... , nameN)` - Similar to `canUseAbility`, `canUseItem`, and `canUseSpell`, but not limited to just one type. Finds the first usable entry from the list, and applies that to the context.
- `use(target, name)` - Use an ability, item, or spell on the specified target. If no target is specified, the current battle target will be used instead. If no ability is specified, the result of the most recent `canUse` will be used instead.

Here's an example