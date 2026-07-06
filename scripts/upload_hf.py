"""Mirror data/ to the Hugging Face dataset (canonical cloud store)."""
import os
from pathlib import Path

from huggingface_hub import HfApi

REPO = "yasumorishima/jpyc-data"


def main():
    if not os.environ.get("HF_TOKEN"):
        raise SystemExit("HF_TOKEN is not set -- cannot sync to HF")
    data_dir = Path(__file__).resolve().parent.parent / "data"
    api = HfApi()
    api.create_repo(REPO, repo_type="dataset", private=False, exist_ok=True)
    api.upload_folder(
        folder_path=str(data_dir),
        path_in_repo="data",
        repo_id=REPO,
        repo_type="dataset",
        commit_message="Sync JPYC data",
    )
    print(f"Synced data/ -> https://huggingface.co/datasets/{REPO}")


if __name__ == "__main__":
    main()
