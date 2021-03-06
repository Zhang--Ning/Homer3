classdef DataTreeClass <  handle
    
    properties
        files
        filesErr
        groups
        dirnameGroup
        currElem
        reg
        config
    end
    
    methods
        
        % ---------------------------------------------------------------
        function obj = DataTreeClass(groupDirs, fmt, procStreamCfgFile)
            obj.groups         = GroupClass().empty();
            obj.currElem      = TreeNodeClass().empty();
            obj.reg           = RegistriesClass().empty();
            obj.config        = ConfigFileClass().empty();
            obj.dirnameGroup  = '';
            
            %%%% Parse args
            
            % Arg 1: get folder of the group being loaded
            if ~exist('groupDirs','var')
                groupDirs{1} = pwd;
            elseif ~iscell(groupDirs)
                groupDirs = {groupDirs};
            end
            
            % Arg 2: get the file format of the data files
            if ~exist('fmt','var')
                fmt = '';
            end
            
            % Arg 3: Get the processing stream config files name
            if ~exist('procStreamCfgFile','var')
                procStreamCfgFile = '';
            end
            
            obj.FindAndLoadGroups(groupDirs, fmt, procStreamCfgFile);
            if obj.IsEmpty()
                return;
            end
            
            % Change current folder to last loaded group; even though we
            % handle multiple groups and use absolute paths we still have
            % group as the basic data unit and context. So we want to 
            % change the current folder to whatever is the current working
            % group.
            cd(obj.groups(end).path);
            
            % Load user function registry
            obj.reg = RegistriesClass();
            if ~isempty(obj.reg.GetSavedRegistryPath())
                fprintf('Loaded saved registry %s\n', obj.reg.GetSavedRegistryPath());
            end
            
            % Initialize the current processing element within the group
            obj.SetCurrElem(1,1,1);
        end
        
        
        % --------------------------------------------------------------
        function delete(obj)
            if isempty(obj.currElem)
                return;
            end
        end


        % --------------------------------------------------------------
        function status = SelectOptionsWhenLoadFails(obj, dataInit)
            status = -1;
            
            msg{1} = sprintf('Could not load any of the requested files in the group folder %s. ', obj.dirnameGroup);
            msg{2} = sprintf('Do you want to select another group folder?');
            q = MenuBox([msg{:}], {'YES','NO'});
            if q==2
                fprintf('Skipping group folder %s...\n', obj.dirnameGroup);
                obj.dirnameGroup = 0;
                return;
            end
            obj.dirnameGroup = uigetdir(pwd, 'Please select another group folder ...');
            if obj.dirnameGroup==0
                fprintf('Skipping group folder %s...\n', obj.dirnameGroup);
                return;
            end
            status = 0;
        end
        
        
        
        
        % --------------------------------------------------------------
        function FindAndLoadGroups(obj, groupDirs, fmt, procStreamCfgFile)
            
            for kk=1:length(groupDirs)
                
                obj.dirnameGroup = convertToStandardPath(groupDirs{kk});

                iGnew = length(obj.groups)+1;
                
                % Get file names and load them into DataTree
                while length(obj.groups) < iGnew
                    obj.files    = FileClass().empty();
                    obj.filesErr = FileClass().empty();
                    
                    dataInit = FindFiles(obj.dirnameGroup, fmt);
                    if isempty(dataInit) || dataInit.isempty()
                        return;
                    end
                    obj.files = dataInit.files;
                    
                    obj.LoadGroup(procStreamCfgFile);
                    if length(obj.groups) < iGnew
                        if SelectOptionsWhenLoadFails(obj, dataInit)<0
                            break;
                        end
                    end
                end
                
            end
            
        end
        
            
        % ---------------------------------------------------------------
        function LoadGroup(obj, procStreamCfgFile)
            if ~exist('procStreamCfgFile','var')
                procStreamCfgFile = '';
            end
            
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            % Load acquisition data from the data files
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            obj.AcqData2Group();
                
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            % Remove file entries from files array for data files 
            % which didn't load correctly because of format incompatibility
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            obj.ErrorCheckLoadedFiles();

            for ii=1:length(obj.groups)
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                % Load derived or post-acquisition data from a file if it
                % exists
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                obj.groups(ii).Load();            
            
            
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                % Initialize procStream for all tree nodes
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                obj.groups(ii).InitProcStream(procStreamCfgFile);
                
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                % Generate the stimulus conditions for the group tree
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                obj.groups(ii).SetConditions();
                
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                % Find the amount of memory the whole group tree requires
                % at the run level. If group runs take up more than half a
                % GB then do not save dc and dod time courses and recalculate
                % dc and dod for each new current element (currElem) on the
                % fly. This should be a menu option in future releases
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                fprintf('Memory required for acquisition data %0.1f MB\n', obj.groups(ii).MemoryRequired() / 1e6);
            end
        end
        
        
        % ----------------------------------------------------------
        function AcqData2Group(obj)
            if isempty(obj.files)
                return;
            end            
            groupCurr = GroupClass().empty();
            subjCurr = SubjClass().empty();
            runCurr = RunClass().empty();
            
            fprintf('\n');
            iG = 1;
            for iF=1:length(obj.files)
                % Extract group, subj, and run names from file struct
                [groupName, subjName, runName] = obj.files(iF).ExtractNames();

                % Create current TreeNode objects corresponding to the current files entry
                if ~isempty(groupName) && ~strcmp(groupName, groupCurr.GetName)
                    groupCurr = GroupClass(obj.files(iF), iG, 'noprint');
                end
                if ~isempty(subjName) && ~strcmp(subjName, subjCurr.GetName)
                    subjCurr = SubjClass(obj.files(iF));
                end
                if ~isempty(runName) && ~strcmp(runName, runCurr.GetName)
                    runCurr = RunClass(obj.files(iF));
                end

                % If current run has successfully loaded acquired data from data file, then add 
                % current group, subject and run to dataTree. Then reset current run to empty. 
                % (We do not reset current subject or group because they can contain multiple 
                % nodes and they cannot be empty once they've been initialized once whereas run 
                % can be if it fails to load a data file. 
                if ~runCurr.IsEmpty()
                    obj.Add(groupCurr, subjCurr, runCurr);
                    runCurr = RunClass().empty();
                end
            end
            
            fprintf('\n');            
        end


       
        % ----------------------------------------------------------
        function Add(obj, group, subj, run)
            if nargin<2
                return;
            end
                        
            % Add group to this dataTree
            jj=0;
            for ii=1:length(obj.groups)
                if strcmp(obj.groups(ii).GetName, group.GetName())
                    jj=ii;
                    break;
                end
            end
            if jj==0
                jj = length(obj.groups)+1;
                group.SetIndexID(jj);
                obj.groups(jj) = group;
                obj.groups(jj).SetPath(obj.dirnameGroup)
                fprintf('Added group %s to dataTree.\n', obj.groups(jj).GetName);
            end

            %v Add subj and run to group
            obj.groups(jj).Add(subj, run);            
        end

        
        % ----------------------------------------------------------
        function ErrorCheckLoadedFiles(obj)
            for iF=length(obj.files):-1:1
                if ~obj.files(iF).Loadable() && obj.files(iF).IsFile()
                    obj.filesErr(end+1) = obj.files(iF).copy;
                    obj.files(iF) = [];
                end                    
            end
        end
        
        
        % ----------------------------------------------------------------------------------
        function list = DepthFirstTraversalList(obj)
            list = {};
            for ii=1:length(obj.groups)
                list = [list; obj.groups(ii).DepthFirstTraversalList()];
            end
        end        
        
        
        % ----------------------------------------------------------
        function SetCurrElem(obj, iGroup, iSubj, iRun)
            if isempty(obj.groups)
                return;
            end
            
            if nargin==1
                iGroup = 0;
                iSubj = 0;
                iRun  = 0;
            elseif nargin==2
                iSubj = 0;
                iRun  = 0;
            elseif nargin==3
                iRun  = 0;
            end
            
            if iSubj==0 && iRun==0
                obj.currElem = obj.groups(iGroup);
            elseif iSubj>0 && iRun==0
                obj.currElem = obj.groups(iGroup).subjs(iSubj);
            elseif iSubj>0 && iRun>0
                obj.currElem = obj.groups(iGroup).subjs(iSubj).runs(iRun);
            end
        end


        % ----------------------------------------------------------
        function procElem = GetCurrElem(obj)
            procElem = obj.currElem;
        end


        % ----------------------------------------------------------
        function [iGroup, iSubj, iRun] = GetCurrElemIndexID(obj)
            iGroup = obj.currElem.iGroup;
            iSubj = obj.currElem.iSubj;
            iRun = obj.currElem.iRun;
        end


        % ----------------------------------------------------------
        function Save(obj)
            obj.groups(obj.currElem.iGroup).Save();
        end


        % ----------------------------------------------------------
        function CalcCurrElem(obj)
            obj.currElem.Calc();
        end

        
        % ----------------------------------------------------------
        function b = IsEmpty(obj)
            b = true;
            if isempty(obj)
                return
            end
            if isempty(obj.files)
                return;
            end
            if isempty(obj.groups)
                return;
            end
            b = false;
        end

    end
    
end