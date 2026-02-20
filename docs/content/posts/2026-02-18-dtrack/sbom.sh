#!/bin/bash
set -euo pipefail

OUTPUT_DIR="./sboms"

# Define projects: "docker_image|docker_hub_repo|tag_pattern"
PROJECTS=(
  "docker.io/python:3.10.0|python|^3\.10\.[0-9]+$"
)

mkdir -p "${OUTPUT_DIR}"

# Fetch all tags from Docker Hub (paginated API)
fetch_tags() {
  local repo="$1"
  local url="https://registry.hub.docker.com/v2/repositories/${repo}/tags/?page_size=100"
  local tags=()

  while [ -n "${url}" ] && [ "${url}" != "null" ]; do
    response=$(curl -s "${url}")
    page_tags=$(echo "${response}" | jq -r '.results[].name' 2>/dev/null)
    tags+=($page_tags)
    url=$(echo "${response}" | jq -r '.next // empty' 2>/dev/null)
  done

  printf '%s\n' "${tags[@]}"
}

for project in "${PROJECTS[@]}"; do
  IFS='|' read -r image repo tag_pattern <<< "${project}"
  project_name=$(basename "${image}")
  project_dir="${OUTPUT_DIR}/${project_name}"
  mkdir -p "${project_dir}"

  echo "============================================"
  echo "Project: ${project_name}"
  echo "Image:   ${image}"
  echo "============================================"

  echo "Fetching tags for ${image}..."
  tags=$(fetch_tags "${repo}")
  tag_count=$(echo "${tags}" | wc -l)
  echo "Found ${tag_count} tags."

  # Filter to version tags only, take last 10
  version_tags=$(echo "${tags}" | grep -E "${tag_pattern}" | sort -V | tail -n 10)
  version_count=$(echo "${version_tags}" | wc -l)
  echo "Using last ${version_count} version tags."
  echo ""

  for tag in ${version_tags}; do
    output_file="${project_dir}/sbom-${tag}.json"

    if [ -f "${output_file}" ]; then
      echo "[SKIP] ${output_file} already exists."
      continue
    fi

    echo "[SCAN] ${image}:${tag} -> ${output_file}"
    syft scan "${image}:${tag}" -o "cyclonedx-json=${output_file}" || {
      echo "[ERROR] Failed to scan ${image}:${tag}, skipping."
      continue
    }
  done

  echo ""
done

echo "Done. SBOMs saved to ${OUTPUT_DIR}/"
