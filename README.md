# SVBuddy
##### The next generation of shitty sv tools
######
#### Ok... but why?
[My old tool](https://github.com/Palomarrrr/BezierSV) was nice but wasn't that great and not many tools that I've found run well on Linux.

... So I tried to make my own... To limited success
######
---
## Building
The GUI api for this tool is provided by [Capy](https://capy-ui.org/) and currently using the master branch

######
**Target Zig Version: zig `0.13.0`/ ([2024.5.0-mach](https://machengine.org/about/nominated-zig/))**
######
If you wish to run the app simply execute in the project directory
```sh
zig build run
```
######
To only build the app execute this instead
```sh
zig build
```
The executable file should be in the `./zig-out/bin/` directory
######
WebAssembly currently doesn't compile or work... I hope to fix this sometime in the future but for now it's not a priority
######
---
## Credits

##### Big thanks to...
- [gosumemory](https://github.com/l3lackShark/gosumemory/tree/master) and [cosutrainer](https://github.com/hwsmm/cosutrainer) for tips on how osu process reading!
