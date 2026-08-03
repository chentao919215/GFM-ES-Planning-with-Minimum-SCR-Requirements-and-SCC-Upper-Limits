%% Find_SCR_Convergence_Boundary.m
% Search the SCR boundary of Grid_Following_Inverters.
%
% The script assumes that a larger SCR is not less stable than a smaller
% SCR. It first finds one converged SCR and one non-converged SCR, then uses
% bisection until the two SCR values are closer than cfg.SCR_Tolerance.
%
% Result variables written to the base workspace:
%   scrConvergenceResult
%   scrConvergenceHistory

cfg = localDefaultConfig();
SCR_Convergence_Result = localFindScrBoundary(cfg);
SCR_Convergence_History = SCR_Convergence_Result.history;

assignin('base', 'scrConvergenceResult', SCR_Convergence_Result);
assignin('base', 'scrConvergenceHistory', SCR_Convergence_History);

fprintf('\nSCR boundary search finished.\n');
fprintf('  Converged SCR     : %.6f\n', SCR_Convergence_Result.convergedSCR);
fprintf('  Non-converged SCR : %.6f\n', SCR_Convergence_Result.nonConvergedSCR);
fprintf('  SCR gap           : %.6f\n', SCR_Convergence_Result.scrGap);
fprintf('  Midpoint estimate : %.6f\n', SCR_Convergence_Result.criticalSCRMidpoint);

%% Local functions

function cfg = localDefaultConfig()
    Script_Path = mfilename('fullpath');
    if isempty(Script_Path)
        Work_Directory = pwd;
    else
        Work_Directory = fileparts(Script_Path);
    end

    cfg.Work_Directory = Work_Directory;
    cfg.Model_Name = 'Grid_Following_Inverters';
    Project_Root = fileparts(fileparts(fileparts(Work_Directory)));
    cfg.Model_Directory = fullfile(Project_Root, 'simulink', 'models');
    cfg.Model_File = fullfile(cfg.Model_Directory, [cfg.Model_Name, '.slx']);
    cfg.Parameter_Script = fullfile(Work_Directory, 'GFL_Parameters.m');
    cfg.Signal_Name = 'v_PCC_mag';

    cfg.Stop_Time = 1.0;
    cfg.Tail_Window = [0.95, 1.00];

    % Search settings. This value is intentionally below 0.01.
    cfg.SCR_Tolerance = 0.005;
    cfg.Bracket_Scale = 2.0;
    cfg.SCR_Min = 0.05;
    cfg.SCR_Max = 20.0;
    cfg.Initial_SCR = NaN;  % NaN means: use SCR from GFL_Parameters.m.
    cfg.Max_Bisection_Iterations = 40;
    cfg.Max_Bracket_Steps = 20;

    % Convergence thresholds, all normalized by V_base.
    cfg.Ripple_Limit_PU = 0.010;          % Tail-window peak-to-peak limit.
    cfg.STD_Limit_PU = 0.003;             % Tail-window standard deviation limit.
    cfg.Slope_Limit_PU_Per_Sec = 0.05;      % Linear trend slope limit.
    cfg.Oscillation_Amplitude_Limit_PU = 0.003;  % Detrended oscillation amplitude limit.
    cfg.Zero_Cross_Deadband_PU = 0.001;
    cfg.Oscillation_Min_Zero_Crossings = 4;

    % Smooth only for the convergence metrics, not for the simulation.
    cfg.Smoothing_Window_Sec = 0.002;
    cfg.Min_Tail_Points = 20;

    cfg.V_BaseVariable = 'V_base';
    cfg.Fallback_V_Base = 38.5e3;
    cfg.Verbose = true;
end

