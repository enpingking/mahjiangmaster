# Mahjong Masters 麻將大師 开发文档（修订版 v3）

## 1. 文档目标

在现有 `MaJiang.lua` 基础上，落地：

1. 单人模式 + 4 人对战模式
2. 主机权威同步 + 12.0 限制态兼容
3. 出牌/动作双倒计时
4. 番数计分
5. 全量 UI 美术与音效替换
6. 设置界面（音乐/音效/语音风格）

---

## 2. 品牌与署名要求（新增）

## 2.1 插件品牌

- 展示名称改为：`Mahjong Masters 麻將大師`
- 作者署名：`晓输童`

## 2.2 参考说明（必须展示）

- 需在插件说明中注明：
- AI 模块源代码参考：`https://www.curseforge.com/wow/addons/majiang`
- 原作者：`shenmidigua2`

## 2.3 落地点

1. `MaJiang.toc`
- `## Title: Mahjong Masters 麻將大師`
- `## Author: 晓输童`
- `## Notes` 增加参考说明（可中英文混排）
2. `MaJiang.lua` 文件头注释增加致谢说明
3. 游戏内“设置/关于”面板增加“参考与署名”文本区

---

## 3. v2 方案关键缺陷修复（保留）

以下修复结论继续有效，必须作为 v3 实现前置：

1. `IsWin` 与副露手不兼容：
- 引入 `IsWinWithMelds(concealedHand, meldCount, winTile, winType)`
2. `EvaluateTurn` 响应优先级错误：
- 改为 `胡 > 杠/碰 > 吃` + 相对座次裁决
3. `CanChow` 只返回单组合：
- 改为 `GetChowCandidates` 返回全部可吃组合
4. 杠牌类型不完整：
- 补齐 `AnGang/MingGang/BuGang` 及抢杠胡
5. 12.0 门禁过窄：
- 增加 `InChatMessagingLockdown` 与 `RestrictedActions` 全量限制态判断
6. 通信可靠性不完整：
- 协议必须有 `seq/ack/actionId/重传/快照重同步`
7. 计时粒度：
- 主机裁决计时改为 `GetTimePreciseSec()`

---

## 4. 模式与房间

## 4.1 模式入口

- 模式 A：`单人模式`
- 模式 B：`对战模式`

## 4.2 对战模式入口

- `建房`
- `加入游戏`

## 4.3 人员结构

- 4 人为正式牌手（seat1-seat4）
- 5 人小队中的第 5 人为旁观者（watcher，可看公开信息）

---

## 5. 12.0 运行门禁（必须）

## 5.1 不允许运行场景

- 对战模式禁止在副本地图中开始（满足你的需求 3）
- 门禁 API：
- `IsInInstance()`
- `C_ChatInfo.InChatMessagingLockdown()`
- `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()`
- `C_RestrictedActions.GetAddOnRestrictionState(...)`
- `C_RestrictedActions.IsAddOnRestrictionActive(...)`

## 5.2 事件监听

- `PLAYER_ENTERING_WORLD`
- `ZONE_CHANGED_NEW_AREA`
- `GROUP_ROSTER_UPDATE`
- `ADDON_RESTRICTION_STATE_CHANGED`

## 5.3 限制态处理

- `Activating`：立即冻结动作提交（`PAUSING`）
- `Active`：保持暂停（`PAUSED`）
- `Inactive`：允许恢复（`RESUME`）

---

## 6. 主机权威同步与反作弊

## 6.1 权威边界

- 只有主机维护真实状态（牌墙/手牌/副露/回合/分数）
- 客户端仅提交动作意图，不直接改状态
- 客户端只接受主机 `ACTION_APPLY`

## 6.2 提升作弊成本

1. 承诺-揭示混洗种子
2. 事件哈希链（`prevHash -> eventHash`）
3. `senderGUID/seat/turn` 三重校验
4. 对局审计日志本地落盘

---

## 7. 通信协议（v3）

## 7.1 Prefix

- `MJ120PVP`（<=16）
- 启动时检查 `RegisterAddonMessagePrefix` 结果并分支处理

## 7.2 消息结构

```lua
{
  proto = 3,
  roomId = "...",
  gameId = "...",
  epoch = 1,
  seq = 101,
  ack = 98,
  senderGuid = "...",
  msgType = "ACTION_REQ",
  actionId = "seat3-turn18-peng",
  payload = {...},
  crc = "..."
}
```

## 7.3 通道

- 公共事件：`PARTY`
- 私密信息（发手牌/摸牌）：`WHISPER`

## 7.4 可靠性

- 关键包 ACK：`GAME_START/DEAL_PRIVATE/TURN_START/ACTION_APPLY/SETTLE`
- 失败码处理：
- `AddonMessageThrottle/ChannelThrottle`：排队重发
- `AddOnMessageLockdown`：暂停局面
- `TargetOffline/NotInGroup`：断线恢复或终止
- 快照重同步：
- `SNAPSHOT_REQ / SNAPSHOT_RESP`

