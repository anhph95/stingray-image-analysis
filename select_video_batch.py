#!/usr/bin/env python3
"""Select one deterministic model-inference batch from a video-list CSV."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def video_index(row: dict[str, str]) -> int:
    value = row.get("video_index", "")
    return int(value) if value else 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video-list", required=True, type=Path)
    parser.add_argument("--batch-id", required=True)
    parser.add_argument("--batch-size", required=True, type=int)
    parser.add_argument("--statuses", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    statuses = set(args.statuses.split(","))
    with args.video_list.open(newline="", encoding="utf-8") as input_file:
        reader = csv.DictReader(input_file)
        if reader.fieldnames is None or "media_path" not in reader.fieldnames:
            raise ValueError(f"{args.video_list} is missing the media_path column")
        rows = list(reader)

    eligible = [
        row
        for row in rows
        if Path(row["media_path"]).suffix.lower() == ".avi"
        and row.get("status", "valid") in statuses
    ]
    eligible.sort(key=video_index)

    if args.batch_id == "all":
        selected = eligible
    else:
        start = int(args.batch_id) * args.batch_size
        selected = eligible[start : start + args.batch_size]

    temporary = args.output.with_suffix(args.output.suffix + ".tmp")
    temporary.write_text(
        "".join(f'{row["media_path"]}\n' for row in selected),
        encoding="utf-8",
    )
    temporary.replace(args.output)
    print(len(eligible), len(selected))


if __name__ == "__main__":
    main()
