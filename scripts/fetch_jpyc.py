"""Fetch JPYC query results from Dune Analytics API and save as CSV."""

import csv
import os
import re
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


def fetch_and_save(dune: DuneClient, query_id: int, name: str, columns: list[str], data_dir: Path) -> list[dict]:
    """Fetch latest result from Dune and save as CSV. Returns rows."""
    print(f"Fetching {name} (query {query_id})...")
    result = dune.get_latest_result(query_id)
    rows = result.result.rows

    if not rows:
        print(f"  No data returned for {name}")
        return []

    output_path = data_dir / f"{name}.csv"
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)

    print(f"  Saved {len(rows)} rows to {output_path}")
    return rows


def generate_readme_section(monthly_rows: list[dict], daily_rows: list[dict], updated: str) -> str:
    """Generate the latest data markdown section for README."""
    lines = []

    # Monthly summary table
    if monthly_rows:
        lines.append("| Month | Chain | Issuance | Redemption | Circulating |")
        lines.append("|-------|-------|----------|------------|-------------|")
        for r in monthly_rows:
            month = r.get("年月", "")
            chain = r.get("チェーン", "")
            iss = r.get("累積発行額 (億円)", 0)
            red = r.get("累積償還額 (億円)", 0)
            circ = r.get("累積流通額 (億円)", 0)
            lines.append(f"| {month} | {chain} | {iss} | {red} | {circ} |")

    # Global totals from latest month (Avalanche row has global data)
    if monthly_rows:
        latest_avl = next(
            (r for r in monthly_rows if r.get("全体累積発行額 (億円)") is not None and r.get("全体累積発行額 (億円)") != ""),
            None,
        )
        if latest_avl:
            g_iss = latest_avl.get("全体累積発行額 (億円)", "N/A")
            g_red = latest_avl.get("全体累積償還額 (億円)", "N/A")
            g_circ = latest_avl.get("全体累積流通額 (億円)", "N/A")
            latest_month = latest_avl.get("年月", "")
            lines.append("")
            lines.append(f"**Global Total ({latest_month})**: Issuance {g_iss} B JPY / Redemption {g_red} B JPY / Circulating {g_circ} B JPY")

    # Daily latest info
    if daily_rows:
        latest = daily_rows[0]
        latest_date = latest.get("日付", "")
        total_users = latest.get("総累積ユニークユーザー数", "N/A")
        lines.append("")
        lines.append(f"**Latest date**: {latest_date} / **Total unique users**: {total_users:,}" if isinstance(total_users, (int, float)) else f"**Latest date**: {latest_date} / **Total unique users**: {total_users}")

    lines.append("")
    lines.append(f"*Last updated: {updated}*")

    return "\n".join(lines)


def update_readme(repo_root: Path, section_content: str):
    """Update the Latest Data section in README.md between markers."""
    readme_path = repo_root / "README.md"
    readme = readme_path.read_text(encoding="utf-8")

    start_marker = "<!-- LATEST_DATA_START -->"
    end_marker = "<!-- LATEST_DATA_END -->"

    pattern = re.compile(
        re.escape(start_marker) + r".*?" + re.escape(end_marker),
        re.DOTALL,
    )

    replacement = f"{start_marker}\n{section_content}\n{end_marker}"

    if start_marker in readme:
        new_readme = pattern.sub(replacement, readme)
    else:
        print("  Warning: markers not found in README.md, skipping update")
        return

    readme_path.write_text(new_readme, encoding="utf-8")
    print("  README.md updated with latest data")


def main():
    api_key = os.environ.get("DUNE_API_KEY")
    if not api_key:
        print("Error: DUNE_API_KEY environment variable is not set")
        raise SystemExit(1)

    dune = DuneClient(api_key)
    repo_root = Path(__file__).resolve().parent.parent
    data_dir = repo_root / "data"
    data_dir.mkdir(exist_ok=True)

    monthly_rows = fetch_and_save(dune, QUERIES["jpyc_monthly"], "jpyc_monthly", MONTHLY_COLUMNS, data_dir)
    daily_rows = fetch_and_save(dune, QUERIES["jpyc_daily"], "jpyc_daily", DAILY_COLUMNS, data_dir)

    # Write timestamp
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    (data_dir / "last_updated.txt").write_text(now + "\n", encoding="utf-8")

    # Update README
    section = generate_readme_section(monthly_rows, daily_rows, now)
    update_readme(repo_root, section)

    print(f"Done. Last updated: {now}")


if __name__ == "__main__":
    main()
