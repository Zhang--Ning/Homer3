classdef SnirfClass < AcqDataClass & FileLoadSaveClass
        
    properties
        formatVersion
        data
        stim
        sd
        aux
        timeOffset
        metaDataTags
    end
    
    methods
        
        % -------------------------------------------------------
        function obj = SnirfClass(varargin)
            %
            % Syntax:
            %   obj = SnirfClass()
            %   obj = SnirfClass(filename);
            %   obj = SnirfClass(nirs);
            %   obj = SnirfClass(data, stim);
            %   obj = SnirfClass(data, stim, sd);
            %   obj = SnirfClass(data, stim, sd, aux);
            %   obj = SnirfClass(d, t, SD, aux, s);
            %   obj = SnirfClass(d, t, SD, aux, s, CondNames);
            %
            % Example 1:
            %   Nirs2Snirf('./Simple_Probe1_run04.nirs');
            %   snirf = SnirfClass('./Simple_Probe1_run04.snirf');
            %    
            %   Here's some of the output:
            %
            %   snirf(1).data ====>
            % 
            %       DataClass with properties:
            %
            %           d: [1200x8 double]
            %           t: [1200x1 double]
            %           ml: [1x8 MeasListClass]
            %
             
            % Initialize properties from SNIRF spec 
            obj.formatVersion = '1.0';
            obj.timeOffset     = 0;
            obj.metaDataTags   = {
                {'SubjectID','subj1'};
                {'MeasurementDate','yyyyddmo'};
                {'MeasurementTime','hhmmss.ms'};
                {'SpatialUnit','mm'};
                };
            obj.data           = DataClass().empty();
            obj.stim           = StimClass().empty();
            obj.sd             = SdClass().empty();
            obj.aux            = AuxClass().empty();
            
            % Set base class properties not part of the SNIRF format
            obj.fileformat = 'hdf5';
            
            % See if we're loading .nirs data format
            if nargin>4
                d         = varargin{1};
                t         = varargin{2};
                SD        = varargin{3};
                aux       = varargin{4};
                s         = varargin{5};
            end
            if nargin>5
                CondNames = varargin{6};
            end
            
            % TBD: Need to find better way of parsing arguments. It gets complicated 
            % because of all the variations of calling this class constructor but 
            % there is should be a simpler way to do this 
            
            % The basic 5 of a .nirs format in a struct
            if nargin==1
                if ischar(varargin{1})
                    obj.Load(varargin{1});
                elseif isstruct(varargin{1})
                    nirs = varargin{1};                    
                    obj.data(1) = DataClass(nirs.d, nirs.t, nirs.SD.MeasList);
                    for ii=1:size(nirs.s,2)
                        if isfield(nirs, 'CondNames')
                            obj.stim(ii) = StimClass(nirs.s(:,ii), nirs.t, nirs.CondNames{ii});
                        else
                            obj.stim(ii) = StimClass(nirs.s(:,ii), nirs.t, num2str(ii));
                        end
                    end
                    obj.sd      = SdClass(nirs.SD);
                    for ii=1:size(nirs.aux,2)
                        obj.aux(ii) = AuxClass(nirs.aux(:,ii), nirs.t, sprintf('aux%d',ii));
                    end
                end                
            elseif nargin>1 && nargin<5
                data = varargin{1};
                obj.SetData(data);
                stim = varargin{2};
                obj.SetStim(stim);
                if nargin>2
                    sd = varargin{3};
                    obj.SetSd(sd);
                end
                if nargin>3
                    aux = varargin{4};
                    obj.SetAux(aux);
                end
            % The basic 5 of a .nirs format as separate args
            elseif nargin==5
                obj.data(1) = DataClass(d,t,SD.MeasList);
                for ii=1:size(s,2)
                    obj.stim(ii) = StimClass(s(:,ii),t,num2str(ii));
                end
                obj.sd      = SdClass(SD);
                for ii=1:size(aux,2)
                    obj.aux(ii) = AuxClass(aux, t, sprintf('aux%d',ii));
                end
            % The basic 5 of a .nirs format plus condition names
            elseif nargin==6
                obj.data(1) = DataClass(d,t,SD.MeasList);
                for ii=1:size(s,2)
                    obj.stim(ii) = StimClass(s(:,ii),t,CondNames{ii});
                end
                obj.sd      = SdClass(SD);
                for ii=1:size(aux,2)
                    obj.aux(ii) = AuxClass(aux, t, sprintf('aux%d',ii));
                end
            end
            
        end
        
        
        % -------------------------------------------------------
        function SortStims(obj)
            temp = obj.stim.copy;
            delete(obj.stim);
            names = {};
            for ii=1:length(temp)
                names{ii} = temp(ii).name;
            end
            [~,idx] = sort(names);
            obj.stim = temp(idx).copy;
        end
        
        
        % -------------------------------------------------------
        function err = LoadHdf5(obj, fname, parent)
            err = 0;
            
            % Arg 1
            if ~exist('fname','var') || ~exist(fname,'file')
                fname = '';
            end
            
            % Arg 2
            if ~exist('parent', 'var')
                parent = '/snirf';
            elseif parent(1)~='/'
                parent = ['/',parent];
            end
            
            % Do some error checking            
            if ~isempty(fname)
                obj.filename = fname;
            else
                fname = obj.filename;
            end
            if isempty(fname)
               err=-1;
               return;
            end
            
            %%%%%%%%%%%% Ready to load from file
            
            obj.formatVersion = strtrim_improve(h5read(fname, [parent, '/formatVersion']));
            obj.timeOffset = hdf5read(fname, [parent, '/timeOffset']);
            
            % Load metaDataTags
            ii=1;
            while 1
                try
                    obj.metaDataTags{ii}{1} = strtrim_improve(h5read(fname, [parent, '/metaDataTags_', num2str(ii), '/k']));
                    obj.metaDataTags{ii}{2} = strtrim_improve(h5read(fname, [parent, '/metaDataTags_', num2str(ii), '/v']));
                catch
                    break;
                end
                ii=ii+1;
            end
            
            % Load data
            ii=1;
            while 1
                if ii > length(obj.data)
                    obj.data(ii) = DataClass;
                end
                if obj.data(ii).LoadHdf5(fname, [parent, '/data_', num2str(ii)]) < 0
                    obj.data(ii).delete();
                    obj.data(ii) = [];
                    break;
                end
                ii=ii+1;
            end
            
            % Load stim
            
            % Since we want to load stims in sorted order (i.e., according to alphabetical order 
            % of condition names), first load to temporary variable.
            ii=1;
            while 1
                if ii > length(obj.stim)
                    obj.stim(ii) = StimClass;
                end
                if obj.stim(ii).LoadHdf5(fname, [parent, '/stim_', num2str(ii)]) < 0
                    obj.stim(ii).delete();
                    obj.stim(ii) = [];
                    break;
                end                
                ii=ii+1;
            end
            obj.SortStims();
            
            % Load sd
            obj.sd = SdClass();
            obj.sd.LoadHdf5(fname, [parent, '/sd']);
            
            % Load aux
            ii=1;
            while 1
                if ii > length(obj.aux)
                    obj.aux(ii) = AuxClass;
                end
                if obj.aux(ii).LoadHdf5(fname, [parent, '/aux_', num2str(ii)]) < 0
                    obj.aux(ii).delete();
                    obj.aux(ii) = [];
                    break;
                end
                ii=ii+1;
            end
        end
        
        
        % -------------------------------------------------------
        function SaveHdf5(obj, fname, parent)
            % Arg 1
            if ~exist('fname','var') || isempty(fname)
                fname = '';
            end
            
            % Args
            if exist(fname, 'file')
                delete(fname);
            end
            fid = H5F.create(fname, 'H5F_ACC_TRUNC', 'H5P_DEFAULT', 'H5P_DEFAULT');
            H5F.close(fid);
            
            if ~exist('parent', 'var')
                parent = '/snirf';
            elseif parent(1)~='/'
                parent = ['/',parent];
            end
            
            %%%%% Save this object's properties
            
            % Save formatVersion
            hdf5write(fname, [parent, '/formatVersion'], obj.formatVersion, 'WriteMode','append');
            
            % Save timeOffset
            hdf5write(fname, [parent, '/timeOffset'], obj.timeOffset, 'WriteMode','append');
            
            % Save metaDataTags
            for ii=1:length(obj.metaDataTags)
                key = sprintf('%s/metaDataTags_%d/k', parent, ii);
                val = sprintf('%s/metaDataTags_%d/v', parent, ii);
                hdf5write_safe(fname, key, obj.metaDataTags{ii}{1});
                hdf5write_safe(fname, val, obj.metaDataTags{ii}{2});
            end
            
            % Save data
            for ii=1:length(obj.data)
                obj.data(ii).SaveHdf5(fname, [parent, '/data_', num2str(ii)]);
            end
            
            % Save stim
            for ii=1:length(obj.stim)
                obj.stim(ii).SaveHdf5(fname, [parent, '/stim_', num2str(ii)]);
            end
            
            % Save sd
            obj.sd.SaveHdf5(fname, [parent, '/sd']);
            
            % Save aux
            for ii=1:length(obj.aux)
                obj.aux(ii).SaveHdf5(fname, [parent, '/aux_', num2str(ii)]);
            end
        end
                
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Basic methods to Set/Get native variable 
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    methods

        % ---------------------------------------------------------
        function SetFormatVersion(obj, val)
            obj.formatVersion = val;            
        end
        
        % ---------------------------------------------------------
        function val = GetFormatVersion(obj)
            val = obj.formatVersion;
        end
        
        % ---------------------------------------------------------
        function SetData(obj, val)
            obj.data = val.copy;            
        end
        
        % ---------------------------------------------------------
        function val = GetData(obj)
            val = obj.data;
        end
        
        % ---------------------------------------------------------
        function SetStim(obj, val)
            obj.stim = val.copy;            
        end
        
        % ---------------------------------------------------------
        function val = GetStim(obj)
            val = obj.stim.copy;
        end
        
        % ---------------------------------------------------------
        function SetSd(obj, val)
            obj.sd = val.copy;            
        end
        
        % ---------------------------------------------------------
        function val = GetSd(obj)
            val = obj.sd;
        end
        
        % ---------------------------------------------------------
        function SetAux(obj, val)
            obj.aux = val.copy;            
        end
        
        % ---------------------------------------------------------
        function val = GetAux(obj)
            val = obj.aux;
        end
        
        % ---------------------------------------------------------
        function SetTimeOffset(obj, val)
            obj.timeOffset = val;        
        end
        
        % ---------------------------------------------------------
        function val = GetTimeOffset(obj)
            val = obj.timeOffset;
        end
        
        % ---------------------------------------------------------
        function SetMetaDataTags(obj, val)
            obj.metaDataTags = val;            
        end
        
        % ---------------------------------------------------------
        function val = GetMetaDataTags(obj)
            val = obj.metaDataTags;
        end
        
    end
    
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Acquired data class methods that must be implemented
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    methods

        % ---------------------------------------------------------
        function t = GetTime(obj, idx)
            if nargin==1
                idx=1;
            end
            t = obj.data(idx).GetTime();
        end
        
        
        % ---------------------------------------------------------
        function datamat = GetDataMatrix(obj, idx)
            if nargin==1
                idx=1;
            end
            datamat = obj.data(idx).GetDataMatrix();
        end
        
        
        % ---------------------------------------------------------
        function ml = GetMeasList(obj, idx)
            if nargin==1
                idx=1;
            end
            ml = obj.data(idx).GetMeasList();
        end
        
        
        % ---------------------------------------------------------
        function wls = GetWls(obj)
            wls = obj.sd.GetWls();
        end
        
        
        % ---------------------------------------------------------
        function SetStims_MatInput(obj, s, t, CondNames)
            if ~exist('CondNames', 'var')
                CondNames = str2cell(num2str(1:size(s,2)));
            end
            CondNamesCurr = obj.GetConditions();
            for ii=1:size(s,2)
                k = find(strcmp(CondNames{ii}, CondNamesCurr));
                if isempty(k)
                    obj.stim(end+1) = StimClass(s(:,ii), t, CondNames{ii});
                    continue;
                end
                tidxs = find(s(:,ii)~=0);
                for jj=1:length(tidxs)
                    if ~obj.stim(k).Exists(t(tidxs(jj)))
                        obj.stim(k).AddStims(t(tidxs(jj)));
                    else
                        obj.stim(k).EditValue(t(tidxs(jj)), s(tidxs(jj),ii));
                    end
                end
            end
        end
        
        
        % ---------------------------------------------------------
        function s = GetStims(obj)
            t = obj.data(1).GetTime();
            s = zeros(length(t), length(obj.stim));
            for ii=1:length(obj.stim)
                [ts, v] = obj.stim(ii).GetStim();
                [~, k] = nearest_point(t, ts);
                if isempty(k)
                    continue;
                end
                s(k,ii) = v;
            end
        end
        
        
        % ---------------------------------------------------------
        function CondNames = GetConditions(obj)
            CondNames = cell(1,length(obj.stim));
            for ii=1:length(obj.stim)
                CondNames{ii} = obj.stim(ii).GetName();
            end
        end
        
        
        
        % ---------------------------------------------------------
        function SD = GetSDG(obj)
            SD.SrcPos = obj.sd.GetSrcPos();
            SD.DetPos = obj.sd.GetDetPos();
        end
                
        
        % ---------------------------------------------------------
        function srcpos = GetSrcPos(obj)
            srcpos = obj.sd.GetSrcPos();
        end
        
        
        % ---------------------------------------------------------
        function detpos = GetDetPos(obj)
            detpos = obj.sd.GetDetPos();
        end
        
        
        % ----------------------------------------------------------------------------------
        function aux = GetAuxiliary(obj)
            aux = struct('data',[], 'names',{{}});            
            for ii=1:size(obj.aux,2)
                aux.data(:,ii) = obj.aux(ii).GetData();
                aux.names{ii} = obj.aux(ii).GetName();
            end
        end
        
    end
    
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Pubic interface for .nirs processing stream
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    methods
        
        % ----------------------------------------------------------------------------------
        function d = Get_d(obj, idx)
            if ~exist('idx','var')
                idx = 1;
            end
            d = obj.data(idx).GetDataMatrix();
        end
        
        
        % ----------------------------------------------------------------------------------
        function t = Get_t(obj, idx)
            if ~exist('idx','var')
                idx = 1;
            end
            t = obj.data(idx).GetTime();
        end
        
        
        % ----------------------------------------------------------------------------------
        function SD = Get_SD(obj, idx)
            if ~exist('idx','var')
                idx = 1;
            end
            SD.Lambda   = obj.sd.GetWls();
            SD.SrcPos   = obj.sd.GetSrcPos();
            SD.DetPos   = obj.sd.GetDetPos();
            SD.MeasList = obj.data(idx).GetMeasList();
            SD.MeasListAct = ones(size(SD.MeasList,1),1);
        end
        
        
        % ----------------------------------------------------------------------------------
        function aux = Get_aux(obj)
            aux = [];
            for ii=1:size(obj.aux,2)
                aux(:,ii) = obj.aux(ii).GetData();
            end
        end
        
        
        % ----------------------------------------------------------------------------------
        function s = Get_s(obj, idx)
            if ~exist('idx','var')
                idx = 1;
            end            
            t = obj.data(idx).GetTime();
            s = zeros(length(t), length(obj.stim));
            for ii=1:length(obj.stim)
                [ts, v] = obj.stim(ii).GetStim();
                [~, k] = nearest_point(t, ts);
                if isempty(k)
                    continue;
                end
                s(k,ii) = v;
            end
        end
        
    end
        
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % All other public methods
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    methods
        
        % ----------------------------------------------------------------------------------
        function AddStims(obj, tPts, condition)
            % Try to find existing condition to which to add stims. 
            for ii=1:length(obj.stim)
                if strcmp(condition, obj.stim(ii).GetName())
                    obj.stim(ii).AddStims(tPts);
                    return;
                end
            end
            
            % Otherwise we have a new condition to which to add the stims. 
            obj.stim(end+1) = StimClass(tPts, condition);
            obj.SortStims();
        end
        
        
        % ----------------------------------------------------------------------------------
        function DeleteStims(obj, tPts, condition)
            % Find all stims for any conditions which match the time points. 
            for ii=1:length(obj.stim)
                obj.stim(ii).DeleteStims(tPts);
            end
        end
        
        
        % ----------------------------------------------------------------------------------
        function MoveStims(obj, tPts, condition)
            if ~exist('tPts','var') || isempty(tPts)
                return;
            end
            if ~exist('condition','var') || isempty(condition)
                return;
            end
            
            % Find the destination condition to move stims (among the time pts in tPts)
            % to
            j = [];
            for ii=1:length(obj.stim)
                if strcmp(condition, obj.stim(ii).GetName())
                    j=ii;
                    break;
                end
            end
            
            % If no destination condition found among existing conditions,
            % then create a new condition to move stims to 
            if isempty(j)
                j = length(obj.stim)+1;
                
                % Otherwise we have a new condition to which to add the stims.
                obj.stim(j) = StimClass([], condition);
                obj.SortStims();
                
                % Recalculate j after sort
                for ii=1:length(obj.stim)
                    if strcmp(condition, obj.stim(ii).GetName())
                        j=ii;
                        break;
                    end
                end
            end

            % Find all stims for any conditions which match the time points.
            for ii=1:length(tPts)
                for kk=1:length(obj.stim)
                    d = obj.stim(kk).GetData();
                    if isempty(d)
                        continue;
                    end
                    k = find(d(:,1)==tPts(ii));
                    if ~isempty(k)
                        if kk==j
                            continue;
                        end
                        
                        % If stim at time point tPts(ii) exists in stim
                        % condition kk, then move stim from obj.stim(kk) to
                        % obj.stim(j)
                        obj.stim(j).AddStims(tPts(ii), d(k(1),2), d(k(1),3));

                        % After moving stim from obj.stim(kk) to
                        % obj.stim(j), delete it from obj.stim(kk)                 
                        d(k(1),:)=[];
                        obj.stim(kk).SetData(d);
                        
                        % Move on to next time point
                        break;
                    end
                end
            end
        end
        
        
        % ----------------------------------------------------------------------------------
        function SetStimTpts(obj, icond, tpts)
            obj.stim(icond).SetTpts(tpts);
        end
        
        
        % ----------------------------------------------------------------------------------
        function tpts = GetStimTpts(obj, icond)
            if icond>length(obj.stim)
                tpts = [];
                return;
            end
            tpts = obj.stim(icond).GetTpts();
        end
        
        
        % ----------------------------------------------------------------------------------
        function SetStimDuration(obj, icond, duration)
            obj.stim(icond).SetDuration(duration);
        end
        
        
        % ----------------------------------------------------------------------------------
        function duration = GetStimDuration(obj, icond)
            if icond>length(obj.stim)
                duration = [];
                return;
            end
            duration = obj.stim(icond).GetDuration();
        end
        
        
        % ----------------------------------------------------------------------------------
        function SetStimValues(obj, icond, vals)
            obj.stim(icond).SetValues(vals);
        end
        
        
        % ----------------------------------------------------------------------------------
        function vals = GetStimValues(obj, icond)
            if icond>length(obj.stim)
                vals = [];
                return;
            end
            vals = obj.stim(icond).GetValues();
        end
        
        
        % ----------------------------------------------------------------------------------
        function RenameCondition(obj, oldname, newname)
            if ~exist('oldname','var') || ~ischar(oldname)
                return;
            end
            if ~exist('newname','var')  || ~ischar(newname)
                return;
            end
            k=[];
            for ii=1:length(obj.stim)
                if strcmp(obj.stim(ii).GetName(), oldname)
                    k = ii;
                    break;
                end
            end
            if isempty(k)
                return;
            end
            obj.stim(k).SetName(newname);
            obj.SortStims();
        end
     
        
        % ----------------------------------------------------------------------------------
        function b = IsEmpty(obj)
            b = true;
            if isempty(obj.data)
                return;
            end
            if isempty(obj.sd)
                return;
            end
            b = false;
        end
        
    end
    
end


