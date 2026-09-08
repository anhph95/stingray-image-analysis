from __future__ import annotations

import csv
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]


class HelperScriptTests(unittest.TestCase):
    def test_build_class_map(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            class_yaml = temporary / "classes.yaml"
            class_csv = temporary / "classes.csv"
            class_tsv = temporary / "classes.tsv"
            class_yaml.write_text(
                "names:\n  0: copepod\n  1: marine snow\n",
                encoding="utf-8",
            )

            subprocess.run(
                [
                    sys.executable,
                    str(REPOSITORY / "build_class_map.py"),
                    "--class-yaml",
                    str(class_yaml),
                    "--class-map-csv",
                    str(class_csv),
                    "--class-map-tsv",
                    str(class_tsv),
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            with class_csv.open(newline="", encoding="utf-8") as input_file:
                rows = list(csv.DictReader(input_file))
            self.assertEqual([row["class"] for row in rows], ["copepod", "marine snow"])
            self.assertEqual(class_tsv.read_text(encoding="utf-8").splitlines()[1], "1\tmarine snow")

    def test_select_video_batch_handles_quoted_csv_paths(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            video_csv = temporary / "videos.csv"
            source_list = temporary / "source.txt"
            with video_csv.open("w", newline="", encoding="utf-8") as output_file:
                writer = csv.DictWriter(
                    output_file,
                    fieldnames=["video_index", "media_path", "status"],
                )
                writer.writeheader()
                writer.writerows(
                    [
                        {"video_index": 0, "media_path": "/data/a,one.avi", "status": "valid"},
                        {"video_index": 1, "media_path": "/data/b.avi", "status": "unreadable"},
                        {"video_index": 2, "media_path": "/data/c.avi", "status": "valid"},
                    ]
                )

            result = subprocess.run(
                [
                    sys.executable,
                    str(REPOSITORY / "select_video_batch.py"),
                    "--video-list",
                    str(video_csv),
                    "--batch-id",
                    "1",
                    "--batch-size",
                    "1",
                    "--statuses",
                    "valid",
                    "--output",
                    str(source_list),
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.stdout.strip(), "2 1")
            self.assertEqual(source_list.read_text(encoding="utf-8"), "/data/c.avi\n")


if __name__ == "__main__":
    unittest.main()
