classdef CDF < handle
% Wrapper class around cdflib to make CDF file creation less awkward.  
%
% This class presents a CDF file an enhanced Map.  Each member of the map
% represents a single variable in a CDF file.  The data for each variable
% has more than one row if the Variable is Record Varying (a CDF term) and 
% only a single row if it's a non record-varying variable.
%
% Value type conversions
% ----------------------
%  datetime            ---> CDF_EPOCH
%  double, float       ---> CDF_REAL8, CDF_REAL4
%  string, char vector ---> CDF_CHAR
%  integers            ---> CDF_INT, of the same size and sign.
%  
% The storage type can be set when a Variable is created (see the subsasgn()
% function), or via the the cdf.Var.type() function.
%
% Array storage, Record Varying vs non record varying
% ---------------------------------------------------
% Data values are associated with a variable via indexed assignment.  The
% following example creates a variable named status and assigns byte values
% to it:
%
%   out = cdf.CDF()
%   out('Status').data = zeros(1, 5000, 'int8')
%
% The 'Status' variable would be saved as a record varying variable.  This 
% is because the size of the last dimension determines the record
% variability of an array.  The zeros function above creates a row-vector
% of size: 
%  
%   [1 5000]
%
% Since the last dimension is > 1 then the array will be stored as a record 
% varying variable when the .save() method is called.
% 
% For a slightly more complex example, consider the following set of column
% vectors:
%
%   B_vec_array = [1 0.7071 0; 
%                  0 0.7071 0; 
%                  0 1      0 ]
%
% The complete set has size [3 3].  Thus the call:
%
%    out('B_gei').data = B_vec_array;
%
% Creates a record varying variable that has 3 values per record.  The
% following column vector:
%
%   Frequency = [10; 
%                20; 
%                30]
%
% has size [3 1].  Thus it is *not* a record varying variable, but does
% have 3 values for it's one, lone constant record.  The following time
% array is record varying and has only one value per record:
%
%   T = [datetime('2019-10-28') datetime('2019-10-28') datetime('2019-10-28')]
%
%
%      Dealing with Rank >= 2 Non-record varying variables
%      ---------------------------------------------------
%   For various reasons matlab drops trailing dimensions of length 1,
%   *only* if the variable is rank 3 or greater.  Thus the language 
%   has a broken symmetry around rank 2 variables.  Since a trailing 
%   rank of 1 is needed to indicate non-record-varying varibles, use the
%   option Rank integer when assigning variables using mkVar() function
%   or manually set the .rank parameter.  For example
%
%   Coefficents = [ 0.9946   -0.0393    0.0015   -2.4940; 
%                   0.0416    1.0004    0.0450   -1.2780;
%                   0.0016   -0.0491    0.9512    9.5738 ]
%
%   out('Coeff').data = Coefficents
%   out('Coeff').rank = 3    
%
% Character Data
% --------------
% To store strings as atomic items, use cell-arrays.  Otherwise the count
% of characters along a string is one of the data variable dimensions.  
% For example:
%
%   cdf.mkVar('char_data', ['Comp A'; 'Comp B'; 'Comp C']);
%
% will generate a two dimensional CDF variable with three records and a
% size of 6 in the second dimension and an element size of  1.  The atomic
% unit of this data array will be a single character.
%
% On the other hand:
%  
%   cdf.mkVar('char_data', {'Comp A'; 'Comp B'; 'Comp C'});
%
% will generate a 1 dimensional CDF variable with three records and
% with an element size of 6.  The atomic uint of this variable is 
% the whole 6-character string.
%
% Properties
% ----------
% Global properties are accessed and set via the '.attrs' map.  For ex:
%
%   out = cdf.CDF();
%   out.attr('Title') = 'Hyper accurate Irridium Mag vectors (GEI)';
% 
% Variable properties are accessed by first indexing to get the variable,
% and then setting a value for that variable's attrs map:
%
%  out = cdf.CDF();
%  out('Epoch').attr('Caution') = 'Leap seconds have been ignored';
%
% History:
%   C. Piker 2019-10-28, original
%
% License: MIT

properties (SetAccess = private)
	nId   = int32(-1)          % File object ID, or -1 if no file associated
	dVars = containers.Map()   % Variables
	attr  = containers.Map()   % Global attributes.
	lVars = {}                 % Ordered list of var keys
end

properties (Dependent)
	keys  % List of all defined variable names
end

