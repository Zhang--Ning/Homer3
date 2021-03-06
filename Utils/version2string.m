function [verstr, V] = version2string(V)

verstr = '';
if ~exist('V','var') || isempty(V)
    V = getVernum();
end
if ischar(V)
    verstr = V;
    return
end
if length(V)==1
    verstr = [V{:},'.0'];
    return;
end
    
for ii=length(V):-1:1
    if ~ischar(V{ii})
        return;
    end
    if ~isnumber(V{ii})
        return;
    end
    if ~strcmp(V{ii},'0') || ii<3
        break;
    end
end
verstr = '';
for kk=1:length(V(1:ii))
    if isempty(verstr)
        verstr = sprintf('%s', V{kk});
    else
        if isnumber(V{3})
            verstr = sprintf('%s.%s', verstr, V{kk});
        else
            verstr = sprintf('%s, %s', verstr, V{kk});
        end
    end
end
