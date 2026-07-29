import os


def scan_project(path):
    result = {
        "deg_file": None,
        "expression_file": None,
        "kegg_file": None
    }

    for root, _, files in os.walk(path):
        for f in files:
            name = f.lower()
            full = os.path.join(root, f)

            if any(x in name for x in ["deg", "diff", "differential"]):
                result["deg_file"] = full

            if any(x in name for x in ["tpm", "fpkm", "count", "expression"]):
                result["expression_file"] = full

            if any(x in name for x in ["kegg", "go", "enrich"]):
                result["kegg_file"] = full

    return result
