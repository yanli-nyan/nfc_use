# NFC Use

[中文](README.md) | [English](README_EN.md)

一个面向 Android 的 Flutter NFC 卡包应用。用户可在本机维护卡片、通过手机的 **HCE 主机卡模拟**让 PN532 等读卡器读取当前选中的卡片 ID，并从 ZIP 包导入由桌面端导出的卡片配置与图片。

## 功能

- 卡片式首页：左右切换卡片，上滑当前卡片启用 HCE 并进入详情页。
- Android HCE：响应指定 AID 的 SELECT APDU，返回当前卡片 ID 与状态字 `9000`。
- NFC 状态诊断：显示 NFC 硬件、HCE 支持、默认付款应用状态、模拟状态，以及最近一次 APDU/响应记录。
- 支持跳转系统 NFC 设置，并请求将本应用设为默认付款应用。
- 本地 SQLite 卡包：持久化卡片 ID、名称、颜色、图片路径和排序；可排序、统计与一键清空。
- 从 ZIP 包导入卡片配置和 PNG/JPG/JPEG/WEBP 图片；缺图时使用占位图。

## 平台与前提条件

- Flutter SDK（项目声明 Dart SDK `^3.11.5`）
- Android 设备或模拟器；实际 NFC/HCE 功能需要支持 NFC 与 HCE 的真机
- 已开启系统 NFC；部分机型还需要在系统中将本应用设为默认付款应用
- 如需让 PN532 读取，读卡器须发送与应用匹配的 SELECT AID 指令

Android Manifest 已声明 NFC、振动及 HCE 能力，但 NFC 与 HCE 被标记为非必需硬件，因此应用可安装在不支持 NFC 的设备上；对应功能不可用。

## 快速开始

```bash
git clone <repository-url>
cd nfc_use
flutter pub get
flutter run
```

构建发布 APK：

```bash
flutter build apk --release
```

当前 Android 包名为 `com.yanli.nfc_use`，release 构建使用 `android/key.properties` 指向的正式密钥库进行签名。首次构建前请参照 [android/key.properties.example](android/key.properties.example) 创建 `android/key.properties`；该文件与密钥库均已被 `.gitignore` 排除，不可提交到仓库。

## 使用 HCE 卡模拟

1. 打开“设置”页，应用会自动检测 NFC 状态并在功能可用时启用卡模拟。
2. 确认 NFC 已开启且设备支持 HCE；必要时点击“设为默认付款应用”并在系统界面确认。
3. 返回首页，左右选择要使用的卡片，然后上滑该卡片。
4. 应用会启用 HCE，并把这张卡片的 `id` 保存为当前响应令牌。
5. 将手机靠近 PN532/读卡器。读卡器对 AID `F0010203040506` 发出 SELECT 指令后，可取得 UTF-8 令牌，末尾状态字为 `9000`。
6. 可在设置页查看最近 APDU、响应和次数，用于排查读卡器兼容性。

HCE 服务使用支付类别 AID 路由。不同 Android 厂商的 NFC 设置和默认付款应用策略不同，HCE 可用性以实际系统行为为准。

## 卡片数据与导入

卡片保存在应用文档目录中的 SQLite 数据库 `card_database.db`，而不是项目目录。首次没有本地卡片时，首页会显示一个 `NONE` 示例卡片。

在设置页使用“导入卡片”选择 ZIP 文件。导入器会查找其中的 `config.json` 和以模块 `character` 命名的图片。ZIP 可使用下列结构（文件可处于子目录）：

```text
config.json
resources/
  K1.png
  K2.png
```

`config.json` 最小示例：

```json
{
  "version": "1.1",
  "modules": [
    {
      "name": "示例卡片",
      "character": "K1",
      "color": "#3B82F6"
    }
  ]
}
```

导入时，`character` 会成为卡片 ID，`name` 成为标题；`color` 应为十六进制颜色。若存在 `resources/K1.png`（也支持 JPG/JPEG/WEBP），应用会复制图片到私有目录；否则使用占位图。相同 ID 会覆盖本地同 ID 卡片。

## 安全与隐私

- HCE 会向兼容读卡器返回所选卡片 ID。请不要用它承载敏感认证信息，也不要将其误作安全支付卡。
- 导入 ZIP 内的图片与卡片标识会写入应用私有存储；清空卡片会同时删除已导入图片。

## 技术栈

- Flutter / Material
- `nfc_manager`：NDEF 标签会话与写入服务
- 原生 Android `HostApduService`：HCE APDU 响应和调试记录
- `sqflite`：本地卡片数据库
- `archive`、`file_picker`、`path_provider`：ZIP 导入与文件管理

## 项目结构

```text
lib/
  core/
    constants/card_item.dart          卡片模型与交互常量
    services/nfc_service.dart         HCE 与 NDEF 服务
    services/sqlite_service.dart      SQLite 卡片数据
    services/card_import_service.dart ZIP 卡包导入
    services/zip.dart                 ZIP 选择、解压与文件工具
  pages/
    Home/                             卡片浏览、详情与排序
    Setting/                          HCE 状态、导入与数据管理设置
android/app/src/main/
  kotlin/.../NfcHceService.kt         自定义 HCE 服务
  kotlin/.../MainActivity.kt          Flutter MethodChannel 桥接
  res/xml/apduservice.xml             HCE AID 声明
```
