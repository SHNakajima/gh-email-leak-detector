#!/bin/bash

# git-filter-repo を使用してGit履歴からメールアドレスを書き換えるスクリプト
# 対象リポジトリを指定して一括処理が可能

set -e

# 色の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}⚠️  git-filter-repo を使用した履歴書き換えツール ⚠️${NC}"
echo "=================================================="
echo -e "${YELLOW}このツールはGit履歴を完全に書き換えます${NC}"
echo -e "${YELLOW}必ずバックアップを取ってから実行してください${NC}"
echo "=================================================="

# git-filter-repo のインストール確認
if ! command -v git-filter-repo >/dev/null 2>&1; then
    echo -e "${RED}エラー: git-filter-repo がインストールされていません${NC}"
    echo ""
    echo "インストール方法:"
    echo "• pip install git-filter-repo"
    echo "• brew install git-filter-repo (macOS)"
    echo "• apt install git-filter-repo (Ubuntu/Debian)"
    echo ""
    exit 1
fi

# GitHub CLIの認証確認（リポジトリ一覧取得のため）
if ! command -v gh >/dev/null 2>&1; then
    echo -e "${YELLOW}警告: GitHub CLIがインストールされていません${NC}"
    echo "手動でリポジトリを指定する必要があります"
    GH_AVAILABLE=false
else
    if gh auth status >/dev/null 2>&1; then
        GH_AVAILABLE=true
        USERNAME=$(gh api user --jq '.login' 2>/dev/null || echo "")
    else
        echo -e "${YELLOW}警告: GitHub CLIで認証されていません${NC}"
        GH_AVAILABLE=false
    fi
fi

# 対象リポジトリの選択
echo ""
echo -e "${BLUE}対象リポジトリの選択:${NC}"
echo "1. 現在のディレクトリのリポジトリのみ"
echo "2. 指定したローカルリポジトリパス"
echo "3. GitHubから選択（GitHub CLI必要）"
echo "4. すべてのGitHubリポジトリ（GitHub CLI必要）"

read -p "選択してください [1-4]: " REPO_MODE

TARGET_REPOS=()

case $REPO_MODE in
    1)
        # 現在のディレクトリがGitリポジトリかチェック
        if [ ! -d ".git" ]; then
            echo -e "${RED}エラー: 現在のディレクトリはGitリポジトリではありません${NC}"
            exit 1
        fi
        TARGET_REPOS+=("$(pwd)")
        echo -e "${GREEN}対象: 現在のディレクトリ${NC}"
        ;;
    2)
        echo "リポジトリのパスを入力してください（複数の場合は空行で終了）:"
        while true; do
            read -p "リポジトリパス: " repo_path
            if [ -z "$repo_path" ]; then
                break
            fi
            if [ ! -d "$repo_path/.git" ]; then
                echo -e "${YELLOW}警告: $repo_path はGitリポジトリではありません${NC}"
                continue
            fi
            TARGET_REPOS+=("$repo_path")
            echo -e "${GREEN}追加: $repo_path${NC}"
        done
        ;;
    3)
        if [ "$GH_AVAILABLE" != "true" ]; then
            echo -e "${RED}エラー: GitHub CLIが利用できません${NC}"
            exit 1
        fi
        echo -e "${BLUE}GitHubリポジトリ一覧を取得中...${NC}"
        REPOS_JSON=$(gh repo list --limit 1000 --json name,isPrivate)
        REPO_COUNT=$(echo "$REPOS_JSON" | jq length)
        
        if [ "$REPO_COUNT" -eq 0 ]; then
            echo -e "${YELLOW}リポジトリが見つかりませんでした${NC}"
            exit 0
        fi
        
        echo "利用可能なリポジトリ:"
        for i in $(seq 0 $((REPO_COUNT - 1))); do
            REPO_NAME=$(echo "$REPOS_JSON" | jq -r ".[$i].name")
            IS_PRIVATE=$(echo "$REPOS_JSON" | jq -r ".[$i].isPrivate")
            PRIVACY_LABEL=""
            if [ "$IS_PRIVATE" = "true" ]; then
                PRIVACY_LABEL=" (Private)"
            else
                PRIVACY_LABEL=" (Public)"
            fi
            echo "$((i + 1)). $REPO_NAME$PRIVACY_LABEL"
        done
        
        echo ""
        echo "処理したいリポジトリの番号を入力してください（複数の場合はスペース区切り、例: 1 3 5）:"
        read -p "選択: " -a SELECTED_NUMBERS
        
        for num in "${SELECTED_NUMBERS[@]}"; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "$REPO_COUNT" ]; then
                REPO_NAME=$(echo "$REPOS_JSON" | jq -r ".[$(($num - 1))].name")
                TARGET_REPOS+=("$USERNAME/$REPO_NAME")
                echo -e "${GREEN}選択: $REPO_NAME${NC}"
            else
                echo -e "${YELLOW}警告: 無効な番号 '$num' をスキップしました${NC}"
            fi
        done
        ;;
    4)
        if [ "$GH_AVAILABLE" != "true" ]; then
            echo -e "${RED}エラー: GitHub CLIが利用できません${NC}"
            exit 1
        fi
        echo -e "${BLUE}すべてのGitHubリポジトリを取得中...${NC}"
        REPOS_JSON=$(gh repo list --limit 1000 --json name)
        REPO_COUNT=$(echo "$REPOS_JSON" | jq length)
        
        for i in $(seq 0 $((REPO_COUNT - 1))); do
            REPO_NAME=$(echo "$REPOS_JSON" | jq -r ".[$i].name")
            TARGET_REPOS+=("$USERNAME/$REPO_NAME")
        done
        echo -e "${GREEN}対象リポジトリ数: ${#TARGET_REPOS[@]}${NC}"
        ;;
    *)
        echo -e "${RED}無効な選択です${NC}"
        exit 1
        ;;
