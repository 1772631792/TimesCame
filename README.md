# TimesCam · 同网快传相机

连同一个 WiFi，手机拍完，电脑选中的文件夹里立刻出现这张照片。
不用数据线、不用微信、不用装网盘——一张 4K 照片通常 **0.3 ~ 0.8 秒** 落地。

```
手机 App（Flutter）                        上位机（Python）
┌──────────────────┐   UDP 37020 广播   ┌──────────────────────┐
│ 雷达页自动找电脑  │ ─────────────────▶ │ 回一条 HOST 广播      │
│ 相机页拍照        │                    │                      │
│ 立即 POST /upload │ ── HTTP 37021 ───▶ │ 直接写进选中的文件夹  │
└──────────────────┘                    └──────────────────────┘
```

<p align="center">
  <img src="host/icon.png" width="120" alt="TimesCam 图标">
</p>

## 目录结构

```text
TimesCame/
├── app/                       Flutter 手机端（Android）
│   ├── lib/
│   │   ├── main.dart              外壳：底部导航、背景光晕、沉浸式相机
│   │   ├── theme.dart             深色配色与全局主题
│   │   ├── widgets.dart           玻璃卡片、渐变按钮、雷达动画
│   │   ├── net_client.dart        UDP 发现 + HTTP 上传 + 心跳测速
│   │   ├── app_state.dart         上传队列、设置持久化、统计
│   │   ├── models.dart            照片模型与缩略图生成
│   │   └── pages/
│   │       ├── home_page.dart         连接页（雷达 / 电脑信息 / 手动连接）
│   │       ├── camera_page.dart       相机页（预览 / 九宫格 / 对焦 / 开拍即传）
│   │       ├── shots_page.dart        相册页（状态 / 耗时 / 重试）
│   │       └── settings_sheet.dart    设置（画质 / 自动同步 / 设备名）
│   ├── android/.../res/       启动图标（由脚本生成，别手改）
│   └── build.py               一键打 APK（自动画图标 + 配代理）
├── host/                      Python 上位机
│   ├── main.py                入口：GUI / --no-gui / --selftest
│   ├── ui.py                  Tkinter 界面（深色、渐变按钮、照片墙）
│   ├── draw.py                手绘组件：圆角渐变按钮、缩略图网格
│   ├── server.py              HTTP 直传服务（/ping /info /upload）
│   ├── discovery.py           UDP 广播发现
│   ├── state.py               保存目录、照片列表、统计
│   ├── config.py              常量、配置读写、本机 IP
│   ├── theme.py               配色与字体
│   ├── build.py               打包成单个 exe（PyInstaller）
│   ├── icon.ico / icon.png    脚本生成的二次元图标
│   └── start_host.bat         Windows 双击启动（优先跑 exe）
└── tools/
    └── make_icon.py           图标生成器（两只脚本共用一张母图）
```

## 快速开始

**1. 电脑端**

双击 `host/dist/TimesCamHost.exe`（打包好的单文件，免 Python），或者：

```bash
cd host
python main.py              # 也可以双击 start_host.bat
```

窗口右上角会显示本机地址，例如 `192.168.1.64:37021`。
首次运行 Windows 弹防火墙提示时，务必勾选 **专用网络** 并允许。

**2. 手机端**

安装 `app/dist/TimesCam-v1.0.0-20261120.apk`，或者自己打一份（见「打包」）。

**3. 用起来**

1. 手机和电脑连**同一个 WiFi**（同一个路由器，别一个 5G 一个访客网络）。
2. 打开 App，首页雷达自动找到电脑，显示「已连接 · 电脑名」与延迟。
3. 点「开始拍摄」，相机全屏预览，按快门 → 顶部提示「已同步 · 320 ms」。
4. 电脑窗口里立刻多出一张缩略图，文件已经在左侧显示的文件夹里。

> 找不到电脑时点「手动连接」，把电脑上那个地址填进去即可（广播被路由器挡掉时用这招）。

## 手机端能做什么

| 页面 | 能力 |
| --- | --- |
| 连接 | 同一 WiFi 内 UDP 广播自动发现、1 秒级重连、延迟实时显示、手动填 IP、断线自动重新搜索；显示电脑保存目录与同步统计 |
| 相机 | 全屏预览、点按对焦、九宫格、自动闪光、前后摄切换、快门动画；拍完立即上传，顶部实时显示进度 / 耗时；未连接时先排队，连上自动补传 |
| 相册 | 本次拍摄的缩略图网格，每张带状态（待传 / 上传中 / 已同步 / 失败）、耗时与大小；点开可放大查看、失败一键重传 |
| 设置 | 画质（最高 / 4K / 1080P / 720P）、拍完自动上传、保留手机副本、设备名（显示在电脑上）、手动地址 |

几个细节：

- **先拍后传**：没连上也能拍，照片进队列，电脑出现后自动补传，不需要重拍。
- **只存必要的**：上传成功后销毁原图缓存（可在设置里关掉），缩略图只留 400px，相册页不炸内存。
- **不经过任何服务器**：照片只在你的局域网里直传，App 没有云端账号。

## 上位机能做什么

- 深色界面：左侧「保存位置 / 连接 / 本次统计」，右侧缩略图墙（新照片排最前、带高亮边框）。
- 保存位置随时可换，选完下次启动还记得（存在 `~/.timescam_host.json`）。
- 实时统计：已接收张数、总容量、最近耗时、最高速度。
- 手机连上后右上角变绿：「已连接 · 你的手机名」，并显示手机 IP；点地址即可复制到 App 里手动连接。
- 点缩略图用系统看图工具打开原图；「打开文件夹」直接跳资源管理器。
- 没有前台窗口也能收：`python main.py --no-gui` 只跑服务、终端打印日志。

