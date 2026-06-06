%% 参数与矩阵设置
% R1 = 10;
% L1 = 1e-3;
% L2 = 300e-6;
% C  = 20e-6;

R1 = 5.1041667;
L1 = 5.1041667e-4;
L2 = 1.53125e-4;
C  = 3.9183673e-5;

fg = 50; 
w  = 2*pi*fg;

A = [-R1/L1      w -1/L1     0    0    0;
         -w -R1/L1     0 -1/L1    0    0;
        1/C      0     0     w -1/C    0;
          0    1/C    -w     0    0 -1/C;
          0      0  1/L2     0    0    w;
          0      0     0  1/L2   -w    0];

B = [1/L1    0;
        0 1/L2;
        0    0;
        0    0;
        0    0;
        0    0];

C = [0 0 0 0 1 0;
     0 0 0 0 0 1];

% 设置传递函数变量s
s = tf('s');
G = C*inv(s*eye(6)*1j-A)*B;

% 求取相对增益矩阵
RGA = G.*(inv(G).');

%% 选择RGA中元素和查看G中传递函数 
% 求取幅频响应
f = logspace(0, 4, 2000);           % 频率轴，Hz
w = 2*pi*f;                         % 转 rad/s
Gjw = squeeze(freqresp(G(1,1), w)); % 求取幅频响应

% FRD 模型
Gfrd = frd(Gjw,w);  
[mag,~,wout] = bode(Gfrd, w);  % mag是幅值(线性)，phase单位度(未使用)
mag = squeeze(mag);            % 转为列向量
f = wout/(2*pi);               % wout转为Hz，这一步是冗余的，不去掉便于理解
figure
plot(f, 20*log10(mag));
grid on
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');
title('|G(j\omega)|');

%% 求取PI参数并验证
% 目标带宽（例：300 Hz）
wc = 2*pi*300;

[Cpi, info] = pidtune(Gfrd,'PI',wc);    % Cpi = Kp + Ki/s
Kp = Cpi.Kp; 
Ki = Cpi.Ki;

% 验证：幅频和相位裕度
% 设置传递函数变量s
s = tf('s');
result_PI = (Kp*s*1j+Ki)/s*1j;

% 幅频响应（dB vs. Hz）
f = logspace(0, 3, 2000);           % 频率轴，Hz
w = 2*pi*f;                         % 转 rad/s
[mag,~,wout] = bode(result_PI, w);  % mag是幅值(线性)，phase单位度(未使用)
mag = squeeze(mag);                 % 转为列向量
f = wout/(2*pi);                    % wout转为Hz，这一步是冗余的，不去掉便于理解
figure
plot(f, 20*log10(mag));
grid on
xlabel('Frequency (Hz)'); 
ylabel('Magnitude (dB)');
title('|G(j\omega)|');

%% 草稿(字面意思，就是草稿)
R1 = 10;
L1 = 1e-3;
L2 = 300e-6;
C  = 20e-6;
fg = 50; 
w  = 2*pi*fg;

A = [-R1/L1      w -1/L1     0    0    0;
         -w -R1/L1     0 -1/L1    0    0;
        1/C      0     0     w -1/C    0;
          0    1/C    -w     0    0 -1/C;
          0      0  1/L2     0    0    w;
          0      0     0  1/L2   -w    0];

B = [1/L1    0;
        0 1/L2;
        0    0;
        0    0;
        0    0;
        0    0];

C = [0 0 0 0 1 0;
     0 0 0 0 0 1];

s = tf('s');
G = C*inv(s*eye(6)*1j-A)*B;

RGA = G.*(inv(G).');

% 幅频响应（dB vs. Hz）
w = logspace(0, 5, 2000);      % 频率向量（rad/s），10^0~10^4
[mag,phase,wout] = bode(G(1,1), w); % mag是幅值（线性），phase单位度
mag = squeeze(mag);            % 转为列向量
f = wout/(2*pi);               % Hz
plot(f, 20*log10(mag)), grid on
xlabel('Frequency (Hz)'), ylabel('Magnitude (dB)')
title('|G(j\omega)|')
