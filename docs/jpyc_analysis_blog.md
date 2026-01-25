# 【完全解説】新JPYCの成長を可視化！Dune Analyticsで累積取引量・ユーザー数を分析するSQLクエリ

## はじめに

2025年10月27日にローンチされた日本初の規制対応ステーブルコイン「JPYC」。この記事では、Ethereum・Polygon・Avalancheの3チェーンで展開されているJPYCの実際の利用状況を、**Dune Analytics**のSQLクエリで分析する方法を、**SQL初心者の方にもわかりやすく**解説します。

### この記事で作成するもの

以下のデータを時系列で可視化できるクエリを作ります：

- ✅ **累積取引量（円建て）** - どれだけJPYCが動いたか
- ✅ **累積取引数** - 何回取引されたか
- ✅ **累積ユーザー数（チェーン別）** - 各チェーンで何人が使ったか
- ✅ **累積ユニークユーザー数（全体）** - 実際に何人が使っているか（重複除外）

---

## 完成形のSQLクエリ

まず、完成形のコードを掲載します。後ほど各部分を詳しく解説します。

```sql
-- 新JPYC 総合分析：2025年10月1日以降を表示（累積値は全期間計算）
WITH all_transfers AS (
    -- Ethereum
    SELECT 
        DATE_TRUNC('day', evt_block_time) as day,
        'Ethereum' as chain,
        value / 1e18 as amount_jpy,
        "from" as from_address,
        "to" as to_address
    FROM erc20_ethereum.evt_Transfer
    WHERE contract_address = 0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29
    AND "from" != 0x0000000000000000000000000000000000000000
    AND "to" != 0x0000000000000000000000000000000000000000
    AND evt_block_time >= TIMESTAMP '2025-10-27'  -- JPYCローンチ日以降
    
    UNION ALL
    
    -- Polygon
    SELECT 
        DATE_TRUNC('day', evt_block_time) as day,
        'Polygon' as chain,
        value / 1e18 as amount_jpy,
        "from" as from_address,
        "to" as to_address
    FROM erc20_polygon.evt_Transfer
    WHERE contract_address = 0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29
    AND "from" != 0x0000000000000000000000000000000000000000
    AND "to" != 0x0000000000000000000000000000000000000000
    AND evt_block_time >= TIMESTAMP '2025-10-27'  -- JPYCローンチ日以降
    
    UNION ALL
    
    -- Avalanche
    SELECT 
        DATE_TRUNC('day', evt_block_time) as day,
        'Avalanche' as chain,
        value / 1e18 as amount_jpy,
        "from" as from_address,
        "to" as to_address
    FROM erc20_avalanche_c.evt_Transfer
    WHERE contract_address = 0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29
    AND "from" != 0x0000000000000000000000000000000000000000
    AND "to" != 0x0000000000000000000000000000000000000000
    AND evt_block_time >= TIMESTAMP '2025-10-27'  -- JPYCローンチ日以降
),

daily_stats_by_chain AS (
    SELECT 
        day,
        chain,
        COUNT(*) as daily_tx_count,
        SUM(amount_jpy) as daily_volume_jpy
    FROM all_transfers
    GROUP BY day, chain
),

all_addresses_by_chain AS (
    SELECT day, chain, from_address as address FROM all_transfers
    UNION ALL
    SELECT day, chain, to_address as address FROM all_transfers
),

first_appearance_by_chain AS (
    SELECT 
        chain,
        address,
        MIN(day) as first_day
    FROM all_addresses_by_chain
    GROUP BY chain, address
),

daily_new_users_by_chain AS (
    SELECT 
        first_day as day,
        chain,
        COUNT(*) as new_users
    FROM first_appearance_by_chain
    GROUP BY first_day, chain
),

all_addresses_global AS (
    SELECT day, from_address as address FROM all_transfers
    UNION ALL
    SELECT day, to_address as address FROM all_transfers
),

first_appearance_global AS (
    SELECT 
        address,
        MIN(day) as first_day
    FROM all_addresses_global
    GROUP BY address
),

daily_new_users_global AS (
    SELECT 
        first_day as day,
        COUNT(*) as new_users_global
    FROM first_appearance_global
    GROUP BY first_day
),

combined AS (
    SELECT 
        COALESCE(s.day, u.day) as day,
        COALESCE(s.chain, u.chain) as chain,
        COALESCE(s.daily_tx_count, 0) as daily_transactions,
        COALESCE(s.daily_volume_jpy, 0) as daily_volume_jpy,
        COALESCE(u.new_users, 0) as daily_new_users_by_chain
    FROM daily_stats_by_chain s
    FULL OUTER JOIN daily_new_users_by_chain u 
        ON s.day = u.day AND s.chain = u.chain
),

-- グローバル値を先に計算（ウィンドウ関数のネスト回避）
with_global_daily AS (
    SELECT 
        c.day,
        c.chain,
        c.daily_transactions,
        c.daily_volume_jpy,
        c.daily_new_users_by_chain,
        -- グローバル新規ユーザー数（重複排除）
        -- 各日の最初のチェーン（アルファベット順）の行にだけ値を設定
        CASE 
            WHEN c.chain = FIRST_VALUE(c.chain) OVER (PARTITION BY c.day ORDER BY c.chain) 
            THEN COALESCE(g.new_users_global, 0) 
            ELSE 0 
        END as daily_new_users_global
    FROM combined c
    LEFT JOIN daily_new_users_global g ON c.day = g.day
)

-- 最終出力：累積値を計算
SELECT 
    day,
    chain,
    
    -- 日次データ
    daily_transactions,
    daily_volume_jpy,
    daily_new_users_by_chain,
    daily_new_users_global,
    
    -- 累積データ（チェーン別）
    SUM(daily_transactions) OVER (PARTITION BY chain ORDER BY day) as cumulative_transactions,
    SUM(daily_volume_jpy) OVER (PARTITION BY chain ORDER BY day) as cumulative_volume_jpy,
    SUM(daily_new_users_by_chain) OVER (PARTITION BY chain ORDER BY day) as cumulative_users_by_chain,
    
    -- 累積グローバルユーザー数（重複排除）
    SUM(daily_new_users_global) OVER (ORDER BY day) as cumulative_users_global
    
FROM with_global_daily
WHERE day >= DATE '2025-10-01'  -- 表示期間（累積値は全期間で計算）
ORDER BY day, chain
```