---

## 8. 倒计时规则（新增重点）

## 8.1 出牌倒计时（需求 3）

- 每回合出牌限时：默认 15 秒（可配置 8-25 秒）
- 主机广播：`TURN_START {seat, deadlinePreciseSec}`
- 到时未出牌：主机自动打出最右牌 `hand[#hand]`
- 广播：`TURN_TIMEOUT_AUTO + ACTION_APPLY`

## 8.2 吃/碰/杠/胡倒计时（需求 2）

- 响应窗口限时：默认 8 秒（可配置 4-12 秒）
- 对每个有权响应的玩家显示倒计时
- 到时未操作：自动 `PASS`
- 广播：`ACTION_WINDOW_TIMEOUT_PASS`

## 8.3 倒计时音效规则

- 仅当“轮到自己出牌且剩余 <= 3 秒”时，播放 `timeup_alarm.mp3`
- 防重复：每秒只触发一次，且同一回合最多触发 3 次

---

## 9. 设置界面（新增）

## 9.1 设置项

1. 背景音乐：开/关
2. 出牌声音：开/关
3. 出牌语音风格：`女声/男声`（默认 `女声`）

## 9.2 默认值

```lua
MahjongMastersDB = {
  audio = {
    bgmEnabled = true,
    sfxEnabled = true,
    voiceGender = "woman", -- woman | man
  },
  timer = {
    discardSec = 15,
    actionSec = 8,
    alarmLast3Sec = true,
  },
}
```

## 9.3 设置 UI 实现建议（12.0）

- 使用 `Settings` API 注册分类（不使用旧 InterfaceOptions 旧写法）
- 分类名：`Mahjong Masters 麻將大師`
- 分组：
- 声音设置
- 对战计时
- 关于与署名

---

## 10. UI 视觉改造（新增）

## 10.1 资源根路径

- 图片：`Interface\\AddOns\\MahJiang\\ui\\img\\`

## 10.2 牌桌与牌背

- 牌桌背景：`bg.png`（主窗口拉伸铺满）
- 手牌背面：`ChouJiangPaiBei.png`（暗牌统一贴图）

## 10.3 牌面贴图规则（需求 5）

牌值到图片文件映射：

- 万：`1.png` - `9.png`
- 筒：`11.png` - `19.png`
- 索：`21.png` - `29.png`
- 字牌：`31.png` - `37.png`（东南西北中发白）

内部建议映射函数：

- `W1..W9 -> 1..9`
- `T1..T9 -> 11..19`
- `S1..S9 -> 21..29`
- `F1..F7 -> 31..37`

## 10.4 玩家方位与身份标识

- 庄家：`zhangjia.png + 玩家姓名`
- 其他玩家：`icon_gold.png + 玩家姓名`
- 方位标记：
- 下家：`down.png`
- 右家：`right.pn`（按需求原文；若资源实际为 `right.png`，代码需兼容回退）
- 上家：`up.png`
- 左家：`left.png`

## 10.5 渲染改造点

1. 替换 `CreateTileUI`：
- 文本渲染 -> `Texture:SetTexture(path)` 贴图渲染
2. 手牌高亮：
- 新摸牌/可出牌边框高亮保留
3. 兼容听牌提示：
- `ShowTingTooltip` 内牌面改用同一贴图映射

---

## 11. 音效与语音系统（新增）

## 11.1 资源根路径

- `Interface\\AddOns\\MahJiang\\ui\\audio\\`

## 11.2 背景音乐（需求 6）

- 曲目：`bgm1.mp3`、`bgm2.mp3`
- 每场开局随机选择 1 首持续播放
- 牌局结束/退出对战停止播放
- 开关受设置项 `bgmEnabled` 控制

## 11.3 倒计时告警

- 文件：`timeup_alarm.mp3`
- 触发条件：仅自己回合最后 3 秒

## 11.4 出牌与动作语音（男/女两套）

语音根目录：

- 女声：`ui\\audio\\woman\\`
- 男声：`ui\\audio\\man\\`

根据 `voiceGender` 选择目录。

动作语音：

- 吃：`chi1.mp3` - `chi4.mp3`（随机）
- 碰：`peng1.mp3` - `peng5.mp3`（随机）
- 杠：`gang1.mp3` - `gang3.mp3`（随机）
- 胡：`hu1.mp3` - `hu3.mp3`（随机）
- 胡（大胡）：`hu_da1.mp3` - `hu_da3.mp3`（随机）
- 胡（炮胡）：`hu_pao1.mp3` - `hu_pao3.mp3`（随机）

出牌语音编号规则：