esac

if [ ${#TARGET_REPOS[@]} -eq 0 ]; then
    echo -e "${RED}処理対象のリポジトリがありません${NC}"
    exit 1
fi
echo -e "${BLUE}設定を入力してください:${NC}"
read -p "置換対象のメールアドレス: " OLD_EMAIL
read -p "新しいメールアドレス: " NEW_EMAIL
read -p "新しい名前 (空白でスキップ): " NEW_NAME

# GitHubユーザー名を取得してnoreplyメールを提案
if [ "$GH_AVAILABLE" = "true" ] && [ -n "$USERNAME" ]; then
    echo -e "${GREEN}推奨noreplyメール: $USERNAME@users.noreply.github.com${NC}"
fi

# 入力値の確認
echo ""
echo -e "${BLUE}確認:${NC}"
echo "処理対象リポジトリ数: ${#TARGET_REPOS[@]}"
for repo in "${TARGET_REPOS[@]}"; do
    echo "  - $repo"
done
echo "置換対象: $OLD_EMAIL"
echo "新しいメール: $NEW_EMAIL"
if [ -n "$NEW_NAME" ]; then
    echo "新しい名前: $NEW_NAME"
fi

echo ""
echo -e "${RED}この操作は以下の影響があります:${NC}"
echo "• すべてのコミットハッシュが変更されます"
echo "• 他の開発者のローカルリポジトリとの整合性が失われます"
echo "• プルリクエストやissueのリンクが壊れる可能性があります"
echo "• 元に戻すことはできません"

echo ""
read -p "続行しますか? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "操作をキャンセルしました"
    exit 0
fi

# バックアップの作成を推奨
echo ""
echo -e "${YELLOW}各リポジトリのバックアップ作成を強く推奨します${NC}"
if [ "$REPO_MODE" = "1" ] || [ "$REPO_MODE" = "2" ]; then
    echo "例: git clone --mirror . ../backup-\$(basename \$(pwd))"
fi
read -p "バックアップを作成しましたか? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}バックアップを作成してから再実行してください${NC}"
    exit 1
fi

# 作業用ディレクトリの作成
WORK_DIR=$(mktemp -d)
echo -e "${BLUE}作業ディレクトリ: $WORK_DIR${NC}"

# 一時ファイルの作成
MAILMAP_FILE="$WORK_DIR/mailmap"

# mailmap ファイルの作成
if [ -n "$NEW_NAME" ]; then
    echo "$NEW_NAME <$NEW_EMAIL> <$OLD_EMAIL>" > "$MAILMAP_FILE"
else
    echo "Unknown <$NEW_EMAIL> <$OLD_EMAIL>" > "$MAILMAP_FILE"
fi

echo -e "${BLUE}Mailmap ファイルの内容:${NC}"
cat "$MAILMAP_FILE"

# 全体のForce Push確認（事前確認オプション）
echo ""
echo -e "${BLUE}Force Push設定:${NC}"
echo "1. 各リポジトリごとに確認する（推奨）"
echo "2. 全リポジトリを一括でForce Pushする"
echo "3. Force Pushをスキップする"

read -p "選択してください [1-3]: " PUSH_MODE

BATCH_PUSH_CONFIRMED=false
if [ "$PUSH_MODE" = "2" ]; then
    echo ""
    echo -e "${RED}⚠️  一括Force Pushの確認 ⚠️${NC}"
    echo "対象リポジトリ数: ${#TARGET_REPOS[@]}"
    echo "すべてのリポジトリの履歴が一括で書き換えられます"
    echo "この操作は元に戻すことができません"
    echo ""
    read -p "本当に一括Force Pushを実行しますか? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        BATCH_PUSH_CONFIRMED=true
        echo -e "${GREEN}一括Force Pushが承認されました${NC}"
    else
        echo -e "${YELLOW}個別確認モードに変更します${NC}"
        PUSH_MODE="1"
    fi
fi
echo ""
echo -e "${BLUE}リポジトリの処理を開始します...${NC}"

PROCESSED_COUNT=0
FAILED_REPOS=()

for repo in "${TARGET_REPOS[@]}"; do
    echo ""
    echo "=================================================="
    echo -e "${BLUE}処理中: $repo [$((PROCESSED_COUNT + 1))/${#TARGET_REPOS[@]}]${NC}"
    echo "=================================================="
    
    REPO_DIR=""
    CLEANUP_NEEDED=false
    
    if [[ "$repo" == *"/"* ]] && [ "$REPO_MODE" != "2" ]; then
        # GitHubリポジトリの場合（username/repo形式）
        REPO_NAME=$(basename "$repo")
        REPO_DIR="$WORK_DIR/$REPO_NAME"
        
        echo -e "${BLUE}リポジトリをクローン中...${NC}"
        if git clone "https://github.com/$repo.git" "$REPO_DIR"; then
            CLEANUP_NEEDED=true
        else
            echo -e "${RED}エラー: $repo のクローンに失敗しました${NC}"
            FAILED_REPOS+=("$repo")
            continue
        fi
    else
        # ローカルリポジトリの場合
        REPO_DIR="$repo"
        if [ ! -d "$REPO_DIR/.git" ]; then
            echo -e "${RED}エラー: $repo はGitリポジトリではありません${NC}"
            FAILED_REPOS+=("$repo")
            continue
        fi
    fi
    
    # リポジトリディレクトリに移動
    cd "$REPO_DIR"
    
    # 現在の名前を取得（mailmapで使用）
    if [ -z "$NEW_NAME" ]; then
        CURRENT_NAME=$(git log --format='%an' --author="$OLD_EMAIL" -1 2>/dev/null || echo "Unknown")
        echo "$CURRENT_NAME <$NEW_EMAIL> <$OLD_EMAIL>" > "$MAILMAP_FILE"
    fi
    
    # 対象メールアドレスが存在するかチェック
    if ! git log --author="$OLD_EMAIL" --format="%ae" | grep -q "$OLD_EMAIL"; then
        echo -e "${YELLOW}スキップ: $OLD_EMAIL を含むコミットが見つかりません${NC}"
        PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
        continue
    fi
    
    echo -e "${BLUE}履歴を書き換え中...${NC}"
    
    # git-filter-repo を実行
    if git filter-repo --use-mailmap --mailmap="$MAILMAP_FILE" --force; then
        echo -e "${GREEN}✓ 履歴の書き換えが完了しました${NC}"
        
        # 変更の確認
        echo -e "${BLUE}変更結果の確認:${NC}"
        git log --oneline --format="%h %an <%ae> %s" -5
        
        # リモートリポジトリの処理
        if [[ "$repo" == *"/"* ]] && [ "$REPO_MODE" != "2" ]; then
            # GitHubリポジトリの場合
            REPO_URL="https://github.com/$repo.git"
            echo ""
            echo -e "${BLUE}リモートリポジトリの設定...${NC}"
            git remote add origin "$REPO_URL"
            
            # Force Push実行の判定
            SHOULD_PUSH=false
            case $PUSH_MODE in
                1)
                    echo -e "${YELLOW}⚠️  Force Pushの確認 ⚠️${NC}"
                    echo "リポジトリ: $repo"
                    echo "URL: $REPO_URL"
                    echo "この操作により、リモートの履歴が完全に書き換えられます"
                    echo ""
                    read -p "Force pushを実行しますか? [y/N]: " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        SHOULD_PUSH=true
                    fi
                    ;;
                2)
                    if [ "$BATCH_PUSH_CONFIRMED" = "true" ]; then
                        SHOULD_PUSH=true
                        echo -e "${BLUE}一括Force Push: $repo${NC}"
                    fi
                    ;;
                3)
                    echo -e "${YELLOW}Force pushをスキップしました${NC}"
                    ;;
            esac
            
            if [ "$SHOULD_PUSH" = "true" ]; then
                echo -e "${BLUE}Force push中...${NC}"
                if git push origin --force --all && git push origin --force --tags; then
                    echo -e "${GREEN}✓ Force pushが完了しました${NC}"
                else
                    echo -e "${RED}エラー: Force pushに失敗しました${NC}"
                    FAILED_REPOS+=("$repo (push failed)")
                fi
            else
                echo "手動でpushする場合:"
                echo "  cd $REPO_DIR"
                echo "  git remote add origin $REPO_URL"
                echo "  git push origin --force --all"
                echo "  git push origin --force --tags"
            fi
        else
            # ローカルリポジトリの場合
            echo ""
            echo -e "${BLUE}リモートリポジトリの確認...${NC}"
            REMOTES=$(git remote -v 2>/dev/null || echo "")
            
            if [ -n "$REMOTES" ]; then
                echo "検出されたリモートリポジトリ:"
                echo "$REMOTES"
                
                # Force Push実行の判定
                SHOULD_PUSH=false
                case $PUSH_MODE in
                    1)
                        echo ""
                        echo -e "${YELLOW}⚠️  Force Pushの確認 ⚠️${NC}"
                        echo "リポジトリ: $repo"
                        echo "この操作により、リモートの履歴が完全に書き換えられます"
                        echo ""
                        read -p "Force pushを実行しますか? [y/N]: " -n 1 -r
                        echo
                        if [[ $REPLY =~ ^[Yy]$ ]]; then
                            SHOULD_PUSH=true
                        fi
                        ;;
                    2)
                        if [ "$BATCH_PUSH_CONFIRMED" = "true" ]; then
                            SHOULD_PUSH=true
                            echo -e "${BLUE}一括Force Push: $repo${NC}"
                        fi
                        ;;
                    3)
                        echo -e "${YELLOW}Force pushをスキップしました${NC}"
                        ;;
                esac
                
                if [ "$SHOULD_PUSH" = "true" ]; then
                    echo -e "${BLUE}Force push中...${NC}"
                    if git push --force --all && git push --force --tags; then
                        echo -e "${GREEN}✓ Force pushが完了しました${NC}"
                    else
                        echo -e "${RED}エラー: Force pushに失敗しました${NC}"
                        FAILED_REPOS+=("$repo (push failed)")
                    fi
                else
                    echo "手動でpushする場合:"
                    echo "  cd $REPO_DIR"
                    echo "  git push --force --all"
                    echo "  git push --force --tags"
                fi
            else
                echo -e "${YELLOW}リモートリポジトリが設定されていません${NC}"
                echo "手動でリモートを設定してpushしてください"
            fi
        fi
    else
        echo -e "${RED}エラー: git-filter-repo の実行に失敗しました${NC}"
        FAILED_REPOS+=("$repo")
    fi
    
    PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
