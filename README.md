# 本機完整後端（local 模式）

前端 `webapp` 的 `local` 模式把所有服務都指向 `https://localhost:8443/<服務>`。
這裡用 Caddy 佔用 8443，依路徑轉給各自獨立啟動的 Spring Boot 服務：

| 路徑 | 服務 | 實際埠號 | 位置 |
|---|---|---|---|
| `/cas`  | cas  | 9443 | `..\cas`（獨立 Gradle 專案） |
| `/klaw` | klaw | 9444 | `..\alpos\klaw` |
| `/oms`  | oms  | 8889 | `..\alpos\oms` |
| `/sys`  | sys  | 8890 | `..\alpos\sys` |

其他路徑（sif、wes…）本機沒有對應服務，Caddy 回 502。

## 前置條件

- 公司內網或 VPN（開發資料庫 `10.199.3.22`）
- Redis 在 `localhost:6379`（Memurai Developer）
- `JAVA_HOME` 指向 JDK 25（Azul Zulu）

## 一次啟動（模擬 CAS）

雙擊 `Start-ImitationDev.cmd`，或在這個資料夾執行它。會依序確認 Memurai，
並打開 Caddy、sys、oms、webapp，以及 imitation-cas 容器。`cas` 與 `klaw` 不會啟動。

改過 `imitation-cas` 的程式後，改執行 `Start-ImitationDev.cmd build` 重新建置容器。

## 啟動順序

每個服務開一個 PowerShell 視窗：

```powershell
cd D:\work\專案\local-dev
.\Start-LocalService.ps1 caddy
.\Start-LocalService.ps1 cas
.\Start-LocalService.ps1 klaw
.\Start-LocalService.ps1 sys
.\Start-LocalService.ps1 oms
```

改過 alpos 程式碼後加 `-Build` 重新打包（一次只跑一個，它們共用 alpos 的 build 目錄）。
平常開發也可以改用 IntelliJ 啟動，設定方式見下方。

前端：

```powershell
cd D:\work\專案\webapp
npx cross-env url=local sysCode=oms rsbuild dev
```

## 檔案說明

| 檔案 | 用途 |
|---|---|
| `Caddyfile` | 8443 反向代理設定 |
| `certs\mycas.crt/.key` | 由專案共用的 `mycas.jks` 匯出，`CN=localhost` |
| `alpos.env` | oms / sys 啟動時必須存在的 AWS 變數（佔位值） |
| `tools\New-EnvFiles.ps1` | 由 repo 內的 local 設定產生 `cas\.env`、`alpos\klaw\.env`；加 `-Force` 覆寫 |
| `tools\ExportPem.java` | 把 `mycas.jks` 轉成 Caddy 可讀的 PEM |

`.env` 內的 OAuth、reCAPTCHA、AWS、簡訊金鑰是佔位值 `local-unset`，相關功能（社群登入、OTP 簡訊與信件、S3）在本機無法使用。
需要時向團隊取得真實值，直接改 `.env`。

## 模擬 CAS 登入（imitation-cas）

取代 cas + klaw 的登入流程，只需 Docker Desktop、Memurai，以及 sys / oms。
`imitation-cas.override.yml` 停用 compose 內建的 Redis（與 Memurai 搶 6379），改讓容器連主機的 Memurai，
這樣 sys / oms 才讀得到同一份 `JwtCache`。

```powershell
cd D:\work\專案\local-dev
docker compose -f ..\imitation-cas\docker-compose.yml -f imitation-cas.override.yml up --build -d
```

- 服務位於 `http://localhost:8081`（Swagger：`/swagger-ui.html`）
- 登入時帳密對照開發 DB（10.199.3.22）的使用者資料，與 CAS 帳號相同
- `IMITATION_USERNAME` / `IMITATION_PASSWORD` 只用來在啟動時於 log 預先產生一組 token，可不設
- webapp 首頁選「模擬 CAS 登入」

## 用 IntelliJ 啟動

- cas：主類別 `com.alp.CasApplication`，Active profiles `standalone,local`，Environment variables 載入 `cas\.env`
- klaw：主類別 `com.alp.KlawApplication`，Environment variables 載入 `alpos\klaw\.env`
- sys：主類別 `com.alp.SysApplication`，Program arguments `--server.http.port=0`，Environment variables 載入 `local-dev\alpos.env`
- oms：主類別 `com.alp.OmsApplication`，Environment variables 載入 `local-dev\alpos.env`
