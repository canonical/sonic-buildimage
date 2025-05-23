import sys
import os
from jinja2 import Environment, FileSystemLoader

branch = os.getenv("BRANCH")
platform = os.getenv("PLATFORM")
output_path = os.getenv("OUTPUT_PATH", "build.yaml")

env = Environment(loader=FileSystemLoader("templates"))
template = env.get_template("build_template.yaml.j2")

rendered = template.render(branch=branch, platform=platform)

with open(output_path, "w") as f:
    f.write(rendered)

print(f"Job YAML generated at {output_path}")
