"""Record the exact static build without exposing local filesystem paths."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import csv
import json

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


files = [p for p in SITE.rglob("*") if p.is_file() and not any(x.startswith("._") for x in p.parts)]
packages = sorted(p for p in files if p.suffix == ".tgz")
with (SITE / "research/data/associations.csv").open(newline="") as handle:
    associations = list(csv.DictReader(handle))
conversion = json.loads((ROOT / "checks/data_conversion.json").read_text())
active_packages = json.loads((ROOT / "checks/active_packages.json").read_text())
manifest = {
    "name": "knhanes_atlas",
    "built_utc": datetime.now(timezone.utc).isoformat(),
    "format": "Shinylive for R",
    "application_sha256": sha256(SITE / "app.json"),
    "homepage_sha256": sha256(SITE / "index.html"),
    "loader_sha256": sha256(SITE / "loader.js"),
    "runtime_sha256": sha256(SITE / "shinylive/webr/R.wasm"),
    "package_archives": [{"file": str(p.relative_to(SITE)), "sha256": sha256(p)} for p in packages],
    "active_package_archives": active_packages,
    "startup_package_bytes": sum((SITE / "shinylive/webr" / p).stat().st_size for p in active_packages),
    "vibration_phenotype_files": len(list((SITE / "data/voe").glob("*.rds"))),
    "study_results": {"pairs": len({row["pair_id"] for row in associations}),
                      "coefficient_contrasts": len(associations),
                      "evaluated_models": conversion["rows"]["models"],
                      "fitted_models": conversion["models_fitted"]},
}
(SITE / "build.json").write_text(json.dumps(manifest, indent=2) + "\n")
files = [p for p in SITE.rglob("*") if p.is_file() and not any(x.startswith("._") for x in p.parts)]
report = {"files": len(files), "total_bytes": sum(p.stat().st_size for p in files),
          "largest": [{"file": str(p.relative_to(SITE)), "bytes": p.stat().st_size}
                      for p in sorted(files, key=lambda p: p.stat().st_size, reverse=True)[:8]]}
assert report["total_bytes"] < 1_000_000_000
assert max(p.stat().st_size for p in files) < 100 * 1024 * 1024
(ROOT / "checks/site_size.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"Static build: {len(files)} files; {report['total_bytes'] / 1024**2:.1f} MiB; {len(packages)} package archives.")
