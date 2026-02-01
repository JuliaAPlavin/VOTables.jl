#!/bin/sh

# Creates some test tables using STILTS.
# See http://www.starlink.ac.uk/stilts/

# Only run manually because it requires Java and STILTS to be installed

nrow=10
coltypes=sfvm

test -r stilts.jar || curl -OL http://www.starlink.ac.uk/stilts/stilts.jar
for fmt in tabledata binary2 binary
do
   file=test-${fmt}.vot
   echo "Writing $file"
   Fmt=`echo $fmt | tr a-z A-Z`
   java -jar stilts.jar tpipe in=:test:${nrow},${coltypes} \
                              cmd='delcols "f_string v_string"' \
                              ofmt="votable(format=$Fmt)" out=$file
done

# Complex type test files.
# STILTS :test: generator doesn't support complex types, so we convert
# from a hand-written TABLEDATA source file. Note: STILTS outputs complex
# columns as arraysize="2" float/double in binary — the field metadata
# must be manually fixed to floatComplex/doubleComplex (binary data is identical).
for fmt in binary binary2
do
   file=complex-${fmt}.vot
   echo "Writing $file"
   Fmt=`echo $fmt | tr a-z A-Z`
   java -jar stilts.jar tpipe in=complex-tabledata.vot \
                              ofmt="votable(format=$Fmt)" out=$file
   # Fix: STILTS writes complex as arraysize="2" float/double, restore floatComplex/doubleComplex
   sed -i '' 's/arraysize="2" datatype="float" name="s_floatComplex"/datatype="floatComplex" name="s_floatComplex"/' $file
   sed -i '' 's/arraysize="2" datatype="double" name="s_doubleComplex"/datatype="doubleComplex" name="s_doubleComplex"/' $file
done
