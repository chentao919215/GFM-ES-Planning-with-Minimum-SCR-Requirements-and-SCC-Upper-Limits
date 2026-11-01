function initialize_equipment_model_from_callback(Model_Name)
%% 为模型准备参数及生成目录。
% 同族参数已经完整初始化时，保留扫描或手动设置的工作区覆盖。
Project_Root = find_project_root(get_param(Model_Name, 'FileName'));
% 两个模型的设备族和初始化入口在此维护，不再通过独立清单传递。
switch Model_Name
    case 'Grid_Following_Inverters'
        Parameter_Family = 'gfl';
        Initialization_Script = 'initialize_gfl_model';
    case 'Grid_Forming_Inverters'
        Parameter_Family = 'gfm';
        Initialization_Script = 'initialize_gfm_model';
    otherwise
        error('EquipmentModel:UnknownModel', '不支持的设备模型：%s', Model_Name);
end
ensure_parameters(Parameter_Family, Initialization_Script, Project_Root);
configure_simulink_file_generation(Project_Root, 'persistent');
end

function ensure_parameters(Parameter_Family, Initialization_Script, Project_Root)
%% 参数缺失或切换设备族时初始化，保留同族的显式工况覆盖。
Initialized = evalin('base', ...
    'exist(''Equipment_Parameter_Family'', ''var'') && exist(''Equipment_Parameter_Names'', ''var'')');
if Initialized
    Family = evalin('base', 'Equipment_Parameter_Family');
    Fields = evalin('base', 'Equipment_Parameter_Names');
    Initialized = isequal(Family, Parameter_Family) && iscellstr(Fields) && ...
        ~isempty(Fields) && all(cellfun(@isvarname, Fields));
end
if Initialized
    for k = 1:numel(Fields)
        Initialized = Initialized && evalin('base', ...
            sprintf('exist(''%s'', ''var'') == 1', Fields{k}));
    end
end
if ~Initialized
    Script = fullfile(Project_Root, 'code', 'scripts', 'equipment', ...
        'initialization', [Initialization_Script '.m']);
    assert(isfile(Script), 'EquipmentModel:MissingInitialization', ...
        '未找到初始化脚本：%s', Script);
    evalin('base', sprintf('run(''%s'');', strrep(Script, '''', '''''')));
end
end