---

## クエリの全体構造：CTEとは？

このクエリは**CTE（Common Table Expression）**という技法を使っています。

### CTEとは？

CTEは日本語で「共通テーブル式」と呼ばれ、**複雑なクエリを小さなパーツに分けて、段階的に処理する**ための仕組みです。

**構文:**
```sql
WITH テーブル名1 AS (
    SELECT ...
),
テーブル名2 AS (
    SELECT ... FROM テーブル名1
)
SELECT ... FROM テーブル名2
```

料理に例えると：
- **CTE1**: 野菜を切る
- **CTE2**: 肉を焼く
- **CTE3**: 調味料を混ぜる
- **最終SELECT**: すべてを組み合わせて完成

このクエリでは**9つのCTE**を使って、段階的にデータを加工していきます。

---

## 各CTEの詳細解説

### CTE 1: `all_transfers` - 全トランザクションを取得

```sql
WITH all_transfers AS (
    -- Ethereum
    SELECT 
        DATE_TRUNC('day', evt_block_time) as day,
        'Ethereum' as chain,
        value / 1e18 as amount_jpy,
        "from" as from_address,
        "to" as to_address
    FROM erc20_ethereum.evt_Transfer
    WHERE contract_address = 0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29
    AND "from" != 0x0000000000000000000000000000000000000000
    AND "to" != 0x0000000000000000000000000000000000000000
    
    UNION ALL
    -- Polygon と Avalanche も同様
)
```

**何をしているか:**
1. **Ethereum、Polygon、Avalancheの3チェーン**から、JPYCのTransferイベントを取得
2. **日付単位に丸める**: `DATE_TRUNC('day', evt_block_time)` で時刻を切り捨て
3. **金額を円に変換**: `value / 1e18` でJPYCは18 decimalsなので、1e18で割る
4. **Mint/Burnを除外**: ゼロアドレス（`0x0000...`）との取引は除外

**ポイント:**
- `UNION ALL`: 複数のチェーンのデータを縦に結合
- `"from"` と `"to"`: SQLの予約語なのでダブルクォートで囲む必要がある

