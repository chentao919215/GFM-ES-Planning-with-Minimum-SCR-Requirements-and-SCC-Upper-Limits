# ver_2.5 code review notes

## Scope and version identification

The repository has no separate `ver_2.5` folder or machine-readable project
version. The active deterministic multiple-snapshot call path was treated as
ver_2.5 because `calculate_impedance_bounds.m` explicitly identifies its
multiple-snapshot formulation as ver_2.5 and the newest result uses that path.

The repository was scanned in full. Detailed review followed the executed path
from `run_multiple_snapshot_planning.m` through parameter loading, network and
Kron construction, impedance bounds, YALMIP optimization, SCC/classic-SCR
constraints, result packaging, diagnostics, warm starts, and result saving.
Single-snapshot and equipment/Simulink scripts are auxiliary or legacy paths and
are not used by the newest multiple-snapshot result.

## Findings

1. **Version and input traceability (scientific reproducibility).** The README
   still states ver_2.0, while the active impedance-bounds code states ver_2.5.
   The saved `Result` has no explicit version, parameter-file hash, or static
   MATPOWER case snapshot. A future result can therefore be paired accidentally
   with a changed JSON file. The visualization adapter now checks the important
   dimensions, time weights, candidate buses, load profile, and available-wind
   profile before plotting, and records both source paths in the run manifest.
   The solver-side package should ultimately store a version, full case snapshot,
   and immutable parameter identifier.

2. **`SCC_0` is not a controlled before/after GFM comparison.** In
   `calculate_short_circuit_currents.m`, `SCC_0` is evaluated with all
   synchronous-generator admittances, whereas `SCC_1` is evaluated using the
   optimized aggregated SCC union state. If the union state does not contain all
   generators, a direct `SCC_0` versus `SCC_1` plot mixes generator-state and GFM
   effects. The new security figure intentionally compares the final constrained
   SCC with its upper limit and with direct post-hoc inversion. If a baseline
   figure is later required, recompute it with the same `u_G_SCC` state.

3. **Security metrics are aggregated, not hourly.** The SCC case uses the union
   of all hourly synchronous-generator states; classic SCR uses their
   intersection. These can be conservative artificial states rather than a
   realized hour. Every security title, table, and manifest entry therefore says
   `aggregated conservative state`.

4. **The voltage-strength metric is classic SCR.** The actual constraint and
   calculation use `add_classic_scr_constraints.m` and
   `calculate_classic_scr.m`. MISCR and IMISCR are not used in the ver_2.5
   planning path and are not reported by this module.

5. **Post-hoc security recalculation is available and reliable.** The saved
   impedance reconstructions and final binary states permit direct nodal
   admittance inversion for both SCC and classic SCR. The module reports both
   model reconstruction and post-hoc values, their safety limits, margins, and
   maximum relative errors. No unsupported electromagnetic-transient “exact”
   result is claimed.

6. **UC cost packaging is aggregated.** `Result.Cost.UC` combines startup and
   shutdown cost. Because actions and unit costs are saved, the module reconstructs
   the two components separately. Future result packaging should save them as
   explicit fields to make downstream analysis self-contained.

7. **Operating cost is the optimization approximation.** The model uses
   piecewise perspective tangent cuts for quadratic synchronous-generator cost.
   `Cost.GEN` is therefore the optimized approximation, not an independently
   recomputed exact quadratic cost. This is appropriate for objective
   decomposition, but a paper comparing approximation quality should add a
   separate post-hoc quadratic-cost table.

8. **Numerical linear algebra cleanup.** A few shared utilities still use
   explicit `inv`, notably the baseline calculation in
   `calculate_short_circuit_currents.m` and one impedance-bound fallback. Replacing
   these with linear solves (`Y \\ eye(size(Y))`) would improve numerical style.
   The ver_2.5 solve path already uses a linear solve for the final SCC matrix.

9. **Network topology plot intentionally omitted.** The current case contains
   branch connectivity but no verified IEEE-30 bus coordinates or existing
   trusted topology plotting function. No coordinates were invented. Line labels
   use the saved case's from-bus/to-bus data after parameter/result compatibility
   checks.

## Latest-result verification

For `multiple_snapshot_planning_result_20260703_032520.mat`:

- GFM-ES build: one module at bus 15, 30 MW / 60 MWh.
- Maximum system power-balance residual: approximately `1.03e-13 MW`.
- Maximum typical-day SOC cycle error: `0 MWh`.
- Cost decomposition error: approximately `1.12e-8` annual cost units.
- Maximum SCC reconstruction/post-hoc relative error: approximately
  `4.46e-4 %`.
- Maximum classic-SCR reconstruction/post-hoc relative error: approximately
  `1.59e-4 %`.
- Minimum SCC margin: approximately `0.0742 kA`.
- Minimum classic-SCR margin: approximately `0.000485 p.u.`.

The generated `validation_summary.csv` is the authoritative machine-readable
record for these checks.