methods
	function self = CDF()
		% Create an empty CDF I/O object. 
		self.nId   = int32(-1);      
		self.dVars = containers.Map();
		self.attr  = containers.Map();
		self.lVars = {};
	end
	
	%%
	function self = mkVar(self, cVarName, varargin)
		% Convenience function to create a CDF variable, set it's data values
		% and it's attributes all in one call.
		%
		%   aVals = linspace(10,100,10).'
		%   out.mkVar('MyVar', aVals, 'CDF_UINT2','Attr1', 'AttrVal1', ...)
		%
		% This is equivalent to the assignment statments:
		%
		%   out('MyVar').data = linspace(10,100,10).';
		%   out('MyVar').setType('CDF_UNIT2');
		%   out('MyVar').attr('Attr1') = 'AttrVal1';
		%
		% Any number of CDF variable attributes may be specified using 
		%    Attribute_Name, Attribute_Value
		% pairs.
		%
		% Any string that starts with 'CDF_' as assumed to specify a CDF 
		% data storage type.  'CDF_...' strings may be included before, after
		% or between any pair of attributes but not between an attribute and
		% it's value.
		%
		% NOTE: Char data in cell arrays is handled differently from char
		%   data in standard arrays.  i.e. this:
		%
		%     cdf.mkVar('my_char_var', ['Comp A'; 'Comp B'; 'Comp C']);
		%
		%   and this:
		%
		%     cdf.mkVar('my_char_var', {'Comp A'; 'Comp B'; 'Comp C'});
		%
		%   have very different effects.
		
		if ~ischar(cVarName)
			throw(MException('cdf:CDF:badarg','Variable name must be a char array'));
		end
		
		if ~self.dVars.isKey(cVarName) 
			self.dVars(cVarName) = cdf.Var(self.nId);
			self.lVars(end+1) = {cVarName};
		end
		var = self.dVars(cVarName);
		if nargin > 2
			var.cCdfType = cdf.getType(varargin{1});
			var.data = varargin{1};
		end
		if nargin > 3
			var.setAttrs( varargin(2:end) );
		end
	end
	
	%% Wrapper around mkVar to insure a variable in set to non-record
	% varying.  This is hand for rank (or greater) constants.
	function self = mkConst(self, cVarName, varargin)
		if ~ischar(cVarName)
			throw(MException('cdf:CDF:badarg','Variable name must be a char array'));
		end
		
		if ~self.dVars.isKey(cVarName) 
			self.dVars(cVarName) = cdf.Var(self.nId);
			self.lVars(end+1) = {cVarName};
		end
		var = self.dVars(cVarName);
		if nargin > 2
			var.cCdfType = cdf.getType(varargin{1});
			var.data = varargin{1};
		end
		if nargin > 3
			var.setAttrs( varargin(2:end) );
		end
		
		aSz = size(var.data);
		
		% To make a constant, we need to insure that the size of the last
		% dimension is 1, or that we set the rank property
		if aSz(end) ~= 1
			var.rank = length(aSz) + 1;
		end
	end
	
	%%
	function lVars = get.keys(self)
		lVars = self.lVars;
	end
	
	%%
	function var = subsref(self, tIdx)
		% All variable access using standard one element indexing. 
		% TODO: Add variable sub object indexing for cleanlyness as well
		if isempty(tIdx)
			var = builtin('subsref', self, tIdx);
			return
		end
		
		switch tIdx(1).type
			case '()'
				var = self.dVars(tIdx(1).subs{1});
			otherwise
				var = builtin('subsref', self, tIdx);
		end
	end
		
	%% 
	function [nAttrNum, cType] = putAttrG(self, cAttrName, val)
		% Enocde single or multi-valued global attribute data
		%  Number of elements in the attribute is equal to the top array len
		
		cType = cdf.getType(val);
		nAttrNum = cdflib.createAttr(self.nId, cAttrName, 'global_scope');
		
		if iscell(val)
			for j = 1:numel(val)		
				tmp = cdf.encodeVals(cType, val{j});
				cdflib.putAttrgEntry(self.nId, nAttrNum, j-1, cType, tmp);
			end
		else
			% Have to treat charater arrays special.  Iterate over rows.  I
			% know there is a broken symmetry here, but that's commonly how
			% strings are though of.  If they need to save multiple strings,
			% use a cell array.
			if ischar(val)
				cdflib.putAttrgEntry(self.nId, nAttrNum, 0, cType, val);
			else
				for j = 1:numel(val) % works for single valued items
					tmp = cdf.encodeVals(cType, val(j));
					cdflib.putAttrgEntry(self.nId, nAttrNum, j-1, cType, tmp);
				end
			end
		end
	end
	
	%%
	function self = save(self, cAbsName)
		% Save in-memory data to a CDF file
		
		% For now just delete it if it's already present.  Probably want to
		% do something nicer in the future.
		if exist(cAbsName, 'file') ~= 0
			delete(cAbsName)
		end
		
		self.nId = cdflib.create(cAbsName);
		
		% Make hyper-put functions work properly for multi-dimensional data
		%cdflib.setMajority(self.nId, 'COLUMN_MAJOR'); 
		
		% Save the global attributes
		lKeys = self.attr.keys();
		for i = 1:numel(lKeys)
			cAttrName = lKeys{i};
			val = self.attr(cAttrName);
			self.putAttrG(cAttrName, val);
		end
		
		% Save the variable data, and get listed attributes
		dVarAttrs = containers.Map();
		nVars = numel(self.lVars);
		for i = 1:nVars
			cVarName = self.lVars{i};
			var = self.dVars(cVarName);
			% Reset the cdf file ID since we know it now
			var.nCdfId = self.nId;
			
			aSz = size(var.data);
			
			% Some constant with rank > 2 may be indicated by a rank value
			if var.rank > length(aSz)
				aSz = [aSz 1];
			else
				var.rank = length(aSz);
			end
			
			% The last index is always the record varying index.  If it is
			% 1, the data are not record varying
			
			nRecords = aSz(var.rank);  % Length last idx
			aDimVary = [];
			aDims = [];
			
			% we are only dimensionally varying if at least one index before
			% the last is > 1
			if any(aSz(1:end-1) > 1)
				aDims = aSz(1:end-1);
				aDimVary = (aDims > 1);
			end
			
			% Create the Variable...
			
			% If the data are in a cell array make sure they values are 
			% character data and get the length of the longest vector.
			nElements = 1;
			if iscell(var.data)
				if ~strcmp(var.cCdfType, 'CDF_CHAR')
					ex = MException('cdf:CDF:cellvalue', ...
						'Cell arrays must contain character data'...
					);
					throw(ex);
				end           
				nElements = max(cellfun(@numel, var.data));
			end
			
			var.nId = cdflib.createVar(...
				self.nId, cVarName, var.cCdfType, nElements, aDims, ...
				nRecords > 1, aDimVary...
			);
			
			% Use GZIP compression for all variables at the default runtime
			% vs compressed size tradoff of 6 
			cdflib.setVarCompression(self.nId, var.nId, 'GZIP_COMPRESSION', 6);
			
			% Write variable data...
			
			% Get the record spec
			% First record index = 0.
			% Num records = length in last index
			% Record increment = 1  (i.e. no skip)
			aRecSpec = [0, nRecords, 1];
			
			% Get the dimension spec.
			aDimSpec = [];
			if numel(aSz) > 1
				aDimStart = zeros(1, var.rank - 1);
				aDimCount =  aSz(1:end-1);
				aDimInterval = ones(1, var.rank - 1);
				aDimSpec = {aDimStart aDimCount aDimInterval};
			end
			
			% cdflib epoch conversions can't handle multiple values, so
			% convert any datetime args to epoch values here
			aData = var.data;
			if isa(var.data, 'datetime')
				rEpoch = cdflib.computeEpoch([1970, 1, 1, 0, 0, 0, 0]);
				% add number of milliseconds since 1970-01-01 to the CDF epoch
				% value for 1970-01-01
				aData = posixtime(var.data)*1000 + rEpoch;
			end
			
			% If it's as cell array, we're going to have to collapse it. 
			% Since string data runs along columns transpose it for proper
			% memory alignment in hyperPut.
			if iscell(var.data)
				% type check for CDF_CHAR was handled above
				aData = transpose(cell2mat( pad(var.data, nElements) ));
			end
			
			% Actually write all the data
			try
				cdflib.hyperPutVarData( ...
					self.nId, var.nId, aRecSpec, aDimSpec, aData ...
				);
			catch EM
				cDatType = class(var.data);
				if iscell(var.data) && numel(var.data) > 0
					cDatType = class(var.data{1});
				end
				cVarMsg = sprintf('For variable %s%s (%s)', ...
					cVarName, mat2str(aSz), cDatType, EM.message ...
				);
				eCause = MException('cdf:CDF:TypeMismatch', cVarMsg);
				throw(eCause);
			end
			
			% Associate our ID with any attributes we may have for writing 
			% in the next section.
			lAttrKeys = var.attr.keys();
			for j = 1:numel(lAttrKeys)
				cAttrKey = lAttrKeys{j};
				if ~isKey(dVarAttrs,	cAttrKey)
					dVarAttrs(cAttrKey) = {cVarName};
				else
					dVarAttrs(cAttrKey) = vertcat(dVarAttrs(cAttrKey), cVarName);
				end
			end
		end
		
		% Handle the variable attribute inversion without a N^2 loop.
		lKeys = dVarAttrs.keys();  % For all variable attributes...
		for i = 1:numel(lKeys)
			cAttrName = lKeys{i};
			nAttrNum = cdflib.createAttr(self.nId, cAttrName, 'variable_scope');
			
			% for all variables which have this attribute ...
			lVarNames = dVarAttrs(cAttrName);
			for j = 1:numel(lVarNames) 
				var = self.dVars(lVarNames{j});
				attrVal = var.attr(cAttrName);
				cType = cdf.getType(attrVal);
				tmpVal = cdf.encodeVals(cType, attrVal);
				cdflib.putAttrEntry(self.nId, nAttrNum, var.nId, cType, tmpVal);
			end
		end
		
		% We're done for now
		cdflib.close(self.nId);
		self.nId = int32(-1);
	end
	
	%%
	function delete(self)
		% Free and underlying cdflib resources that have been allocated,
		% incase an exception is hit.  If save works normally this is not
		% needed
		if self.nId ~= -1
			cdflib.close(self.nId);
			self.nId = int32(-1);
		end
	end
	
end

end