**具体例:**
| day | chain | amount_jpy | from_address | to_address |
|-----|-------|-----------|--------------|------------|
| 2025-10-27 | Ethereum | 50000 | 0xABC... | 0xDEF... |
| 2025-10-27 | Polygon | 100000 | 0x123... | 0x456... |

---

### CTE 2: `daily_stats_by_chain` - 日次統計を計算

```sql
daily_stats_by_chain AS (
    SELECT 
        day,
        chain,
        COUNT(*) as daily_tx_count,
        SUM(amount_jpy) as daily_volume_jpy
    FROM all_transfers
    GROUP BY day, chain
)
```

**何をしているか:**
1. **日付とチェーン**でグループ化
2. **取引数をカウント**: `COUNT(*)` でその日の取引数
3. **取引量を合計**: `SUM(amount_jpy)` でその日の合計金額

**具体例:**
| day | chain | daily_tx_count | daily_volume_jpy |
|-----|-------|----------------|------------------|
| 2025-10-27 | Ethereum | 30 | 1,438,187 |
| 2025-10-27 | Polygon | 371 | 22,865,648 |

---

### CTE 3-5: チェーン別のユニークユーザー数を計算

```sql
all_addresses_by_chain AS (
    SELECT day, chain, from_address as address FROM all_transfers
    UNION ALL
    SELECT day, chain, to_address as address FROM all_transfers
),

first_appearance_by_chain AS (
    SELECT 
        chain,
        address,
        MIN(day) as first_day
    FROM all_addresses_by_chain
    GROUP BY chain, address
),

daily_new_users_by_chain AS (
    SELECT 
        first_day as day,
        chain,
        COUNT(*) as new_users
    FROM first_appearance_by_chain
    GROUP BY first_day, chain
)
```

**何をしているか:**

**ステップ1 (`all_addresses_by_chain`):**
- `from_address`（送信者）と`to_address`（受信者）を**別々の行**として抽出
- これで「取引に関わったすべてのアドレス」のリストができる

**ステップ2 (`first_appearance_by_chain`):**
- 各アドレスが**初めて登場した日**を特定
- `MIN(day)` で最も古い日付を取得

**ステップ3 (`daily_new_users_by_chain`):**
- 各日の**新規ユーザー数**をカウント

**具体例:**
| day | chain | new_users |
|-----|-------|-----------|
| 2025-10-27 | Ethereum | 25 |
| 2025-10-28 | Ethereum | 10 |

**重要な点:**
- これは**チェーン別**なので、同じアドレスがEthereumとPolygonの両方で取引すると、2人としてカウントされます
- 次のステップで、この重複を除外した「真のユニークユーザー数」も計算します

---

### CTE 6-8: 全チェーン統合のユニークユーザー数（重複除外）

```sql
all_addresses_global AS (
    SELECT day, from_address as address FROM all_transfers
    UNION ALL
    SELECT day, to_address as address FROM all_transfers
),

first_appearance_global AS (
    SELECT 
        address,
        MIN(day) as first_day
    FROM all_addresses_global
    GROUP BY address
),

daily_new_users_global AS (
    SELECT 
        first_day as day,
        COUNT(*) as new_users_global
    FROM first_appearance_global
    GROUP BY first_day
)
```

**何をしているか:**

**チェーン別との違い:**
- `chain`カラムを含めない
- 同じアドレスが複数チェーンで取引しても、**1人としてカウント**

**具体例:**
アドレス`0xABC...`が：
- 2025-10-27にEthereumで取引
- 2025-10-30にPolygonで取引

→ **新規ユーザーとしてカウントされるのは2025-10-27のみ**

---

### CTE 9: `combined` - すべてのデータを結合

```sql
combined AS (
    SELECT 
        COALESCE(s.day, u.day) as day,
        COALESCE(s.chain, u.chain) as chain,
        COALESCE(s.daily_tx_count, 0) as daily_transactions,
        COALESCE(s.daily_volume_jpy, 0) as daily_volume_jpy,
        COALESCE(u.new_users, 0) as daily_new_users_by_chain
    FROM daily_stats_by_chain s
    FULL OUTER JOIN daily_new_users_by_chain u 
        ON s.day = u.day AND s.chain = u.chain
)
```