function result = localFindScrBoundary(cfg)
    Old_Directory = pwd;
    Cleanup_Obj = onCleanup(@() cd(Old_Directory));
    cd(cfg.Work_Directory);

    if ~isfile(cfg.Parameter_Script)
        error('Parameter script not found: %s', cfg.Parameter_Script);
    end

    if ~isfile(cfg.Model_File)
        error('Model file not found: %s', cfg.Model_File);
    end

    localLoadBaseParameters(cfg);
    Project_Root = fileparts(cfg.Model_Directory);
    Equipment_Directory = fullfile(Project_Root, 'code', 'functions', 'equipment');
    if isempty(which('configure_simulink_file_generation'))
        addpath(Equipment_Directory);
    end
    File_Generation_Cleanup = configure_simulink_file_generation(Project_Root); %#ok<NASGU>
    load_system(cfg.Model_File);

    set_param(cfg.Model_Name, 'ReturnWorkspaceOutputs', 'on');
    set_param(cfg.Model_Name, 'StopTime', localNumToText(cfg.Stop_Time));

    if isnan(cfg.Initial_SCR)
        cfg.Initial_SCR = evalin('base', 'SCR');
    end
    cfg.V_Base = localReadBaseScalar(cfg.V_BaseVariable, cfg.Fallback_V_Base);

    fprintf('Searching SCR boundary for %s.\n', cfg.Model_Name);
    fprintf('  Tail window : %.3f to %.3f s\n', cfg.Tail_Window(1), cfg.Tail_Window(2));
    fprintf('  SCR target gap < %.6f\n\n', cfg.SCR_Tolerance);

    history = localEmptyHistory();
    [trial, history] = localEvaluateAndStore(cfg.Initial_SCR, cfg, history);

    if trial.converged
        Stable_Trial = trial;
        Unstable_Trial = [];
        Next_SCR = cfg.Initial_SCR / cfg.Bracket_Scale;

        for step = 1:cfg.Max_Bracket_Steps
            if Next_SCR < cfg.SCR_Min
                break;
            end

            [trial, history] = localEvaluateAndStore(Next_SCR, cfg, history);
            if trial.converged
                Stable_Trial = trial;
                Next_SCR = Next_SCR / cfg.Bracket_Scale;
            else
                Unstable_Trial = trial;
                break;
            end
        end

        if isempty(Unstable_Trial)
            error(['No non-converged SCR was found down to SCR = %.6g. ', ...
                   'Lower cfg.SCR_Min or start from a smaller cfg.Initial_SCR.'], cfg.SCR_Min);
        end
    else
        Unstable_Trial = trial;
        Stable_Trial = [];
        Next_SCR = cfg.Initial_SCR * cfg.Bracket_Scale;

        for step = 1:cfg.Max_Bracket_Steps
            if Next_SCR > cfg.SCR_Max
                break;
            end

            [trial, history] = localEvaluateAndStore(Next_SCR, cfg, history);
            if trial.converged
                Stable_Trial = trial;
                break;
            else
                Unstable_Trial = trial;
                Next_SCR = Next_SCR * cfg.Bracket_Scale;
            end
        end

        if isempty(Stable_Trial)
            error(['No converged SCR was found up to SCR = %.6g. ', ...
                   'Raise cfg.SCR_Max or start from a larger cfg.Initial_SCR.'], cfg.SCR_Max);
        end
    end

    for iter = 1:cfg.Max_Bisection_Iterations
        if abs(Stable_Trial.SCR - Unstable_Trial.SCR) < cfg.SCR_Tolerance
            break;
        end

        Mid_SCR = 0.5 * (Stable_Trial.SCR + Unstable_Trial.SCR);
        [trial, history] = localEvaluateAndStore(Mid_SCR, cfg, history);

        if trial.converged
            Stable_Trial = trial;
        else
            Unstable_Trial = trial;
        end
    end

    result = struct();
    result.convergedSCR = Stable_Trial.SCR;
    result.nonConvergedSCR = Unstable_Trial.SCR;
    result.scrGap = abs(Stable_Trial.SCR - Unstable_Trial.SCR);
    result.criticalSCRMidpoint = 0.5 * (Stable_Trial.SCR + Unstable_Trial.SCR);
    result.toleranceTarget = cfg.SCR_Tolerance;
    result.tailWindow = cfg.Tail_Window;
    result.convergedMetrics = Stable_Trial.metrics;
    result.nonConvergedMetrics = Unstable_Trial.metrics;
    result.history = struct2table(history);
    result.config = cfg;
