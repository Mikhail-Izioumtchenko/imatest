to be continued

'imatest' is a testing tool. 

THE PREVIOUS STATEMENT IS NOT A CLAIM FOR TOOL's  suitability for any purpose whatsoever.

It tests MySQL server 8.0+
This is very much work in progress.
As of 2024-01-21 it is a working model.
Currently it tests with a single server.
The aim is to test InnoDB Cluster, then InnoDB ClusterSet, then InnoDB ReplicaSet, then maybe more.
ATM the server is run on the same server as the test. Support for remote server is a todo.
The testing tool itself is tested like this:
* WSL
* OEL 9
* MySQL 8.0.34 community server production build.
* the server is instantiated in a mysqlsh SandBox

TODO: use debugging build, build mysqld from source, use a server which is not a sandbox.

So the tool is expected to work with little or no changes on any RedHat like Linux, standalone or WSL.

How it tests, short version: start server, run a workload, check for failures. Bug filing is manual.
What it tests: mysqld primarily. It aims to get assertion and errors that result in SIGSEGV SIGBUS etc,
catch database corruptions, hangs in server and client, failure of mysqld to (re)start.
Much of all this is in the todo list, the tool is WIP.
What it does not (especially) test:
* security
* workings inside client
* SQL wrong results
* unwarranted errors or warnings
* I14N
* performance

How it tests:
TBC
