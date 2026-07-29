#!/usr/bin/env python3
"""Insert fail-closed, unbuffered progress markers into XSBench v20 sources."""

from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(
            f"{path}: expected one instrumentation anchor, found {count}: {old!r}"
        )
    path.write_text(text.replace(old, new, 1))


def instrument_main(path: Path) -> None:
    replace_once(
        path,
        '#include "XSbench_header.h"\n',
        '#include "XSbench_header.h"\n#include "p3_xsbench_markers.h"\n',
    )
    replace_once(
        path,
        "int main( int argc, char* argv[] )\n{\n",
        'int main( int argc, char* argv[] )\n{\n'
        '\tp3_xs_mark("P3_XS M00 main_entry\\n");\n',
    )
    replace_once(
        path,
        "\tunsigned long long verification;\n\n\t#ifdef MPI\n",
        '\tunsigned long long verification;\n\n'
        '\tp3_xs_mark("P3_XS M01 runtime_init_begin\\n");\n'
        "\t#ifdef MPI\n",
    )
    replace_once(
        path,
        "\t#endif\n\n\t// Process CLI Fields -- store in \"Inputs\" structure\n"
        "\tInputs in = read_CLI( argc, argv );\n",
        '\t#endif\n\n\tp3_xs_mark("P3_XS M02 runtime_init_done\\n");\n'
        "\t// Process CLI Fields -- store in \"Inputs\" structure\n"
        '\tp3_xs_mark("P3_XS M10 cli_begin\\n");\n'
        "\tInputs in = read_CLI( argc, argv );\n"
        '\tp3_xs_mark("P3_XS M11 cli_done\\n");\n',
    )
    replace_once(
        path,
        "\t// Set number of OpenMP Threads\n\t#ifdef OPENMP\n"
        "\tomp_set_num_threads(in.nthreads); \n\t#endif\n",
        '\t// Set number of OpenMP Threads\n'
        '\tp3_xs_mark("P3_XS M20 openmp_set_begin\\n");\n'
        "\t#ifdef OPENMP\n\tomp_set_num_threads(in.nthreads); \n\t#endif\n"
        '\tp3_xs_mark("P3_XS M21 openmp_set_done\\n");\n',
    )
    replace_once(
        path,
        "\t// Print-out of Input Summary\n\tif( mype == 0 )\n"
        "\t\tprint_inputs( in, nprocs, version );\n",
        '\t// Print-out of Input Summary\n'
        '\tp3_xs_mark("P3_XS M30 print_inputs_begin\\n");\n'
        "\tif( mype == 0 )\n\t\tprint_inputs( in, nprocs, version );\n"
        '\tp3_xs_mark("P3_XS M31 print_inputs_done\\n");\n',
    )
    replace_once(
        path,
        "\tSimulationData SD;\n\n\t// If read from file mode is selected",
        '\tSimulationData SD;\n\n'
        '\tp3_xs_mark("P3_XS M40 grid_dispatch_begin\\n");\n'
        "\t// If read from file mode is selected",
    )
    replace_once(
        path,
        "\telse\n\t\tSD = grid_init_do_not_profile( in, mype );\n",
        "\telse\n\t\tSD = grid_init_do_not_profile( in, mype );\n"
        '\tp3_xs_mark("P3_XS M49 grid_dispatch_done\\n");\n',
    )
    replace_once(
        path,
        "\t// Start Simulation Timer\n\tomp_start = get_time();\n",
        '\t// Start Simulation Timer\n'
        '\tp3_xs_mark("P3_XS M50 timer_begin\\n");\n'
        "\tomp_start = get_time();\n"
        '\tp3_xs_mark("P3_XS M51 timer_done\\n");\n',
    )
    replace_once(
        path,
        "\t// Run simulation\n\tif( in.simulation_method == EVENT_BASED )\n",
        '\t// Run simulation\n'
        '\tp3_xs_mark("P3_XS M60 simulation_begin\\n");\n'
        "\tif( in.simulation_method == EVENT_BASED )\n",
    )
    replace_once(
        path,
        "\telse\n\t\tverification = run_history_based_simulation(in, SD, mype);\n\n"
        "\tif( mype == 0)",
        "\telse\n\t\tverification = run_history_based_simulation(in, SD, mype);\n"
        '\tp3_xs_mark("P3_XS M69 simulation_done\\n");\n\n'
        "\tif( mype == 0)",
    )
    replace_once(
        path,
        "\t// Print / Save Results and Exit\n"
        "\tint is_invalid_result = print_results( in, mype, omp_end-omp_start, nprocs, verification );\n",
        '\t// Print / Save Results and Exit\n'
        '\tp3_xs_mark("P3_XS M70 results_begin\\n");\n'
        "\tint is_invalid_result = print_results( in, mype, omp_end-omp_start, nprocs, verification );\n"
        '\tp3_xs_mark("P3_XS M79 results_done\\n");\n',
    )
    replace_once(
        path,
        "\treturn is_invalid_result;\n",
        '\tp3_xs_mark_u64("P3_XS M99 exit_status=", '
        "(uint64_t) is_invalid_result);\n"
        "\treturn is_invalid_result;\n",
    )


