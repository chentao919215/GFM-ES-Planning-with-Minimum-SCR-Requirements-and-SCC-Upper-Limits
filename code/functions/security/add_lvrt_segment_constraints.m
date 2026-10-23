function [C, Segment, Part] = add_lvrt_segment_constraints(V, Phi, On, Sat, Slope, Limit)
%% 新版式(9)：连续三段LVRT函数的精确有界析取表达。
% V与Phi均为标量；分段端点允许相邻两段中的任意一段被选中。

Segment = binvar(3,1,'full');
Part = sdpvar(3,1,'full');
Lower = [On;Sat;0];
Upper = [1;On;Sat];
C = [sum(Segment) == 1, Lower.*Segment <= Part, Part <= Upper.*Segment, ...
    V == sum(Part), Phi == Slope*(On*Segment(2)-Part(2))+Limit*Segment(3)];
end
