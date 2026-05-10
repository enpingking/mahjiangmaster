# Mahjong Masters 麻將大師 开发维护文档（WoW 12.0）

## 1. 目标与范围

本插件实现：

1. 单人模式（本地 AI）
2. 4 人对战模式（5 人小队下第 5 人可旁观）
3. WoW 12.0 限制态兼容（副本/聊天限制态门禁）
4. 主机权威牌局同步（客户端仅提交动作意图）
5. 出牌倒计时、吃碰杠胡动作倒计时（超时自动托管）
6. 番数计分（RuleSet v1）

核心入口文件：`MaJiang.lua`  
模块目录：`modules/`  
回归脚本：`tests/run_logic_regression.lua`  
入口清单：`MaJiang.toc`

---

## 2. 品牌与元信息

- 插件名：`Mahjong Masters 麻將大師`
- 作者：`晓输童`
- 参考说明：AI 模块源代码参考 [majiang](https://www.curseforge.com/wow/addons/majiang)，原作者 `shenmidigua2`
- `SavedVariables`：`MahjongMastersDB`

---

## 3. 运行结构总览

当前采用“多文件模块化加载 + 主入口编排”：

1. `modules/core_utils.lua`
2. `modules/i18n.lua`
3. `locales/zhCN.lua`
4. `locales/enUS.lua`
5. `modules/ruleset.lua`
6. `modules/game_rules.lua`
7. `modules/ai_engine.lua`
8. `modules/scoring.lua`
9. `modules/addon_audio.lua`
10. `modules/addon_result_ops.lua`
11. `modules/addon_ui_utils.lua`
12. `MaJiang.lua`

职责划分：

1. `core_utils`：表操作、字符串处理、牌编码、排序、洗牌、资源索引转换
2. `i18n + locales`：文本本地化（简体中文/英文），按 `GetLocale()` 自动切换
3. `ruleset`：玩法枚举、规则开关、洗牌牌墙、四川缺门与打缺限制
4. `game_rules`：胡牌判定、碰碰胡判定、听牌列表（支持规则参数）
5. `ai_engine`：向听估算、吃杠候选、AI 弃牌策略（支持规则上下文）
6. `scoring`：番型识别与番数汇总（按规则变体）
7. `addon_audio`：音频播放、BGM 轮播、动作/出牌/倒计时语音
8. `addon_result_ops`：对局结算对象构建、战绩存档、结算/历史面板渲染
9. `addon_ui_utils`：规则下拉选择器、牌面 Frame 创建、子控件清理工具
10. `MaJiang.lua`：状态机、联机协议、事件分发、模块装配

加载顺序要求：

1. `core_utils` 必须先于所有逻辑模块加载
2. `i18n` 依赖独立，可提前加载
3. `locales/*` 依赖 `i18n`
4. `ruleset` 依赖 `core_utils`
5. `game_rules` 依赖 `core_utils + ruleset`
6. `ai_engine` 依赖 `core_utils + game_rules + ruleset`
7. `scoring` 依赖 `core_utils + game_rules + ruleset`
8. `scoring` 之后加载主入口辅助模块（`addon_audio/addon_result_ops/addon_ui_utils`）
9. `MaJiang.lua` 通过 `NS.*` 绑定模块函数，按依赖注入装配运行时上下文

---

## 4. 关键状态对象

全局状态 `STATE`：

- 模式：`NONE | SINGLE | BATTLE`
- 阶段：`IDLE | LOBBY | PLAYING | FINISHED | PAUSED`
- 牌局：玩家、牌墙、当前回合、庄家、最后弃牌、分数
- 玩法：`ruleId`（国际/广东/四川传统/四川血流）
- 房间：`room.id / room.gameId / room.ruleId / room.hostName / players / watchers`
- 网络：发送序号、接收序号、ACK、重发队列、快照缓存、事件哈希链
- 计时器：出牌计时、动作计时、倒计时告警去重

---

## 5. 12.0 API 合规要点

### 5.1 通信 API

- `C_ChatInfo.RegisterAddonMessagePrefix`
- `C_ChatInfo.SendAddonMessage`
- 事件：`CHAT_MSG_ADDON`

### 5.2 限制态/门禁 API

- `IsInInstance()`
- `C_ChatInfo.InChatMessagingLockdown()`
- `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()`
- `C_RestrictedActions.GetAddOnRestrictionState(...)`
- `C_RestrictedActions.IsAddOnRestrictionActive(...)`
- 事件：`ADDON_RESTRICTION_STATE_CHANGED`

### 5.3 计时与设置 API

- `GetTimePreciseSec()`
- `Settings.RegisterCanvasLayoutCategory(...)`

---

## 6. 对战协议（v3）

### 6.1 封包字段

每包包含：

- `proto`
- `msgType`
- `seq`
- `ack`
- `roomId`
- `gameId`
- `epoch`
- `payload`
- `actionId`
- `senderGuid`
- `prevHash`
- `eventHash`
- `crc`

### 6.2 可靠消息

关键消息启用 ACK + 重发：

- `GAME_START`
- `HAND_SYNC`
- `TURN_START`
- `ACTION_PROMPT`
- `DRAW_APPLY`
- `DISCARD_APPLY`
- `MELD_APPLY`
- `ROUND_FINISH`
- `SNAPSHOT_REQ`
- `SNAPSHOT_PART`

实现机制：

1. 发送后进入 `pendingReliable`
2. 目标端回 `ACK {ackActionId, ackSeq}`
3. 超时未 ACK 自动重发
4. 到期未恢复则丢弃并可触发重同步

### 6.3 分叉恢复（快照重同步）

- 客户端触发条件：
  - 序号断档（`seq gap`）
  - 哈希链断裂（`event hash mismatch`）
  - CRC 校验失败
- 流程：
  - 客户端发 `SNAPSHOT_REQ`
  - 主机分片发 `SNAPSHOT_PART`（避免超长包）
  - 客户端重组后 `ApplySnapshot` 覆盖本地公开态与本家手牌

---

## 7. 反作弊边界（现阶段）

当前策略：

1. 主机权威：客户端不直接改真实牌局
2. 客户端提交仅为动作意图（`ACTION_REQ`）
3. 主机做合法性校验：
   - 令牌校验（`pendingActionToken`）
   - 座位校验（sender -> seat）
   - 手牌可出校验
   - 吃牌组合合法校验（必须匹配 legal combos）
4. 事件链哈希 + 包 CRC，提升篡改成本
5. 可重同步，避免限流/丢包后长期分叉

说明：该方案提升作弊成本，但不等于“密码学不可作弊”。

---

## 8. 计时规则

### 8.1 出牌倒计时

- 默认 15 秒（DB 可配）
- 到时自动打出最右牌（`hand[#hand]`）
- 轮到自己且最后 3 秒播放 `timeup_alarm.mp3`

### 8.2 动作倒计时（吃碰杠胡）

- 默认 8 秒（DB 可配）
- 超时自动 `PASS`

---

## 9. 计分规则（RuleSet v1）

玩法规则：

- 国际麻将：允许吃碰杠，禁十三幺
- 广东麻将：允许吃碰杠，含十三幺
- 四川麻将（传统）：禁吃、缺一门、无字牌
- 四川麻将（血流成河）：禁吃、缺一门、无字牌，胡牌后继续行牌

支持番型：

- 平胡 1
- 门前清 1
- 自摸 1
- 碰碰胡 2
- 混一色 2
- 清一色 4
- 七对 4
- 国士无双 13
- 杠上开花 1
- 抢杠胡 1
- 海底捞月 1

结算：

- `base = 2^(totalFan+1)`，13 番封顶按当前实现处理
- 自摸：其余三家各付
- 点炮：点炮者双倍支付

---

## 10. AI 难度与决策模型

当前单人模式 AI 支持 4 档难度（设置项 `MajongMastersDB.ai.difficulty`）：

1. `beginner`（新手）：基础胡牌推进，偏向降向听，防守权重低
2. `advanced`（进阶，默认）：平衡进攻与防守，兼顾向听、听牌与牌效率
3. `expert`（专家）：加入更强的危险度与剩余有效牌评估
4. `master`（大师）：在专家基础上加入读牌倾向与小幅虚张声势（近似最优解中做可控扰动）

实现入口：

1. `modules/ai_engine.lua`
2. `AI.ChooseAIDiscard(...)`
3. `AI.DecideResponse(...)`
4. `AI.SelectKongInDraw(...)`

策略参考：

- `kobalab/majiang-ai` 的有效牌数量评估、危险度估算、押退阈值思路与分层演进方法

---

## 11. UI/资源映射

### 10.1 贴图

根路径：`Interface\AddOns\MaJiang\ui\img\`

- 牌桌：`bg.png`
- 牌背：`ChouJiangPaiBei.png`
- 万：`1..9.png`
- 筒：`11..19.png`
- 索：`21..29.png`
- 字：`31..37.png`
- 庄家：`zhangjia.png`
- 非庄：`icon_gold.png`
- 方位：`down.png / right.pn(兼容回退 right.png) / up.png / left.png`

### 10.2 音频

根路径：`Interface\AddOns\MaJiang\ui\audio\`

- BGM：`bgm1.mp3 / bgm2.mp3`
- 倒计时：`timeup_alarm.mp3`
- 语音目录：`woman/` 与 `man/`
- 出牌语音：`pai_0 .. pai_33`
- 动作语音：`chi/peng/gang/hu/hu_da/hu_pao`（含命名兼容）

---

## 12. 设置与存档

`MahjongMastersDB` 默认结构：

```lua
MahjongMastersDB = {
  audio = {
    bgmEnabled = true,
    sfxEnabled = true,
    voiceGender = "woman",
  },
  ai = {
    difficulty = "advanced", -- beginner | advanced | expert | master
  },
  rules = {
    defaultRule = "guangdong", -- international | guangdong | sichuan_traditional | sichuan_bloodriver
  },
  timer = {
    discardSec = 15,
    actionSec = 8,
    alarmLast3Sec = true,
  },
}
```

---

## 13. 维护与升级建议

1. 先稳协议再加玩法：
   - 新消息类型必须决定是否走可靠传输
   - 关键状态消息必须携带 `actionId`
2. 新规则优先在“主机裁决层”实现，客户端仅做展示
3. 涉及节流风险的新增消息必须评估包长度（当前阈值 240）
4. 改 UI 贴图时保持 `CardToImageKey` 与资源命名一致
5. 新音效增加后，优先按“候选列表”方式接入，避免单文件缺失导致静音
6. 新玩法优先放进 `modules/ruleset.lua`（规则定义）+ `modules/game_rules.lua`（胡牌判定）再由主入口接线
7. AI 逻辑仅在 `modules/ai_engine.lua` 维护，避免在入口层夹带策略分支
8. 单人模式 AI 相关 `C_Timer` 回调需具备异常兜底与超时回退，避免“等待超时才继续”的卡顿体验

---

## 14. 验证清单（每次发版）

1. `luac -p modules/core_utils.lua` 通过
2. `luac -p modules/i18n.lua` 通过
3. `luac -p locales/zhCN.lua` 通过
4. `luac -p locales/enUS.lua` 通过
5. `luac -p modules/ruleset.lua` 通过
6. `luac -p modules/game_rules.lua` 通过
7. `luac -p modules/ai_engine.lua` 通过
8. `luac -p modules/scoring.lua` 通过
9. `luac -p modules/addon_audio.lua` 通过
10. `luac -p modules/addon_result_ops.lua` 通过
11. `luac -p modules/addon_ui_utils.lua` 通过
12. `luac -p MaJiang.lua` 通过
13. `lua tests/run_logic_regression.lua` 通过
14. 副本地图下：对战模式建房/开局被门禁拦截
15. 4 人可正常开局，第 5 人作为旁观者
16. 单人模式/建房模式可切换国际、广东、四川传统、四川血流
17. 四川规则下禁吃、生效打缺、无字牌牌墙
18. 出牌与动作倒计时超时自动处理
19. 丢包/断档后可触发 `SNAPSHOT_REQ` 并恢复
20. 牌面贴图、庄家标记、方位标记、音效开关均正常
21. 客户端语言为 `zhCN` 时显示中文，其他语言显示英文
