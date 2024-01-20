#!/bin/sh
### kill and destroy multiple instances
### 1: mandatory comma delimited list of relative port ranges
ports="$1"

. `pwd`/imavars.dot

$IMAKILLMANY "$ports"
$IMADESTROYMANY "$ports"
