| Tip                                                          |
| ------------------------------------------------------------ |
| *Shift+Alt+G* on the keyboard will toggle automation on or off. |



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

#### **verbosity -level {normal|verbose|debug|trace}**

Controls the chat log output level. Gambit will only show output that is at or below the configured level. Valid values for *verbosity* are as follows:

- ```normal``` - Minimal output. You don't want to see much at all.
- ```verbose``` - More detailed output, helping you track what the addon is doing. This is the default, and is generally recommended.
- ```debug``` - This starts to get noisy. This mode can be helpful if you're an addon developer, or if you're having trouble understanding what your actions are doing. This can be like drinking from a fire hose.
- ```trace``` - This is the highest level of output. Think of it as similar to `debug`, but . Every triggered action is written to the chat. This can be like drinking from a fire hydrant. 

## Settings

TBD
