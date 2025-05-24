classdef dict
  % A value object working with early Matlab without dictionary
  properties, keys uint8; values string; end
  methods
    function obj = dict(keys, vals), obj.keys = keys; obj.values = vals; end
    function k = key(obj, val), k = obj.keys(val == obj.values); end
    function v = val(obj, key), v = obj.values(key == obj.keys); end
    function L = list(obj), L = join(obj.values, ', '); end
  end
end
