classdef TracePool < matlab.mixin.Copyable
% class definition for raw data maps container
    
    properties
        cen;
        t;
        speed;
        duration;
        updated;
        death_cen;
    end
    
    properties (Hidden = true)
        max_num;
        max_duration;
        bounded;
    end
    
    methods
        function obj = TracePool(n, max_num, max_duration, varargin)
            
            setMax(obj,max_num(1));
            obj.max_duration  = max_duration;
            obj.max_num = max_num(1);
            obj.bounded = true;
            
            for i = 1:numel(varargin)
                arg = varargin{i};
                switch arg
                    case 'Bounded'
                        i = i+1;
                        obj.bounded = varargin{i};
                end
            end
            
            if ~obj.bounded
                obj.max_num = -1;              
            end
            
            out = [];
            for i = 1:n
                tmp = copy(obj);
                if numel(max_num)>1
                    setMax(tmp,max_num(i));
                end
                out = [out;tmp];
            end

            obj = out;
        end
        
        function updateDuration(obj)
            
            mm = obj.max_duration;
            d = obj.duration;
            u = obj.updated;
            d(u) = d(u) + 1;
            d(~obj.updated) = d(~u) - 1;
            d(d > mm) = mm;
            d(d == 0) = NaN;
            is_active = d > 0;
            was_active = ~isnan(obj.cen(:,1));
            

            
            if obj.bounded
                
                % record centroid of trace death
                is_dying = was_active & ~is_active;
                if any(is_dying)
                    obj.death_cen(is_dying,:) = obj.cen(is_dying,:);
                end
            
                obj.cen(~is_active,:) = NaN;
                obj.t(~is_active,:) = NaN;
                u(~is_active) = false;
            else
                obj.cen(~is_active,:) = [];
                obj.t(~is_active) = [];
                u(~is_active) = [];
                d(~is_active) = [];
            end
            
            obj.duration = d;
            obj.updated = u;
        end
        
        function reviveTrace(obj, new_cen, new_t)
            
            if ~obj.bounded
                return
            end
            if iscell(new_cen)
                new_cen = new_cen{1};
            end
            if ~isempty(new_cen)
                
                % attempt to assign to dead trace with closest last known
                % location
                idx = find(isnan(obj.cen(:,1)));
                tmp.cen = obj.death_cen(idx,:);
                tmp.t = obj.t(idx);
                tmp.speed = NaN(numel(idx));
                [ba, bp, tmp] = ...
                    sortROI_multitrack(tmp, new_cen, new_t, 1000);
                obj.cen(idx(tmp.updated),:) = new_cen(bp,:);
                obj.duration(idx(tmp.updated)) = obj.max_duration;
                obj.t(idx(tmp.updated)) = new_t;

                % exit if all assigned
                if sum(tmp.updated) == numel(ba)
                    return
                end
                
                % if any are left over, assign to remaining slots
                dead_traces = find(isnan(obj.cen(:,1)), size(new_cen,1), 'first');
                obj.cen(dead_traces,:) = new_cen(1:numel(dead_traces),:);
                obj.duration(dead_traces) = obj.max_duration;
                obj.t(dead_traces) = new_t;
                
            end
        end
        
        function setMax(obj, max_num)
            
            obj.cen = single(NaN(max_num,2));
            obj.t = single(NaN(max_num,1));
            obj.speed = single(NaN(max_num,1));
            obj.duration = single(NaN(max_num,1));
            obj.updated = false(max_num,1);
            obj.max_num = max_num;
            obj.death_cen = single(NaN(max_num,2));
        end
        
    end   

        
end
    
    
    
