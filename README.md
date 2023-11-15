# Wally Fork of TopbarPlus by ForeverHD

https://github.com/1ForeverHD/TopbarPlus

## Latest 2.10

Main changes: 
- Updated meta files to work with wally: 
  - Changed `default.project.json` to match expected package behavior.
   - Added `wally.toml`. 
- Removed "Action Required" callout in favor of a documented `Icon.setVoiceChatEnabled()` function.


### Documentation
https://1foreverhd.github.io/TopbarPlus/

### Installation through Wally

Import via wally using 

```toml   
[dependencies]
Icon = "bebopdevelopmentstudios/topbarplus@2.10.0"
```

### Config

To offset the topbar to create space for the Roblox Voice Chat GUI, use 
```lua
Icon = require("path")

--  staticmethod
Icon.setVoiceChatEnabled(boolean) 

-- alternatively, you can directly access IconController
IconController = require(Icon.IconController)
IconController.voiceChatEnabled = boolean
```