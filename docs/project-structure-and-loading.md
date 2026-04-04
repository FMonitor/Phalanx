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

## 2. 顶层目录职责

当前项目建议把“游戏直接加载目录”和“项目共享逻辑目录”分开：

- 游戏直接加载：
  - `tool/`
  - `vehicle/`
  - `haptic/`
  - `main.lua`
  - `main.xml`
  - `spawn.txt`

- 项目共享逻辑：
  - `shared/`

其中：
- `tool/` 和 `vehicle/` 是给游戏直接引用的内容目录
- `shared/` 是项目内部复用逻辑目录

## 3. 当前可工作的加载链

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

## 4. 推荐目录规范

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

### 共享模块

推荐格式：

```text
shared/
  phalanx_weapon/
```

用途：
- 放 tool 和 vehicle 共用的武器系统逻辑
- 不作为游戏内容分类目录

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

## 5. 路径引用规则

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

## 6. 为什么工具不能只靠 `main.xml -> tool/phalanx/phalanx.lua`

这是本次整理最重要的结论之一。

我们已经实际验证过：
- 直接让 [main.xml](C:/Users/13723/Documents/Teardown/mods/Phalanx/main.xml) 加载 [phalanx.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/tool/phalanx/phalanx.lua)
- 会导致整个工具栏消失，工具无法注册

而恢复为：
- `main.xml -> main.lua -> #include tool/phalanx/phalanx.lua`

之后工具栏和工具都恢复正常。

这说明在本项目里：
- 根目录 `main.lua` 才是稳定的全局工具注册入口

## 7. 推荐的全局入口模式

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

## 8. 当前项目建议

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

5. 共享逻辑放：
   - `shared/模块名/`

6. 载具继续放：
   - `vehicle/...`

7. 载具通过 `spawn.txt` 管理，不走工具注册链

## 9. 未来可以继续补充的文档

接下来比较值得继续写成文档的有：

1. 工具模板规范  
   例如一个新工具最少需要哪些文件

2. 载具模板规范  
   例如一个新载具最少需要哪些 xml / lua / spawn 条目

3. 资源命名规范  
   例如 `mil-`、`phalanx_`、`tool/工具名/工具名.*`

4. 调试约定  
   例如日志、`DebugWatch`、调试开关放哪里

## 10. 当前相关文件

- 全局入口：[main.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/main.lua)
- 地图入口：[main.xml](C:/Users/13723/Documents/Teardown/mods/Phalanx/main.xml)
- 工具脚本：[phalanx.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/tool/phalanx/phalanx.lua)
- 工具 xml：[phalanx.xml](C:/Users/13723/Documents/Teardown/mods/Phalanx/tool/phalanx/phalanx.xml)
- 共享模块规范：[shared-module-convention.md](C:/Users/13723/Documents/Teardown/mods/Phalanx/docs/shared-module-convention.md)
- 载具脚本：[car_phalanx.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/vehicle/military/car_phalanx.lua)
- 载具 xml：[mil-car-phalanx.xml](C:/Users/13723/Documents/Teardown/mods/Phalanx/vehicle/military/mil-car-phalanx.xml)

## 11. 调试记录

### 2026-04-04: shared include 路径在 tool 和 vehicle 中不能直接照搬

现象：
- 手持 `phalanx` 正常
- 车载 `phalanx` 炮塔失去玩家控制，无法旋转和开火

原因：
- [phalanx.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/tool/phalanx/phalanx.lua) 是经由 [main.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/main.lua) 被 include
- [car_phalanx.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/vehicle/military/car_phalanx.lua) 是由载具 xml 直接加载
- 两者的 `#include` 相对路径解析上下文不一样

错误写法：

```lua
#include "shared/phalanx_weapon/phalanx_weapon_config.lua"
```

这在 tool 脚本里可工作，但在 vehicle 脚本里会导致共享模块没有正确加载。

修正写法：

