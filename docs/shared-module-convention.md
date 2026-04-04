# Shared Module Convention

这份文档定义项目里的“共享模块”放置方式，用来和 Teardown 实际直接加载的目录区分开。

## 1. 目标

把“游戏直接引用的内容”和“项目内部复用逻辑”分开：

- 游戏直接引用：
  - `tool/`
  - `vehicle/`
  - `haptic/`
  - `main.lua`
  - `main.xml`
  - `spawn.txt`

- 项目内部共享：
  - `shared/`

这样可以避免后面项目变大后：
- tool 和 vehicle 互相复制逻辑
- 找不到某个武器系统的“唯一真源”
- 工具资源目录和逻辑复用目录混在一起

## 2. 顶层目录约定

推荐长期保持下面这套结构：

```text
shared/
  phalanx_weapon/

tool/
  phalanx/

vehicle/
  military/

haptic/
docs/
```

含义：

- `shared/`
  - 项目内部复用逻辑
  - 不直接作为游戏内容分类

- `tool/`
  - 手持工具
  - 这里放游戏直接注册和引用的工具脚本/xml/模型

- `vehicle/`
  - 载具
  - 这里放游戏直接生成和引用的载具脚本/xml/模型

## 3. shared 的命名规则

共享模块建议统一采用：

```text
shared/模块名/
```

当前武器系统建议命名为：

```text
shared/phalanx_weapon/
```

原因：
- `phalanx` 是具体武器名
- `weapon` 明确这是武器系统，不是工具、不是真实载具、不是真实 prefab

## 4. shared/phalanx_weapon 的职责

这个目录应该放“可同时给 tool 和 vehicle 使用”的逻辑。

建议内容：

```text
shared/phalanx_weapon/
  phalanx_weapon_config.lua
  phalanx_weapon_projectile.lua
  phalanx_weapon_fx.lua
  phalanx_weapon_spin.lua
  phalanx_weapon_audio.lua
```

### `phalanx_weapon_config.lua`

放：
- 武器名
- 弹丸速度
- 重力
- 生命周期
- 爆炸强度
- 光照半径
- 音量
- 射速
- 散布

也就是“名字 + 属性”的中心配置文件。

### `phalanx_weapon_projectile.lua`

放：
- `createProjectile`
- `tickProjectiles`
- 命中处理
- 爆炸处理

### `phalanx_weapon_fx.lua`

放：
- 曳光
- 烟雾
- 枪口闪光
- 发光粒子
- 公共音效辅助逻辑

### `phalanx_weapon_spin.lua`

放：
- 转管角速度
- 转管角度推进
- 旋转 shape 的辅助函数
- 开火节奏状态推进

### `phalanx_weapon_audio.lua`

放：
- 通用音效加载
- 开火音效播放
- 转管循环音播放

## 5. tool / vehicle 各自保留什么

### tool 负责

- `RegisterTool`
- 手持输入
- 第一人称/第三人称 tool 动画
- 手部 IK
- tool 自己的 xml / vox

### vehicle 负责

- 炮塔 body / joint / muzzle 获取
- 载具输入
- 相机控制
- UI
- 载具自己的 xml / vox

### shared 负责

- 通用武器参数
- 弹丸
- 特效
- 转管状态推进

## 6. 依赖方向规则

为了后面结构稳定，建议遵守这条规则：

- `tool/` 可以 include `shared/`
- `vehicle/` 可以 include `shared/`
- `shared/` 不反向依赖 `tool/` 或 `vehicle/`

也就是说：
- `shared` 是底层
- `tool` / `vehicle` 是上层适配

不要让：
- `shared/phalanx_weapon/*.lua`
  里直接引用手持工具专用 API 状态
- 或直接依赖车载专用 body / camera 变量

## 7. 一条重要原则

共享的是“武器系统”，不是“武器实例挂载方式”。

也就是说：
- tool 和 vehicle 可以共用弹道逻辑
- tool 和 vehicle 可以共用特效逻辑
- tool 和 vehicle 不一定共用 xml
- tool 和 vehicle 不一定共用模型

这点非常重要。

## 8. 迁移建议

当前项目不要一次性把所有逻辑都搬走，建议分三步：

1. 先建立 `shared/phalanx_weapon/` 骨架
2. 先迁移“纯参数”和“纯弹丸模拟”
3. 再迁移特效和转管

这样最稳，不容易把当前已工作的载具和工具同时搞坏。

## 9. 当前推荐骨架

建议从这几个文件开始：

- [phalanx_weapon_config.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/shared/phalanx_weapon/phalanx_weapon_config.lua)
- [phalanx_weapon_projectile.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/shared/phalanx_weapon/phalanx_weapon_projectile.lua)
- [phalanx_weapon_fx.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/shared/phalanx_weapon/phalanx_weapon_fx.lua)

## 10. 当前项目里的推荐引用方式

后续建议像这样使用：

```lua
#include "shared/phalanx_weapon/phalanx_weapon_config.lua"
#include "shared/phalanx_weapon/phalanx_weapon_projectile.lua"
#include "shared/phalanx_weapon/phalanx_weapon_fx.lua"
```

然后：
- `tool/phalanx/phalanx.lua` 负责把玩家输入转成开火
- `vehicle/military/car_phalanx.lua` 负责把车载输入转成开火

两边共享同一套武器核心。
