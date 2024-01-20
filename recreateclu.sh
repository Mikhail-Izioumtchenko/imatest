#!/bin/sh
### recreate single cluster
### 1: mandatory comma delimited list of relative port ranges
ports="$1"

. `pwd`/imavars.dot

$IMAKILLMANY "$ports"
$IMADESTROYMANY "$ports"
$IMACREATEMANY "$ports"
$IMACREATECLU "$ports"
$IMASHOWALL
