# gh-email-leak-detector


🛡️ **Git履歴からのメールアドレス流出を検出・修正するツールセット**

GitHubリポジトリのコミット履歴に含まれるメールアドレスの流出を検出し、安全に修正するためのBashスクリプトセットです。

## 📋 概要

- **detector.sh**: 全リポジトリのコミット履歴をスキャンしてメールアドレス流出を検出
- **fixer.sh**: 検出されたメールアドレスを安全にGitHub noreplyメールに書き換え

## 🚀 クイックスタート

### 1. 前提条件

```bash
# GitHub CLI のインストールと認証
brew install gh  # macOS
# または apt install gh  # Ubuntu/Debian

gh auth login

# git-filter-repo のインストール（fixer.sh用）
pip install git-filter-repo
# または brew install git-filter-repo  # macOS

# 権限付与
chmod a+x *.sh
```

### 2. 流出検出

```bash
# すべてのリポジトリをチェック
./detector.sh
```

### 3. 流出修正

```bash
# 検出されたメールアドレスを修正
./fixer.sh
```

## 🔍 detector.sh - メール流出検出ツール

### 機能
- 全GitHubリポジトリのコミット履歴をスキャン
- `@users.noreply.github.com` 以外のメールアドレスを検出
- プライベート・パブリックリポジトリの区別表示
- 詳細な流出レポートを生成

### 使用方法

```bash
./detector.sh
```

### 出力例

```
GitHub リポジトリメール流出チェックツール
==================================================
ユーザー: your-username
取得したリポジトリ数: 25

[1/25] my-project (Public) ✓
[2/25] private-repo (Private) ✓ (GitHubのnoreplyメールのみ)
[3/25] old-project (Public) ✓

==================================================
チェック結果
==================================================
⚠️  以下のメールアドレスがコミットに含まれています:

📧 john.doe@example.com
   出現回数: 15
   リポジトリ: my-project old-project legacy-app

推奨される対策:
1. 今後のコミットでGitHubのnoreplyメールを使用する
   git config --global user.email "your-username@users.noreply.github.com"

2. 既存のコミット履歴を書き換える (注意: 危険な操作)
   git filter-branch または git filter-repo を使用

3. センシティブなメールアドレスの場合は、該当リポジトリの削除を検討
```

## 🔧 fixer.sh - メール流出修正ツール

### 機能
- 複数リポジトリの一括処理
- 安全な履歴書き換え（git-filter-repo使用）
- 自動Force Push（確認付き）
- 詳細なエラーハンドリング

### 使用方法

```bash
./fixer.sh
```

### リポジトリ選択オプション

1. **現在のディレクトリのリポジトリのみ**
2. **指定したローカルリポジトリパス**
3. **GitHubから選択**
4. **すべてのGitHubリポジトリ**

### Force Push設定

1. **各リポジトリごとに確認する（推奨）**
2. **全リポジトリを一括でForce Pushする**
3. **Force Pushをスキップする**

### 実行例

```bash
./fixer.sh

# 設定例:
対象リポジトリの選択: 3 (GitHubから選択)
選択: 1 3 5 7  # 複数リポジトリを番号で指定

置換対象のメールアドレス: john.doe@example.com
新しいメールアドレス: your-username@users.noreply.github.com
新しい名前 (空白でスキップ): John Doe

Force Push設定: 1 (個別確認)
```

## ⚠️ 重要な注意事項

### 🔴 リスク
- **履歴書き換えは不可逆的**: 元に戻すことはできません
- **チーム開発への影響**: 他の開発者のローカルリポジトリとの整合性が失われます
- **完全な削除は困難**: 他の人がクローンしている可能性があります

### 🟡 必須の事前準備
1. **バックアップ作成**: `git clone --mirror . ../backup-repo`
2. **チーム通知**: 履歴変更を事前に通知
3. **作業調整**: 進行中のプルリクエストやブランチ作業の確認

### 🟢 推奨手順
1. `detector.sh`で流出状況を確認
2. 重要度の低いリポジトリでテスト実行
3. バックアップを作成
4. チームに通知
5. `fixer.sh`で修正実行
6. 全員にfresh cloneを依頼

## 🛠️ トラブルシューティング

### GitHub CLI認証エラー
```bash
gh auth login
gh auth refresh
```

### Force Push失敗
- ブランチ保護設定を一時的に無効化
- リポジトリの管理者権限を確認
- ネットワーク接続を確認

## 📚 詳細情報

### 依存関係
- Bash 4.0+
- Git 2.0+
- GitHub CLI
- git-filter-repo
- jq

## 📄 ライセンス

MIT License

## 🔗 関連リンク

- [GitHub CLI Documentation](https://cli.github.com/manual/)
- [git-filter-repo Documentation](https://github.com/newren/git-filter-repo)
- [GitHub Email Privacy Settings](https://docs.github.com/en/account-and-profile/setting-up-and-managing-your-personal-account-on-github/managing-email-preferences/setting-your-commit-email-address)

---

⚠️ **免責事項**: このツールは教育・個人利用目的で提供されています。商用利用や重要なプロジェクトでの使用は十分にテストしてから行ってください。履歴の書き換えによる影響について、作者は一切の責任を負いません。