- `pai_0.mp3` - `pai_8.mp3`：1-9 筒
- `pai_9.mp3` - `pai_17.mp3`：1-9 条（索）
- `pai_18.mp3` - `pai_26.mp3`：1-9 万
- `pai_27.mp3` - `pai_33.mp3`：东南西北中发白

## 11.5 音效触发规范

1. 触发时机由主机事件驱动：
- 收到 `ACTION_APPLY` 后本地播放对应音效，避免各端时机不一致
2. 防抖：
- 同一 `actionId` 音效只播一次
3. 开关：
- 出牌/动作/倒计时语音统一受 `sfxEnabled` 控制

---

## 12. 计分规则（RuleSet v1）

番型（保持 v2）：

- 平胡 1 番
- 门前清 1 番
- 自摸 1 番
- 碰碰胡 2 番
- 混一色 2 番
- 清一色 4 番
- 七对 4 番（仅闭手）
- 国士无双 13 番（仅闭手）
- 杠上开花 1 番
- 抢杠胡 1 番
- 海底捞月 1 番

结算：

- `totalFan = sum(fanList)`
- `basePoint = 2 ^ (totalFan + 1)`
- 自摸：其余三家各付 `basePoint`
- 点炮：点炮者付 `basePoint * 2`

---

## 13. 代码改造清单（v3）

## 13.1 必改函数

1. `IsWin` -> `IsWinWithMelds`
2. `CanChow` -> `GetChowCandidates`
3. `CanKong` -> `GetKongCandidates`
4. `EvaluateTurn` -> `CollectResponses + ResolveResponses`
5. `DrawTile`：拆分为阶段函数并接入回合计时器
6. `CreateTileUI`：文本牌面 -> 贴图牌面
7. `ShowActions`：增加动作倒计时 UI + 超时自动 PASS

## 13.2 新增模块（可先 table 化，后续拆文件）

- `MJGate`：12.0 门禁与限制态
- `MJNet`：通信协议与可靠传输
- `MJRoom`：建房/加入/座位与就绪
- `MJBattle`：主机状态机
- `MJTimer`：出牌/动作双倒计时
- `MJTheme`：贴图映射与界面资源
- `MJAudio`：BGM/SFX/语音路由
- `MJSettings`：设置持久化与 Settings 面板
- `MJScore`：番型与结算

---

## 14. 里程碑（v3）

## M1 联机核心

- 模式选择、建房/加入、4 人开局
- 主机权威同步（基础）

## M2 规则与计时

- 响应优先级修正
- 出牌倒计时超时自动出牌
- 吃碰杠胡倒计时超时自动 PASS

## M3 美术与音效

- 牌面贴图化
- 背景/牌背/方位/庄家标识
- BGM 与男女语音切换

## M4 设置与稳定性

- 设置面板（音乐/音效/语音）
- ACK/重传/快照重同步
- 限制态暂停恢复

---

## 15. 验收标准（新增后）

1. 插件展示名、作者、参考署名符合要求
2. 对战模式在副本地图无法开局
3. 出牌倒计时超时会自动打出最右牌
4. 吃碰杠胡均有倒计时，超时自动 PASS
5. 设置界面可开关 BGM、SFX，可切换男女声，默认女声
6. 牌桌、牌面、庄家标识、方位图标全部走 `ui/img` 资源
7. 语音与动作事件匹配正确，牌面语音索引映射正确
8. 异常网络下不会出现不可恢复分叉（可重同步）

---

## 16. 资源清单校验（实现前必做）

## 16.1 图片

- `ui/img/bg.png`
- `ui/img/ChouJiangPaiBei.png`
- `ui/img/1.png` - `9.png`
- `ui/img/11.png` - `19.png`
- `ui/img/21.png` - `29.png`
- `ui/img/31.png` - `37.png`
- `ui/img/zhangjia.png`
- `ui/img/icon_gold.png`
- `ui/img/down.png`
- `ui/img/right.pn`（或 `right.png`，需兼容）
- `ui/img/up.png`
- `ui/img/left.png`

## 16.2 音频

- `ui/audio/bgm1.mp3`
- `ui/audio/bgm2.mp3`
- `ui/audio/timeup_alarm.mp3`
- `ui/audio/woman/*`
- `ui/audio/man/*`

---

## 17. 参考接口（12.0）

- `C_ChatInfo.RegisterAddonMessagePrefix`
- `C_ChatInfo.SendAddonMessage`
- `CHAT_MSG_ADDON`
- `C_ChatInfo.InChatMessagingLockdown`
- `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted`
- `C_RestrictedActions.GetAddOnRestrictionState`
- `C_RestrictedActions.IsAddOnRestrictionActive`
- `ADDON_RESTRICTION_STATE_CHANGED`
- `IsInInstance`
- `GetTimePreciseSec`
- `PlaySoundFile`
- `StopSound`
- `Settings.*`（设置界面注册）

