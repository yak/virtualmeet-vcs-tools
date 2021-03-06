#!/usr/bin/env bash

#
# Virtualmeet VCS tools: DATABASE SCHEMA REVISION UPDATE SCRIPT
#
# See README for usage instructions and ../LICENSE for the Virtualmeet VCS
# tools license.
#
# Copyright (c) 2008-2013 Kristoffer Lindqvist <kris@tsampa.org>

PSQL="/usr/bin/env psql"
ERR_PREF="\n**** ERROR **** "
CHANGESET_PIPE='cat'

# get db and db user from the command line
while [ "$1" != "" ]; do
	case $1 in
		-i | --import-latest-baseline)
					BASELINE=1
					;;
		-d | --database)	shift
					DB=$1
					;;
		-U | --user)	shift
					DB_USER=$1
					;;
		-a | --admin-user)	shift
					ADMIN_USER=$1
					;;
		-p | --port)	shift
					DB_PORT=$1
					;;
		-h | --host)	shift
					DB_HOST=$1
					;;
		-e | --extensions)	shift
					DB_EXTENSIONS=$1
					;;
		-t | --unlogged-tables)
					UNLOGGED_TABLES=1

					# Note: sed does not support non-capturing groups, here we will remove any cosmetic whitespace when doing the
					# replace
					CHANGESET_PIPE="sed -e 's/^\s\{0,\}CREATE TABLE/CREATE UNLOGGED TABLE/gI'"
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
		-c | --changeset-path)	shift
					SQL_REVISION_PATH=$1
					;;
		--drop)
					DROP=1
					;;
		--help)
					echo -e "\n$0\n"
					echo "Required options"
					echo " -d, --database:	database to connect"
					echo " -U, --user: user to connect as"
					echo " -c, --changeset-path: path to where the changeset files are"
					echo -e "\nDefault behavior is to update to latest revision, other options"
					echo " -i, --import-latest-baseline: import the latest baseline"
					echo " --drop: drop the database (careful!)"
					echo -e "\nOptional options:"
					echo " -h, --host: host to connect to (default is localhost)"
					echo " -p, --port: port to connect to (default to 5432)"
					echo " -a, --admin-user: user to connect as when performing administrative commands such as dropping databases and installing extensions (default is postgres)"
					echo " -t, --unlogged-tables: modify all CREATE TABLE statements to CREATE UNLOGGED TABLE. Useful for speeding up db intensive tests"
					echo " -e, --extensions: comma separated string of database extensions which should be initialized for the database if not already present"
					echo " -r, --revision: don't upgrade beyond this revision"
					echo " -l, --list-only: only list which revisions would be applied (does not apply to importing baselines)"
					echo " -v, --verbose: list the actual SQL queries"
					echo -e "\n"
					exit 0
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

if [ -z "$DB" ]; then
	echo -e "${ERR_PREF}Please pass a database (--database, -d) to run this script"
	exit 9
fi

if [ -z "$DB_USER" ]; then
	echo -e "${ERR_PREF}Please pass a user to connect to the database with (--user, -d)"
	exit 9
fi

if [ -z "$ADMIN_USER" ]; then
	ADMIN_USER="postgres"
fi

if [ -z "$DB_HOST" ]; then
	DB_HOST='127.0.0.1'
fi

if [ -z "$DB_PORT" ]; then
  DB_PORT=5432
fi

conn_str="$PSQL -U $DB_USER -h $DB_HOST -p $DB_PORT"
conn_str_admin="$PSQL -U $ADMIN_USER -h $DB_HOST -p $DB_PORT"

if [ -z "$SQL_REVISION_PATH" ]; then
	echo -e "${ERR_PREF}Please pass the full path to the directory holding the changesets (--changeset-path, -p)"
	exit 9
fi

if [ "$DB_EXTENSIONS" ]; then
	DB_EXTENSIONS=$(echo $DB_EXTENSIONS | tr "," "\n")
else
	DB_EXTENSIONS=()
fi

if [ "$BASELINE" ] && [ "$DROP" ]; then
	echo -e "${ERR_PREF}Conflicting parameters --import-latest-baseline and --drop"
	exit 9
fi

