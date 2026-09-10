# 流水账

> 一款**纯本地**的记账 App：账单文件导入 + 通知自动记账 + 手动记录，数据只存在自己手机里。

Flutter 单代码库 → Android（正式使用）/ Web（开发调试）。**零第三方运行时插件**，原生部分全部用 Kotlin 自写。

---

## 它解决什么问题

微信/支付宝的官方账单导出有硬伤：**导出流程繁琐**（导出 → 邮箱 → 通知栏找解压密码 → 解码），
而且**微信导出不含群聊转账**。于是本项目把「通知自动记账」做成核心通道，与导入互补：

| 途径 | 角色 | 覆盖 |
|---|---|---|
| 📡 **通知自动记账** | 日常主力 | 微信支付/收款到账、支付宝大部分交易；监听系统通知 → 本地解析 → 待确认 |
| 📥 **导入账单文件** | 每月兜底 | 微信/支付宝官方导出的 CSV/XLSX，补历史与盲区；自动去重（单号 + 指纹桥） |
| ✍️ **手动记录** | 随手补 | 被扫支付、现金、临时补记 |

**已知平台盲区**（App 内教程也会直说）：支付宝「被扫」支付、微信主动转账/发红包、微信群红包
等场景**平台本身不发通知** → 靠导入对账或手动补。

## 功能

- 记账主体：收支列表 / 筛选（账户·时间跨度·收支）/ 汇总（收入·支出·结余）/ 增删改 / 批量操作
- 通知自动记账全链路：原生 `NotificationListenerService` 采集 → 标题特征过滤 → 队列落盘 →
  Flutter 解析入库 → 待确认页单条/批量/全部确认 → 正式账单
- 可靠性：监听服务自愈重绑（组件 toggle）、前台保活服务、开机自启、健康自检（发探测通知回读队列）
- 分类管理：内置分类停用/启用、自定义分类（名称 + 图标，支持图片图标）
- 数据：本地 JSON 持久化、导出 CSV/JSON、JSON 备份恢复（合并去重 / 全量覆盖）、待确认治理
- 隐私：`allowBackup=false`，不申请联网权限，通知只在本机解析

## 技术要点

- **解析器与编排纯 Dart**：Web 模拟面板与 Android 原生监听共用同一条链路，端到端可测
- **零插件**：文件选择/保存用 `ACTION_OPEN_DOCUMENT` / `ACTION_CREATE_DOCUMENT`（SAF），
  持久化用 MethodChannel 取私有目录 + `dart:io`，避免引入任何 pub 插件
- **金额以分为单位**（`int amountCents`），展示层才格式化，杜绝浮点误差
- **去重双保险**：导入按官方单号；通知按"账户+方向+金额+±1 分钟"指纹；
  两侧交叉时用 **±5 分钟指纹桥**把通知记录与官方单号配对并回填单号（此后永久单号去重）

## 目录结构

```
lib/
├── data/            RecordStore（记录/查询/治理）、CategoryStore（分类配置）
├── models/          Record / Account / Category ...
├── pages/           账单流水 / 我的 / 记一笔 / 待确认 / 导入 / 分类管理 / 通知设置 / 使用教程
├── services/
│   ├── notify/      通知解析器、入库编排、样本库、队列补拉、平台通道封装
│   ├── storage/     存储抽象（Web localStorage / Android 私有目录文件 / 内存）
│   └── ...          账单解析、导出、备份恢复、文件选择/保存
└── widgets/         账户徽标、分类图标等

android/app/src/main/kotlin/com/liushuizhang/app/
    MainActivity.kt            三个 MethodChannel：lsz_storage / lsz_notify / lsz_file
    NotifyListenerService.kt   通知监听（包名过滤 + 标题特征过滤 + 队列落盘）
    KeepAliveService.kt        前台保活服务
    BootReceiver.kt            开机自启

test/                148 项测试（解析器 / 去重 / 导入 / 备份 / UI / 分类 / 通知全链路）
```

## 构建与运行

```bash
flutter pub get

# 开发（Web）
flutter run -d chrome

# 正式包（Android，arm64 + 32 位 ARM 通用包）
flutter build apk --release --target-platform android-arm64,android-arm
```

签名：在 `android/` 下放置 `key.properties`（`storePassword` / `keyAlias` / `keyPassword`）并配置
`signingConfig` 即可；**密钥文件已在 `.gitignore` 中排除，请勿入库**。

## 测试

```bash
flutter analyze     # 期望：No issues found
flutter test        # 期望：148 项全绿
```

测试样本为**脱敏后的真实格式**（列顺序、时间/金额格式、掩码位数、单号长度均保留），
因此格式回归能力不受影响。

## 隐私

- 正式包不申请 `INTERNET` 权限，数据不联网
- 账单数据存于应用私有目录；`allowBackup=false` + `dataExtractionRules` 拒绝系统云备份/换机迁移
- 通知内容仅在本机解析，不接任何外部服务

## 已知限制

- 依赖微信/支付宝**发送系统通知**的行为，平台不发通知的交易无法自动记录（见上文盲区）
- 国产 ROM 需用户一次性授权：通知使用权 + 自启动/后台运行白名单（App 内「使用教程」有引导）
- 仅 Android 为正式目标平台，Web 端用于开发调试

## 许可

本项目采用 [MIT License](LICENSE)。

## 免责声明

本项目为个人自用工具，与微信、支付宝及其关联公司无任何关系。
请遵守相关平台的服务条款，导出的账单数据仅用于个人记账。

