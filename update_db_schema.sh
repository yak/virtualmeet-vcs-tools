#!/bin/sh

#################################################################
# DB SCHEMA REVISION UPDATE SCRIPT
# All changes to the virtualmeet database schema are committed
# as change files to the version control repository. This script
# checks if new revision have been checked out and applies them
# one-by-one to the virtualmeet database in the current environment
# (it assumes there is a trust relationship from localhost). The
# schema_revision table keeps track of what version the database
# currently has.
#
# The revisions are applied with an implicit transaction and should
# be cleanly rollbacked should anything fail provided the revision
# SQL does not use explicit transactions. 
#
# For more information, please consult the devmeet wiki.
#
# (c) Kristoffer Lindqvist, 2008
#
################################################################

PSQL="/usr/bin/psql"
DB_USER="virtualmeet"
DB="virtualmeet"
SQL_REVISION_PATH="./sql"

# ---------- YOU SHOULD NOT NEED TO EDIT BELOW THIS LINE --------------

ERR_PREF="\n**** ERROR **** "

# check that we have the db and db user set up properly
set `$PSQL -U $DB_USER -l | grep -v FATAL | grep $DB` 
if [ -z "$1" ]; then
	clear  # hide the mess psql spits out in this scenario
	echo "${ERR_PREF}Could not connect to db $DB with user $DB_USER using $PSQL. Is your database properly configured and running?";
	exit 9;
fi

# try to fetch the current schema version from the target db
set `$PSQL -t -U $DB_USER $DB -c 'SELECT revision FROM schema_revision ORDER BY revision DESC limit 1;'` 
current_revision=$1;

if [ -z "$current_revision" ]; then
	echo "${ERR_PREF}No revision number found in the $DB database. You probably need to import the latest baseline.";
	exit 9;
fi

current_revision=`echo $current_revision | grep [0-9]`
if [ -z "$current_revision" ]; then
	echo "${ERR_PREF}Non-numeric revision number found in the $DB database. Something is very wrong here.";
	exit 9;
fi

if [ ! -e $SQL_REVISION_PATH ]; then
	echo "${ERR_PREF}The SQL revision path $SQL_REVISION_PATH does not exist.";
	exit 9;
fi

if [ $(ls -1A $SQL_REVISION_PATH | wc -l) -eq 0 ]; then
	echo "${ERR_PREF}The SQL revision path $SQL_REVISION_PATH is empty. Have you correctly checked out the project?";
	exit 9;
fi

# --- EVERYTHING SEEMS OK, LET'S ROCK! ---

next_revision=$(($current_revision + 1))

while [ -e ${SQL_REVISION_PATH}/${next_revision}_rev.sql ]
do
	echo "...applying revision $next_revision"
	$PSQL --single-transaction -v ON_ERROR_STOP=1 -U $DB_USER $DB < ${SQL_REVISION_PATH}/${next_revision}_rev.sql
	if [ "$?" -ne "0" ]; then
		echo "${ERR_PREF}The revision failed, aborting. The revision is automatically wrapped in a transaction when ran, but explicit use of transaction blocks within the revision script will override this. Unless they are present and failed, the revision should have been properly rollbacked."
		exit 9;
	fi
	$PSQL -U $DB_USER $DB -c "INSERT INTO schema_revision (revision) VALUES ($next_revision)"
	next_revision=$(($next_revision + 1))
done

# see if we ran into a new baseline!
if [ -e ${SQL_REVISION_PATH}/${next_revision}_baseline.sql ]; then
	found_baseline=1;	
fi

# final words of wisdom
if [ $(($next_revision - 1)) -eq "$current_revision" ]; then
	if [ -z "$found_baseline" ]; then
		echo "No updates found."
	fi
	echo "At revision $current_revision"
else 
	at_revision=$(($next_revision - 1))
	echo "Upgraded from revision $current_revision to $at_revision"; 
fi

if [ "$found_baseline" ]; then
	echo "Revision $next_revision is a new baseline. It should be applied cleanly by dropping the database (do dump the data first if this is the production environment...).";
fi
	
exit
