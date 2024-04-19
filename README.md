
`imatest` is a testing tool for MySQL.

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
* the server is instantiated in a mysqlsh Sandbox

TODO: use debugging build, build mysqld from source, use a server which is not a sandbox.

So the tool is expected to work with little or no changes on any RedHat like Linux, standalone or WSL.

How it tests, short version: start server, run a workload, check for failures. Bug filing is manual.
What it tests: mysqld and InnoDB primarily. It aims to get assertion and errors that result in SIGSEGV SIGBUS etc,
catch database corruptions, hangs in server and client, failure of mysqld to (re)start.
Much of all this is in the todo list, the tool is WIP.
What it does not (especially) test:
* security
* workings inside clients.
* SQL wrong results
* unwarranted errors or warnings
* I14N
* performance
* engines that are not InnoDB
* mysqld that is not on Linux. Though of course it can test whatever as long as it can connect to whatever. But then log mining is left to the user.

How it tests:

* implementation is perl and bash
* start test script imatest.pl through its cover script imatest.sh
* read, parse and check test description file, by default imatest.yaml. Its 'syntax' is described by default in a separate file, imatest_syntax.yaml.
* start or create the sandbox and create internal database description. Can create a random set of schemas and tables as well.
* now we have a database. There is no initial data loading atm.
* start (fork()) a thread that every random number of seconds stops or kills mysqld in a random fashion, then restarts it.
* start (fork()) workload thread(s) that execute random SQL against the server. The tool strives to use mysqlsh over x protocol.
* waits the specified test duration time
* kills test threads (processes)
* optionally shuts and equally optionally destroy the sandbox
* exits

User's guide:
* have an installation of MySQL on a server
* instantiate all files in this repo in a single directory, atm on the same server.
* eventually there will be a self test. For now there is none.
* become root.
* cd to that directory
* the environment should be suitable to use MySQL installation, MYSQL_HOME etc.
* create or edit the supplied imatest.yaml file. The description of each parameter, such as it is, is inside.
* run something like (there is a `--help` available). You may want to try --dry-run to sort out errors in your `imatest.yaml`.
   Option `--test` is mandatory.

` ./imatest.sh  now --test imatest.yaml --seed N --verbose 0 --nodry-run` 2>&1 | tee somelogfile

* for log mining there is `logmine.sh` which is very crude atm. In any case the logs are somelogfile, the file mentioned in the 'See also' line of the script output, mysqld error.log, Linux logfiles if it comes to that.
* to try to reproduce a problem rerun the test with the same `--seed`. If --seed was not supplied it can be found in the test run output.

FAQ:

Q: how much is 2 by 2:

4.

Q1: why perl?

Rapid Application Development. Would be nice to rewrite in Go eventually.
However the notoriously poor performance of perl should not matter much as the tool is expected to spend most of CPU
generating non cryptographic quality random numbers. Non cryptographic RNG should be about the same in any language.
I may be mistaken.
Equally notorious perl syntax and looks is a matter of taste imho. perl is readable for an average person. 

Q2: why mysqlsh to execute SQL and not DBD::mysql?

Rapid Application Development, but this is not the only reason.