end

function [trial, history] = localEvaluateAndStore(SCR_Value, cfg, history)
    trial = localEvaluateSCR(SCR_Value, cfg);
    history(end + 1) = localHistoryRow(trial);

    if cfg.Verbose
        fprintf(['SCR=%9.5f -> %-13s  ripple=%8.4g pu  std=%8.4g pu  ', ...
                 'slope=%8.4g pu/s  oscAmp=%8.4g pu  zc=%2d  time=%6.2f s\n'], ...
            trial.SCR, char(trial.status), trial.metrics.ripplePu, ...
            trial.metrics.stdPu, trial.metrics.slopePuPerSec, ...
            trial.metrics.oscillationAmpPu, trial.metrics.oscillationZeroCrossings, ...
            trial.elapsedSec);
    end
end

function trial = localEvaluateSCR(SCR_Value, cfg)
    t_Start = tic;
    metrics = localBlankMetrics();

    trial = struct();
    trial.SCR = SCR_Value;
    trial.converged = false;
    trial.status = "not_converged";
    trial.metrics = metrics;
    trial.elapsedSec = NaN;

    try
        Grid_Vars = localApplySCRToBase(SCR_Value);

        Simulation_Input = Simulink.SimulationInput(cfg.Model_Name);
        Simulation_Input = Simulation_Input.setModelParameter( ...
            'Stop_Time', localNumToText(cfg.Stop_Time), ...
            'ReturnWorkspaceOutputs', 'on');

        Simulation_Input = Simulation_Input.setVariable('SCR', SCR_Value);
        Simulation_Input = Simulation_Input.setVariable('Zg', Grid_Vars.Zg);
        Simulation_Input = Simulation_Input.setVariable('Lg', Grid_Vars.Lg);
        if isfield(Grid_Vars, 'Lij')
            Simulation_Input = Simulation_Input.setVariable('Lij', Grid_Vars.Lij);
        end

        Simulation_Out = sim(Simulation_Input);
        [t, y] = localExtractSignal(Simulation_Out, cfg.Signal_Name);
        [trial.converged, metrics] = localJudgeConvergence(t, y, cfg);

        if trial.converged
            trial.status = "converged";
        else
            trial.status = "not_converged";
        end
    catch ME
        metrics.message = "Simulation or signal extraction failed: " + string(ME.message);
        trial.converged = false;
        trial.status = "sim_failed";
    end

    trial.metrics = metrics;
    trial.elapsedSec = toc(t_Start);
end