can_connect_to_server=`$conn_str_admin --tuples-only $psql_verbose -c "SELECT 1;"`
if [ ! "$can_connect_to_server" ]; then
	echo -e "${ERR_PREF}Failed to connect to the database server with admin user $ADMIN_USER."
	exit 9
fi

if [ "$DROP" ]; then
  $conn_str_admin $psql_verbose -c "DROP DATABASE $DB;"
  echo -e "DONE! Dropped database $DB"
  exit 0
fi

if [ "$BASELINE" ]; then
	# use basename to take any path out of the sort, pipe any error messages about nothing being found to /dev/null
	LATEST_BASELINE=`ls -t ${SQL_REVISION_PATH}/*_baseline.sql 2>/dev/null | xargs -n1 basename 2>/dev/null | /usr/bin/sort -n | tail -n1`

	if [ -z "$LATEST_BASELINE" ]; then
		echo -e "${ERR_PREF}No baseline found in ${SQL_REVISION_PATH}"
		exit 9
	fi

	# check that we don't have the database already
	EXISTING_DB_NAME=`$conn_str_admin --list | cut -f2 -d ' ' | grep -i $DB | tr "[:upper:]" "[:lower:]" 2>/dev/null`
	LC_DB_NAME=`echo $DB | tr "[:upper:]" "[:lower:]" 2>/dev/null`

	if [ "$EXISTING_DB_NAME" = "$LC_DB_NAME" ]; then
		echo -e "${ERR_PREF}The database $EXISTING_DB_NAME already exists. You need to drop it manually first (DO save any data you need to migrate first!)"
		exit 9
	fi

	current_revision=`echo "$LATEST_BASELINE" | grep -o '^[0-9]*'`

	# create the database and assign it to the user
	$conn_str_admin $psql_verbose -c "CREATE DATABASE $DB WITH TEMPLATE = template0 ENCODING = 'UTF8';"
	$conn_str_admin $psql_verbose -c "ALTER DATABASE $DB OWNER TO $DB_USER;"
fi

# check that we have the db and db user set up properly
set `$conn_str -l | grep -v FATAL | grep $DB`
if [ -z "$1" ]; then
	echo -e "${ERR_PREF}Could not connect to db $DB running on $DB_HOST with user $DB_USER using $PSQL. Is your database properly configured and running?"
	exit 9
fi

if [ "$DB_EXTENSIONS" ]; then
	HAS_EXTENSION_ERRORS=0
	EXT_INSTALLED_REGEX='^[0-9\.]+$'
	for ext in $DB_EXTENSIONS; do
		ext_cmd="$conn_str $DB -c \"SELECT installed_version FROM pg_available_extensions WHERE name = '$ext';\"|head -n 3|tail -n 1|sed 's/^[[:space:]]*\(.*\)[[:space:]]*$/\1/'"
		ext_avail=`eval $ext_cmd`
		if [[ $ext_avail =~ '0 rows' ]]; then
			echo -e "\n${ERR_PREF}Database extension $ext has been specified as required, but it is not available for installation."
			HAS_EXTENSION_ERRORS=1
			continue
		fi

		if [[ ! $ext_avail =~ $EXT_INSTALLED_REGEX ]]; then
			echo -e "\nRequired extension $ext is available but not installed. "
			if [ "$LISTONLY" ]; then
				echo -e "\ ...would have installed it."
				continue
			fi
			$conn_str_admin $DB -c "CREATE EXTENSION $ext;"
			ext_avail=`eval $ext_cmd`
		fi
		# TODO we could do a version check here and say whether the installed version is the same as the available version,
		#      should we even have a flag to offer auto-updating?

		if [[ $ext_avail =~ $EXT_INSTALLED_REGEX ]]; then
			echo -e "\nRequired extension $ext is installed at version $ext_avail."
		else
			echo -e "\n${ERR_PREF}Failed to install required extension $ext."
			HAS_EXTENSION_ERRORS=1
		fi
	done

	if [ "$HAS_EXTENSION_ERRORS" != "0" ]; then
		if [ "$LISTONLY" ]; then
			echo -e "\n...would have terminated here due to extension errors. Proceeding since in list mode.";
		else
			exit 9
		fi
	fi
fi

