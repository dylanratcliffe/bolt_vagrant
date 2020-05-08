
# bolt_vagrant

This module provides a custom bolt inventory plugin for Vagrant. This allows you to run Bolt from your Vagrant directory and the have the inventory automatically populated from Vagrant.

## Usage

Configure the Bolt `inventory.yaml` to use the plugin as follows:

```yaml
version: 2

targets:
  - _plugin: task
    task: bolt_vagrant::targets
```

See the [Bolt documentation](https://puppet.com/docs/bolt/latest/inventory_file_v2.html) for more info.

## Parameters

```yaml
version: 2

targets:
  - _plugin: task
    task: bolt_vagrant::targets
    parameters:
      vagrant_dir: /Users/dylan/git/bolt_project_dir
      winrm_regex: win
```

**`vagrant_dir`:** The location of the Vagrant directory, defaults to `cwd`

**`winrm_regex`:** A regular expression used to determine which machines should be connected to using winrm. Unfortunately Vagrant doesn't give that information out at the command line and there is no way of working it out. This regex is passed to `Regexp.new()` as a string. Running the `targets.rb` file manually will provide debugging info.

**`match`:** A regular expression used to determine which machines should be returned in the inventory. This regex is passed to `Regexp.new()` as a string.
