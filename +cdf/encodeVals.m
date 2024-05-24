function [gzout] = encodeVals(cCdfType, gzin)
% encodeVal - Translate some matlab values prior to output in a CDF file
%
%   By an large this function is a no-op, but some types such as datetimes
%   have special flag values (aka NaT) and need manual handling.  Other 
%   that function call overhead, there's no harm in passing all values to
%   be emitted into a CDF file through this function.  It is maintained 
%   outside the CDF class for easy inspection of the output without
%   instantiating a CDF data object.
%
% Params:
%    cCdfType (char vec) - One of the CDF data type names as returned from
%       cdf.getType()
%
%    gzin (any) - The value to encode, may be a normal array, but NOT a
%       cell array.
%
% History:
%   C. Piker 2021-08-06: in draft

	if iscell(gzin) || isstruct(gzin)
		throw(MException('cdf:encodeVal:todo', ['Input must not be a '...
			'structure or cell array']));
	end
   
	% Special handling for datetimes
	if isa(gzin, 'datetime')
		if strcmp('CDF_EPOCH', cCdfType)
			rEpoch = cdflib.computeEpoch([1970, 1, 1, 0, 0, 0, 0]);
			
			gzout = zeros(size(gzin)); % Default everything to zero
			
			idx = ~isnat(gzin);         % set valid times only
			gzout(idx) = posixtime(gzin(idx))*1000 + rEpoch;
		else
			throw(MException('cdf:encodeVal:todo', ...
				'Non CDF_EPOCH encoding of datetimes is not yet implemented'...
			));
		end
		return;
	end
	
	% Special handling for logicals
	if isa(gzin, 'logical')
		switch cCdfType
			case 'CDF_CHAR'  % Map to T, and F characters
				gzout = char(zeros(size(gzin)));
				gzout(gzin) = 'T';
				gzout(~gzin) = 'F';
			case {...        % Map to 0 and 1
				'CDF_INT1','CDF_UINT1','CDF_INT2', 'CDF_UINT2','CDF_INT4',...
				'CDF_UINT4','CDF_REAL4','CDF_REAL8'...
			}
				gzout = zeros(size(gzin), cdf.Var.g_lTypesCdf2Ml(cCdfType));
				gzout(gzin) = 1;
			otherwise
				throw(MException('cdf:encodeVal:noMap', ['Can''t encode matlab '...
					'logical values to CDF type ' cCdfType]));
		end
		return;
	end
	
	% Pass through for all the rest (though should check encoding)
	gzout = gzin;
end

