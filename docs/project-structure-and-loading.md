# Project Structure And Loading

这份文档整理当前项目里已经验证通过的目录规范，以及 Teardown mod 在本项目中的脚本加载机制。

## 1. 当前结论

当前项目里，工具、地图、载具三类内容的加载方式并不一样。

已经验证通过的规则：

1. `main.xml` 是地图场景入口  
   游戏把当前 mod 当作地图加载时，会先读这个文件

2. 工具注册需要经过根目录 `main.lua`  
   直接让 `main.xml` 去加载深层工具脚本，工具栏会消失，工具也不会正常注册

3. 载具不需要在 `main.lua` 单独注册  
   载具依靠 `spawn.txt -> xml -> <script file="...">` 这条链路自己生效

所以目前最稳的方案是：
- 保留根目录 `main.lua`
- 在 `main.lua` 里 `#include` 工具脚本
- 工具自己的逻辑和资源仍然可以放在 `tool/工具名/`

## 2. 当前可工作的加载链

### 工具

当前 `phalanx` 工具的工作链路是：

1. [main.xml](C:/Users/13723/Documents/Teardown/mods/Phalanx/main.xml)  
   加载根目录脚本

2. [main.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/main.lua)  
   `#include "tool/phalanx/phalanx.lua"`

3. [phalanx.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/tool/phalanx/phalanx.lua)  
   执行 `RegisterTool("phalanx", ..., "MOD/tool/phalanx/phalanx.xml", ...)`

4. [phalanx.xml](C:/Users/13723/Documents/Teardown/mods/Phalanx/tool/phalanx/phalanx.xml)  
   引用 [phalanx.vox](C:/Users/13723/Documents/Teardown/mods/Phalanx/tool/phalanx/phalanx.vox)

### 载具

当前 `phalanx car` 载具的工作链路是：

1. [spawn.txt](C:/Users/13723/Documents/Teardown/mods/Phalanx/spawn.txt)  
   注册可生成载具 prefab

2. [mil-car-phalanx.xml](C:/Users/13723/Documents/Teardown/mods/Phalanx/vehicle/military/mil-car-phalanx.xml)  
   在 prefab 内直接声明载具和脚本

3. [car_phalanx.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/vehicle/military/car_phalanx.lua)  
   作为该载具实例自己的控制脚本运行

这条链不依赖根目录 `main.lua`。

## 3. 推荐目录规范

### 工具

推荐格式：

```text
tool/
  phalanx/
    phalanx.lua
    phalanx.xml
    phalanx.vox
```

规则：
- 工具脚本、xml、主模型尽量放同一目录
- 路径命名统一成 `tool/工具名/工具名.xxx`
- 这样最容易维护，也最方便复制出新工具

### 触觉

推荐格式：

```text
haptic/
  gun_fire.xml
  background.xml
```

规则：
- 通用 haptic 放根目录 `haptic/`
- 多个工具/载具可复用
- 脚本里统一用 `MOD/haptic/...`

### 载具

推荐格式：

```text
vehicle/
  military/
    car_phalanx.lua
    mil-car-phalanx.xml
    mil-car.vox
```

规则：
- 载具脚本和其 XML/prefab 放在同级目录
- 载具 prefab 内直接引用脚本
- 通过 `spawn.txt` 暴露给生成菜单

## 4. 路径引用规则

这部分是当前项目里最重要的实践经验。

### A. `main.xml` 中的脚本路径

推荐写法：

```xml
<script file="main.lua"/>
```

结论：
- `main.xml` 里应该指向根目录全局入口脚本
- 不建议直接让 `main.xml` 指向深层工具脚本作为唯一入口

### B. `main.lua` 中的 include

当前可工作写法：

```lua
#include "tool/phalanx/phalanx.lua"
```

结论：
- `#include` 可以把工具脚本放到根入口里统一管理
- 后面有多个工具时，也推荐继续用这个模式

### C. 资源路径

推荐用 `MOD/...`

例如：

```lua
RegisterTool("phalanx", "Phalanx", "MOD/tool/phalanx/phalanx.xml", 6)
LoadHaptic("MOD/haptic/gun_fire.xml")
```

以及：

```xml
<vox file="MOD/tool/phalanx/phalanx.vox" scale="0.4"/>
```

结论：
- 资源文件路径最稳的是 `MOD/...`
- 包括 tool xml、vox、haptic、snd 等

## 5. 为什么工具不能只靠 `main.xml -> tool/phalanx/phalanx.lua`

这是本次整理最重要的结论之一。

我们已经实际验证过：
- 直接让 [main.xml](C:/Users/13723/Documents/Teardown/mods/Phalanx/main.xml) 加载 [phalanx.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/tool/phalanx/phalanx.lua)
- 会导致整个工具栏消失，工具无法注册

而恢复为：
- `main.xml -> main.lua -> #include tool/phalanx/phalanx.lua`

之后工具栏和工具都恢复正常。

这说明在本项目里：
- 根目录 `main.lua` 才是稳定的全局工具注册入口

## 6. 推荐的全局入口模式

如果后面工具变多，推荐把 [main.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/main.lua) 维持成一个很薄的入口：

```lua
#version 2

#include "tool/phalanx/phalanx.lua"
-- #include "tool/another_tool/another_tool.lua"
-- #include "tool/some_tool/some_tool.lua"
```

优点：
- 不影响工具各自独立目录
- 全局注册点清晰
- 很适合逐步扩展项目

## 7. 当前项目建议

后续建议遵循下面这套规则：

1. 根目录保留：
   - [main.xml](C:/Users/13723/Documents/Teardown/mods/Phalanx/main.xml)
   - [main.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/main.lua)

2. 工具全部放到：
   - `tool/工具名/工具名.lua`
   - `tool/工具名/工具名.xml`
   - `tool/工具名/工具名.vox`

3. `main.lua` 统一 include 工具脚本

4. 通用 haptic 放：
   - `haptic/`

5. 载具继续放：
   - `vehicle/...`

6. 载具通过 `spawn.txt` 管理，不走工具注册链

## 8. 未来可以继续补充的文档

接下来比较值得继续写成文档的有：

1. 工具模板规范  
   例如一个新工具最少需要哪些文件

2. 载具模板规范  
   例如一个新载具最少需要哪些 xml / lua / spawn 条目

3. 资源命名规范  
   例如 `mil-`、`phalanx_`、`tool/工具名/工具名.*`

4. 调试约定  
   例如日志、`DebugWatch`、调试开关放哪里

## 9. 当前相关文件

- 全局入口：[main.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/main.lua)
- 地图入口：[main.xml](C:/Users/13723/Documents/Teardown/mods/Phalanx/main.xml)
- 工具脚本：[phalanx.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/tool/phalanx/phalanx.lua)
- 工具 xml：[phalanx.xml](C:/Users/13723/Documents/Teardown/mods/Phalanx/tool/phalanx/phalanx.xml)
- 载具脚本：[car_phalanx.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/vehicle/military/car_phalanx.lua)
- 载具 xml：[mil-car-phalanx.xml](C:/Users/13723/Documents/Teardown/mods/Phalanx/vehicle/military/mil-car-phalanx.xml)