if [ "$BASELINE" ]; then
	# import the baseline
	cat ${SQL_REVISION_PATH}/${LATEST_BASELINE} | eval "$CHANGESET_PIPE" | $conn_str $psql_verbose $DB

	# create the schema revision table if it does not exist. This allows for easy baselining as the current
	# database schema can be dumped together with the schema_revision table.
	has_schema_revision=`$conn_str $DB -c "SELECT tablename FROM pg_tables WHERE tablename = 'schema_revision';" | grep schema_revision`
	if [ ! "$has_schema_revision" ]; then
		echo -e "Creating the schema_revision table"
		echo "CREATE TABLE schema_revision (revision integer NOT NULL PRIMARY KEY, applied_stamp timestamp without time zone DEFAULT now());" | eval "$CHANGESET_PIPE" | $PSQL -U $DB_USER $DB
		$conn_str $DB -c "COMMENT ON TABLE schema_revision IS 'Log of applied DB schema revisions from change files in source control; allows only new change files to be applied';"
	else
		echo -e "schema_revision table already exists, not re-creating"
	fi

	$conn_str $DB -c "INSERT INTO schema_revision (revision) VALUES ($current_revision)"
	echo -e "DONE! Imported baseline ${SQL_REVISION_PATH}/${LATEST_BASELINE}"
	exit 0
fi

if [ "$TO_REVISION" ]; then
	TO_REVISION=`echo $TO_REVISION | grep -v [^0-9]`

	if [ -z "$TO_REVISION" ]; then
		echo -e "${ERR_PREF}Non-numeric revision number passed."
		exit 9
	fi
fi

# try to fetch the current schema version from the target db (note, -- is required to escape the -c ticks correctly)
set -- `$conn_str --tuples-only $DB -c 'SELECT revision FROM schema_revision ORDER BY revision DESC limit 1;'`
current_revision=$1;

if [ -z "$current_revision" ]; then
	echo -e "${ERR_PREF}No revision number found in the $DB database. You probably need to import the latest baseline."
	exit 9
fi

current_revision=`echo $current_revision | grep -v [^0-9]`
if [ -z "$current_revision" ]; then
	echo -e "${ERR_PREF}Non-numeric revision number found in the $DB database. Something is very wrong here."
	exit 9
fi

if [ ! -e $SQL_REVISION_PATH ]; then
	echo -e "${ERR_PREF}The SQL revision path $SQL_REVISION_PATH does not exist."
	exit 9
fi

if [ $(ls -1A $SQL_REVISION_PATH | wc -l) -eq 0 ]; then
	echo -e "${ERR_PREF}The SQL revision path $SQL_REVISION_PATH is empty. Have you correctly checked out the project?"
	exit 9
fi

if [ "$TO_REVISION" ] && [ "$TO_REVISION" -le "$current_revision" ]; then
	echo -e "\nNothing to do. Asked to go no further than revision $TO_REVISION, currently at revision $current_revision.\n"
	exit 0
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
			cat ${SQL_REVISION_PATH}/${next_revision}_rev.sql | eval "$CHANGESET_PIPE"
		fi;
	else
		echo "...applying revision $next_revision"
		cat ${SQL_REVISION_PATH}/${next_revision}_rev.sql | eval "$CHANGESET_PIPE" | $conn_str --single-transaction $psql_verbose -v ON_ERROR_STOP=1 $DB
		if [ "$?" -ne "0" ]; then
			echo -e "${ERR_PREF}The revision failed, aborting. The revision is automatically wrapped in a transaction when ran, but explicit use of transaction blocks within the revision script will override this. Unless they are present and failed, the revision should have been properly rollbacked."
			exit 9
		fi
		$conn_str $DB -c "INSERT INTO schema_revision (revision) VALUES ($next_revision)"
	fi;
	next_revision=$(($next_revision + 1))
done

# see if we ran into a new baseline!
if [ -e ${SQL_REVISION_PATH}/${next_revision}_baseline.sql ]; then
	found_baseline=1
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
		echo -e "\nWould have upgraded from revision $current_revision to $at_revision\n"
	else
		echo -e "\nUpgraded from revision $current_revision to $at_revision\n"
	fi
fi

if [ "$found_baseline" ]; then
	echo -e "\nRevision $next_revision is a new baseline. It should be applied cleanly by dropping the database (do dump the data first if this is the production environment...)."
fi

exit 0

