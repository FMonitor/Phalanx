# Teardown Joint Control Notes

这份文档面向当前项目，重点整理 Teardown 里 `joint` 的常见控制方式，以及它们在炮塔/武器上的适用场景。

## 1. 先记住一个核心结论

在 Teardown 里，做“可转动炮塔”通常有两条路：

1. 用 `joint` 当真正的运动机构  
   典型 API 是 `SetJointMotor(...)` 和 `SetJointMotorTarget(...)`

2. 用 `joint` 只当物理连接/支点，脚本直接 `SetBodyTransform(...)`  
   这是我们当前 `Phalanx` 载具正在用的方案

两种都能做，但适合的事情不同。

## 2. 当前项目里已经在用的方式

文件：
- [car_phalanx.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/vehicle/military/car_phalanx.lua)
- [mil-car-phalanx.xml](C:/Users/13723/Documents/Teardown/mods/Phalanx/vehicle/military/mil-car-phalanx.xml)

当前 `gun` 炮塔的旋转方式不是 `SetJointMotor(...)`，而是：

1. 在 XML 里让 `gun` 作为独立 `body`
2. 用一个 `joint` 把 `gun` 接到车体上
3. 在脚本里每 tick 计算目标朝向
4. 用 `SetBodyTransform(gun, nt)` 直接把整个炮塔 body 旋过去

优点：
- 简单
- 稳定
- 很容易做“跟随相机”
- 不太容易被 joint 参数折磨

缺点：
- 不是真正的机械驱动
- 做多级联动时不够优雅
- 容易和其它局部 shape 动画互相影响

## 3. `joint` 相关常用 API

这些定义可以在 [script_defs.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/reference_mod/data/script_defs.lua) 里找到。

### 查找和识别

- `FindJoint(tag, global)`
- `FindJoints(tag, global)`
- `GetJointType(joint)`
- `IsJointBroken(joint)`
- `GetJointShapes(joint)`
- `GetJointOtherShape(joint, shape)`
- `GetShapeJoints(shape)`
- `GetJointedBodies(body)`

用途：
- 找某个炮塔关节
- 看某个 body/shape 被哪些 joint 连着
- 确认 joint 断没断

### 电机控制

- `SetJointMotor(joint, velocity, strength)`
- `SetJointMotorTarget(joint, target, maxVel, strength)`

这两个是最重要的。

`SetJointMotor`：
- 更像“给电机一个转速”
- hinge joint 里 `velocity` 是弧度/秒
- 适合持续旋转、手动调速、转盘类机构

`SetJointMotorTarget`：
- 更像“让关节追一个目标角度/位移”
- hinge joint 里 `target` 是角度，单位是度
- `maxVel` 是最大角速度，单位是弧度/秒
- 适合炮塔对准目标角、舱门开合、机械臂定位

### 读 joint 当前状态

- `GetJointLimits(joint)`
- `GetJointMovement(joint)`

用途：
- 读 hinge 的最小/最大角度
- 读当前已经转到了多少角
- 做限位控制、阻尼控制、分段逻辑

### 断开连接

- `DetachJointFromShape(joint, shape)`

用途：
- 破坏玩法
- 炮塔被炸飞
- 可拆卸模块

## 4. 炮塔最常见的三种结构

### A. 单 body + 单 joint + `SetBodyTransform`

结构：
- 车体 body
- 炮塔 gun body
- 一个 hinge joint 连在一起

控制：
- 脚本直接 `SetBodyTransform(gun, nt)`

适合：
- 单轴炮塔
- 快速验证手感
- 需要先跑通玩法

### B. 单 body + 单 joint + `SetJointMotorTarget`

结构：
- 车体 body
- 炮塔 gun body
- 一个 hinge joint 做 yaw

控制：
- 找到 hinge joint
- 每 tick 算目标 yaw
- 用 `SetJointMotorTarget(joint, targetYaw, maxVel, strength)`

适合：
- 真实炮塔转盘
- 有明确限位
- 想保留物理感

### C. 双 body + 双 joint

结构：
- 底座 body
- 炮管/炮耳 body
- yaw joint
- pitch joint

控制：
- yaw joint 控水平转向
- pitch joint 控抬头/俯仰

适合：
- 复杂炮塔
- 防空炮
- 坦克炮塔
- 想独立控制 yaw / pitch

这是你后面做“更复杂炮塔控制”最推荐的最终结构。

## 5. `SetJointMotor` 和 `SetJointMotorTarget` 怎么选

如果你想要的是“持续转动”：
- 选 `SetJointMotor`

如果你想要的是“跟踪一个角度”：
- 选 `SetJointMotorTarget`

炮塔跟相机，通常更适合：
- yaw 用 `SetJointMotorTarget`
- pitch 也用 `SetJointMotorTarget`

因为你真正想控制的是“角度”，不是“转速”。

## 6. hinge 角度控制时最容易踩的坑

### 1. 目标角单位和速度单位不一样

- `target` 是度
- `maxVel` 是弧度/秒

这是最容易写错的地方。

### 2. joint 的零点不是你以为的零点

joint 的 0 度来自 XML 里 joint 初始安装姿态，不一定等于“模型朝前”。