**何をしているか:**

**FULL OUTER JOIN:**
- 取引統計とユーザー統計を日付・チェーンで結合
- どちらかにしかデータがない日も含める

**COALESCE関数:**
- `COALESCE(値1, 値2)` は「値1がNULLなら値2を使う」
- データがない日は0として扱う

**具体例:**
| day | chain | daily_transactions | daily_new_users_by_chain |
|-----|-------|--------------------|--------------------------|
| 2025-10-27 | Ethereum | 30 | 25 |
| 2025-10-28 | Ethereum | 0 | 5 |（取引なし、新規ユーザーのみ）

---

## 最終SELECT：累積値の計算

```sql
SELECT 
    c.day,
    c.chain,
    c.daily_transactions,
    SUM(c.daily_transactions) OVER (PARTITION BY c.chain ORDER BY c.day) as cumulative_transactions,
    c.daily_volume_jpy,
    SUM(c.daily_volume_jpy) OVER (PARTITION BY c.chain ORDER BY c.day) as cumulative_volume_jpy,
    c.daily_new_users_by_chain,
    SUM(c.daily_new_users_by_chain) OVER (PARTITION BY c.chain ORDER BY c.day) as cumulative_users_by_chain,
    
    -- グローバル新規ユーザー数：各日の最初のチェーン（アルファベット順）の行にだけ値を設定
    CASE 
        WHEN c.chain = FIRST_VALUE(c.chain) OVER (PARTITION BY c.day ORDER BY c.chain) 
        THEN COALESCE(g.new_users_global, 0) 
        ELSE 0 
    END as daily_new_users_global,
    
    -- 累積グローバルユーザー数
    SUM(
        CASE 
            WHEN c.chain = FIRST_VALUE(c.chain) OVER (PARTITION BY c.day ORDER BY c.day, c.chain) 
            THEN COALESCE(g.new_users_global, 0) 
            ELSE 0 
        END
    ) OVER (ORDER BY c.day) as cumulative_users_global
    
FROM combined c
LEFT JOIN daily_new_users_global g ON c.day = g.day
WHERE c.day >= DATE '2025-10-01'
ORDER BY c.day, c.chain
```

### ウィンドウ関数とは？

**ウィンドウ関数**は、行ごとに「周辺の行も見ながら計算する」関数です。

**構文:**
```sql
SUM(列名) OVER (PARTITION BY グループ列 ORDER BY 並び順列)
```

**各部分の意味:**
- `SUM(列名)`: 合計を計算
- `OVER`: ウィンドウ関数であることを示す
- `PARTITION BY chain`: チェーンごとに別々に計算（EthereumとPolygonは別々）
- `ORDER BY day`: 日付順に累積していく

**具体例:**

元のデータ：
| day | chain | daily_transactions |
|-----|-------|--------------------|
| 10-27 | Ethereum | 30 |
| 10-28 | Ethereum | 50 |
| 10-29 | Ethereum | 40 |

↓ ウィンドウ関数適用後

| day | chain | daily_transactions | cumulative_transactions |
|-----|-------|--------------------|-------------------------|
| 10-27 | Ethereum | 30 | **30** |
| 10-28 | Ethereum | 50 | **80** (30+50) |
| 10-29 | Ethereum | 40 | **120** (30+50+40) |

---

### グローバルユーザー数の計算方法

ここが最も重要なポイントです！

**問題:**
`combined`テーブルの粒度は「日次 × チェーン」です。つまり、1日に3行（Ethereum、Polygon、Avalanche）存在します。

もし単純にグローバルユーザー数を結合すると：

| day | chain | new_users_global（仮） |
|-----|-------|----------------------|
| 2025-10-27 | Ethereum | 100 |
| 2025-10-27 | Polygon | 100 | ← 同じ値が重複
| 2025-10-27 | Avalanche | 100 | ← 同じ値が重複

累積計算で`SUM(100 + 100 + 100) = 300人`となり、**実際は100人なのに3倍**にカウントされてしまいます。

**解決策: FIRST_VALUE()を使う**

```sql
CASE 
    WHEN c.chain = FIRST_VALUE(c.chain) OVER (PARTITION BY c.day ORDER BY c.chain) 
    THEN COALESCE(g.new_users_global, 0) 
    ELSE 0 
END as daily_new_users_global
```

