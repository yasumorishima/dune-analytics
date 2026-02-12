"""Fetch JPYC query results from Dune Analytics API and save as CSV."""

import csv
import os
from datetime import datetime, timezone
from pathlib import Path

from dune_client.client import DuneClient

# Query IDs on Dune
QUERIES = {
    "jpyc_monthly": 6603840,
    "jpyc_daily": 6593053,
}

# Column order for CSV output
MONTHLY_COLUMNS = [
    "年月",
    "チェーン",
    "月次発行額 (億円)",
    "月次償還額 (億円)",
    "月次純増額 (億円)",
    "累積発行額 (億円)",
    "累積償還額 (億円)",
    "累積流通額 (億円)",
    "全体累積発行額 (億円)",
    "全体累積償還額 (億円)",
    "全体累積流通額 (億円)",
]

DAILY_COLUMNS = [
    "日付",
    "チェーン",
    "日次発行額 (億円)",
    "日次償還額 (億円)",
    "日次純増額 (億円)",
    "累積発行額 (億円)",
    "累積償還額 (億円)",
    "累積流通額 (億円)",
    "日次新規ユーザー (チェーン別)",
    "累積ユーザー数 (チェーン別)",
    "総累積ユニークユーザー数",
]


def fetch_and_save(dune: DuneClient, query_id: int, name: str, columns: list[str], data_dir: Path) -> Path:
    """Fetch latest result from Dune and save as CSV."""
    print(f"Fetching {name} (query {query_id})...")
    result = dune.get_latest_result(query_id)
    rows = result.result.rows

    if not rows:
        print(f"  No data returned for {name}")
        return None

    output_path = data_dir / f"{name}.csv"
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)

    print(f"  Saved {len(rows)} rows to {output_path}")
    return output_path


def main():
    api_key = os.environ.get("DUNE_API_KEY")
    if not api_key:
        print("Error: DUNE_API_KEY environment variable is not set")
        raise SystemExit(1)

    dune = DuneClient(api_key)
    data_dir = Path(__file__).resolve().parent.parent / "data"
    data_dir.mkdir(exist_ok=True)

    fetch_and_save(dune, QUERIES["jpyc_monthly"], "jpyc_monthly", MONTHLY_COLUMNS, data_dir)
    fetch_and_save(dune, QUERIES["jpyc_daily"], "jpyc_daily", DAILY_COLUMNS, data_dir)

    # Write timestamp
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    (data_dir / "last_updated.txt").write_text(now + "\n", encoding="utf-8")
    print(f"Done. Last updated: {now}")


if __name__ == "__main__":
    main()
