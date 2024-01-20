#!/bin/sh
### kill and destroy multiple instances, then recreate and restart them
### 1: mandatory comma delimited list of relative port ranges
ports="$1"

. `pwd`/imavars.dot

$IMAKILLMANY "$ports"
$IMADESTROYMANY "$ports"
$IMACREATEMANY "$ports"
$IMASTARTMANY "$ports"
$IMASHOWALL
