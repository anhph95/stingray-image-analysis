#!/usr/bin/env python3
"""Build the canonical class-map CSV from a model class-names YAML file."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import yaml


def read_class_names(path: Path) -> list[tuple[int, str]]:
    document = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(document, dict) or "names" not in document:
        raise ValueError(f"{path} does not contain a names section")

    names = document["names"]
    if isinstance(names, list):
        items = list(enumerate(names))
    elif isinstance(names, dict):
        items = []
        for raw_class_id, class_name in names.items():
            try:
                class_id = int(raw_class_id)
            except (TypeError, ValueError) as error:
                raise ValueError(
                    f"Invalid class ID in {path}: {raw_class_id!r}"
                ) from error
            items.append((class_id, class_name))
        items.sort()
    else:
        raise ValueError(f"{path} names must be a list or mapping")

    normalized: list[tuple[int, str]] = []
    seen_ids: set[int] = set()
    for class_id, raw_name in items:
        if class_id < 0 or class_id in seen_ids:
            raise ValueError(f"Invalid or duplicate class ID in {path}: {class_id}")
        class_name = str(raw_name).strip()
        if not class_name:
            raise ValueError(f"Empty class name in {path} for ID {class_id}")
        normalized.append((class_id, class_name))
        seen_ids.add(class_id)

    if not normalized:
        raise ValueError(f"{path} names section is empty")
    return normalized


def write_rows(path: Path, rows: list[list[object]], delimiter: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.writer(output_file, delimiter=delimiter)
        writer.writerows(rows)
    temporary.replace(path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--class-yaml", required=True, type=Path)
    parser.add_argument("--class-map-csv", required=True, type=Path)
    parser.add_argument("--class-map-tsv", type=Path)
    args = parser.parse_args()

    items = read_class_names(args.class_yaml)
    csv_rows: list[list[object]] = [
        ["class_id", "class", "source_file", "source_format"]
    ]
    csv_rows.extend(
        [class_id, name, str(args.class_yaml), "class_names_yaml"]
        for class_id, name in items
    )
    write_rows(args.class_map_csv, csv_rows, ",")

    if args.class_map_tsv is not None:
        write_rows(
            args.class_map_tsv,
            [[class_id, name] for class_id, name in items],
            "\t",
        )

    print(f"[INFO] Class names discovered: {len(items)}")
    print(f"[INFO] Class map written: {args.class_map_csv}")


if __name__ == "__main__":
    main()