## 打包

### 上位机 → 单个 exe

```bash
cd host
python build.py
```

- 产物：`host/dist/TimesCamHost.exe`（约 28 MB，免安装、免 Python）。
- 脚本会先跑 `tools/make_icon.py` 现画 **二次元大眼睛** 图标 `icon.ico`，再交给 PyInstaller。
- 没装 PyInstaller / Pillow 会自动 `pip install`，默认走 `127.0.0.1:7897` 代理：

```bash
python build.py --proxy ""        # 不用代理
python build.py --no-icon         # 沿用现有图标
python build.py --keep-build      # 保留中间产物，排查问题用
```

### 手机端 → APK

```bash
cd app
python build.py
```

- 产物：`app/dist/TimesCam-v1.0.0-20261120.apk`（约 51 MB），脚本结束会自动打开 dist 目录。
- 三件事自动完成：① 生成 mdpi~xxxhdpi 五档启动图标 ② 把代理写进 `android/gradle.properties` ③ `flutter build apk --release`。
- 首次构建要下 Gradle 依赖 + 编译原生库，**十几分钟是正常的**；同一份工程第二次打包通常 1~2 分钟。
- 参数：

```bash
python build.py --proxy ""        # 不走代理（直连慢）
python build.py --no-icon         # 不重画图标
python build.py --no-build        # 只生成图标 + 写代理配置
python build.py --split-abi       # 按 ABI 分包，单包更小
```

> 代理默认 `127.0.0.1:7897`（Clash 常用端口）。脚本会先探测端口：没开就自动改成直连，
> 不会因为代理挂了把构建卡死。换端口就 `python build.py --proxy 127.0.0.1:端口`。

## 图标 / 二次元

`tools/make_icon.py` 用 Pillow 现画：粉紫→电光青的圆角底 + 一只带虹膜放射纹、高光、睫毛和
星星闪光的大眼睛，2048px 母图缩到各个尺寸，64px 仍能看清是「眼睛」。

```bash
python tools/make_icon.py --out host                                   # 写 host/icon.ico + icon.png
python tools/make_icon.py --android app/android/app/src/main/res       # 写 Android 五档 mipmap
python tools/make_icon.py --png preview.png --size 512                 # 只看效果
```

两个 build 脚本都会自动调用它，改配色就改文件顶部的 `GRAD_TL / GRAD_TR / GRAD_BL / GRAD_BR`。

## 协议（想自己写固件 / 脚本时看）

**发现（UDP，端口 37020）**

```text
手机 → 255.255.255.255:37020    TIMESCAM/DISCOVER v1
电脑 → 手机单播                  TIMESCAM/HOST {"name":"DESKTOP","port":37021,"dir":"D:\\Photos","count":12,"ver":1}
```

手机收到后会用 `GET /ping` 验一次，通了才算连接成功；之后每 5 秒心跳，连续 3 次失败自动重连。

**直传（HTTP，默认端口 37021，被占用会自动 +1 到 37040）**

| 接口 | 说明 |
| --- | --- |
| `GET /ping` | `{"ok":true,"name":"...","t":...}`，用来测延迟 |
| `GET /info` | 返回电脑名、保存目录、已收张数，手动连接时用 |
| `POST /upload` | 请求体就是 JPEG 原始字节 |

`POST /upload` 的请求头：

```text
Content-Type: image/jpeg
Content-Length: 2621440
X-File-Name: TimesCam_20261120_143012_812.jpg   # URL 编码
X-Device: %E6%88%91%E7%9A%84%E6%89%8B%E6%9C%BA    # URL 编码，显示在电脑上
```

响应：

```json
{"ok": true, "file": "TimesCam_20261120_143012_812.jpg", "bytes": 2621440, "ms": 318.4, "speed": 7.85, "count": 13}
```

想用命令行试一下：

```bash
curl -X POST http://192.168.1.64:37021/upload \
     -H "X-File-Name: test.jpg" \
     --data-binary @test.jpg
```

## 常见问题

| 现象 | 原因 / 处理 |
| --- | --- |
| 一直「正在寻找电脑」 | ① 确认同一 WiFi；② Windows 防火墙放行 TimesCamHost.exe / python.exe（专用网络）；③ 路由器开了「AP 隔离 / 访客网络隔离」时广播过不来，改用「手动连接」填 IP |
| 发现了电脑但连不上 | 广播能过、HTTP 被挡：放行入站 TCP 37021 |
| 上传很慢 | 手机连的是 2.4G 或信号弱；靠近路由器，或把画质调到 1080P |
| 相机黑屏 / 报权限 | 系统设置 → 应用 → TimesCam → 相机权限；被其他 App 占用时关掉再进 |
| 电脑端没缩略图 | 没装 Pillow，`pip install Pillow` 即可（照片本身已经收下来了；exe 版自带） |
| 端口被占用 | 上位机会自动顺延到 37021~37040，地址以窗口右上角为准 |
| `pip install pyinstaller` 很慢 | 代理没开。`python build.py --proxy 127.0.0.1:7897`，或先手动装好 |
| APK 打包卡在 `Running Gradle task` | 同上：确认代理端口能连（脚本会自动探测，连不上就直连）；第一次构建慢属正常 |

## 已知限制

- 只做 Android（Flutter 工程未生成 iOS 目录）。
- 手机端同一时间只连一台电脑；换电脑点「重新搜索」即可。
- 单张照片一次性读进内存（4K JPEG 约 2~4 MB），没有做分片断点续传。
- 明文 HTTP，没有做鉴权——只适合自己家的局域网，别在公共 WiFi 上用。