function localLoadBaseParameters(cfg)
    Escaped_Path = strrep(cfg.Parameter_Script, '''', '''''');
    try
        evalc(sprintf('evalin(''base'', ''run(''''%s'''');'');', Escaped_Path));
    catch ME
        error('Failed to run parameter script %s\n%s', cfg.Parameter_Script, ME.message);
    end
end

function Grid_Vars = localApplySCRToBase(SCR_Value)
    Vg = evalin('base', 'Vg');
    S_base = evalin('base', 'S_base');
    f = evalin('base', 'f');

    Zg = Vg^2 / (S_base * SCR_Value);
    Lg = Zg / (2 * pi * f);

    assignin('base', 'SCR', SCR_Value);
    assignin('base', 'Zg', Zg);
    assignin('base', 'Lg', Lg);

    Grid_Vars = struct('Zg', Zg, 'Lg', Lg);

    if evalin('base', 'exist(''MISCR'', ''var'')') == 1
        MISCR = evalin('base', 'MISCR');
        Lij = (SCR_Value / MISCR - 1) * Lg;
        assignin('base', 'Lij', Lij);
        Grid_Vars.Lij = Lij;
    end
end

function value = localReadBaseScalar(Variable_Name, Fallback_Value)
    if evalin('base', sprintf('exist(''%s'', ''var'')', Variable_Name)) == 1
        value = evalin('base', Variable_Name);
        if ~isscalar(value) || ~isnumeric(value) || ~isfinite(value)
            value = Fallback_Value;
        end
    else
        value = Fallback_Value;
    end
end

function [t, y] = localExtractSignal(Simulation_Out, Signal_Name)
    try
        Raw_Signal = Simulation_Out.get(Signal_Name);
    catch
        try
            Raw_Signal = Simulation_Out.(Signal_Name);
        catch ME
            Available_Names = "";
            try
                Available_Names = strjoin(string(Simulation_Out.who), ", ");
            catch
            end
            error('Cannot read simOut.%s. Available outputs: %s\n%s', ...
                Signal_Name, Available_Names, ME.message);
        end
    end

    [t, y] = localSignalToXY(Raw_Signal);
end

function [t, y] = localSignalToXY(Raw_Signal)
    if isa(Raw_Signal, 'timeseries')
        t = Raw_Signal.Time;
        y = Raw_Signal.Data;
    elseif isa(Raw_Signal, 'Simulink.SimulationData.Signal')
        values = Raw_Signal.Values;
        [t, y] = localSignalToXY(values);
        return;
    else
        error('Unsupported signal type: %s', class(Raw_Signal));
    end

    t = double(t(:));
    y = double(squeeze(y));

    if ~isvector(y)
        y = reshape(y, size(y, 1), []);
        y = y(:, 1);
    end

    y = y(:);
    if numel(t) ~= numel(y)
        error('Signal time and data lengths differ: numel(t)=%d, numel(y)=%d.', ...
            numel(t), numel(y));
    end
end

function [converged, metrics] = localJudgeConvergence(t, y, cfg)
    metrics = localBlankMetrics();

    valid = isfinite(t) & isfinite(y);
    t = t(valid);
    y = y(valid);

    if isempty(t)
        metrics.message = "Signal is empty or non-finite.";
        converged = false;
        return;
    end

    [t, order] = sort(t);
    y = y(order);

    idx = (t >= cfg.Tail_Window(1)) & (t <= cfg.Tail_Window(2));
    metrics.tailPointCount = nnz(idx);
    if metrics.tailPointCount < cfg.Min_Tail_Points
        metrics.message = "Too few points in the tail window.";
        converged = false;
        return;
    end

    t_Tail = t(idx);
    Y_Tail_PU = y(idx) ./ cfg.V_Base;

    dt = median(diff(unique(t_Tail)));
    if ~isfinite(dt) || dt <= 0
        metrics.message = "Tail-window time vector is not usable.";
        converged = false;
        return;
    end

    Smooth_Points = max(1, round(cfg.Smoothing_Window_Sec / dt));
    if Smooth_Points > 1
        Y_Trend_PU = movmean(Y_Tail_PU, Smooth_Points, 'Endpoints', 'shrink');
    else
        Y_Trend_PU = Y_Tail_PU;
    end

    t_Fit = t_Tail - t_Tail(1);
    Fit_Coeff = polyfit(t_Fit, Y_Trend_PU, 1);
    Fitted_PU = polyval(Fit_Coeff, t_Fit);
    Residual_PU = Y_Trend_PU - Fitted_PU;

    metrics.meanPu = mean(Y_Trend_PU);
    metrics.ripplePu = max(Y_Trend_PU) - min(Y_Trend_PU);
    metrics.stdPu = std(Y_Trend_PU);
    metrics.slopePuPerSec = abs(Fit_Coeff(1));
    metrics.oscillationAmpPu = 0.5 * (max(Residual_PU) - min(Residual_PU));
    metrics.oscillationZeroCrossings = localSignificantZeroCrossings( ...
        Residual_PU, cfg.Zero_Cross_Deadband_PU);

    metrics.smallRipple = metrics.ripplePu <= cfg.Ripple_Limit_PU;
    metrics.lowStd = metrics.stdPu <= cfg.STD_Limit_PU;
    metrics.lowSlope = metrics.slopePuPerSec <= cfg.Slope_Limit_PU_Per_Sec;
    metrics.noSustainedOscillation = ...
        (metrics.oscillationAmpPu <= cfg.Oscillation_Amplitude_Limit_PU) || ...
        (metrics.oscillationZeroCrossings < cfg.Oscillation_Min_Zero_Crossings);

    converged = metrics.smallRipple && metrics.lowStd && ...
        metrics.lowSlope && metrics.noSustainedOscillation;

    if converged
        metrics.message = "Tail window is settled.";
    else
        metrics.message = sprintf(['Not settled: smallRipple=%d, lowStd=%d, ', ...
            'lowSlope=%d, noSustainedOscillation=%d.'], ...
            metrics.smallRipple, metrics.lowStd, metrics.lowSlope, ...
            metrics.noSustainedOscillation);
    end
end

function count = localSignificantZeroCrossings(x, deadband)
    x = x(:) - mean(x(:));
    x(abs(x) < deadband) = 0;
    signs = sign(x);
    signs(signs == 0) = [];

    if numel(signs) < 2
        count = 0;
    else
        count = sum(signs(1:end-1) .* signs(2:end) < 0);
    end
end

function metrics = localBlankMetrics()
    metrics = struct();
    metrics.tailPointCount = 0;
    metrics.meanPu = NaN;
    metrics.ripplePu = NaN;
    metrics.stdPu = NaN;
    metrics.slopePuPerSec = NaN;
    metrics.oscillationAmpPu = NaN;
    metrics.oscillationZeroCrossings = 0;
    metrics.smallRipple = false;
    metrics.lowStd = false;
    metrics.lowSlope = false;
    metrics.noSustainedOscillation = false;
    metrics.message = "";
end

function history = localEmptyHistory()
    row = struct();
    row.SCR = NaN;
    row.converged = false;
    row.status = "";
    row.elapsedSec = NaN;
    row.tailPointCount = 0;
    row.meanPu = NaN;
    row.ripplePu = NaN;
    row.stdPu = NaN;
    row.slopePuPerSec = NaN;
    row.oscillationAmpPu = NaN;
    row.oscillationZeroCrossings = 0;
    row.smallRipple = false;
    row.lowStd = false;
    row.lowSlope = false;
    row.noSustainedOscillation = false;
    row.message = "";
    history = row([]);
end

function row = localHistoryRow(trial)
    row = struct();
    row.SCR = trial.SCR;
    row.converged = trial.converged;
    row.status = trial.status;
    row.elapsedSec = trial.elapsedSec;
    row.tailPointCount = trial.metrics.tailPointCount;
    row.meanPu = trial.metrics.meanPu;
    row.ripplePu = trial.metrics.ripplePu;
    row.stdPu = trial.metrics.stdPu;
    row.slopePuPerSec = trial.metrics.slopePuPerSec;
    row.oscillationAmpPu = trial.metrics.oscillationAmpPu;
    row.oscillationZeroCrossings = trial.metrics.oscillationZeroCrossings;
    row.smallRipple = trial.metrics.smallRipple;
    row.lowStd = trial.metrics.lowStd;
    row.lowSlope = trial.metrics.lowSlope;
    row.noSustainedOscillation = trial.metrics.noSustainedOscillation;
    row.message = string(trial.metrics.message);
end

function text = localNumToText(value)
    text = sprintf('%.15g', value);
end
