#!/bin/bash

# GitHub CLIを使用してすべてのリポジトリのコミットからメールアドレスをチェックするスクリプト
# 一時ファイルを使わずにメモリ上で処理するバージョン

set -e

# 色の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 結果保存用の変数
EMAIL_DATA=""

echo -e "${BLUE}GitHub リポジトリメール流出チェックツール${NC}"
echo "=================================================="

# GitHub CLIの認証確認
if ! gh auth status >/dev/null 2>&1; then
    echo -e "${RED}エラー: GitHub CLIで認証されていません${NC}"
    echo "gh auth login を実行してください"
    exit 1
fi

# 現在のユーザー名を取得
USERNAME=$(gh api user --jq '.login')
echo -e "${GREEN}ユーザー: $USERNAME${NC}"

echo -e "${BLUE}リポジトリ一覧を取得中...${NC}"

# すべてのリポジトリを取得（プライベートも含む）
REPOS_JSON=$(gh repo list --limit 1000 --json name,isPrivate)

# リポジトリ数を確認
REPO_COUNT=$(echo "$REPOS_JSON" | jq length)
echo -e "${GREEN}取得したリポジトリ数: $REPO_COUNT${NC}"

if [ "$REPO_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}リポジトリが見つかりませんでした${NC}"
    exit 0
fi

# 各リポジトリを処理
echo -e "${BLUE}各リポジトリのコミットを確認中...${NC}"

for i in $(seq 0 $((REPO_COUNT - 1))); do
    REPO_NAME=$(echo "$REPOS_JSON" | jq -r ".[$i].name")
    IS_PRIVATE=$(echo "$REPOS_JSON" | jq -r ".[$i].isPrivate")
    
    echo -n "[$((i + 1))/$REPO_COUNT] $REPO_NAME "
    if [ "$IS_PRIVATE" = "true" ]; then
        echo -n "(Private) "
    else
        echo -n "(Public) "
    fi
    
    # コミット一覧を取得してメールアドレスを抽出
    COMMIT_OUTPUT=$(gh api "repos/$USERNAME/$REPO_NAME/commits" --paginate --jq '.[] | "\(.commit.author.email) \(.commit.committer.email)"' 2>/dev/null || echo "")
    
    if [ -z "$COMMIT_OUTPUT" ]; then
        echo -e "${YELLOW}スキップ (コミット取得失敗またはコミットなし)${NC}"
        continue
    fi
    
    # メールアドレスを抽出
    EMAILS=$(echo "$COMMIT_OUTPUT" | tr ' ' '\n' | grep -E '^[^@]+@[^@]+\.[^@]+$' | sort -u)
    
    if [ -n "$EMAILS" ]; then
        echo -e "${GREEN}✓${NC}"
        while IFS= read -r email; do
            if [[ "$email" != *"@users.noreply.github.com" ]]; then
                EMAIL_DATA="$EMAIL_DATA$email|$REPO_NAME"$'\n'
            fi
        done <<< "$EMAILS"
    else
        echo -e "${GREEN}✓ (GitHubのnoreplyメールのみ)${NC}"
    fi
done

echo ""
echo "=================================================="
echo -e "${BLUE}チェック結果${NC}"
echo "=================================================="

# 結果の表示
if [ -z "$EMAIL_DATA" ]; then
    echo -e "${GREEN}✅ メールアドレスの流出は検出されませんでした${NC}"
    echo "すべてのコミットでGitHubのnoreplyメールアドレスが使用されています"
else
    echo -e "${RED}⚠️  以下のメールアドレスがコミットに含まれています:${NC}"
    echo ""
    
    # メールアドレスごとに集計
    UNIQUE_EMAILS=$(echo "$EMAIL_DATA" | cut -d'|' -f1 | sort -u)
    
    while IFS= read -r email; do
        if [ -n "$email" ]; then
            # 同じメールアドレスの出現回数とリポジトリ一覧を取得
            count=$(echo "$EMAIL_DATA" | grep -c "^$email|" || echo "0")
            repos=$(echo "$EMAIL_DATA" | grep "^$email|" | cut -d'|' -f2 | sort -u | tr '\n' ' ')
            
            echo -e "${YELLOW}📧 $email${NC}"
            echo -e "   出現回数: $count"
            echo -e "   リポジトリ: $repos"
            echo ""
        fi
    done <<< "$UNIQUE_EMAILS"
    
    echo -e "${BLUE}推奨される対策:${NC}"
    echo "1. 今後のコミットでGitHubのnoreplyメールを使用する"
    echo "   git config --global user.email \"$USERNAME@users.noreply.github.com\""
    echo ""
    echo "2. 既存のコミット履歴を書き換える (注意: 危険な操作)"
    echo "   git filter-branch または git filter-repo を使用"
    echo ""
    echo "3. センシティブなメールアドレスの場合は、該当リポジトリの削除を検討"
fi

echo ""
echo -e "${BLUE}チェック完了${NC}"