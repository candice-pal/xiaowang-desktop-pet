<p align="center">
  <img src="assets/xiaowang.png" width="280" alt="白色馬爾濟斯桌面寵物小汪">
</p>

<h1 align="center">小汪桌面寵物</h1>

<p align="center">使用 PowerShell 與 WPF 製作的輕量 Windows 桌面夥伴。</p>

<p align="center"><a href="README.md">English</a></p>

## 預覽

![Xiao Wang desktop pet running on Windows](media/xiaowang-demo.png)

## 功能

- 透明背景、保持置頂的桌面寵物視窗
- 支援拖曳、點擊、雙擊與右鍵互動
- 站立、揮手、坐下與睡覺四種姿勢
- 輕微呼吸動態與可選擇的自動散步
- 系統匣控制顯示、大小、散步速度與置頂
- `Ctrl+Alt+W` 切換勿擾／滑鼠穿透模式
- 25 分鐘專注與自動 5 分鐘休息
- 每 30 分鐘提醒喝水
- 依早上、中午、下午、晚上及深夜顯示不同對話
- 完全離線執行，沒有外部服務、帳號或遙測

## 快速開始

1. 下載並解壓縮最新的 Release ZIP。
2. 雙擊 `Start-XiaoWang.cmd`。
3. 在小汪或工作列右下角的小汪圖示按右鍵，即可開啟控制選單。

Windows PowerShell 5.1、WPF 與 Windows Forms 都是 Windows 內建元件，不需要另外安裝。

## 操作方式

| 操作 | 結果 |
| --- | --- |
| 點一下小汪 | 揮手並顯示一句話 |
| 拖曳小汪 | 移動桌面位置 |
| 雙擊小汪 | 睡覺或起床 |
| 右鍵點小汪 | 開啟快速控制 |
| `Ctrl+Alt+W` | 切換勿擾／滑鼠穿透模式 |
| 雙擊系統匣圖示 | 顯示或隱藏小汪 |

## 調整大小

開啟 `XiaoWangPet.ps1`，修改檔案上方的設定：

```powershell
$petScale = 0.75
```

例如 `0.60` 會更小，`1.00` 是原始尺寸。也可以直接從系統匣選單切換大小。

## AI 圖片聲明

角色參考圖由專案作者提供，屬 AI 生成圖片；透明去背與三個動作姿勢亦透過 AI 圖片工具生成或編修，再由專案作者挑選並整合。本專案未刻意使用第三方藝人、團體或品牌角色素材。

MIT License 僅適用於程式碼。圖片素材另依 [ASSET_NOTICE.md](ASSET_NOTICE.md) 說明處理。

## 授權

程式碼採用 [MIT License](LICENSE)。圖片素材不包含在 MIT 授權範圍內，詳見 [ASSET_NOTICE.md](ASSET_NOTICE.md)。