def instrument_grid(path: Path) -> None:
    replace_once(
        path,
        '#include "XSbench_header.h"\n',
        '#include "XSbench_header.h"\n#include "p3_xsbench_markers.h"\n',
    )
    replace_once(
        path,
        "SimulationData grid_init_do_not_profile( Inputs in, int mype )\n{\n",
        "SimulationData grid_init_do_not_profile( Inputs in, int mype )\n{\n"
        '\tp3_xs_mark("P3_XS G00 grid_init_entry\\n");\n',
    )
    replace_once(
        path,
        "\tSD.length_nuclide_grid = in.n_isotopes * in.n_gridpoints;\n"
        "\tSD.nuclide_grid     = (NuclideGridPoint *) malloc( SD.length_nuclide_grid * sizeof(NuclideGridPoint));\n"
        "\tassert(SD.nuclide_grid != NULL);\n",
        "\tSD.length_nuclide_grid = in.n_isotopes * in.n_gridpoints;\n"
        '\tp3_xs_mark_u64("P3_XS G10 nuclide_count=", SD.length_nuclide_grid);\n'
        '\tp3_xs_mark("P3_XS G11 nuclide_malloc_begin\\n");\n'
        "\tSD.nuclide_grid     = (NuclideGridPoint *) malloc( SD.length_nuclide_grid * sizeof(NuclideGridPoint));\n"
        "\tassert(SD.nuclide_grid != NULL);\n"
        '\tp3_xs_mark("P3_XS G12 nuclide_malloc_done\\n");\n',
    )
    replace_once(
        path,
        "\tnbytes += SD.length_nuclide_grid * sizeof(NuclideGridPoint);\n"
        "\tfor( int i = 0; i < SD.length_nuclide_grid; i++ )\n",
        "\tnbytes += SD.length_nuclide_grid * sizeof(NuclideGridPoint);\n"
        '\tp3_xs_mark("P3_XS G13 nuclide_fill_begin\\n");\n'
        "\tfor( int i = 0; i < SD.length_nuclide_grid; i++ )\n",
    )
    replace_once(
        path,
        "\t}\n\n\t// Sort so that each nuclide has data stored in ascending energy order.\n"
        "\tfor( int i = 0; i < in.n_isotopes; i++ )\n"
        "\t\tqsort( &SD.nuclide_grid[i*in.n_gridpoints], in.n_gridpoints, sizeof(NuclideGridPoint), NGP_compare);\n",
        '\t}\n\tp3_xs_mark("P3_XS G14 nuclide_fill_done\\n");\n\n'
        "\t// Sort so that each nuclide has data stored in ascending energy order.\n"
        '\tp3_xs_mark("P3_XS G20 nuclide_sort_begin\\n");\n'
        "\tfor( int i = 0; i < in.n_isotopes; i++ )\n\t{\n"
        "\t\tqsort( &SD.nuclide_grid[i*in.n_gridpoints], in.n_gridpoints, sizeof(NuclideGridPoint), NGP_compare);\n"
        "\t\tif((i & 7) == 7 || i == in.n_isotopes - 1)\n"
        '\t\t\tp3_xs_mark_u64("P3_XS G21 nuclide_sorted=", (uint64_t) i + 1);\n'
        "\t}\n"
        '\tp3_xs_mark("P3_XS G29 nuclide_sort_done\\n");\n',
    )
    replace_once(
        path,
        "\tif( in.grid_type == UNIONIZED )\n\t{\n"
        "\t\tif(mype == 0) printf(\"Intializing unionized grid...\\n\");\n",
        "\tif( in.grid_type == UNIONIZED )\n\t{\n"
        '\t\tp3_xs_mark("P3_XS U00 unionized_entry\\n");\n'
        "\t\tif(mype == 0) printf(\"Intializing unionized grid...\\n\");\n",
    )
    replace_once(
        path,
        "\t\tSD.length_unionized_energy_array = in.n_isotopes * in.n_gridpoints;\n"
        "\t\tSD.unionized_energy_array = (double *) malloc( SD.length_unionized_energy_array * sizeof(double));\n"
        "\t\tassert(SD.unionized_energy_array != NULL );\n",
        "\t\tSD.length_unionized_energy_array = in.n_isotopes * in.n_gridpoints;\n"
        '\t\tp3_xs_mark_u64("P3_XS U10 unionized_count=", SD.length_unionized_energy_array);\n'
        '\t\tp3_xs_mark("P3_XS U11 unionized_malloc_begin\\n");\n'
        "\t\tSD.unionized_energy_array = (double *) malloc( SD.length_unionized_energy_array * sizeof(double));\n"
        "\t\tassert(SD.unionized_energy_array != NULL );\n"
        '\t\tp3_xs_mark("P3_XS U12 unionized_malloc_done\\n");\n',
    )
    replace_once(
        path,
        "\t\t// Copy energy data over from the nuclide energy grid\n"
        "\t\tfor( int i = 0; i < SD.length_unionized_energy_array; i++ )\n"
        "\t\t\tSD.unionized_energy_array[i] = SD.nuclide_grid[i].energy;\n\n"
        "\t\t// Sort unionized energy array\n"
        "\t\tqsort( SD.unionized_energy_array, SD.length_unionized_energy_array, sizeof(double), double_compare);\n",
        "\t\t// Copy energy data over from the nuclide energy grid\n"
        '\t\tp3_xs_mark("P3_XS U20 unionized_copy_begin\\n");\n'
        "\t\tfor( int i = 0; i < SD.length_unionized_energy_array; i++ )\n"
        "\t\t\tSD.unionized_energy_array[i] = SD.nuclide_grid[i].energy;\n"
        '\t\tp3_xs_mark("P3_XS U21 unionized_copy_done\\n");\n\n'
        "\t\t// Sort unionized energy array\n"
        '\t\tp3_xs_mark("P3_XS U30 unionized_sort_begin\\n");\n'
        "\t\tqsort( SD.unionized_energy_array, SD.length_unionized_energy_array, sizeof(double), double_compare);\n"
        '\t\tp3_xs_mark("P3_XS U31 unionized_sort_done\\n");\n',
    )
    replace_once(
        path,
        "\t\tSD.length_index_grid = SD.length_unionized_energy_array * in.n_isotopes;\n"
        "\t\tSD.index_grid = (int *) malloc( SD.length_index_grid * sizeof(int));\n"
        "\t\tassert(SD.index_grid != NULL);\n",
        "\t\tSD.length_index_grid = SD.length_unionized_energy_array * in.n_isotopes;\n"
        '\t\tp3_xs_mark_u64("P3_XS U40 index_count=", SD.length_index_grid);\n'
        '\t\tp3_xs_mark("P3_XS U41 index_malloc_begin\\n");\n'
        "\t\tSD.index_grid = (int *) malloc( SD.length_index_grid * sizeof(int));\n"
        "\t\tassert(SD.index_grid != NULL);\n"
        '\t\tp3_xs_mark("P3_XS U42 index_malloc_done\\n");\n',
    )
    replace_once(
        path,
        "\t\t// Generates the double indexing grid\n"
        "\t\tint * idx_low = (int *) calloc( in.n_isotopes, sizeof(int));\n",
        "\t\t// Generates the double indexing grid\n"
        '\t\tp3_xs_mark("P3_XS U50 helper_alloc_begin\\n");\n'
        "\t\tint * idx_low = (int *) calloc( in.n_isotopes, sizeof(int));\n",
    )
    replace_once(
        path,
        "\t\tassert(energy_high != NULL );\n\n"
        "\t\tfor( int i = 0; i < in.n_isotopes; i++ )\n",
        "\t\tassert(energy_high != NULL );\n"
        '\t\tp3_xs_mark("P3_XS U51 helper_alloc_done\\n");\n\n'
        "\t\tfor( int i = 0; i < in.n_isotopes; i++ )\n",
    )
    replace_once(
        path,
        "\t\tfor( long e = 0; e < SD.length_unionized_energy_array; e++ )\n"
        "\t\t{\n\t\t\tdouble unionized_energy",
        '\t\tp3_xs_mark("P3_XS U60 index_fill_begin\\n");\n'
        "\t\tfor( long e = 0; e < SD.length_unionized_energy_array; e++ )\n"
        "\t\t{\n\t\t\tdouble unionized_energy",
    )
    replace_once(
        path,
        "\t\t\t}\n\t\t}\n\n\t\tfree(idx_low);\n\t\tfree(energy_high);\n",
        "\t\t\t}\n"
        "\t\t\tif((e & 65535) == 65535)\n"
        '\t\t\t\tp3_xs_mark_u64("P3_XS U61 index_filled=", (uint64_t) e + 1);\n'
        "\t\t}\n"
        '\t\tp3_xs_mark("P3_XS U69 index_fill_done\\n");\n\n'
        "\t\tfree(idx_low);\n\t\tfree(energy_high);\n"
        '\t\tp3_xs_mark("P3_XS U79 unionized_done\\n");\n',
    )
    replace_once(
        path,
        '\tif(mype == 0) printf("Intializing material data...\\n");\n',
        '\tif(mype == 0) printf("Intializing material data...\\n");\n'
        '\tp3_xs_mark("P3_XS V00 materials_begin\\n");\n',
    )
    replace_once(
        path,
        "\tSD.length_concs = SD.length_mats;\n",
        "\tSD.length_concs = SD.length_mats;\n"
        '\tp3_xs_mark("P3_XS V09 materials_done\\n");\n',
    )
    replace_once(
        path,
        '\tif(mype == 0) printf("Intialization complete. Allocated %.0lf MB of data.\\n", nbytes/1024.0/1024.0 );\n'
        "\treturn SD;\n",
        '\tif(mype == 0) printf("Intialization complete. Allocated %.0lf MB of data.\\n", nbytes/1024.0/1024.0 );\n'
        '\tp3_xs_mark_u64("P3_XS G99 allocated_bytes=", nbytes);\n'
        "\treturn SD;\n",
    )