所以很常见的做法是：
- 先 `DebugWatch(GetJointMovement(joint))`
- 看当前正前方时读数是多少
- 再加一个 `jointAngleOffset`

### 3. 世界 yaw 不等于 joint 本地 yaw

如果车体在转，世界空间的角度不能直接塞给 joint。

正确思路通常是：
1. 先拿车体 transform
2. 把目标方向变到车体本地空间
3. 再在本地空间里算 yaw / pitch
4. 把这个局部角度给 joint

### 4. 超过俯仰极限时会翻到背面

这正是你前面已经遇到过的问题。

解决方式：
- 先把相机方向转成 `yaw/pitch`
- 再对 `pitch` 做 clamp
- 最后再转回方向向量或 joint 目标角

## 7. 车载炮塔推荐控制流程

如果后续你要做双轴炮塔，推荐每 tick 按这个顺序来：

1. 获取车体、yaw joint、pitch joint、炮口位置
2. 获取玩家相机 forward
3. 把相机方向转到车体本地空间
4. 计算本地 yaw / pitch
5. 对 yaw / pitch 做限位
6. 用 `SetJointMotorTarget` 驱动两个 joint
7. 从炮口发射弹丸
8. 客户端做转管/枪口火焰/音效/UI

## 8. 一个典型双轴炮塔的伪代码

```lua
local baseBody = FindBody("turret_base")
local gunBody = FindBody("turret_gun")
local yawJoint = FindJoint("turret_yaw")
local pitchJoint = FindJoint("turret_pitch")

function tick(dt)
	local camForward = TransformToParentVec(GetCameraTransform(), Vec(0, 0, -1))
	local baseT = GetBodyTransform(baseBody)
	local localDir = TransformToLocalVec(baseT, camForward)

	local yaw, pitch = dirToYawPitch(localDir)
	yaw = clamp(yaw, -160, 160)
	pitch = clamp(pitch, -10, 75)

	SetJointMotorTarget(yawJoint, yaw, math.rad(180), 400)
	SetJointMotorTarget(pitchJoint, pitch, math.rad(120), 300)
end
```

注意：
- 这里只是结构示意
- 具体正负方向、零点偏移，通常还要按你的模型再修一次

## 9. 什么时候该继续用 `SetBodyTransform`

以下情况继续用 `SetBodyTransform` 是合理的：

- 你只想先验证玩法
- 炮塔只有一个自由度
- joint 怎么调都不顺
- 你更在意“镜头跟随手感”，不是机械真实性

对小项目来说，这不是坏方案。

## 10. 什么时候该切到 joint 驱动

以下情况建议切到 joint 控制：

- 需要 yaw / pitch 两级联动
- 需要明确机械限位
- 需要炮塔被撞、被炸时仍保留物理表现
- 需要和悬挂、车身姿态、后坐力耦合

## 11. 当前项目的建议路线

你现在最合适的下一步不是立刻把整套炮塔改成 joint 驱动，而是：

1. 保持当前 `SetBodyTransform` 炮塔跟随
2. 先把车载 `phalanx` 的弹道、特效、转管完全做顺
3. 等玩法稳定后，再单开一个分支尝试双 joint 炮塔

原因：
- 你现在已经有一套稳定的相机和射击链路
- 直接切 joint 会把“相机/炮塔/俯仰/限位”四件事重新耦合在一起

## 12. 调试建议

做 joint 控制时，建议至少常驻这些调试值：

- `DebugWatch("yaw current", GetJointMovement(yawJoint))`
- `DebugWatch("yaw min/max", mi .. " / " .. ma)`
- `DebugWatch("pitch current", GetJointMovement(pitchJoint))`
- `DebugWatch("target yaw", yaw)`
- `DebugWatch("target pitch", pitch)`

这样你很快就能分辨：
- 是目标角算错了
- 还是 joint 零点不对
- 还是 strength / maxVel 太小

## 13. 和当前 barrel 自转相关的一点经验

现在 `barrel` 的自转不是 joint，而是 shape 本地 transform 动画。

适合这样做的部件：
- 转管
- 雷达小天线
- 仪表小机构

不太适合这样做的部件：
- 整个炮塔 yaw
- 炮管 pitch
- 需要真实受力的机械结构

所以后面你的复杂炮塔结构很适合做成：
- 炮塔 yaw：joint
- 炮管 pitch：joint
- 多管旋转：shape 本地动画

## 14. 本项目里相关文件

- 炮塔脚本：[car_phalanx.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/vehicle/military/car_phalanx.lua)
- 炮塔 XML：[mil-car-phalanx.xml](C:/Users/13723/Documents/Teardown/mods/Phalanx/vehicle/military/mil-car-phalanx.xml)
- API 参考：[script_defs.lua](C:/Users/13723/Documents/Teardown/mods/Phalanx/reference_mod/data/script_defs.lua)

如果你下一步想做“双 joint 炮塔”，最合适的顺序是：
- 先在 XML 里拆成 yaw body 和 pitch body
- 然后我再帮你把当前 `getShootDir()` 这套相机方向，改成 joint 目标角驱动
