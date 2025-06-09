Return to the [main documentation page](../readme.md).

# Actions

*Actions* are used to control the steps that are taken when a given condition is met. The most important components of an action are the condition (driven via the `when` clause) and a set of commands that will be executed when the condition is met (the `commands` array).

Gambit uses an *action cycle* of 2 Hz (twice per second). In each cycle, Gambit will run down the list of actions  in order until it finds one whose `when` condition is satisfied. It will then execute the associated commands and end the current cycle. If no conditions are met, the cycle will end without any commands being executed.

## The Basics

In order to use actions, a very basic understanding of [JSON](https://www.w3schools.com/whatis/whatis_json.asp) and [Lua](https://www.lua.org/about.html) would be helpful but not required. JSON is used to define the overall structure, and *very* simplified Lua expressions are used to drive your conditional triggers (`when`) and corresponding `commands`. 

The important parts of Lua to understand are [functions](https://www.lua.org/pil/5.html) and [logical operators](https://www.lua.org/pil/3.3.html), but you will *probably* have a more pleasant learning experience by viewing and modifying examples than by reading language docs.

I recommend downloading a free code editor like [Visual Studio Code](https://code.visualstudio.com/download) (preferred) or [Notepad++](https://notepad-plus-plus.org/downloads/) (also great).

Actions sets are defined using JSON files under the Gambit addon directory:

```bash
./settings/<character-name>/actions
```

By default, an action file named after your current job/sub job will be loaded. If you are a RDM50/BLM25 named Shrek, then actions would be loaded from:

```
./settings/Shrek/actions/rdm-blm.json
```

If a job/sub job file cannot be found, a file named for your current main job will be loaded instead. This is actually the way Gambit generates new action files for you when running`//gbt actions -save-default`.

```
./settings/Shrek/actions/rdm.json
```

If no matching actions file can be found, default values will be loaded. The default actions file is defined in the following location:

```
./actions/defaults/default-actions.json
```

I don't recommend editing the default actions, but if you do so just be sure to back up your changes in case they get overwritten by a version update.

## Anatomy of an Action

As mentioned above, actions are defined in JSON and use Lua to determine `when` they should trigger and how they should behave (`commands`).

A ~~picture~~ *example* is worth a thousand words, so why not start there. Let's say we want an action that will nuke our target mob with the black magic spell *Fire*.

``````json
{
    "when": "canUseSpell('Fire')",
    "commands": "useSpell()"
}
``````

In plain English, this action says:

> When I'm able to use Fire, use it.

That's pretty straightforward. This will cause you to nuke with Fire as fast as your recast timers allow, until the battle is over.

As straightforward as this is, it may not be incredibly useful on its own. For one thing, we'll probably burn through MP rather quickly (pun sort of intended). To address this, we'll add a `frequency` setting to ensure we use the spell at most once every 10 seconds.

``````json
{
    "when": "canUseSpell('Fire')",
    "commands": "useSpell()",
    "frequency": 10
}
``````

The above is all fine and good, but we're RDM50 now and we want to start using Fire II instead. One option is to just edit the `when` part to use Fire II, but we could actually turn this into something that's more flexible:

``````json
{
    "when": "canUseSpell('Fire II', 'Fire')",
    "commands": "useSpell()",
    "frequency": 10
}
``````

This demonstrates that the *canUseSpell* function actually allows us to specify any number of spells. It will go through the list, stopping at the first one that is usable at the time it's checked.

In plain English, the above action says:

> Every 10 seconds, use the best available of Fire II or Fire on the enemy.

We can also change tack a bit here -- what if we want to cycle through several tier-2 black magic nuking spells, rather than just blasting with fire?



``````json
{
    "when": "canUseSpell(randomize('Thunder II', 'Blizzard II', 'Fire II'))",
    "commands": "useSpell()",
    "frequency": 10
}
``````

The *randomize* function just randomizes the list so that it's not always in the same order. This causes *canUseSpell* to find the first usable spell from a randomized list rather than a fixed one.

In plain English, this new action says:

> Every 10 seconds, pick a random spell from Thunder II, Blizzard II, or Fire II, and cast that on the enemy.

The [action functions](./functions.md) section goes into detail on all of the various functions available to you for use in actions. Similarly, the [action library](./action-library.md) section will cover some of the pre-defined actions that are ready for you to use out of the box.

We've seen `when`, `commands`, and `frequency` in use so far. Here's the full list of properties you can make use of in your actions:

- **when** - The condition(s) under which the action will be triggered. This can either be a string (as you've seen), or an array of strings that are internally AND'ed together when determining if the conditions have been met. For example, the following "when" specifications mean the exact same thing (though the latter might be considered more readable as the number of conditions grows).

```json
"when": "me.hpp > 20 and canUseSpell('Fire II')"
```

```json
"when": [
    "me.hpp > 20", 
    "canUseSpell('Fire II')"
]
```

- **commands** - The set of commands to execute if the *when* condition is met. This can be either a string (single command) or an array (multiple commands).

- **comment** - *Optional* This is human-readable text that can be used to help describe what the action is doing.

- **delay** - *Optional* This is a number controls how long you must be in the current *action category* (see below) before this action is allowed to execute. For example, a *delay* value of 5 on our nuking action above would cause us to wait 5 seconds before starting to cast.

- **disabled** - *Optional* This Boolean (true or false) value allows you to turn off the current action without deleting it.

- **frequency** - *Optional* This is a number that sets the maximum frequency, in seconds, at which this action is allowed to trigger. If omitted, it will be executed as often as the condition is met -- assuming no higher priority actions are triggered first! 

  Note that the special string value `infinity` (or `inf` for short) can be used to specify that an action can only be executed once within the given scope.

- **import** - *Optional* This allows you to pull in externally defined actions. Those actions will be inserted in place of the importing action. An **import** directive causes all other action properties to be ignored, with the exception of **disable** (which will cause the import to be skipped).

- **scope** - *Optional* This allows you to control how the `frequency` value is evaluated. By default, the global scope is used and frequency is applied literally. However, if you specify a scope if `battle`, then frequency tracking is cleared once you become disengaged. For example, if you specify a frequency of 30 without a scope, the action will have no chance of executing until 30 seconds has elapsed; however, with a scope of `battle` the action *could* execute sooner if you acquire a new target. A scope of `battle` with a frequency of `infinite` allows you to specify once-per-battle actions.

   

## Action Categories

We've looked at an action example above, but that may not make sense in all situations. You're not *always* in battle, and there are often things you'd like to do between fights. 

Gambit allows you to define distinct, independent actions based on current conditions. There are five categories available you:

- **battle** - These are actions that are executed in the heat of battle. Note that you will always transition out of idle/pull into battle if a mob is aggroing you or a party member.
- **dead** - These are actions that will be performed in the unfortunate event of your death. You could send a tell to your bestie to give you a rez, or return to your home point.
- **idle** - These are actions that will be performed when outside of battle. This could be used to recast buffs, remove status ailments, cycle Trusts, or allow for recovery of MP.
- **idle_battle** - These are actions that can only be executed while using the `manual` targeting strategy. These will be fired when you are disengaged (idle) but your party leader has acquired a battle target.
- **mounted** - These are actions that will be performed when you are riding a mount (rented chocobos or personal mounts).
- **pull** - These are actions that will be performed when no *Idle* actions remain and a mob is ready to be pulled. This could be used to move into position, or use a pulling spell/ability.
- **resting** - These are actions that will be performed when you are resting (i.e. "taking a knee"). This could be used to trigger standing up when HP or MP has recovered to a certain point.

In JSON, each of these categories is defined as an array of actions. The top-level definition would look like the following:

```json
{
    "idle": [],
    "pull": [],
    "battle": [],
    "idle_battle": [],
    "mounted": [],
    "resting": [],
    "dead": []
}
```

The nuking action we described above would make the most sense under the *battle* category.



Return to the [main documentation page](../readme.md).