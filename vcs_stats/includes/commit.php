<?php


/**
 * Simple commit data wrapper (aka glorified array)
 *
 * @package    vcs-stats
 * @author     Kristoffer Lindqvist <kris@tsampa.org>
 * @copyright  2009 Kristoffer Lindqvist
 * @license    http://www.opensource.org/licenses/mit-license.php MIT license
 */
class Commit {

	protected $revision = null;

	protected $author = null;

	protected $commit_date = null;

	protected $commit_message = null;


	/**
	 * Constructor
	 *
	 * @param    string   $revision: revision id
	 * @param    string   $author: author of the revision
	 * @param    string   $commit_date: date string for the commit time
	 * @param    string   $commit_message
	 */
	public function __construct($revision, $author, $commit_date, $commit_message) {
		$this->revision = $revision;
		$this->author = $author;
		$this->commit_date = $commit_date;
		$this->commit_message = $commit_message;
	}


	/**
	 * Get the revision for the commit
	 *
	 * @return   string
	 */
	public function get_revision() {
		return $this->revision;
	}


	/**
	 * Get the author of the commit
	 *
	 * @return   string
	 */
	public function get_author() {
		return $this->author;
	}


	/**
	 * Get the commit date string
	 *
	 * @return    string
	 */
	public function get_commit_date() {
		return $this->commit_date;
	}


	/**
	 * Get the commit message
	 *
	 * @return    string
	 */
	public function get_commit_message() {
		return $this->commit_message;
	}

}
