function [current, Eref, saturated] = calculate_gfm_port_current(voltage, slim, theory)
%% 根据端口电压、虚拟阻抗状态和设备参数计算固定内电势电流。
Original_Size = size(voltage);
voltage = voltage(:);
if isscalar(slim)
    slim = repmat(slim, size(voltage));
else
    slim = slim(:);
end
assert(numel(slim) == numel(voltage), ...
    'Slim and voltage sizes differ.');

X = theory.X_L2_pu+slim*theory.X_vir_pu;
Impedance_Squared = theory.R_L2_pu^2+X.^2;
discriminant = (voltage.*X).^2 ...
    -Impedance_Squared.*(voltage.^2-theory.E0_pu^2);
assert(all(discriminant >= -1e-12), ...
    'Fixed-E port equation has no real current solution.');
current = (-voltage.*X+sqrt(max(discriminant, 0))) ...
    ./Impedance_Squared;
current = reshape(max(current, 0), Original_Size);
Eref = repmat(theory.E0_pu, Original_Size);
saturated = false(Original_Size);
end
