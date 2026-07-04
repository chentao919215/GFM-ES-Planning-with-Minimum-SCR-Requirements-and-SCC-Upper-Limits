# ver_2.5 visualization and result export

Run from MATLAB:

```matlab
addpath('D:\Project_With_Codex\Project_2\code\figures');
Report = generate_ver_2_5_figures();
```

The default call selects the newest `multiple_snapshot_planning_result_*.mat`
under `results/` and writes vector PDF, 600 dpi PNG, CSV tables, a validation
summary, a run manifest, and a reusable MAT report under `figs/ver_2_5/`.

Explicit paths are also supported:

```matlab
Report = generate_ver_2_5_figures(result_file, output_root, param_file);
```

Security plots use the model's actual definitions: SCC is evaluated in the
union-state aggregated conservative condition, while classic SCR is evaluated
in the intersection-state aggregated conservative condition. The module compares
the saved optimization impedance reconstruction with a direct post-hoc nodal
admittance inversion. No time-resolved security result is implied.

No topology figure is generated because the project does not include verified
IEEE-30 bus coordinates. Branch endpoint labels are taken from the case data.
