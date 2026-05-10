# Mahjong Masters（麻将大师）

World of Warcraft（Retail）插件，提供 4 人麻将单人/对战玩法，支持规则切换、结算与历史战绩展示。

## 功能概览

- 单人模式（本地 AI 对手）
- 对战模式（4 人对局，5 人小队可含 1 名旁观）
- 多规则支持（当前版本内置 27 种玩法规则）
- 胡牌番型计分与分数统计
- 结算弹窗与历史战绩详情
- 中英文本地化（`zhCN` / `enUS`）
- 音效与 BGM 播放

## 安装

1. 克隆仓库到插件目录：
```bash
git clone https://github.com/JovenCalme/mahjiangmaster.git MahJiang
```
2. 目标路径应为：
`World of Warcraft\_retail_\Interface\AddOns\MahJiang`
3. 重启游戏或执行 `/reload`。
4. 在角色选择界面确认插件已启用。

## 使用方式

- `/mj`：打开/关闭主界面
- `/mjset`：打开设置页
- `/mjhistory`：打开历史战绩

主界面可选择单人模式或对战模式，并在开局前选择玩法规则与 AI 难度。

## 目录结构

- `MahJiang.toc`：插件加载清单
- `MahJiang.lua`：主入口（UI、状态机、事件、联机流程）
- `modules/`：核心逻辑模块（规则、胡牌判定、AI、计分、结算渲染、音频等）
- `locales/`：本地化文本
- `ui/`：图片与音频资源
- `tests/`：逻辑回归脚本

## 本地回归测试

项目提供 Lua 逻辑回归脚本（不依赖游戏客户端 UI）：

```bash
lua tests/run_logic_regression.lua
```

预期输出：

```text
OK: logic regression passed
```

## 兼容性

- 目标接口版本：`120005`
- 支持 WoW Retail 12.0 分支

## 致谢

- AI 模块参考项目：<https://www.curseforge.com/wow/addons/majiang>
- 原作者：`shenmidigua2`