**FIRST_VALUE()とは？**

`FIRST_VALUE(列名) OVER (...)` は、ウィンドウ内の**最初の行の値**を取得する関数です。

**動作の説明:**

1. **PARTITION BY c.day**: 日付ごとにグループ化
2. **ORDER BY c.chain**: チェーン名のアルファベット順に並べる
3. **FIRST_VALUE(c.chain)**: その日の最初のチェーン名を取得

**具体例:**

2025-10-27のデータ（アルファベット順）：
- Avalanche
- Ethereum  
- Polygon

→ `FIRST_VALUE(c.chain)` = **'Avalanche'**

**CASE文の判定:**
```sql
WHEN c.chain = 'Avalanche' THEN 100  -- ✅ Avalancheの行のみTRUE
ELSE 0                               -- ❌ 他の行はFALSE
```

**結果テーブル:**
| day | chain | daily_new_users_global |
|-----|-------|------------------------|
| 10-27 | Avalanche | 100 | ✅ 値が入る
| 10-27 | Ethereum | 0 | 
| 10-27 | Polygon | 0 |

累積計算：`SUM(100 + 0 + 0) = 100人` ← **正しい！**

**なぜこの方法が優れているか:**

- ✅ 特定のチェーン名（Ethereumなど）に依存しない
- ✅ もしAvalancheでその日取引がなくても、Ethereumが自動的に選ばれる
- ✅ どのチェーンでも取引がある限り、グローバル値が漏れない

---

### WHEREフィルタ

```sql
WHERE c.day >= DATE '2025-10-01'
```

**重要なポイント:**
- このフィルタは**ウィンドウ関数の後**に適用される
- つまり、累積値は**全期間のデータで計算**され、**表示だけが10月1日以降**になる
- これにより、6月のテスト期間のデータも累積値に含まれます

### パフォーマンス最適化

クエリの実行速度を向上させるため、最初の`all_transfers` CTEで**日付フィルタ**を追加しています：

```sql
AND evt_block_time >= TIMESTAMP '2025-10-27'  -- JPYCローンチ日以降
```

**効果:**
- 2025年6月〜10月のテスト期間データ（約4ヶ月分）を除外
- スキャンするデータ量が約50%削減
- クエリ実行時間が大幅に短縮

この日付フィルタは各チェーンのWHERE句に含まれており、ブロックチェーンから取得する段階で不要なデータを除外します。

---

## 出力データの説明

このクエリは以下の列を出力します：

### 日次データ
- `day` - 日付
- `chain` - チェーン名（Ethereum/Polygon/Avalanche）
- `daily_transactions` - その日の取引数
- `daily_volume_jpy` - その日の取引量（円）
- `daily_new_users_by_chain` - その日の新規ユーザー数（チェーン別）
- `daily_new_users_global` - その日の新規ユーザー数（全チェーン統合）

### 累積データ
- `cumulative_transactions` - 累積取引数
- `cumulative_volume_jpy` - 累積取引量（円）
- `cumulative_users_by_chain` - 累積ユーザー数（チェーン別、重複あり）
- `cumulative_users_global` - 累積ユニークユーザー数（重複なし）

---

## Duneでのグラフ作成方法

### グラフ1: 累積取引量（円建て）

**設定:**
- Chart Type: **Line Chart** または **Area Chart**
- X軸: `day`
- Y軸: `cumulative_volume_jpy`
- Series: `chain`
- タイトル: "JPYC累積取引量の推移（円建て）"

**見えるもの:**
- どのチェーンが最も取引されているか
- 取引量の成長速度

### グラフ2: 累積取引数

**設定:**
- Chart Type: **Line Chart**
- X軸: `day`
- Y軸: `cumulative_transactions`
- Series: `chain`
- タイトル: "JPYC累積取引数の推移"

**見えるもの:**
- 取引の活発さ
- どのチェーンが利用されているか

### グラフ3: 累積ユーザー数（チェーン別）

**設定:**
- Chart Type: **Line Chart**
- X軸: `day`
- Y軸: `cumulative_users_by_chain`
- Series: `chain`
- タイトル: "JPYC累積ユーザー数（チェーン別）"