def instrument_simulation(path: Path) -> None:
    replace_once(
        path,
        '#include "XSbench_header.h"\n',
        '#include "XSbench_header.h"\n#include "p3_xsbench_markers.h"\n',
    )
    replace_once(
        path,
        "unsigned long long run_event_based_simulation(Inputs in, SimulationData SD, int mype)\n{\n",
        "unsigned long long run_event_based_simulation(Inputs in, SimulationData SD, int mype)\n{\n"
        '\tp3_xs_mark("P3_XS E00 event_entry\\n");\n',
    )
    replace_once(
        path,
        "\tunsigned long long verification = 0;\n\tint i = 0;\n"
        "\t#pragma omp parallel for schedule(dynamic,100) reduction(+:verification)\n",
        "\tunsigned long long verification = 0;\n\tint i = 0;\n"
        '\tp3_xs_mark("P3_XS E10 event_loop_begin\\n");\n'
        "\t#pragma omp parallel for schedule(dynamic,100) reduction(+:verification)\n",
    )
    replace_once(
        path,
        "\treturn verification;\n}\n\n"
        "unsigned long long run_history_based_simulation",
        '\tp3_xs_mark("P3_XS E99 event_loop_done\\n");\n'
        "\treturn verification;\n}\n\n"
        "unsigned long long run_history_based_simulation",
    )
    replace_once(
        path,
        "unsigned long long run_history_based_simulation(Inputs in, SimulationData SD, int mype)\n{\n",
        "unsigned long long run_history_based_simulation(Inputs in, SimulationData SD, int mype)\n{\n"
        '\tp3_xs_mark("P3_XS H00 history_entry\\n");\n',
    )
    replace_once(
        path,
        "\tint p = 0;\n\t#pragma omp parallel for schedule(dynamic, 100) reduction(+:verification)\n",
        "\tint p = 0;\n"
        '\tp3_xs_mark("P3_XS H10 history_loop_begin\\n");\n'
        "\t#pragma omp parallel for schedule(dynamic, 100) reduction(+:verification)\n",
    )
    replace_once(
        path,
        "\t\t\tp_energy = LCG_random_double(&seed);\n"
        "\t\t\tmat      = pick_mat(&seed); \n\t\t}\n\n\t}\n"
        "\treturn verification;\n",
        "\t\t\tp_energy = LCG_random_double(&seed);\n"
        "\t\t\tmat      = pick_mat(&seed); \n\t\t}\n"
        "\t\tif((p % 100) == 99)\n"
        '\t\t\tp3_xs_mark_u64("P3_XS H11 particles_done=", (uint64_t) p + 1);\n'
        "\t}\n\n"
        '\tp3_xs_mark("P3_XS H99 history_loop_done\\n");\n'
        "\treturn verification;\n",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, required=True)
    args = parser.parse_args()
    source_dir = args.source_dir.resolve()

    instrument_main(source_dir / "openmp-threading" / "Main.c")
    instrument_grid(source_dir / "openmp-threading" / "GridInit.c")
    instrument_simulation(source_dir / "openmp-threading" / "Simulation.c")
    print(f"Instrumented XSBench sources: {source_dir}")


if __name__ == "__main__":
    main()
