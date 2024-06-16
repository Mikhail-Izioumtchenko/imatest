
`imatest` is a testing tool for MySQL.

2024-06-15

THE PREVIOUS STATEMENT IS NOT A CLAIM FOR TOOL's  suitability for any purpose whatsoever.

Yield: not everything filed as a bug because bug filing is fairly pointless activity in most cases for lack of care of the target audience at the manufacturer of the code. imho.

15. 2024-06-16: 8.4LTS. SEGV. 2024-06-16T18:44:01Z UTC - mysqld got signal 11 ; buf_flush_LRU_list_batch at /usr/src/debug/mysql-community-8.4.0-1.el9.x86_64/mysql-8.4.0/storage/innobase/buf/buf0flu.cc:1808

14. 2024-06-16: 8.4LTS. 2024-06-16T17:17:08.393423Z 23 [ERROR] [MY-013183] [InnoDB] Assertion failure: dyn0buf.h:111:ptr <= begin() + m_buf_end thread 139875615458880

13. https://bugs.mysql.com/bug.php?id=115349 2024-06-15: mysql-8.4.0/sql/dd/impl/cache/dictionary_client.cc:945: bool dd::cache::Dictionary_client::acquire(const K&, const T**, bool*, bool*) [with K = dd::Item_name_key; T = dd::Column_statistics]: Assertion `MDL_checker::is_read_locked(m_thd, *object)' failed.

12. 2024-06-15: Also happens in 8.4. mysql-8.3.0/sql/opt_explain.cc:2099: bool explain_query_specification(THD*, const THD*, Query_term*, enum_parsing_context): Assertion `ret || !explain_thd->is_error()' failed.

11. 2024-06-14: Also happens in 8.4. Correlated with using SELECT ... UNION/INTERSECT
https://bugs.mysql.com/bug.php?id=115346 mysql-8.3.0/sql/iterators/composite_iterators.cc:2970: int materialize_iterator::SpillState::read_next_row_secondary_overflow(): Assertion `false' failed.

10. 2024-06-14T01:58:40.260276Z 20 [ERROR] [MY-013183] [InnoDB] Assertion failure: row0sel.cc:2796:(!prebuilt->idx_cond && prebuilt->m_mysql_handler->end_range != nullptr) || (prebuilt->trx->isolation_level == TRX_ISO_READ_UNCOMMITTED) 

9. 2024-06-09T02:13:33.473147Z 1 [ERROR] [MY-012237] [InnoDB] Corrupted page [page id: space=10337, page number=0] of datafile './gts3/tt22.ibd' could not be found in the doublewrite buffer. 2024-06-09T02:13:33.473262Z 1 [ERROR] [MY-015090] [InnoDB] [FATAL] Tablespace '10143' mentioned in the redo log is corrupted in a way it is unrecoverable by double-write buffer, so further redo log recovery is not possible! 2024-06-09T02:13:33.473280Z 1 [ERROR] [MY-013183] [InnoDB] Assertion failure: log0recv.cc:1163:ib::fatal triggered thread 140240576562752

8. 2024-05-26T04:18:00.658915Z 17 [ERROR] [MY-013183] [InnoDB] Assertion failure: row0sel.cc:2796:(!prebuilt->idx_cond && prebuilt->m_mysql_handler->end_range != nullptr) || (prebuilt->trx->isolation_level == TRX_ISO_READ_UNCOMMITTED)

7. 2024-05-21 bool:parse_sql(THD*,:Parser_state*, 1 (1 distinct) Object_creation_ctx*): Assertion `!mysql_parse_status || mysql_parse_status && thd->is_error()) || (mysql_parse_status && thd->get_internal_handler())' failed.

6. 2024-05-13T04:41:02.318333Z 0 [ERROR] [MY-013183] [InnoDB] Assertion failure: trx0rec.ic:95:len < ((ulint)srv_page_size)

5. https://bugs.mysql.com/?id=114133 dd corrupt assert lob0impl.cc:1237:total_read == len || total_read == avail_lob
4. https://bugs.mysql.com/?id=113951 SEGV in INSERT
3. https://bugs.mysql.com/?id=113860 Assertion `rc == TYPE_OK' CREATE TABLE sql/dd/impl/raw/raw_record.cc:158
2. https://bugs.mysql.com/?id=113410 hang creating InnoDB Cluster
1. https://bugs.mysql.com/?id=113694  misleading error message comparing a spatial column with numeric using < or such

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

* for log mining there is posttest.sh which is a bit crude. 
* to try to reproduce a problem rerun the test with the same `--seed`. If --seed was not supplied it can be found in the test run output.
* see also testright.sh

FAQ:

Q1: why perl?

Rapid Application Development. Would be nice to rewrite in Go eventually.
However the notoriously poor performance of perl should not matter much as the tool is expected to spend most of CPU
generating non cryptographic quality random numbers. Non cryptographic RNG should be about the same in any language.
I may be mistaken.
Equally notorious perl syntax and looks is a matter of taste imho.  
Still it would be nice to have a testing client that supports MySQL X protocol.

Q2: why mysqlsh to execute SQL and not DBD::mysql?

Rapid Application Development it was, now it is all DBI within perl but mysqlsh in shell hooks. As a client mysql and mysqlsh are disappointing. 
