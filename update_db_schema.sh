#!/bin/bash

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
# Inspired by:
# http://odetocode.com/Blogs/scott/archive/2008/01/31/11710.aspx
# http://odetocode.com/Blogs/scott/archive/2008/02/02/11721.aspx
# http://stackoverflow.com/questions/173/how-do-i-version-my-ms-sql-database-in-svn#516
#
# Tangentally, see also:
# http://martinfowler.com/articles/evodb.html
#
# For more information, please consult the devmeet wiki.
#
# (c) Kristoffer Lindqvist, 2008
#
################################################################


PSQL="/usr/bin/psql"
PWD="/bin/pwd"

# get path relative to absolute location, needed to run this from anywhere
SCRIPT_PATH_NAME=$(cd ${0%/*} 2>/dev/null && echo $PWD/${0##*/})
SCRIPT_PATH=`dirname "$SCRIPT_PATH_NAME"`
SQL_REVISION_PATH="${SCRIPT_PATH}/sql"

# ---------- YOU SHOULD NOT NEED TO EDIT BELOW THIS LINE --------------

ERR_PREF="\n**** ERROR **** "

# get db and db user from the command line
while [ "$1" != "" ]; do
	case $1 in
		-i | --import-latest-baseline)	BASELINE=1
						;;
		-d | --database)	shift
					DB=$1
					;;
		-u | --user)		shift
					DB_USER=$1
					;;
		-l | --list-only)
					LISTONLY=1
					;;
		-v | --verbose)
					VERBOSE=1
					;;
		-r | --revision)	shift
					TO_REVISION=$1
					;;
		-h | --help)
					echo "\n$0\n"
					echo "Required options"
					echo " -d, --database:	database to connect to on localhost"
					echo " -u, --user:		database user to connect with"
					echo "\nOptional options:";
					echo " -r, --revision:	don't upgrade beyond this revision"
					echo " -l, --list-only:	only list which revisions would be applied"
					echo " -v, --verbose:		list the actual SQL queries"
					echo "\n"
					exit
					;;
		*)
					echo -e "${ERR_PREF}Unknown flag $1. Try $0 --help"
					exit 9
					;;
	esac
	shift
done

psql_verbose=''
if [ "$VERBOSE" ]; then
	psql_verbose='--echo-queries'
fi

if [ -z "$DB" ] || [ -z "$DB_USER" ]; then
        echo -e "${ERR_PREF}Please pass both a database (--database) and database user (--user) to run this script"
	exit 9;
fi

if [ "$BASELINE" ]; then
	# use basename to take any path out of the sort, pipe any error messages about nothing being found to /dev/null
	LATEST_BASELINE=`ls -t ${SQL_REVISION_PATH}/*_baseline.sql 2>/dev/null | xargs -n1 basename 2>/dev/null | /usr/bin/sort -ng | tail -n1`

	if [ -z "$LATEST_BASELINE" ]; then
		echo -e "${ERR_PREF}No baseline found in ${SQL_REVISION_PATH}";
		exit 9;
	fi

	# check that we don't have the database already
	EXISTING_DB_NAME=`$PSQL -U postgres --list | cut -f2 -d ' ' | grep -i $DB | tr "[:upper:]" "[:lower:]" 2>/dev/null`
	LC_DB_NAME=`echo $DB | tr "[:upper:]" "[:lower:]" 2>/dev/null` 

	if [ "$EXISTING_DB_NAME" = "$LC_DB_NAME" ]; then
		echo -e "${ERR_PREF}The database $CREATE_DB_NAME already exists. You need to drop it manually first (DO save any data you need to migrate first!)";
		exit 9
	fi

	current_revision=`echo "$LATEST_BASELINE" | grep -o '^[0-9]*'`

	$PSQL -U postgres $psql_verbose < ${SQL_REVISION_PATH}/${LATEST_BASELINE}
	$PSQL -U $DB_USER $DB -c "INSERT INTO schema_revision (revision) VALUES ($current_revision)"
	echo -e "DONE! Imported baseline ${SQL_REVISION_PATH}/${LATEST_BASELINE}"
	exit 1
fi

if [ -z "$DB" ] || [ -z "$DB_USER" ]; then
	echo -e "${ERR_PREF}Please pass both a database (--database) and database user (--user) to run this script"
	exit 9;
fi

