#!/usr/bin/env python3
"""Build the canonical class-map CSV from a model class-names YAML file."""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path


def clean(value: str) -> str:
    value = value.strip()
    if value.startswith(("'", '"')) and value.endswith(("'", '"')):
        value = value[1:-1]
    return value


def read_class_names(path: Path) -> list[tuple[int, str]]:
    names_started = False
    names_by_id: dict[int, str] = {}
    names_list: list[str] = []

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line_without_comment = raw_line.split("#", 1)[0].rstrip()
        stripped = line_without_comment.strip()
        if not stripped:
            continue

        if not names_started:
            if stripped == "names:":
                names_started = True
            continue

        if not raw_line.startswith((" ", "\t", "-")) and stripped != "names:":
            break

        list_match = re.match(r"^-\s*(.+)$", stripped)
        if list_match:
            names_list.append(clean(list_match.group(1)))
            continue

        dict_match = re.match(r"^(\d+)\s*:\s*(.+)$", stripped)
        if dict_match:
            names_by_id[int(dict_match.group(1))] = clean(dict_match.group(2))

    if names_by_id:
        return sorted(names_by_id.items())
    if names_list:
        return list(enumerate(names_list))
    raise ValueError(f"{path} does not contain a supported names section")


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
