# [Prato](https://github.com/shileima/Prato)

**Prato** 是一款面向中文用户的 AI 原生视频编辑器，基于开源项目 [Palmier Pro](https://github.com/palmier-io/palmier-pro) 二次开发，提供完整的简体中文界面与自定义大模型接入能力。

> 仅支持 macOS 26+，Apple Silicon

---

## 主要特性

- **完整中文界面** — 菜单、面板、对话框全面汉化
- **自定义模型 API** — 兼容 OpenAI 格式，支持接入 Claude、Gemini、DeepSeek 等任意大模型
- **AI 视频生成** — 支持 Veo、Kling、Seedance 等主流视频生成模型（需订阅）
- **AI 字幕** — 自动转写并生成字幕轨道
- **AI 音乐** — 根据时间线风格生成背景音乐
- **MCP 服务器** — 可通过 Claude Desktop、Cursor、Claude Code 等客户端直接编辑时间线
- **多轨时间线** — 视频/音频编辑，支持关键帧、文字叠加、速度控制

---

## 快速开始

### 编译运行

```bash
git clone https://github.com/shileima/Prato
cd Prato
swift build
```

### 配置自定义大模型

**方式一：环境变量（推荐，立即生效）**

```bash
CUSTOM_API_BASE_URL="https://api.openai.com/v1" \
CUSTOM_API_KEY="sk-..." \
CUSTOM_API_MODEL="gpt-4o" \
.build/debug/PalmierPro
```

**方式二：应用内设置**

打开 **设置 → 智能体 → 自定义模型 API**，填写地址、Key 和模型名后保存。

支持的模型（OpenAI 兼容格式）：

| 提供商 | 示例模型 |
|--------|---------|
| Anthropic | `claude-opus-4-6`、`claude-sonnet-4-6` |
| Google | `gemini-2.5-flash`、`gemini-2.5-pro` |
| DeepSeek | `deepseek-v3` |
| OpenAI | `gpt-4o`、`o3` |
| 其他 | 任何 OpenAI 兼容端点 |

---

## 界面说明

| 区域 | 功能 |
|------|------|
| 媒体 | 导入、搜索、管理素材 |
| 字幕 | AI 转写 + 样式定制 |
| 音乐 | AI 生成背景音乐 |
| 时间线 | 多轨拖拽编辑 |
| 智能体 | 对话式操作，支持自定义大模型 |
| 检查器 | 片段属性、变换、关键帧 |

---

## 与原版对比

| | 原版 Palmier Pro | Prato |
|-|-----------------|-------|
| 界面语言 | 英文 | 简体中文 |
| 智能体模型 | Anthropic / Palmier 云端 | 任意 OpenAI 兼容 API |
| AI 视频/音频生成 | 需 Palmier 订阅 | 需 Palmier 订阅 |
| 开源协议 | GPL v3 | GPL v3 |

---

## 系统要求

- macOS 26+
- Xcode 26 / Swift 6.2+
- Swift Package Manager（依赖自动拉取）

---

## 许可证

本项目基于 [Palmier Pro](https://github.com/palmier-io/palmier-pro)（GPL v3）二次开发，同样遵循 **GPL v3** 许可证。
