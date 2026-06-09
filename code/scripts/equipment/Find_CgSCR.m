%% Find_SCR_Convergence_Boundary.m
% Search the SCR boundary of Grid_Following_Inverters.
%
% The script assumes that a larger SCR is not less stable than a smaller
% SCR. It first finds one converged SCR and one non-converged SCR, then uses
% bisection until the two SCR values are closer than cfg.scrTolerance.
%
% Result variables written to the base workspace:
%   scrConvergenceResult
%   scrConvergenceHistory

cfg = localDefaultConfig();
scrConvergenceResult = localFindScrBoundary(cfg);
scrConvergenceHistory = scrConvergenceResult.history;

assignin('base', 'scrConvergenceResult', scrConvergenceResult);
assignin('base', 'scrConvergenceHistory', scrConvergenceHistory);

fprintf('\nSCR boundary search finished.\n');
fprintf('  Converged SCR     : %.6f\n', scrConvergenceResult.convergedSCR);
fprintf('  Non-converged SCR : %.6f\n', scrConvergenceResult.nonConvergedSCR);
fprintf('  SCR gap           : %.6f\n', scrConvergenceResult.scrGap);
fprintf('  Midpoint estimate : %.6f\n', scrConvergenceResult.criticalSCRMidpoint);

%% Local functions

function cfg = localDefaultConfig()
    scriptPath = mfilename('fullpath');
    if isempty(scriptPath)
        workDir = pwd;
    else
        workDir = fileparts(scriptPath);
    end

    cfg.workDir = workDir;
    cfg.modelName = 'Grid_Following_Inverters';
    cfg.parameterScript = fullfile(workDir, 'Invert_Parameters.m');
    cfg.signalName = 'v_PCC_mag';

    cfg.stopTime = 1.0;
    cfg.tailWindow = [0.95, 1.00];

    % Search settings. This value is intentionally below 0.01.
    cfg.scrTolerance = 0.005;
    cfg.bracketScale = 2.0;
    cfg.scrMin = 0.05;
    cfg.scrMax = 20.0;
    cfg.initialSCR = NaN;  % NaN means: use SCR from Invert_Parameters.m.
    cfg.maxBisectionIterations = 40;
    cfg.maxBracketSteps = 20;

    % Convergence thresholds, all normalized by V_base.
    cfg.rippleLimitPu = 0.010;          % Tail-window peak-to-peak limit.
    cfg.stdLimitPu = 0.003;             % Tail-window standard deviation limit.
    cfg.slopeLimitPuPerSec = 0.05;      % Linear trend slope limit.
    cfg.oscillationAmpLimitPu = 0.003;  % Detrended oscillation amplitude limit.
    cfg.zeroCrossDeadbandPu = 0.001;
    cfg.oscillationMinZeroCrossings = 4;

    % Smooth only for the convergence metrics, not for the simulation.
    cfg.smoothingWindowSec = 0.002;
    cfg.minTailPoints = 20;

    cfg.vBaseVariable = 'V_base';
    cfg.fallbackVBase = 38.5e3;
    cfg.verbose = true;
end

