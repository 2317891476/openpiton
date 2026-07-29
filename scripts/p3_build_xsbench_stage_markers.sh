#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_repo="${P3_XSBENCH_SOURCE_REPO:-$repo_dir/build/a7203x/XSBench}"
source_commit="ba08e5221af6106252b866e50ea123c69d31a4e2"
reference_sha256="1e896862da3294129c02bcbd8dfbd89fe70e093ef4c03f430882b6fede110930"
work_dir="${P3_XSBENCH_MARKER_WORK_DIR:-$repo_dir/build/p3_xsbench_marker_work}"
out_dir="${P3_XSBENCH_MARKER_OUT_DIR:-$repo_dir/build/huaprop3/opensbi1_build66_linux612_xsbench_marker}"
output="$out_dir/XSBench_marked"
cross="${CROSS_COMPILE:-riscv64-linux-gnu-}"
source_dir="$work_dir/source"
threading_dir="$source_dir/openmp-threading"

for tool in awk find git grep install python3 sha256sum strings tar \
    "${cross}gcc" "${cross}objdump"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: missing required command: $tool" >&2
        exit 1
    fi
done
for path in \
    "$source_repo/.git" \
    "$repo_dir/scripts/p3_instrument_xsbench.py" \
    "$repo_dir/scripts/p3_xsbench_markers.c" \
    "$repo_dir/scripts/p3_xsbench_markers.h"; do
    if [[ ! -e "$path" ]]; then
        echo "ERROR: missing required XSBench input: $path" >&2
        exit 1
    fi
done
if ! git -C "$source_repo" cat-file -e "${source_commit}^{commit}"; then
    echo "ERROR: required XSBench commit is unavailable: $source_commit" >&2
    exit 1
fi

mkdir -p "$source_dir" "$out_dir"
find "$source_dir" -mindepth 1 -delete
git -C "$source_repo" archive "$source_commit" | tar -x -C "$source_dir"

sources=(
    Main.c io.c Simulation.c GridInit.c XSutils.c Materials.c
)
cflags=(
    -std=gnu99 -Wall -flto -fopenmp -DOPENMP -O3
)
ldflags=(
    -lm -static
)

echo "[1/3] Rebuilding the unmodified board-validated XSBench reference"
(
    cd "$threading_dir"
    "${cross}gcc" "${cflags[@]}" "${sources[@]}" \
        -o XSBench_reference_rebuilt "${ldflags[@]}"
)
actual_reference_sha256="$(
    sha256sum "$threading_dir/XSBench_reference_rebuilt" | awk '{print $1}'
)"
if [[ "$actual_reference_sha256" != "$reference_sha256" ]]; then
    echo "ERROR: unmodified XSBench rebuild does not reproduce the board binary" >&2
    echo "  expected=$reference_sha256" >&2
    echo "  actual=$actual_reference_sha256" >&2
    exit 1
fi

echo "[2/3] Inserting fail-closed direct-write stage markers"
python3 "$repo_dir/scripts/p3_instrument_xsbench.py" --source-dir "$source_dir"
install -m 0644 \
    "$repo_dir/scripts/p3_xsbench_markers.c" \
    "$repo_dir/scripts/p3_xsbench_markers.h" \
    "$threading_dir/"

echo "[3/3] Building and validating the marked static RISC-V executable"
(
    cd "$threading_dir"
    "${cross}gcc" "${cflags[@]}" "${sources[@]}" p3_xsbench_markers.c \
        -o XSBench_marked "${ldflags[@]}"
)
objdump_path="$threading_dir/XSBench_marked.objdump"
strings_path="$threading_dir/XSBench_marked.strings"
"${cross}objdump" -d "$threading_dir/XSBench_marked" > "$objdump_path"
strings "$threading_dir/XSBench_marked" > "$strings_path"
if grep -Eq 'csr(w|wi|s|c)[[:space:]]+0x701' "$objdump_path"; then
    echo "ERROR: marked XSBench contains a write to custom CSR 0x701" >&2
    exit 1
fi
for marker in \
    "P3_XS M-1 constructor" \
    "P3_XS M00 main_entry" \
    "P3_XS M21 openmp_set_done" \
    "P3_XS G13 nuclide_fill_begin" \
    "P3_XS G20 nuclide_sort_begin" \
    "P3_XS U30 unionized_sort_begin" \
    "P3_XS U60 index_fill_begin" \
    "P3_XS H10 history_loop_begin" \
    "P3_XS M99 exit_status="; do
    if ! grep -Fxq "$marker" "$strings_path"; then
        echo "ERROR: marked XSBench is missing marker: $marker" >&2
        exit 1
    fi
done

install -m 0755 "$threading_dir/XSBench_marked" "$output"
output_sha256="$(sha256sum "$output" | awk '{print $1}')"
compiler="$("${cross}gcc" -dumpfullversion -dumpversion)"
manifest="$out_dir/XSBench_marked.manifest"
{
    echo "xsbench_source_commit=$source_commit"
    echo "xsbench_reference_sha256=$reference_sha256"
    echo "compiler=${cross}gcc $compiler"
    echo "compile_flags=${cflags[*]} ${ldflags[*]}"
    echo "instrumenter_sha256=$(sha256sum "$repo_dir/scripts/p3_instrument_xsbench.py" | awk '{print $1}')"
    echo "marker_source_sha256=$(sha256sum "$repo_dir/scripts/p3_xsbench_markers.c" | awk '{print $1}')"
    echo "marked_binary_sha256=$output_sha256"
} > "$manifest"

echo "XSBench stage-marker build passed:"
echo "  output=$output"
echo "  sha256=$output_sha256"
echo "  manifest=$manifest"
