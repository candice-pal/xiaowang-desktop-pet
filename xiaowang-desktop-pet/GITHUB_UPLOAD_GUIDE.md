# GitHub 上傳指南

## 建立公開儲存庫

1. 登入 GitHub，選擇 **New repository**。
2. Repository name 建議填入 `xiaowang-desktop-pet`。
3. Visibility 選擇 **Public**。
4. 不要勾選自動建立 README、`.gitignore` 或 License，因為本資料夾已經準備完成。
5. 建立儲存庫後，把本資料夾內的所有檔案上傳到儲存庫根目錄。

## 建立 Release

1. 進入儲存庫右側的 **Releases**，選擇 **Create a new release**。
2. Tag 建議使用 `v1.0.0`。
3. Release title 可使用 `Xiao Wang Desktop Pet v1.0.0`。
4. 上傳另外提供的 `xiaowang-desktop-pet-v1.0.0.zip`。
5. 在說明中列出 Windows 系統需求與主要功能，再發布 Release。

## 發布前確認

- README 頁面能正常顯示小汪圖片。
- GitHub Actions 的 Validate Windows desktop pet 工作成功。
- 儲存庫中沒有桌面捷徑 `.lnk`、個人路徑、API 金鑰或其他私人資料。
- 已確認原 AI 圖片生成平台允許將輸出公開展示。