if [ "$TO_REVISION" ]; then
	TO_REVISION=`echo $TO_REVISION | grep -v [^0-9]`
	
	if [ -z "$TO_REVISION" ]; then
		echo "${ERR_PREF}Non-numeric revision number passed.";
		exit 9;
	fi
fi

# check that we have the db and db user set up properly
set `$PSQL -U $DB_USER -l | grep -v FATAL | grep $DB` 
if [ -z "$1" ]; then
	clear  # hide the mess psql spits out in this scenario
	echo -e "${ERR_PREF}Could not connect to db $DB with user $DB_USER using $PSQL. Is your database properly configured and running?";
	exit 9;
fi

# try to fetch the current schema version from the target db (note, -- is required to escape the -c ticks correctly)
set -- `$PSQL -t -U $DB_USER $DB -c 'SELECT revision FROM schema_revision ORDER BY revision DESC limit 1;'` 
current_revision=$1;

if [ -z "$current_revision" ]; then
	echo -e "${ERR_PREF}No revision number found in the $DB database. You probably need to import the latest baseline.";
	exit 9;
fi

current_revision=`echo $current_revision | grep -v [^0-9]`
if [ -z "$current_revision" ]; then
	echo -e "${ERR_PREF}Non-numeric revision number found in the $DB database. Something is very wrong here.";
	exit 9;
fi

if [ ! -e $SQL_REVISION_PATH ]; then
	echo -e "${ERR_PREF}The SQL revision path $SQL_REVISION_PATH does not exist.";
	exit 9;
fi

if [ $(ls -1A $SQL_REVISION_PATH | wc -l) -eq 0 ]; then
	echo -e "${ERR_PREF}The SQL revision path $SQL_REVISION_PATH is empty. Have you correctly checked out the project?";
	exit 9;
fi

if [ "$TO_REVISION" ] && [ "$TO_REVISION" -le "$current_revision" ]; then
	echo -e "\nNothing to do. Asked to go no further than revision $TO_REVISION, currently at revision $current_revision.\n"
	exit
fi

# --- EVERYTHING SEEMS OK, LET'S ROCK! ---
psql_verbose=''
if [ "$VERBOSE" ]; then
	psql_verbose='--echo-queries'
fi

next_revision=$(($current_revision + 1))

while [ -e ${SQL_REVISION_PATH}/${next_revision}_rev.sql ]
do
	if [ "$TO_REVISION" ] && [ "$next_revision" -gt "$TO_REVISION" ]; then
		break
	fi	

	if [ "$LISTONLY" ]; then
		echo -e "\n...would apply revision $next_revision"
		if [ "$VERBOSE" ]; then
			cat ${SQL_REVISION_PATH}/${next_revision}_rev.sql
		fi;
	else
		echo "...applying revision $next_revision"
		$PSQL --single-transaction $psql_verbose -v ON_ERROR_STOP=1 -U $DB_USER $DB < ${SQL_REVISION_PATH}/${next_revision}_rev.sql
		if [ "$?" -ne "0" ]; then
			echo -e "${ERR_PREF}The revision failed, aborting. The revision is automatically wrapped in a transaction when ran, but explicit use of transaction blocks within the revision script will override this. Unless they are present and failed, the revision should have been properly rollbacked."
			exit 9;
		fi
		$PSQL -U $DB_USER $DB -c "INSERT INTO schema_revision (revision) VALUES ($next_revision)"
	fi;
	next_revision=$(($next_revision + 1))
done

# see if we ran into a new baseline!
if [ -e ${SQL_REVISION_PATH}/${next_revision}_baseline.sql ]; then
	found_baseline=1;	
fi

# final words of wisdom
if [ $(($next_revision - 1)) -eq "$current_revision" ]; then
	if [ -z "$found_baseline" ]; then
		echo -e "\nNo updates found."
	fi
	echo "At revision $current_revision"
else 
	at_revision=$(($next_revision - 1))
	if [ "$LISTONLY" ]; then
		echo -e "\nWould have upgraded from revision $current_revision to $at_revision\n";
	else
		echo -e "\nUpgraded from revision $current_revision to $at_revision\n";
	fi 
fi

if [ "$found_baseline" ]; then
	echo -e "\nRevision $next_revision is a new baseline. It should be applied cleanly by dropping the database (do dump the data first if this is the production environment...).";
fi
	
exit
