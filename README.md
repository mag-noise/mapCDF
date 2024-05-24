# mapCDF
An enhanced map interface for writing NASA CDF files

*Wrapper class around cdflib to make CDF file creation less awkward.*

This class presents a CDF files as an enhanced Map.  Each member of the map
represents a single variable in a CDF file.  The data for each variable
has more than one row if the Variable is Record Varying (a CDF term) and 
only a single row if it's a non record-varying variable.


## Installation

Copy the `+cdf` folder somewhere to your MATLAB path.  That's it.

 
## Usage

A brief overview of how to use the +CDF module from mapCDF follows.

### Value type conversions
  
| MATLAB Type |  CDF Type |
+-------------+-----------+
|datetime     | CDF_EPOCH |
|double       | CDF_REAL8 |
|float        | CDF_REAL4 |
|string       | CDF_CHAR  |
|char array   | CDF_CHAR  |
|integers     | CDF_INT of the same size and sign |

The storage type can be set when a Variable is created (see the subsasgn()
function), or via the the `cdf.Var.type` function.

### Array storage, Record Varying vs non record varying

Data values are associated with a variable via indexed assignment.  The
following example creates a variable named status and assigns byte values
to it:
```matlab
   out = cdf.CDF()
   out('Status').data = zeros(1, 5000, 'int8')
```
 The 'Status' variable would be saved as a record varying variable.  This 
 is because the size of the last dimension determines the record
 variability of an array.  The zeros function above creates a row-vector
 of size: 
 ```matlab
   [1 5000]
```
Since the last dimension is > 1 then the array will be stored as a record 
varying variable when the .save() method is called.
 
For a slightly more complex example, consider the following set of column
vectors:
```matlab
   B_vec_array = [1 0.7071 0; 
                  0 0.7071 0; 
                  0 1      0 ]
```
The complete set has size [3 3].  Thus the call:
```matlab
   out('B_gei').data = B_vec_array;
```
Creates a record varying variable that has 3 values per record.  The
following column vector:
```matlab
   Frequency = [10; 
                20; 
                30]
```
has size [3 1].  Thus it is *not* a record varying variable, but does
have 3 values for it's one, lone constant record.  The following time
array is record varying and has only one value per record:
```matlab
   T = [datetime('2019-10-28') datetime('2019-10-28') datetime('2019-10-28')]
```

#### Dealing with Rank >= 2 Non-record varying variables

For various reasons matlab drops trailing dimensions of length 1,
*only* if the variable is rank 3 or greater.  Thus the language 
has a broken symmetry around rank 2 variables.  Since a trailing 
rank of 1 is needed to indicate non-record-varying varibles, use the
option Rank integer when assigning variables using mkVar() function
or manually set the .rank parameter.  For example
```matlab
   Coefficents = [ 0.9946   -0.0393    0.0015   -2.4940; 
                   0.0416    1.0004    0.0450   -1.2780;
                   0.0016   -0.0491    0.9512    9.5738 ]

   out('Coeff').data = Coefficents
   out('Coeff').rank = 3    
```

### Character Data

To store strings as atomic items, use cell-arrays.  Otherwise the count
of characters along a string is one of the data variable dimensions.  
For example:
```matlab
   cdf.mkVar('char_data', ['Comp A'; 'Comp B'; 'Comp C']);
```
will generate a two dimensional CDF variable with three records and a
size of 6 in the second dimension and an element size of  1.  The atomic
unit of this data array will be a single character.

On the other hand:
```matlab 
   cdf.mkVar('char_data', {'Comp A'; 'Comp B'; 'Comp C'});
```
will generate a 1 dimensional CDF variable with three records and
with an element size of 6.  The atomic uint of this variable is 
the whole 6-character string.

### Properties

Global properties are accessed and set via the '.attrs' map.  For ex:
```matlab
   out = cdf.CDF();
   out.attr('Title') = 'Hyper accurate Irridium Mag vectors (GEI)';
 ```
 Variable properties are accessed by first indexing to get the variable,
 and then setting a value for that variable's attrs map:
```matlab
  out = cdf.CDF();
  out('Epoch').attr('Caution') = 'Leap seconds have been ignored';
```