function result = localFindScrBoundary(cfg)
    oldDir = pwd;
    cleanupObj = onCleanup(@() cd(oldDir));
    cd(cfg.workDir);

    if ~isfile(cfg.parameterScript)
        error('Parameter script not found: %s', cfg.parameterScript);
    end

    modelFile = fullfile(cfg.workDir, [cfg.modelName, '.slx']);
    if ~isfile(modelFile)
        error('Model file not found: %s', modelFile);
    end

    localLoadBaseParameters(cfg);
    load_system(cfg.modelName);

    try
        set_param(cfg.modelName, 'ReturnWorkspaceOutputs', 'on');
    catch
        % Older releases may not expose this parameter.
    end
    set_param(cfg.modelName, 'StopTime', localNumToText(cfg.stopTime));

    if isnan(cfg.initialSCR)
        cfg.initialSCR = evalin('base', 'SCR');
    end
    cfg.vBase = localReadBaseScalar(cfg.vBaseVariable, cfg.fallbackVBase);

    fprintf('Searching SCR boundary for %s.\n', cfg.modelName);
    fprintf('  Tail window : %.3f to %.3f s\n', cfg.tailWindow(1), cfg.tailWindow(2));
    fprintf('  SCR target gap < %.6f\n\n', cfg.scrTolerance);

    history = localEmptyHistory();
    [trial, history] = localEvaluateAndStore(cfg.initialSCR, cfg, history);

    if trial.converged
        stableTrial = trial;
        unstableTrial = [];
        nextSCR = cfg.initialSCR / cfg.bracketScale;

        for step = 1:cfg.maxBracketSteps
            if nextSCR < cfg.scrMin
                break;
            end

            [trial, history] = localEvaluateAndStore(nextSCR, cfg, history);
            if trial.converged
                stableTrial = trial;
                nextSCR = nextSCR / cfg.bracketScale;
            else
                unstableTrial = trial;
                break;
            end
        end

        if isempty(unstableTrial)
            error(['No non-converged SCR was found down to SCR = %.6g. ', ...
                   'Lower cfg.scrMin or start from a smaller cfg.initialSCR.'], cfg.scrMin);
        end
    else
        unstableTrial = trial;
        stableTrial = [];
        nextSCR = cfg.initialSCR * cfg.bracketScale;

        for step = 1:cfg.maxBracketSteps
            if nextSCR > cfg.scrMax
                break;
            end

            [trial, history] = localEvaluateAndStore(nextSCR, cfg, history);
            if trial.converged
                stableTrial = trial;
                break;
            else
                unstableTrial = trial;
                nextSCR = nextSCR * cfg.bracketScale;
            end
        end

        if isempty(stableTrial)
            error(['No converged SCR was found up to SCR = %.6g. ', ...
                   'Raise cfg.scrMax or start from a larger cfg.initialSCR.'], cfg.scrMax);
        end
    end

    for iter = 1:cfg.maxBisectionIterations
        if abs(stableTrial.SCR - unstableTrial.SCR) < cfg.scrTolerance
            break;
        end

        midSCR = 0.5 * (stableTrial.SCR + unstableTrial.SCR);
        [trial, history] = localEvaluateAndStore(midSCR, cfg, history);

        if trial.converged
            stableTrial = trial;
        else
            unstableTrial = trial;
        end
    end

    result = struct();
    result.convergedSCR = stableTrial.SCR;
    result.nonConvergedSCR = unstableTrial.SCR;
    result.scrGap = abs(stableTrial.SCR - unstableTrial.SCR);
    result.criticalSCRMidpoint = 0.5 * (stableTrial.SCR + unstableTrial.SCR);
    result.toleranceTarget = cfg.scrTolerance;
    result.tailWindow = cfg.tailWindow;
    result.convergedMetrics = stableTrial.metrics;
    result.nonConvergedMetrics = unstableTrial.metrics;
    result.history = struct2table(history);
    result.config = cfg;
end

function [trial, history] = localEvaluateAndStore(scrValue, cfg, history)
    trial = localEvaluateSCR(scrValue, cfg);
    history(end + 1) = localHistoryRow(trial);

    if cfg.verbose
        fprintf(['SCR=%9.5f -> %-13s  ripple=%8.4g pu  std=%8.4g pu  ', ...
                 'slope=%8.4g pu/s  oscAmp=%8.4g pu  zc=%2d  time=%6.2f s\n'], ...
            trial.SCR, char(trial.status), trial.metrics.ripplePu, ...
            trial.metrics.stdPu, trial.metrics.slopePuPerSec, ...
            trial.metrics.oscillationAmpPu, trial.metrics.oscillationZeroCrossings, ...
            trial.elapsedSec);
    end
end

function trial = localEvaluateSCR(scrValue, cfg)
    tStart = tic;
    metrics = localBlankMetrics();

    trial = struct();
    trial.SCR = scrValue;
    trial.converged = false;
    trial.status = "not_converged";
    trial.metrics = metrics;
    trial.elapsedSec = NaN;

    try
        gridVars = localApplySCRToBase(scrValue);

        simInput = Simulink.SimulationInput(cfg.modelName);
        simInput = simInput.setModelParameter( ...
            'StopTime', localNumToText(cfg.stopTime), ...
            'ReturnWorkspaceOutputs', 'on');

        simInput = simInput.setVariable('SCR', scrValue);
        simInput = simInput.setVariable('Zg', gridVars.Zg);
        simInput = simInput.setVariable('Lg', gridVars.Lg);
        if isfield(gridVars, 'Lij')
            simInput = simInput.setVariable('Lij', gridVars.Lij);
        end

        simOut = sim(simInput);
        [t, y] = localExtractSignal(simOut, cfg.signalName);
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
    trial.elapsedSec = toc(tStart);
end

