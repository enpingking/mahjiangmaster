# MaJiang 逻辑架构文档（模块化规则 + 本地化）

## 1. 加载顺序

`MaJiang.toc` 当前加载顺序：

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

## 2. 模块职责

### 2.1 `modules/core_utils.lua`

通用工具：数组/字符串/牌编码/排序/资源映射。

### 2.2 `modules/i18n.lua` + `locales/*.lua`

本地化层：

1. `I18N.T(key, ...)` 文本读取与格式化
2. `GetLocale()` 自动识别客户端语言
3. 语言策略：
   - `zhCN` -> 简体中文
   - 其他 -> 英文回退（`enUS`）

### 2.3 `modules/ruleset.lua`

规则定义层：

1. 国际麻将
2. 广东麻将
3. 四川麻将（传统）
4. 四川麻将（血流成河）

并提供牌墙生成、规则开关、四川缺门/打缺辅助。

### 2.4 `modules/game_rules.lua`

胡牌/听牌判定层，支持规则参数（`ruleId`）。

### 2.5 `modules/ai_engine.lua`

AI 决策层，支持规则上下文（禁吃、打缺、候选牌集）。

### 2.6 `modules/scoring.lua`

番型评估层，按规则变体计算番型。

### 2.7 `MaJiang.lua`

编排层：状态机、联机协议、主机裁决、模块装配。

### 2.8 `modules/addon_audio.lua`

音频子模块：

1. BGM 轮播与可播放性检查
2. 动作语音（吃碰杠胡）
3. 出牌语音与倒计时告警

### 2.9 `modules/addon_result_ops.lua`

结算与战绩子模块：

1. `BuildRoundResult/SaveHistory/AnnounceToChat`
2. 结算面板渲染与分数行刷新
3. 历史面板列表与详情渲染

### 2.10 `modules/addon_ui_utils.lua`

UI 通用子模块：

1. 规则下拉选择器
2. 牌面 `Frame` 创建
3. 子控件批量隐藏（`ClearChildren`）

## 3. 规则与本地化接线

### 3.1 规则选择入口

1. 单人模式按钮上方“单人规则”
2. 对战大厅“房间规则”（房主可改）
3. 设置面板“默认玩法规则”

### 3.2 联机同步

`ROOM_ANNOUNCE/LOBBY_SYNC/GAME_START/ROUND_* /SNAPSHOT_*` 携带 `ruleId`。

### 3.3 文本本地化

1. UI 文本、提示文案通过 `T("...")`
2. 动态文案通过 `T("格式串", arg1, arg2)`
3. 番型名称展示层做二次翻译（`T(item.name)`）

## 4. 回归验证

1. `luac -p modules/core_utils.lua`
2. `luac -p modules/i18n.lua`
3. `luac -p locales/zhCN.lua`
4. `luac -p locales/enUS.lua`
5. `luac -p modules/ruleset.lua`
6. `luac -p modules/game_rules.lua`
7. `luac -p modules/ai_engine.lua`
8. `luac -p modules/scoring.lua`
9. `luac -p modules/addon_audio.lua`
10. `luac -p modules/addon_result_ops.lua`
11. `luac -p modules/addon_ui_utils.lua`
12. `luac -p MaJiang.lua`
13. `lua tests/run_logic_regression.lua`