```lua
#include "../../shared/phalanx_weapon/phalanx_weapon_config.lua"
#include "../../shared/phalanx_weapon/phalanx_weapon_projectile.lua"
#include "../../shared/phalanx_weapon/phalanx_weapon_fx.lua"
```

结论：
- tool 侧共享 include 路径可以从根入口视角写
- vehicle 侧共享 include 路径必须按脚本所在目录写相对路径
- 后续做 shared 迁移时，要分别验证 tool 和 vehicle 两条链路

### 2026-04-04: 第一人称视角下载具本体抽搐，第三人称正常

现象：
- 载具高速移动时，第一人称更容易看到载具本体抽搐
- 第三人称相机基本流畅
- 问题主要体现在第一人称，不是环境整体抖动

原因：
- 第三人称分支使用的是：
  - `AttachCameraTo(body, false)`
  - `SetCameraOffsetTransform(localTransform)`
- 第一人称分支之前使用的是：
  - `SetCameraTransform(worldTransform)`

这意味着第一人称和第三人称相机分别走了“世界空间直接设相机”和“车体本地空间附着”两套不同的采样方式，高速移动时更容易出现观感不一致。

### 2026-04-04: 车载第一人称近距离体素出现半透明

现象：
- 玩家切到车载第一人称时，离镜头很近的车体体素会出现半透明
- 第三人称下这个现象不明显

当前处理：
- 在自定义车载相机运行时持续请求第三人称模式
- 同时对车体和炮塔调用 `SetPivotClipBody(...)`

说明：
- 这是按当前 API 能力做的工程性规避，推测目标是绕开引擎默认的第一人称载具淡出行为
- 如果后续测试表明效果稳定，可以保留这套做法作为车载第一人称相机的固定模板

### 2026-04-04: 车载 spin 音效不播放，但炮塔已正常转动

现象：
- 手持 `phalanx` 有转管 `spin` 声
- 车载 `phalanx` 炮塔会预热、会转、会开火，但没有 `spin` 声
- 弹丸、开火声和爆炸声都正常

定位思路：
- 先确认服务端和客户端“是否正在转”的状态链是否正常
- 再确认 `playSpin(...)` 这段代码是否真的执行到
- 当普通 `DebugWatch` 太多、条目显示不稳定时，不要继续堆更多日志
- 改成“阶段式”单条日志，例如：
  - `after_init`
  - `after_camera_sync`
  - `after_muzzle`
  - `spin_enter_fire`
  这样可以快速定位脚本到底停在哪一段

最终定位：
- 车载客户端本地状态 `clientGunFx` 缺少 `angle = 0.0`
- 共享模块 [phalanx_weapon_spin.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/shared/phalanx_weapon/phalanx_weapon_spin.lua) 的 `tickSpin()` 会执行：

```lua
state.angle = state.angle + state.angVel * dt
```

- 因为 `clientGunFx.angle` 未初始化，这一段会中断后续本地逻辑
- 结果表现为：
  - 前面的相机/输入/开火链路正常
  - 后面的 `spin` 音效分支始终进不去

修复：
- 在 [car_phalanx.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/vehicle/military/car_phalanx.lua) 的 `clientGunFx` 初始化中补上：

```lua
angle = 0.0
```

结论：
- 当共享状态结构被多个脚本复用时，初始化字段必须完整对齐
- 如果怀疑某段客户端逻辑“静默失效”，优先用阶段式日志逐段缩小范围
- 比起一次性堆很多 `DebugWatch`，复用一条阶段标签通常更可靠

修复：
- 第一人称分支也改成先计算世界空间相机
- 再转成车体本地 transform
- 然后统一用：

```lua
AttachCameraTo(body, false)
SetCameraOffsetTransform(cameraLocalTransform)
```

结果：
- 第一人称抽搐问题消失
- 第三人称保持原本流畅表现

结论：
- 对于高速载具，相机最好统一走车体本地空间附着
- 即使是第一人称，也尽量避免直接 `SetCameraTransform(world)` 作为最终输出