function localLoadBaseParameters(cfg)
    escapedPath = strrep(cfg.parameterScript, '''', '''''');
    try
        evalc(sprintf('evalin(''base'', ''run(''''%s'''');'');', escapedPath));
    catch ME
        error('Failed to run parameter script %s\n%s', cfg.parameterScript, ME.message);
    end
end

function gridVars = localApplySCRToBase(scrValue)
    Vg = evalin('base', 'Vg');
    S_base = evalin('base', 'S_base');
    f = evalin('base', 'f');

    Zg = Vg^2 / (S_base * scrValue);
    Lg = Zg / (2 * pi * f);

    assignin('base', 'SCR', scrValue);
    assignin('base', 'Zg', Zg);
    assignin('base', 'Lg', Lg);

    gridVars = struct('Zg', Zg, 'Lg', Lg);

    if evalin('base', 'exist(''MISCR'', ''var'')') == 1
        MISCR = evalin('base', 'MISCR');
        Lij = (scrValue / MISCR - 1) * Lg;
        assignin('base', 'Lij', Lij);
        gridVars.Lij = Lij;
    end
end

function value = localReadBaseScalar(variableName, fallbackValue)
    if evalin('base', sprintf('exist(''%s'', ''var'')', variableName)) == 1
        value = evalin('base', variableName);
        if ~isscalar(value) || ~isnumeric(value) || ~isfinite(value)
            value = fallbackValue;
        end
    else
        value = fallbackValue;
    end
end

function [t, y] = localExtractSignal(simOut, signalName)
    try
        rawSignal = simOut.get(signalName);
    catch
        try
            rawSignal = simOut.(signalName);
        catch ME
            availableNames = "";
            try
                availableNames = strjoin(string(simOut.who), ", ");
            catch
            end
            error('Cannot read simOut.%s. Available outputs: %s\n%s', ...
                signalName, availableNames, ME.message);
        end
    end

    [t, y] = localSignalToXY(rawSignal);
end

function [t, y] = localSignalToXY(rawSignal)
    if isa(rawSignal, 'timeseries')
        t = rawSignal.Time;
        y = rawSignal.Data;
    elseif isa(rawSignal, 'Simulink.SimulationData.Signal')
        values = rawSignal.Values;
        [t, y] = localSignalToXY(values);
        return;
    elseif isstruct(rawSignal) && isfield(rawSignal, 'time') && isfield(rawSignal, 'signals')
        t = rawSignal.time;
        y = rawSignal.signals.values;
    else
        error('Unsupported signal type: %s', class(rawSignal));
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

    idx = (t >= cfg.tailWindow(1)) & (t <= cfg.tailWindow(2));
    metrics.tailPointCount = nnz(idx);
    if metrics.tailPointCount < cfg.minTailPoints
        metrics.message = "Too few points in the tail window.";
        converged = false;
        return;
    end

    tTail = t(idx);
    yTailPu = y(idx) ./ cfg.vBase;

    dt = median(diff(unique(tTail)));
    if ~isfinite(dt) || dt <= 0
        metrics.message = "Tail-window time vector is not usable.";
        converged = false;
        return;
    end

    smoothPoints = max(1, round(cfg.smoothingWindowSec / dt));
    if smoothPoints > 1
        yTrendPu = movmean(yTailPu, smoothPoints, 'Endpoints', 'shrink');
    else
        yTrendPu = yTailPu;
    end

    tFit = tTail - tTail(1);
    fitCoeff = polyfit(tFit, yTrendPu, 1);
    fittedPu = polyval(fitCoeff, tFit);
    residualPu = yTrendPu - fittedPu;

    metrics.meanPu = mean(yTrendPu);
    metrics.ripplePu = max(yTrendPu) - min(yTrendPu);
    metrics.stdPu = std(yTrendPu);
    metrics.slopePuPerSec = abs(fitCoeff(1));
    metrics.oscillationAmpPu = 0.5 * (max(residualPu) - min(residualPu));
    metrics.oscillationZeroCrossings = localSignificantZeroCrossings( ...
        residualPu, cfg.zeroCrossDeadbandPu);

    metrics.smallRipple = metrics.ripplePu <= cfg.rippleLimitPu;
    metrics.lowStd = metrics.stdPu <= cfg.stdLimitPu;
    metrics.lowSlope = metrics.slopePuPerSec <= cfg.slopeLimitPuPerSec;
    metrics.noSustainedOscillation = ...
        (metrics.oscillationAmpPu <= cfg.oscillationAmpLimitPu) || ...
        (metrics.oscillationZeroCrossings < cfg.oscillationMinZeroCrossings);

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
