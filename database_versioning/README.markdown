README 
DATABASE SCHEMA REVISION UPDATE SCRIPT
======================================

WHAT DOES IT DO?
----------------

This is a shell script for applying [PostgreSQL](http://www.postgresql.org/) SQL
changesets comitted to any version control system (VCS) to a local database.

Each database has a table which keeps track of what the revision it is at. This
script handles upgrading the database to the latest (or a specific revision) by
running the applicable newer changesets one-by-one. It also supports dry runs,
database drops, baselining (see below) etc.

Each changeset is applied inside its own transaction, i.e. if the update fails
it should be cleanly rollbacked.



WHY?
----

Because we want to...

1. 	leave a trail of what changes have been applied to the database schema
	...just like we do for any piece of code under version control. If the 
	shit hits the fan, we want to know what happened so we can fix it ASAP.

2. 	be able to just commit a changeset from our development machine and know
	that it will be cleanly and automatically applied when that commit is 
	pulled to another machine (eg. keep development, staging and production 
	databases transparently in sync).

3. 	be able to create a fresh instance of the latest revision of the database 
	by running a single command... a boon for automatic integration testing.

####Inspired by

* <http://odetocode.com/Blogs/scott/archive/2008/01/31/11710.aspx>
* <http://odetocode.com/Blogs/scott/archive/2008/02/02/11721.aspx>
* <http://stackoverflow.com/questions/173/how-do-i-version-my-ms-sql-database-in-svn#516>

Tangentally, also see <http://martinfowler.com/articles/evodb.html>



HOW DO I SET UP AND USE IT?
---------------------------

Requirements:

* 	**Linux and a BASH shell** (has not been tested nor designed for any other
	environment, feedback/patches warmly welcome)

* 	a recently fresh copy of **PostgreSQL** (any 8.x line at least probably ok)

* 	**a Version Control System of your choice** (Git/Subversion/CVS...). Strictly
	speaking optional, but this script makes little sense for use without one.


First set up
-------------

**Dump the database schema into a file called 1_baseline.sql.** This file
should live in a suitable version controlled directory (duh).

    pg_dump -s -U DB_USER_HERE DB_NAME_HERE > VERSIONED_CONTROLLED_DIRECTORY_FOR_CHANGESETS_HERE/1_baseline.sql


**Create a config file (see config.example).** This defines the database user
who owns the database tables and which the script will use for any database
operations like applying changesets. This user must already exist in the
database. Required database extensions can also be specified (Postgres 9.1+).
The presence of these extensions is checked on every run and installation into
the database is attempted if the extension is missing (if this fails, the
script will terminate).

    DB_USER=your-db-user-here
    DB_EXTENSIONS=(required_extension1 required_extensions2)

**Create a fresh database based on your baseline.** The -i flag tells the
script to import the latest baseline.

    sh update_db_schema.bash -d DB_NAME_HERE -p VERSIONED_CONTROLLED_DIRECTORY_FOR_CHANGESETS_HERE/1_baseline.sql -i


...DONE! If you log into DB_NAME_HERE and *SELECT * FROM schema_revision;* you
should now see that the database is at revision 1. Repeat this step for any
other database instances.


Daily use
---------

When you next change the schema (or add data which should always be in a fresh
database instance) add the changes to a changeset file called 2_rev.sql in the
same directory as your baseline file and commit it. To update another database
instance to the latest revision, pull/checkout the changeset from the version
control repository and run:

    ./update_db_schema.bash -p VERSIONED_CONTROLLED_DIRECTORY_FOR_CHANGESETS_HERE -d DB_NAME_HERE

This will upgrade your database to version 2.

You probably also want to make this command run automatically after every
update from version control. That way you can commit database changes and have
them automatically propagated in all environments. Sweet :)

####Things to keep in mind || problem####

**Obviously, take extra care to commit all schema changes.** Ideally, test the
changeset against a database you have not tampered with manually. If the
changeset is broken causing the databases to fail their upgrades you obviously
need to commit a fix to the same changeset. But generally, you should avoid
changing any committed changeset like the plague; if the changeset has already
been applied to any database it will not be ran again forcing you to add the
changes by hand. Whenever possible, commit a second changeset to fix any
issues. 

**Existing data in the databases to be upgraded can cause an update to fail if
you're not paying attention.** A trivial example would be to add a UNIQUE
constraint that fails because there is non-unique data in the database to be
updated. Such cases can usually be handled properly as long as you think ahead.

**Do not use transactions in your changesets.** A transaction is automatically
wrapped around each changeset.

**Required extensions are only checked for presence; upgrading or downgrading
them needs to be done manually. Removing an extension from the config will not
cause it to be uninstalled from the database.

Creating a new baseline
------------------------

After some time of development, you may end up with a large number of
changesets. Setting up a fresh instance for integration testing is starting to
take longer and longer... you feel the pain. Or you finally get around to
releasing a new version. At that stage you may want to start from the beginning
with a new baseline.

To do that, just repeat the steps from the first setup described above
(obviously, you do not need to do step 1 as you already have the
schema_revision table in the database). ALSO, DUMP THE SCHEMA INTO A NEW
BASELINE. If your last changeset was 98_rev.sql, then your next baseline should
be called 99_baseline.sql.

In an ideal world, you would then start anew by dropping the database and
importing the new baseline. If you have production data in the database, you
should either not baseline OR take the needed steps to dump the data back in
properly.


FOUND A BUG? FEATURE REQUEST? WANT TO DISCUSS THIS FURTHER?
-----------------------------------------------------------

The prefered place to report a bug or to request a feature is the [Github issue
tracker](http://github.com/yak/virtualmeet-vcs-tools/issues).

Please take a moment to see whether the issue has already been reported, if so
add to that issue if needed.

If you want to fix it yourself or improve the script, please send me a pull
request or patch. <3

You can always reach me at <kris@tsampa.org> too, I'd love to hear from you. :)

