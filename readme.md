| Tips                                                         |
| ------------------------------------------------------------ |
| *Shift+Alt+G* on the keyboard will toggle automation on or off. |
| *Ctrl+F* on the keyboard will toggle a custom "follow" operation on your current target. Hitting the hotkey again will cancel your follow. |

##### Documentation is a huge work in progress, and is quite lacking at this point. Sorry.

# Gambit

## Overview

Gambit is a Windower 4 addon that allows you to define data-driven, customizable, scripted action sequences for use in FFXI. It is used to automate all manner of operations within the game.

The automation documentation is broken down into several categories:

- Actions
  - [An introduction to actions](./docs/actions.md) - An overview of the basic action structure; how they are defined, how they are triggered, and how they are configured.
  - Libraries - Pre-defined actions ready for you to use
- Lua interface
  - [Action properties](./docs/properties.md) - An overview of the properties available for use in your action conditions and commands.
  - [Action functions](./docs/functions.md) - An overview of the functions available for use in your action conditions and commands. 



## The Basics

Once you've got the addon installed, it can be loaded in the standard way.

```bash
//lua r gambit
```

Doing so, it will show you some information including how to enable automation with the `Ctrl+Alt+G` hotkey. The same hotkey will disable automation again, and the addon will output information about its current enabled/disabled state as you change it.

The default actions will cause you to engage with any aggroing mob near you, and will use the best available XP or CP rings on hand.

If you want to *initiate* aggro, you can change the *targeting strategy* to "aggressor". As the name suggests, the aggressor strategy will pick the nearest mob and fight it. If you already have aggro, the aggroing mob will take priority. That is, Gambit won't engage with an idle mob while another one is coming for you.

To change the strategy to aggressor, run the following command:

```bash
//gbt config -strategy aggressor
```

So switch back, you can use the following:

```bash
//gbt config -strategy leader
```

The "leader" strategy (default) will have you engage whatever mob your party leader is engaged with. It's smart enough to detect if you *are* the party leader, and will instead fall back to the default "nearest aggroing mob" behavior.

By default, Gambit will only "see" mobs within 25 yalms of your position. You can set this to 50 (the max that FFXI allows) using the following command:

```bash
//gbt config -d 50
```

Any value between 5 and 50 (inclusive) is accepted; any other value will be clamped to this range.

Similarly, Gambit gives you the ability to control the maximum vertical ("Z") distance it will look for. This is useful on multi-leveled areas (think of Escha Ru'Aun) where you wouldn't want to try to attack something 20 yalms directly below you.

The default Z distance is 5.0 yalms, and it can be configured with the following command:

```bash
//gbt config -z 3
```

As you've likely already guessed, this will set the Z distance to 3 rather than the default 5.

The custom follow mentioned in the tips at the very top of this document has a few added benefits. Firstly, it will try to "jitter" itself out of corners if it detects that it's stuck. This isn't true pathfinding, but it will try to backup for a bit and course correct. This won't get you out of a maze, but it will get you around pillars or sharp corners.

The second thing that the custom follow will get you is a configurable follow distance. For example, if you run the following your follow will not get closer than 4 yalms from the target;

```bash
//gbt config -fd 4
```

Note that there will be some variation here while you're moving, as server latency can cause things to get out of sync. Once you're stationary, it will end up at roughly the distance you've set.

***Note:*** *One weird thing about this is that you won't actually follow your target out of the zone. Once they exit, you'd stop 4 yalms from the zone line (if going by the above example). This may or may not be desirable, and I'll consider ways to change this in the future.*

## Addon Commands

Gambit provides a handful of commands and hotkeys to help you configure the addon from within FFXI. These are broken down into what I call *user commands* (those intended to be used by you) and *system commands* (those intended to be used by the addon itself to manage its own state).

Windower addon commands can be executed directly via the FFXI chat. This is done by typing forward slashes, followed by the addon name (or alias), followed by the actual commands to send. For Gambit, this could look like the following:

```bash
//gambit verbosity -level verbose
```

This would set the addon's chat log output level to `verbose`, which is the highest level recommended for non-developers.

Gambit can be aliased as `gbt`, so the following command is equivalent to the one above:

```bash
//gbt verbosity -level verbose
```

For brevity, all commands listed below will omit the initial `//gambit` or `//gbt` part. Just keep in mind that these *are* required -- they are how Windower determines which addon to route the rest of the command to.



---

**Before we get into the actual commands,** I'll leave a few notes on how to read their description:

- Items in *[square brackets]* represent something that is optional.
- Items in *{curly braces}* represent a placeholder for something you must fill in.
- The vertical bar *|* can be thought of as "OR"; it separates a list of options that you can from.



### User Commands

#### **disable**

Disables automation. Has no effect if automation is already disabled. See also: `enable`, `toggle`

#### **enable**

Enables automation. Has no effect if automation is already enabled. See also: `disable`, `toggle`

#### **reload** [-settings-only] [-actions {action-name}]

Forces the addon to reload all settings and actions, resetting the action processing state. This *does not* affect whether automation is enabled.

- `-settings-only`, `-so` - Force the addon to reload settings but not actions. This is primarily useful if you've modified the settings file directly, and want to reload those without resetting the action state.
- `-actions {action-name}` - Perform a full reload, but load the specified action set rather than the default job-based one. This is completely ignored if you've asked for a settings-only reload.

#### **show**

Displays all of your configured settings in the chat log.

#### **toggle**

Toggle automation on or off. This is identical to running `enable` when disabled, or `disable` when enabled. Se also: `disable`, `enable`

> The `toggle` command is bound to the hotkey **Shift+Alt+G**

#### **verbosity -level {normal|verbose|comment|debug|trace}**

Controls the chat log output level. Gambit will only show output that is at or below the configured level. Valid values for *verbosity* are as follows:

- ```normal``` - Minimal output. You don't want to see much at all.
- ```verbose``` - More detailed output, helping you track what the addon is doing. This is the default, and is generally recommended.
- `comment` - This is similar to verbose, but it will include things that could be considered more informational and noisy.
- ```debug``` - This starts to get objectively noisy. This mode is mostly helpful if you're an addon developer, or if you're having trouble understanding what your actions are doing. This can be like drinking from a fire hose.
- ```trace``` - This is the highest level of output. Think of it as similar to `debug`, but every triggered action is written to the chat. This can be like drinking from a fire hydrant. 

## Settings

TBD
