<?php

require_once('shell.php');
require_once('commit.php');


/**
 * Git interface
 *
 * Simplistic Git interface geared towards getting commit data and branching
 * for the purpose of running code stats against the source. As such, it only
 * wraps a subset of functionality.
 *
 * @package    vcs-stats
 * @author     Kristoffer Lindqvist <kris@tsampa.org>
 * @copyright  2009 Kristoffer Lindqvist
 * @license    http://www.opensource.org/licenses/mit-license.php MIT license
 */
class VCS_Git {

	const CUT_BINARY = '/usr/bin/env cut';

	const WC_BINARY = '/usr/bin/env wc';

	protected $repository_path = null;

	protected $binary_path = null;

	protected $changelog = null;

	/**
	 * Convenience wrapper for all gymnastics required to call Git
	 *
	 * @var string
	 */
	protected $git_cmd_prefix = null;

	public function __construct($repository_path, $binary_path = '/usr/bin/git') {

		// ---- got Git?
		if (!is_file($binary_path)) {
			throw new GitException("Could not find Git at $binary_path");
		}

		// ---- got a repository?
		if (!is_string($repository_path) || strlen($repository_path) == 0) {
			throw new InvalidArgumentException('Invalid or no repository path');
		}

		if (!is_dir($repository_path)) {
			throw new GitException("There is no Git repository at $repository_path");
		}

		if (!is_dir("$repository_path/.git")) {
			$this->error("$repository_path is not a Git repository");
		}

		$this->binary_path = $binary_path;
		$this->repository_path = $repository_path;
		$this->git_cmd_prefix = 'cd ' . $this->repository_path . ' && ' . $this->binary_path;
	}


	// ----- repository ----- //

	/**
	 * Get the path to the root of the repository
	 *
	 * @return   string
	 */
	public function get_repository_path() {
		return $this->repository_path;
	}


	/**
	 * Get the name of the Version Control System
	 *
	 * @return   string
	 */
	public function get_vcs_name() {
		return 'git';
	}


	/**
	 * Get the version of the Version Control System
	 *
	 * @return    string
	 */
	public function get_vcs_version() {
		$stdout = Shell::exec($this->binary_path . ' --version | cut -d " " -f3', $exit_code, $stderr);

		if ($exit_code !== 0) {
			throw new GitException("Could not get git version: $stderr");
		}

		return $stdout;
	}

	// ----- branching ----- //

	/**
	 * Get the name of the currently active branch
	 *
	 * @return    string
	 */
	public function get_current_branch() {
		$stdout = trim(Shell::exec($this->git_cmd_prefix . ' branch | ' . self::CUT_BINARY . ' -d " " -f 2', $exit_code, $stderr));

		if ($exit_code !== 0 || strlen($stdout) === 0) {
			throw new GitException("Could not get current branch: $stderr");
		}

		return $stdout;
	}


	/**
	 * Create a new branch from a commit id
	 *
	 * @param    string   $branch: name of the new branch to create
	 * @param    string   $commit_id: commit id to branch from
	 * @return   boolean  true if the create succeeded
	 */
	public function create_branch($branch, $commit_id) {
		$stdout = Shell::exec($this->git_cmd_prefix . " branch $branch $commit_id", $exit_code, $stderr);

		if ($exit_code !== 0) {
			throw new GitException("Could not create branch $branch: $stderr");
		}

		return true;
	}


	/**
	 * Delete a branch
	 *
	 * @param    string   $branch: name of the branch to delete
	 * @return   boolean  true if the delete succeeded
	 */
	public function delete_branch($branch) {

		Shell::exec($this->git_cmd_prefix . ' branch -D ' . $branch, $exit_code, $stderr);  //  . " > /dev/null"

		if ($exit_code !== 0) {
			throw new GitException("Could not delete branch $branch: $stderr");
		}

		return true;
	}


	/**
	 * Switch to an existing branch
	 *
	 * @param    string   $branch: name of the branch to switch to
	 * @return   boolean  true if the switch succeeded
	 */
	public function switch_to_branch($branch) {
		$stdout = Shell::exec($this->git_cmd_prefix . ' checkout ' . $branch, $exit_code, $stderr);

		if ($exit_code !== 0) {
			throw new GitException("Could not switch branch to $branch: $stderr");
		}

		return true;
	}


	// ----- log ----- //


	/**
	 * Get the HEAD commit, eg. the most recent commit in the active branch
	 *
	 * @return    Commit
	 */
	public function get_head_commit() {
		$stdout = Shell::exec($this->git_cmd_prefix . ' log -n 1', $exit_code, $stderr);

		if ($exit_code !== 0) {
			throw new GitException("Could not get HEAD commit: $stderr");
		}

		return $this->create_commit($stdout);
	}

	/**
	 * Get the parent (first older) commit of a commit
	 *
	 * @param    string   $commit_id: commit id to get the parent for
	 * @return   Commit
	 */
	public function get_parent_of_commit($commit_id) {
		$stdout = Shell::exec($this->git_cmd_prefix . ' log -n 1 ' . $commit_id . '^', $exit_code, $stderr);

		if ($exit_code !== 0) {
			throw new GitException("Could not get parent of commit $commit_id: $stderr");
		}

		return $this->create_commit($stdout);

	}


	/**
	 * Get the total number of commits in the currently active branch
	 *
	 * @return   integer
	 */
	public function get_commit_count() {
		$stdout = Shell::exec($this->git_cmd_prefix . ' log --oneline | ' . self::WC_BINARY . ' -l', $exit_code, $stderr);

		if ($exit_code !== 0 || !is_numeric($stdout)) {
			throw new GitException("Could not get commit count: $stderr");
		}

		return (int)$stdout;
	}


	/**
	 * Get a particulat commit
	 *
	 * @param     string   $commit_id: commit to get
	 * @return    Commit
	 */
	public function get_commit($commit_id) {

		if (strlen($commit_id) !== 40) {
			throw new GitException('Commit is not a SHA1 hash: ' . $commit_id);
		}

		$stdout = Shell::exec($this->git_cmd_prefix . ' log -c ' . $commit_id . ' -n 1', $exit_code, $stderr);

		if ($exit_code !== 0) {
			throw new GitException("Could not get commit $commit_id: $stderr");
		}

		return $this->create_commit($stdout);
	}



	// ===== PRIVATE INTERFACE ===== //

	/**
	 * Create a Commit based on Git log data
	 *
	 * @param    string   $commit_data: commit data to parse
	 * @return   Commit
	 */
	protected function create_commit($commit_data) {
		$commit_data = explode("\n", $commit_data);

		if ($commit_data) {

			$line_count = count($commit_data);

			$commit_author = null;
			$commit_date = null;

			for ($i = 0; $i < $line_count; $i++) {

				$line = explode(' ', $commit_data[$i], 2);
				if (!isset($line[1])) {
					continue;
				}

				$line[1] = trim($line[1]);

				switch ($line[0]) {

					case 'commit':
						$commit_id = $line[1];
						break;

					case 'Author:':
						$commit_author = $line[1];
						break;

					case 'Date:':
						// postgres can munch this standard date string as-is, no
						// need to go via a Unix timestamp, eg. strtotime()
						$commit_date = $line[1];
						break;

					default:
						continue;
				}
			}

			$commit_message = trim( $commit_data[$line_count - 1] );

			return new Commit($commit_id, $commit_author, $commit_date, $commit_message);
		}
	}

}

class GitException extends Exception { }
