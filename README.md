# AgentHub — 通用Agent移动客户端

> Agent版Termius — 一个App聚合管理所有AI Agent实例

## 🏗️ 架构

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────┐
│  AgentHub App   │◄──WS──►│ AgentHub Server  │◄──CLI──►│  OpenClaw   │
│  (Flutter)      │  REST  │  (Node.js)       │         │  Agent      │
│  iOS + Android  │        │  Port 18790      │         │  Port 18789 │
└─────────────────┘         └──────────────────┘         └─────────────┘
```

**App不直接碰LLM API。** App只跟AgentHub Server通信，Server通过OpenClaw CLI与Agent交互。

## ✅ 已实现功能

### Flutter App (agenthub/)
- 多Agent管理（添加/删除/状态显示）
- QR码扫码配对
- Session列表浏览
- 流式聊天界面（Markdown渲染）
- 工具调用审批按钮
- 连接状态指示（在线/离线/思考中）
- 深色主题

### AgentHub Server (agenthub-server/)
- `/hub/status` — Agent健康检查
- `/hub/pair` — 设备配对（Ed25519公钥 + HMAC Token）
- `/hub/sessions` — Session列表
- `/hub/chat` — 非流式聊天（REST）
- `/hub/ws` — WebSocket流式聊天
- `/hub/devices` — 已配对设备管理
- 设备持久化存储
- 自动重连 + 心跳

### 端到端测试通过 ✅
- REST: 发送消息 → OpenClaw回复 "嘿！👋"
- WS: 发送消息 → 36.6s后收到正确流式回复
- 配对: 设备配对 → Token生成 → 认证访问

## 📱 安装

### 1. 启动AgentHub Server

```bash
cd agenthub-server
npm install
node src/index.js
# Server runs on http://0.0.0.0:18790
```

环境变量：
- `AGENTHUB_PORT` — 服务端口（默认18790）
- `OPENCLAW_BIN` — openclaw CLI路径（默认`openclaw`）
- `AGENTHUB_PAIR_SECRET` — 配对密钥（自动生成）

### 2. 安装App

将 `app-release.apk` 安装到Android设备：
```bash
adb install app-release.apk
```

### 3. 在App中添加Agent

- 打开App → 点击 +
- 输入AgentHub Server地址（如 `http://你的服务器IP:18790`）
- 选择平台：OpenClaw
- 点击 Connect

## 🔐 安全架构

- 传输：TLS 1.3（生产环境需配置反向代理）
- 认证：Ed25519设备公钥 + HMAC Token
- 权限分级：6级（默认聊天+Session管理）
- 设备绑定：Agent端可随时撤销设备权限

## 📂 项目结构

```
agenthub/                   # Flutter App
├── lib/
│   ├── main.dart           # 入口
│   ├── protocol/           # AgentHub通信协议定义
│   ├── models/             # 数据模型（Agent, Chat, Session）
│   ├── services/           # 连接管理 + 本地存储
│   └── screens/            # UI界面（Home, Chat, AddAgent, Session）
├── android/                # Android构建配置
└── pubspec.yaml            # 依赖

agenthub-server/            # Node.js桥接服务器
├── src/
│   └── index.js            # 服务主文件（Express + WS）
├── data/                   # 设备持久化存储
└── package.json
```

## 🔮 后续规划

- [ ] 真正的流式输出（逐token推送而非等完整回复）
- [ ] E2E加密
- [ ] 推送通知（FCM/APNs）
- [ ] Dify平台插件
- [ ] 文件传输
- [ ] 工具调用可视化
- [ ] iOS版本发布
- [ ] 多用户权限管理

## 📊 测试结果

| 测试项 | 结果 | 耗时 |
|--------|------|------|
| Server启动 | ✅ | <1s |
| REST Status | ✅ | <1s |
| 设备配对 | ✅ | <1s |
| Session列表 | ✅ | <2s |
| REST Chat | ✅ | ~30s |
| WS Chat (流式) | ✅ | ~36s |
| Flutter Analyze | ✅ 0 error | 1.5s |
| APK Build (release) | ✅ 73MB | ~4min |

---

*AgentHub v0.1.0 — 2026-04-29*