done

# 処理結果のサマリー
echo ""
echo "=================================================="
echo -e "${BLUE}処理完了サマリー${NC}"
echo "=================================================="
echo -e "${GREEN}成功: $((${#TARGET_REPOS[@]} - ${#FAILED_REPOS[@]})) リポジトリ${NC}"
if [ ${#FAILED_REPOS[@]} -gt 0 ]; then
    echo -e "${RED}失敗: ${#FAILED_REPOS[@]} リポジトリ${NC}"
    for failed_repo in "${FAILED_REPOS[@]}"; do
        echo "  - $failed_repo"
    done
fi

# 一時ファイルの削除
rm -rf "$WORK_DIR"

echo ""
echo -e "${BLUE}重要な次のステップ:${NC}"
echo "1. 各リポジトリの変更内容を確認してください"
if [ "$PUSH_MODE" = "3" ]; then
    echo "2. 必要に応じて手動でforce pushしてください"
fi
echo "2. チームメンバーに履歴変更を通知してください"
echo "3. 他の開発者には fresh clone を依頼してください"
echo ""
echo -e "${YELLOW}注意事項:${NC}"
echo "• git-filter-repo はリモートを自動削除します"
echo "• プルリクエストやissueは再作成が必要な場合があります"
echo "• この変更は元に戻すことができません"

echo ""
echo -e "${GREEN}処理が完了しました${NC}"