**見えるもの:**
- 各チェーンのユーザー獲得状況
- ※同じユーザーが複数チェーンで重複カウントされる

### グラフ4: 累積ユニークユーザー数（真の値）

**設定:**
- Chart Type: **Line Chart**
- X軸: `day`
- Y軸: `cumulative_users_global`
- **Filter**: `chain = 'avalanche'` または `chain = 'ethereum'` （どれか1つ選択）

**見えるもの:**
- JPYCの実際のユーザーベース規模
- 重複を除いた真のユーザー数

**⚠️ 重要な注意点:**
クエリの出力は「日次 × チェーン」の粒度なので、同じ日の3つのチェーン（Avalanche/Ethereum/Polygon）すべてに**同じグローバル値**が入っています。

そのため、グラフ設定で：
1. **Filterで1つのチェーンのみ選択**（推奨）
2. または、Seriesを指定せずに表示（3本の線が重なって1本に見える）

どちらかの方法で対応してください。

---

## よくある質問

### Q1: なぜ`value / 1e18`で割るのですか？

**A:** ERC-20トークンは通常、最小単位で保存されています。JPYCは18 decimalsなので：
- ブロックチェーン上の値: `1000000000000000000`（18個のゼロ）
- 実際の値: `1 JPYC`（= 1円）

`1e18`（= 1,000,000,000,000,000,000）で割ることで、人間が読める単位に変換します。

### Q2: FIRST_VALUE()とは何ですか？

**A:** `FIRST_VALUE()`はウィンドウ関数の一種で、**指定した範囲内の最初の行の値**を取得します。

このクエリでは、「その日に存在する複数のチェーンのうち、アルファベット順で最初のチェーン」を選ぶために使っています。これにより、グローバル新規ユーザー数を1日1回だけカウントできます。

### Q3: チェーン別と全チェーン統合のユーザー数の違いは？

**A:**

**チェーン別（`cumulative_users_by_chain`）:**
- アドレス`0xABC`がEthereumで取引 → 1人
- 同じ`0xABC`がPolygonでも取引 → また1人
- **合計: 2人**（チェーンごとのアクティビティを測定）

**全チェーン統合（`cumulative_users_global`）:**
- アドレス`0xABC`がEthereumで取引 → 1人
- 同じ`0xABC`がPolygonでも取引 → **カウントしない**
- **合計: 1人**（真のユーザー数を測定）

### Q4: なぜMint/Burnを除外するのですか？

**A:** Mint（発行）とBurn（償還）は：
- Mint: ゼロアドレス（`0x0000...`）**から**ユーザーへ
- Burn: ユーザー**から**ゼロアドレスへ

これらは「JPYC社が事前準備したトークン」や「償還処理」であり、**実際のユーザー間取引ではない**ため除外します。

### Q5: 日付フィルタ（10月1日以降）を変更するには？

**A:** 最後のWHERE句を変更してください：

```sql
WHERE c.day >= DATE '2025-10-01'  -- ← ここを変更
```

例：
- 公式ローンチ以降のみ: `WHERE c.day >= DATE '2025-10-27'`
- 11月以降のみ: `WHERE c.day >= DATE '2025-11-01'`
- フィルタなし（全期間）: `WHERE`行を削除

---

## まとめ

このクエリを使うことで：

✅ JPYCの**実際の利用状況**を可視化できる  
✅ **どのチェーンが人気か**がわかる  
✅ **ユーザー数の成長**を追跡できる  
✅ **重複を排除**して、真のユーザー数を計測できる  
✅ **Mint/Burnを除外**して、真の経済活動だけを分析できる  

Dune Analyticsにこのクエリをコピー&ペーストするだけで、すぐに分析を始められます！

---

## 参考リソース

- **JPYC公式サイト**: https://jpyc.jp
- **Dune Analytics**: https://dune.com
- **Ethereum Etherscan**: https://etherscan.io/token/0xE7C3D8C9a439feDe00D2600032D5dB0Be71C3c29
- **Polygon Polygonscan**: https://polygonscan.com/address/0xe7c3d8c9a439fede00d2600032d5db0be71c3c29

---

**この記事が役立ったら、ぜひDuneダッシュボードを作成して、JPYCの成長を追跡してみてください！** 📊🚀
